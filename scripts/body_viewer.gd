class_name BodyViewer
extends Node3D
## Visor 3D del cuerpo: cámara, luces y el nodo "Cuerpo".
##
## Responsabilidades:
##   - Indexar el cuerpo según la convención Cuerpo/<Sistema>/<Organo>.
##   - Crear colisiones en tiempo de ejecución para poder seleccionar con un rayo
##     (funciona igual con primitivas que con modelos .glb).
##   - Detectar clics (sin confundirlos con arrastres de cámara) y resaltar el órgano elegido.
##     Si el órgano está formado por partes (p. ej. el cráneo: frontal, temporal, estribo...),
##     se resalta la parte exacta en la que se hizo clic.
##   - Aislar la parte u órgano seleccionado (para ver estructuras internas como el estribo).
##   - Mostrar un sistema: pedir al GestorCapas que retire las capas que lo cubren, desactivar
##     la selección de las capas retiradas y encuadrar el sistema con la cámara.
## No sabe nada de la interfaz: solo emite señales que escucha la escena principal.

signal organo_seleccionado(id_organo: String, id_sistema: String, id_parte: String)  ## id_parte "" = sin partes
signal seleccion_limpiada
signal sistema_mostrado(id_sistema: String)   ## "" = cuerpo completo
signal organo_bajo_cursor(id_organo: String, id_parte: String)  ## "" = ninguno (nombre al pasar el mouse)
signal aislamiento_cambiado(activo: bool)

## Distancia máxima (en píxeles) entre presionar y soltar para considerar que fue un clic
const UMBRAL_CLIC := 6.0
const LARGO_RAYO := 100.0
const CAPA_CERRADA := "Piel"   ## Capa que envuelve todo el cuerpo (ver _mostrar_interior)
const CAPA_RENDER_AISLADA := 2  ## Capa de dibujo (bit) para lo aislado: la cámara solo ve esa capa
const TRANSPARENCIA_CONTEXTO := 0.9  ## Sistemas de contexto al mostrar uno (0 = opaco, 1 = invisible)
const SHADER_RESALTADO := preload("res://shaders/resaltado.gdshader")
const SHADER_TINTE := preload("res://shaders/tinte.gdshader")
const SHADER_RAYOS_X := preload("res://shaders/resaltado_rayos_x.gdshader")
const RADIO_MINIMO_CONTEXTO := 0.12   ## Al marcar una parte pequeña se encuadra al menos esta zona (m)
const RADIO_PARTE_PEQUENA := 0.03     ## Partes más pequeñas que esto llevan un marcador visible
const COLOR_MARCADOR := Color(1.0, 0.82, 0.15)

@onready var camara: CamaraOrbital = $Camara
var cuerpo: Node3D   ## Se carga en _ready según data/visuales.json (cuerpo_activo)
@onready var capas: GestorCapas = $GestorCapas
@onready var visuales: VisualesFisiologia = $Visuales

var _organos: Dictionary = {}       ## id -> Node3D del órgano
var _sistemas: Dictionary = {}      ## id -> Node3D del sistema
var _colisiones: Dictionary = {}    ## id de sistema -> Array[StaticBody3D]
var _cajas_sistemas: Dictionary = {}  ## id de sistema -> AABB en el mundo (posición original)
var _caja_cuerpo := AABB()
var _sistema_actual := ""
var _tintes: Dictionary = {}          ## Node3D del órgano (o malla de una parte) -> ShaderMaterial de tinte
var _organo_actual: Node3D = null
var _parte_actual: Node3D = null      ## Parte seleccionada dentro del órgano (null si no tiene partes)
var _aislado: Array[MeshInstance3D] = []   ## Mallas aisladas (vacío = sin aislar)
var _colisiones_aisladas: Dictionary = {}  ## StaticBody3D -> collision_layer original
var _parte_bajo_cursor := ""
var _vista_antes_de_aislar: Array = []     ## [yaw, pitch, distancia, objetivo] para volver al salir
var _material_resaltado: ShaderMaterial
var _material_rayos_x: ShaderMaterial   ## Para partes: se ve a través de lo que las tapa
var _marcador: MeshInstance3D           ## Esfera que pulsa alrededor de partes diminutas (huesecillos...)
var _pos_presion := Vector2.INF
var _pos_cursor_pendiente := Vector2.INF   ## Última posición del mouse aún sin consultar
var _organo_bajo_cursor := ""


func _ready() -> void:
	_material_resaltado = ShaderMaterial.new()
	_material_resaltado.shader = SHADER_RESALTADO
	_material_rayos_x = ShaderMaterial.new()
	_material_rayos_x.shader = SHADER_RAYOS_X
	_material_rayos_x.render_priority = 100   # Encima de todo lo demás, incluidos los fantasmas
	_crear_marcador()
	camara.configurar(Datos.camara)
	cuerpo = BodyViewer.instanciar_cuerpo()
	add_child(cuerpo)
	_indexar_cuerpo()
	capas.configurar(_sistemas, Datos.orden_capas, Datos.animacion_capas, camara, _caja_cuerpo.get_center())
	capas.capa_retirada.connect(_on_capa_retirada)
	capas.capa_restaurada.connect(_on_capa_restaurada)
	visuales.configurar(self, Datos.visuales)
	_mostrar_interior(false)
	_preparar_edad()
	_completar_colisiones([CAPA_CERRADA])   # Con la piel completa solo se puede tocar la piel


# --- API pública --------------------------------------------------------------

## emitir = false: solo resalta (lo usa el cuestionario para mostrar la respuesta correcta).
## parte: nodo de la parte dentro del órgano (null = todo el órgano).
func seleccionar_organo(id: String, emitir := true, parte: Node3D = null) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		push_warning("Órgano desconocido: %s" % id)
		return
	if organo == _organo_actual and parte == _parte_actual:
		return
	if not _aislado.is_empty():
		aislar(false)
	var anterior := _organo_actual
	_organo_actual = organo
	_parte_actual = parte
	_actualizar_overlay_si(anterior)
	_actualizar_overlay(organo)
	_actualizar_marcador()
	if emitir:
		organo_seleccionado.emit(id, organo.get_meta("sistema"), String(parte.name) if parte else "")


func limpiar_seleccion() -> void:
	if _organo_actual == null:
		return
	if not _aislado.is_empty():
		aislar(false)
	var anterior := _organo_actual
	_organo_actual = null
	_parte_actual = null
	_actualizar_overlay(anterior)
	_actualizar_marcador()
	seleccion_limpiada.emit()


## Marca una estructura DENTRO de su sistema, aunque esté escondida (p. ej. el estribo,
## dentro del temporal): muestra el sistema (si no se está viendo ya), la selecciona con el
## resaltado de rayos X y acerca la cámara dejando ver lo que la rodea.
func ir_a_estructura(id_organo: String, id_parte := "", aislar_ := false) -> void:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null:
		return
	if not _aislado.is_empty():
		aislar(false)
	var sistema: String = organo.get_meta("sistema")
	if sistema == CAPA_CERRADA:
		if not _sistema_actual.is_empty():
			mostrar_cuerpo_completo()
	elif _sistema_actual != sistema:
		mostrar_sistema(sistema)
	var parte: Node3D = null
	if not id_parte.is_empty():
		parte = organo.find_child(id_parte, true, false)
	seleccionar_organo(id_organo, true, parte)
	if aislar_:
		aislar(true)
	else:
		var caja := _caja_de_mallas(mallas_de(parte if parte else organo))
		var radio := maxf(caja.size.length() * 0.5, RADIO_MINIMO_CONTEXTO)
		_encuadrar(AABB(caja.get_center() - Vector3.ONE * radio, Vector3.ONE * radio * 2.0), 0.75)


func _crear_marcador() -> void:
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 2.0
	esfera.radial_segments = 24
	esfera.rings = 12
	var material := ShaderMaterial.new()
	material.shader = SHADER_RAYOS_X
	material.set_shader_parameter("color_resaltado", COLOR_MARCADOR)
	material.render_priority = 101
	esfera.material = material
	_marcador = MeshInstance3D.new()
	_marcador.name = "MarcadorParte"
	_marcador.mesh = esfera
	_marcador.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marcador.visible = false
	add_child(_marcador)


## Coloca el marcador alrededor de la parte seleccionada si es muy pequeña para verla de lejos.
func _actualizar_marcador() -> void:
	if _parte_actual == null or not _aislado.is_empty():
		_marcador.visible = false
		return
	var caja := _caja_de_mallas(mallas_de(_parte_actual))
	var radio := caja.size.length() * 0.5
	_marcador.visible = radio < RADIO_PARTE_PEQUENA
	_marcador.global_position = caja.get_center()
	_marcador.scale = Vector3.ONE * maxf(radio * 3.0, 0.012)


# --- Edad -------------------------------------------------------------------------------

var _formas_edad: Array = []          ## [MeshInstance3D, índice "Bebe", índice "Anciano"]
var _objetivo_adulto := Vector3.ZERO
var _distancia_adulto := 0.0
var _color_cabello := Color.BLACK
var _material_cabello: BaseMaterial3D
var _edad_actual := -1.0
var _pesos_colision: Array = []   ## Pesos con los que se crearon las colisiones actuales


func _preparar_edad() -> void:
	_objetivo_adulto = camara.objetivo_inicial()
	_distancia_adulto = camara.distancia_inicial()
	_formas_edad = preparar_formas(cuerpo)
	for f in _formas_edad:
		_forma_de_malla[f[0]] = f
	var cabello: Node3D = _organos.get("Cabello")
	if cabello:
		var malla := mallas_de(cabello)[0]
		_material_cabello = malla.get_active_material(0) as BaseMaterial3D
		if _material_cabello:
			_color_cabello = _material_cabello.albedo_color
	_pesos_colision = [0.0, 0.0, 0.0, 0.0, 0.0]


## Mallas con formas de edad de un cuerpo: [MeshInstance3D, índices Bebe, Anciano, SinMamas, Liso, Encogido].
func preparar_formas(raiz: Node3D) -> Array:
	var lista := []
	for mi in mallas_de(raiz):
		var m := mi.mesh as ArrayMesh
		if m and m.get_blend_shape_count() >= 2:
			lista.append([mi, mi.find_blend_shape_by_name("Bebe"), mi.find_blend_shape_by_name("Anciano"),
					mi.find_blend_shape_by_name("SinMamas"), mi.find_blend_shape_by_name("Liso"),
					mi.find_blend_shape_by_name("Encogido"), mi.find_blend_shape_by_name("Sentado")])
	return lista


## Pesos de las formas de edad: [bebe, anciano, sin_mamas, encogido, sentado] y "liso" aparte.
func _pesos_edad(anios: float) -> Array:
	var bebe := Datos.curva_edad("peso_bebe", anios)
	var anciano := Datos.curva_edad("peso_anciano", anios)
	# La forma "Bebe" ya aplana el pecho; "SinMamas" completa lo que falta hasta la pubertad
	var sin_mamas := maxf(0.0, Datos.curva_edad("peso_sin_mamas", anios) - bebe)
	var liso := Datos.curva_edad("peso_liso", anios)   # Abdomen sin definición en la infancia
	# Recién nacido en posición fetal: "Encogido" ya incluye la forma de bebé (y el abdomen liso),
	# así que reemplaza a "Bebe" en la medida en que se activa
	var encogido := bebe * Datos.curva_edad("peso_encogido", anios)
	var sentado := (bebe - encogido) * Datos.curva_edad("peso_sentado", anios)   # Igual, sentado
	bebe -= encogido + sentado
	liso *= 1.0 - encogido - sentado
	return [[bebe, anciano, sin_mamas, encogido, sentado], liso]


## pesos: [bebe, anciano, sin_mamas, encogido, sentado]
func _aplicar_pesos(formas: Array, pesos: Array, liso: float) -> void:
	for f in formas:
		var bebe: float = pesos[0]
		for i in [3, 4]:   # Posturas: si la malla no las tiene, se queda con la forma "Bebe"
			var indice: int = f[i + 2] if f.size() > i + 2 else -1
			if indice >= 0:
				f[0].set_blend_shape_value(indice, pesos[i])
			else:
				bebe += pesos[i]
		f[0].set_blend_shape_value(f[1], bebe)
		f[0].set_blend_shape_value(f[2], pesos[1])
		if f[3] >= 0:
			f[0].set_blend_shape_value(f[3], pesos[2])
		if f.size() > 4 and f[4] >= 0:
			f[0].set_blend_shape_value(f[4], liso)


## Melena y mamas según la edad (en cualquier cuerpo: el principal o el comparado).
func _detalles_edad(raiz: Node3D, anios: float) -> void:
	var cabello := raiz.find_child("Cabello", true, false)
	if cabello:
		for malla in mallas_de(cabello):
			if String(malla.name).contains("hair_loose"):
				malla.visible = anios >= float(Datos.edad.get("melena_desde", 3))
	var mamas := raiz.find_child("Mamas", true, false) as Node3D
	if mamas:
		mamas.visible = anios >= float(Datos.edad.get("mamas_desde", 11))


## Edad de otro cuerpo (el que se compara): formas, estatura y detalles, sin colisiones.
func aplicar_edad_a(raiz: Node3D, formas: Array, anios: float) -> void:
	var pesos := _pesos_edad(anios)
	_aplicar_pesos(formas, pesos[0], pesos[1])
	raiz.scale = Vector3.ONE * Datos.curva_edad("altura_relativa", anios)
	_detalles_edad(raiz, anios)


## Cambia la edad del cuerpo (años). Mezcla las formas "Bebe" y "Anciano" precalculadas (en la GPU,
## instantáneo), escala la estatura, agrega canas y oculta las mamas en la infancia.
## final = true cuando se suelta la barra: entonces se recalculan las colisiones.
func fijar_edad(anios: float, final := false) -> void:
	_edad_actual = anios
	var pesos := _pesos_edad(anios)
	pesos_actuales = pesos[0]
	_aplicar_pesos(_formas_edad, pesos[0], pesos[1])
	var escala := Datos.curva_edad("altura_relativa", anios)
	cuerpo.scale = Vector3.ONE * escala
	visuales.scale = Vector3.ONE * escala   # Trayectorias de la simulación (pies en el origen)
	if _material_cabello:
		var gris := Color.from_string(Datos.edad.get("color_canas", "#cfcfcc"), Color.GRAY)
		_material_cabello.albedo_color = _color_cabello.lerp(gris, Datos.curva_edad("canas", anios))
	# Un recién nacido casi no tiene pelo (la melena aparece con la edad) ni mamas desarrolladas
	_detalles_edad(cuerpo, anios)
	# Encuadre de referencia y cajas de los sistemas según el nuevo tamaño
	camara.fijar_referencia(Vector3(_objetivo_adulto.x, _objetivo_adulto.y * escala, _objetivo_adulto.z),
			maxf(_distancia_adulto * lerpf(0.55, 1.0, escala), 0.8))
	for id in _sistemas:
		_cajas_sistemas[id] = _caja_mundo(_sistemas[id])
	if final:
		_actualizar_colisiones_edad(pesos[0])
		if _sistema_actual.is_empty() and _aislado.is_empty():
			camara.encuadrar(camara.objetivo_inicial(), camara.distancia_inicial())
		elif _aislado.is_empty():   # Viendo un sistema: se reencuadra a su nuevo tamaño
			_encuadrar(_cajas_sistemas[_sistema_actual])


func edad_actual() -> float:
	return _edad_actual


## Las colisiones (para elegir con clic) se calculan con los vértices ya mezclados.
## Se hace en varios hilos en segundo plano (WorkerThreadPool): la barra no se traba.
var _tarea_colisiones := -1
var _pendiente_colisiones: Array = []   ## [] = nada pendiente
var _trabajos: Array = []          ## [CollisionShape3D, base, índices, Bebe, Anciano, SinMamas, Encogido]
var _resultados: Array = []        ## ConcavePolygonShape3D nuevas (mismo orden que _trabajos)
var _pesos_en_calculo: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


func _actualizar_colisiones_edad(pesos: Array) -> void:
	if pesos == _pesos_colision:
		return
	if _tarea_colisiones != -1:
		_pendiente_colisiones = pesos   # Se hará al terminar la tarea actual
		return
	if not _cola_colisiones.is_empty():
		_pendiente_colisiones = pesos   # Se hará al terminar la cola de colisiones
		return
	_pesos_en_calculo = pesos
	_resultados.resize(_trabajos.size())
	_tarea_colisiones = WorkerThreadPool.add_group_task(_calcular_colision, _trabajos.size(), -1, true,
			"Colisiones por edad")


## Colisiones (para elegir con clic): leer una malla pide sus datos a la GPU, y leer las ~1150
## de golpe congela el arranque unos segundos. Se crean de a poco en el hilo principal (unos
## milisegundos por cuadro) en una cola; las del sistema que se va a mostrar se adelantan. La
## misma lectura sirve para las formas de edad (_trabajos).
var _cola_colisiones: Array = []   ## [CollisionShape3D, MeshInstance3D, id de sistema]
var _forma_de_malla: Dictionary = {}   ## MeshInstance3D -> entrada de _formas_edad
const PRESUPUESTO_COLA_US := 10000


func _procesar_cola(limite_us: int) -> void:
	var fin := Time.get_ticks_usec() + limite_us
	while not _cola_colisiones.is_empty() and Time.get_ticks_usec() < fin:
		_crear_forma(_cola_colisiones.pop_back())
	if _cola_colisiones.is_empty() and not _pendiente_colisiones.is_empty():
		var p := _pendiente_colisiones
		_pendiente_colisiones = []
		_actualizar_colisiones_edad(p)


## Termina ya las colisiones de estos sistemas (todas si ids está vacío).
func completar_colisiones(ids: Array = []) -> void:
	_completar_colisiones(ids)


func _completar_colisiones(ids: Array) -> void:
	var resto := []
	for item in _cola_colisiones:
		if ids.is_empty() or item[2] in ids:
			_crear_forma(item)
		else:
			resto.append(item)
	_cola_colisiones = resto
	if _cola_colisiones.is_empty() and not _pendiente_colisiones.is_empty():
		var p := _pendiente_colisiones
		_pendiente_colisiones = []
		_actualizar_colisiones_edad(p)


func _crear_forma(item: Array) -> void:
	var nodo: CollisionShape3D = item[0]
	var malla: MeshInstance3D = item[1]
	if not is_instance_valid(nodo) or malla.mesh == null:
		return
	var m := malla.mesh as ArrayMesh
	if m == null or m.get_surface_count() != 1:
		nodo.shape = malla.mesh.create_trimesh_shape()
		return
	var arrays := m.surface_get_arrays(0)
	var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var f: Array = _forma_de_malla.get(malla, [])
	if f.is_empty():
		var caras := PackedVector3Array()
		caras.resize(indices.size())
		for k in indices.size():
			caras[k] = base[indices[k]]
		var forma := ConcavePolygonShape3D.new()
		forma.set_faces(caras)
		nodo.shape = forma
		return
	var formas := m.surface_get_blend_shape_arrays(0)
	var trabajo := [nodo, base, indices,
			formas[f[1]][Mesh.ARRAY_VERTEX], formas[f[2]][Mesh.ARRAY_VERTEX],
			formas[f[3]][Mesh.ARRAY_VERTEX] if f[3] >= 0 else base,
			formas[f[5]][Mesh.ARRAY_VERTEX] if f.size() > 5 and f[5] >= 0 else base,
			formas[f[6]][Mesh.ARRAY_VERTEX] if f.size() > 6 and f[6] >= 0 else base]
	_trabajos.append(trabajo)
	nodo.shape = _forma_con_pesos(trabajo, _pesos_colision)


func _calcular_colision(k: int) -> void:
	_resultados[k] = _forma_con_pesos(_trabajos[k], _pesos_en_calculo)


## Pesos de las formas de edad que se ven ahora: [bebe, anciano, sin_mamas, encogido, sentado].
var pesos_actuales: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


## Datos de vértices (base y formas de edad) de las mallas de un órgano, en el formato de
## _trabajos: [CollisionShape3D, base, índices, Bebe, Anciano, SinMamas, Encogido, Sentado].
func trabajos_de(organo: Node3D) -> Array:
	var sistema: String = organo.get_meta("sistema", "")
	_completar_colisiones([sistema])
	var mallas := mallas_de(organo)
	return _trabajos.filter(func(t): return is_instance_valid(t[0]) and t[0].get_parent().get_parent() in mallas)


## Posición en el mundo del vértice i de una malla, con la edad y postura que se ven ahora.
func punto_deformado(t: Array, i: int) -> Vector3:
	var base: PackedVector3Array = t[1]
	var p := pesos_actuales
	var wb: float = p[0] + (p[3] if t[6] == base else 0.0) + (p[4] if t[7] == base else 0.0)
	var v: Vector3 = base[i] + (t[3][i] - base[i]) * wb + (t[4][i] - base[i]) * p[1] + (t[5][i] - base[i]) * p[2] \
			+ (t[6][i] - base[i]) * p[3] + (t[7][i] - base[i]) * p[4]
	var malla: MeshInstance3D = t[0].get_parent().get_parent()
	return malla.global_transform * v


func _forma_con_pesos(t: Array, pesos: Array) -> ConcavePolygonShape3D:
	var base: PackedVector3Array = t[1]
	var indices: PackedInt32Array = t[2]
	var vb: PackedVector3Array = t[3]
	var va: PackedVector3Array = t[4]
	var vs: PackedVector3Array = t[5]
	var ve: PackedVector3Array = t[6]
	var vt: PackedVector3Array = t[7]
	# Una malla sin las formas de postura usa la de bebé (ver _aplicar_pesos)
	var wb: float = pesos[0] + (pesos[3] if ve == base else 0.0) + (pesos[4] if vt == base else 0.0)
	var caras := PackedVector3Array()
	caras.resize(indices.size())
	for i in indices.size():
		var j := indices[i]
		caras[i] = base[j] + (vb[j] - base[j]) * wb + (va[j] - base[j]) * pesos[1] + (vs[j] - base[j]) * pesos[2] \
				+ (ve[j] - base[j]) * pesos[3] + (vt[j] - base[j]) * pesos[4]
	var forma := ConcavePolygonShape3D.new()
	forma.set_faces(caras)
	return forma


func _revisar_tarea_colisiones() -> void:
	if _tarea_colisiones == -1 or not WorkerThreadPool.is_group_task_completed(_tarea_colisiones):
		return
	WorkerThreadPool.wait_for_group_task_completion(_tarea_colisiones)
	_tarea_colisiones = -1
	for k in _trabajos.size():
		_trabajos[k][0].shape = _resultados[k]
	_pesos_colision = _pesos_en_calculo
	if not _pendiente_colisiones.is_empty():
		var p := _pendiente_colisiones
		_pendiente_colisiones = []
		_actualizar_colisiones_edad(p)


## Partes de un órgano: [[id_parte, nombre], ...] ordenadas por nombre ([] si no tiene partes).
func partes_de(id_organo: String) -> Array:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null or organo is MeshInstance3D:
		return []
	var lista := []
	for malla in mallas_de(organo):
		var id := String(malla.name)
		var nombre := Datos.nombre_parte(id)
		lista.append([id, nombre if not nombre.is_empty() else id])
	lista.sort_custom(func(a, b): return a[1].naturalnocasecmp_to(b[1]) < 0)
	return lista


## Muestra SOLO la parte (u órgano) seleccionada y la encuadra; activo = false vuelve a mostrar todo.
## Se hace con capas de dibujo (la cámara solo ve la capa 2), sin tocar la visibilidad de los
## nodos, así no interfiere con la animación de capas.
func aislar(activo: bool) -> void:
	if activo and _organo_actual == null:
		return
	if activo == not _aislado.is_empty():
		return
	var bit := 1 << (CAPA_RENDER_AISLADA - 1)
	if activo:
		var objetivo: Node3D = _parte_actual if _parte_actual else _organo_actual
		_aislado = mallas_de(objetivo)
		for malla in _aislado:
			malla.layers = bit
			malla.material_overlay = null   # Sin resaltado: se ve el color real de la pieza
			for hijo in malla.get_children():
				if hijo is StaticBody3D:
					_colisiones_aisladas[hijo] = hijo.collision_layer
					hijo.collision_layer = bit
		camara.cull_mask = bit
		_vista_antes_de_aislar = [camara.yaw, camara.pitch, camara.distancia, camara.objetivo]
		camara.permitir_acercamiento(true)
		_encuadrar(_caja_de_mallas(_aislado), 1.8)
	else:
		for malla in _aislado:
			if is_instance_valid(malla):
				malla.layers = 1
		for cuerpo_fisico in _colisiones_aisladas:
			if is_instance_valid(cuerpo_fisico):
				cuerpo_fisico.collision_layer = _colisiones_aisladas[cuerpo_fisico]
		_aislado.clear()
		_colisiones_aisladas.clear()
		_actualizar_overlay_si(_organo_actual)
		camara.cull_mask = 0xFFFFF
		camara.permitir_acercamiento(false)
		if not _vista_antes_de_aislar.is_empty():
			var v := _vista_antes_de_aislar
			camara.animar_a(v[0], v[1], v[2], v[3])
			_vista_antes_de_aislar = []
	_actualizar_marcador()
	aislamiento_cambiado.emit(activo)


func esta_aislado() -> bool:
	return not _aislado.is_empty()


## Muestra un sistema y lo encuadra con la cámara:
##   - se retiran las capas que lo cubren (sistemas.json -> cubierto_por),
##   - se ocultan los sistemas que quedan DENTRO de él (p. ej. los órganos en la vista muscular),
##   - el resto queda como fantasma muy tenue: da contexto sin tapar y no se puede seleccionar.
func mostrar_sistema(id: String) -> void:
	enfocar_sistema(id, TRANSPARENCIA_CONTEXTO)


func enfocar_sistema(id: String, transparencia := TRANSPARENCIA_CONTEXTO) -> void:
	if not _sistemas.has(id):
		push_warning("Sistema desconocido: %s" % id)
		return
	_sistema_actual = id
	var retirar: Array = Datos.cubierto_por(id).duplicate()
	var dentro := []
	for otro in _sistemas:
		if otro != id and id in Datos.cubierto_por(otro) and not otro in retirar:
			dentro.append(otro)   # Está dentro del sistema elegido: no se vería y costaría dibujarlo
	var fantasmas := {}
	for otro in _sistemas:
		if otro != id and not otro in retirar and not otro in dentro:
			fantasmas[otro] = transparencia
	_completar_colisiones([id] + fantasmas.keys())
	capas.retirar_solo(retirar + dentro, fantasmas, dentro)
	_encuadrar(_cajas_sistemas[id])
	sistema_mostrado.emit(id)


## Restaura todas las capas y vuelve a encuadrar el cuerpo entero.
func mostrar_cuerpo_completo() -> void:
	_sistema_actual = ""
	capas.restaurar_todo()
	camara.encuadrar(camara.objetivo_inicial(), camara.distancia_inicial())
	sistema_mostrado.emit("")


## Desarma el cuerpo según la "vista" de un escenario (ver data/escenarios.json):
## {capas_retiradas: [...], capas_fantasma: {id: transparencia}, encuadre: "cuerpo" | id de sistema}
func mostrar_vista(vista: Dictionary) -> void:
	_sistema_actual = ""
	_completar_colisiones(_sistemas.keys().filter(func(x): return not x in vista.get("capas_retiradas", [])))
	capas.retirar_solo(vista.get("capas_retiradas", []), vista.get("capas_fantasma", {}))
	var encuadre: String = vista.get("encuadre", "cuerpo")
	var caja: AABB = _cajas_sistemas.get(encuadre, _caja_cuerpo)
	# El panel del gráfico ocupa la parte baja de la pantalla: se aleja un poco y se baja el
	# objetivo para que el sistema quede en la zona visible de arriba.
	_encuadrar(caja, vista.get("margen", 1.4), vista.get("subir_en_pantalla", 0.12))
	sistema_mostrado.emit("")


## Escala adicional de un órgano (latido, respiración). Se combina con la animación de capas.
func escalar_organo(id: String, escala: Vector3) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		return
	if organo is MeshInstance3D:
		capas.fijar_escala_extra(organo, escala)
	else:
		# Órgano con partes: se escala el nodo del órgano (ubicado en su centro), así las partes
		# se mueven juntas (p. ej. aurículas y ventrículos del corazón)
		organo.scale = escala


## Tiñe un órgano con un color semitransparente encima de su material (cantidad 0 = sin tinte).
## manchas (0 a 1): el tinte se hace irregular, en parches.
func tenir_organo(id: String, color: Color, cantidad: float, manchas := 0.0) -> void:
	var organo: Node3D = _organos.get(id)
	if organo != null:
		_tenir(organo, organo, color, cantidad, manchas)


## Tiñe solo algunas partes de un órgano (p. ej. los dientes del cráneo o las manos en la piel):
## las partes cuyo id contiene alguna de las claves. Tiene prioridad sobre el tinte del órgano.
func tenir_partes(id_organo: String, claves: Array, color: Color, cantidad: float, manchas := 0.0) -> void:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null:
		return
	for malla in mallas_de(organo):
		var nombre := String(malla.name).to_lower()
		if malla != organo and claves.any(func(c): return nombre.contains(String(c).to_lower())):
			_tenir(malla, organo, color, cantidad, manchas)


func _tenir(clave: Node3D, organo: Node3D, color: Color, cantidad: float, manchas: float) -> void:
	var tinte: ShaderMaterial = _tintes.get(clave)
	if cantidad <= 0.001:
		if tinte != null:
			_tintes.erase(clave)
			_actualizar_overlay(organo)
		return
	if tinte == null:
		tinte = ShaderMaterial.new()
		tinte.shader = SHADER_TINTE
		_tintes[clave] = tinte
		_actualizar_overlay(organo)
	tinte.set_shader_parameter("color_tinte", color)
	tinte.set_shader_parameter("cantidad", clampf(cantidad, 0.0, 1.0))
	tinte.set_shader_parameter("manchas", manchas)


## ids de los órganos de un sistema.
func organos_de_sistema(id_sistema: String) -> Array:
	var sistema: Node3D = _sistemas.get(id_sistema)
	if sistema == null:
		return []
	return sistema.get_children().filter(func(n): return _organos.has(String(n.name))) \
			.map(func(n): return String(n.name))


func establecer_modo_fantasma(activo: bool) -> void:
	capas.establecer_modo_fantasma(activo)


func sistema_actual() -> String:
	return _sistema_actual


func obtener_organo(id: String) -> Node3D:
	return _organos.get(id)


func obtener_sistema(id: String) -> Node3D:
	return _sistemas.get(id)


func sistema_de(id_organo: String) -> String:
	var organo: Node3D = _organos.get(id_organo)
	return organo.get_meta("sistema") if organo else ""


func ids_organos() -> Array:
	return _organos.keys()


## ids de todas las partes (nodos de malla dentro de órganos con partes).
func ids_partes() -> Array:
	var ids := []
	for organo in _organos.values():
		if not organo is MeshInstance3D:
			for malla in mallas_de(organo):
				ids.append(String(malla.name))
	return ids


## Primera parte del órgano cuyo id empieza por "prefijo" (null si no hay).
func buscar_parte(id_organo: String, prefijo: String) -> Node3D:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null or prefijo.is_empty():
		return null
	for malla in mallas_de(organo):
		var n := String(malla.name)
		if n.begins_with(prefijo):
			return malla
	return null


## Crea el cuerpo del modelo activo (Z-Anatomy o procedural), con el nombre de nodo "Cuerpo".
static func instanciar_cuerpo() -> Node3D:
	var ruta: String = Datos.cuerpo_activo().get("escena", "res://scenes/cuerpo_prueba.tscn")
	var escena := load(ruta) as PackedScene
	if escena == null:
		push_error("No se pudo cargar el cuerpo %s; se usa el procedural" % ruta)
		escena = load("res://scenes/cuerpo_prueba.tscn")
	var nodo: Node3D = escena.instantiate()
	nodo.name = "Cuerpo"
	return nodo


## Todas las MeshInstance3D de un órgano (él mismo si es una malla, y sus descendientes).
static func mallas_de(nodo: Node) -> Array[MeshInstance3D]:
	var resultado: Array[MeshInstance3D] = []
	if nodo is MeshInstance3D:
		resultado.append(nodo)
	for n in nodo.find_children("*", "MeshInstance3D", true, false):
		resultado.append(n)
	return resultado


# --- Indexado y colisiones ---------------------------------------------------

func _indexar_cuerpo() -> void:
	for sistema in cuerpo.get_children():
		if not sistema is Node3D:
			continue
		if Datos.sistema(sistema.name).is_empty():
			push_warning("El nodo '%s' no está declarado en sistemas.json" % sistema.name)
		var id_sistema := String(sistema.name)
		_sistemas[id_sistema] = sistema
		_colisiones[id_sistema] = []
		for organo in sistema.get_children():
			if not organo is Node3D:
				continue
			organo.set_meta("sistema", id_sistema)
			_organos[String(organo.name)] = organo
			_colisiones[id_sistema].append_array(_crear_colisiones(organo))
		_cajas_sistemas[id_sistema] = _caja_mundo(sistema)
		_caja_cuerpo = _cajas_sistemas[id_sistema] if _caja_cuerpo.size == Vector3.ZERO \
				else _caja_cuerpo.merge(_cajas_sistemas[id_sistema])


func _crear_colisiones(organo: Node3D) -> Array:
	var creados := []
	for malla in mallas_de(organo):
		if malla.mesh == null or _es_transparente(malla):
			continue   # Lo semitransparente (grasa mamaria) no se elige con clic: dejaría pasar el clic a lo de adentro
		var cuerpo_fisico := StaticBody3D.new()
		cuerpo_fisico.name = "Colision"
		cuerpo_fisico.set_meta("organo", organo)
		if malla != organo:
			cuerpo_fisico.set_meta("parte", malla)
		var forma := CollisionShape3D.new()
		cuerpo_fisico.add_child(forma)
		malla.add_child(cuerpo_fisico)
		creados.append(cuerpo_fisico)
		_cola_colisiones.append([forma, malla, organo.get_meta("sistema")])
	return creados


static func _es_transparente(malla: MeshInstance3D) -> bool:
	var m := malla.get_active_material(0)
	return m is BaseMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


func _caja_mundo(nodo: Node3D) -> AABB:
	var resultado := AABB()
	var primero := true
	for malla in mallas_de(nodo):
		var caja: AABB = malla.global_transform * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado


## Mueve la cámara para que la caja quepa en pantalla, manteniendo el ángulo actual.
## margen_extra multiplica la distancia; subir_en_pantalla (fracción de la distancia) baja el
## punto de mira para que el contenido se vea más arriba en la pantalla.
func _encuadrar(caja: AABB, margen_extra := 1.0, subir_en_pantalla := 0.0) -> void:
	var radio := caja.size.length() * 0.5
	var margen: float = Datos.animacion_capas.get("margen_encuadre", 0.9) * margen_extra
	var distancia := radio / sin(deg_to_rad(camara.fov * 0.5)) * margen
	camara.encuadrar(caja.get_center() - Vector3(0, distancia * subir_en_pantalla, 0), distancia)


# --- Reacción a las capas ----------------------------------------------------------

func _on_capa_retirada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 0   # El rayo de selección ya no lo encuentra
	if id_sistema == CAPA_CERRADA:
		_mostrar_interior(true)
	if _organo_actual and _organo_actual.get_meta("sistema") == id_sistema and _aislado.is_empty():
		limpiar_seleccion()


func _on_capa_restaurada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 1
	if id_sistema == CAPA_CERRADA:
		_mostrar_interior(false)


## Plano del corte (ver HerramientasVisor): normal y distancia; w = INF sin corte.
var plano_corte := Vector4(0, 0, 0, INF)
var _interior_forzado := false


## Con el corte activo se dibuja todo el interior aunque la piel esté completa.
func mostrar_interior_forzado(activo: bool) -> void:
	_interior_forzado = activo
	_mostrar_interior(activo or CAPA_CERRADA in capas.capas_retiradas())


## Caja del cuerpo en su tamaño actual (cambia con la edad).
func caja_cuerpo_actual() -> AABB:
	return _caja_mundo(cuerpo)


## Optimización: mientras la piel (superficie cerrada y opaca) está completa, nada de su interior
## se ve, así que no se dibuja. Reduce mucho los triángulos por cuadro en GPU integradas.
func _mostrar_interior(visible_: bool) -> void:
	visible_ = visible_ or _interior_forzado
	for id in _sistemas:
		if id != CAPA_CERRADA:
			_sistemas[id].visible = visible_


# --- Entrada -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Solo se consulta el órgano bajo el cursor si no se está arrastrando la cámara
		_pos_cursor_pendiente = event.position if event.button_mask == 0 else Vector2.INF
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed:
		if event.pressed:
			_pos_presion = event.position
		elif _pos_presion != Vector2.INF:
			if event.position.distance_to(_pos_presion) <= UMBRAL_CLIC:
				_seleccionar_en_pantalla(event.position)
			_pos_presion = Vector2.INF


func _process(_delta: float) -> void:
	if not _cola_colisiones.is_empty():
		_procesar_cola(PRESUPUESTO_COLA_US)
	_revisar_tarea_colisiones()
	# Una consulta por cuadro como máximo, aunque lleguen muchos eventos de movimiento
	var id := _organo_bajo_cursor
	var id_parte := _parte_bajo_cursor
	if get_viewport().gui_get_hovered_control() != null:
		id = ""
		id_parte = ""
	elif _pos_cursor_pendiente != Vector2.INF:
		var choque := _objetivo_en(_pos_cursor_pendiente)
		id = String(choque.organo.name) if choque else ""
		id_parte = String(choque.parte.name) if choque and choque.parte else ""
		_pos_cursor_pendiente = Vector2.INF
	if id != _organo_bajo_cursor or id_parte != _parte_bajo_cursor:
		_organo_bajo_cursor = id
		_parte_bajo_cursor = id_parte
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id != "" else Input.CURSOR_ARROW)
		organo_bajo_cursor.emit(id, id_parte)


func _seleccionar_en_pantalla(pos: Vector2) -> void:
	var choque := _objetivo_en(pos)
	if choque == null:
		if _aislado.is_empty():
			limpiar_seleccion()
		return
	seleccionar_organo(String(choque.organo.name), true, choque.parte)


## Órgano (y parte) visible bajo un punto de la pantalla (rayo físico), o null.
## Mientras hay algo aislado, el rayo solo encuentra lo aislado.
func _objetivo_en(pos: Vector2) -> Choque:
	var desde := camara.project_ray_origin(pos)
	var hasta := desde + camara.project_ray_normal(pos) * LARGO_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	if not _aislado.is_empty():
		consulta.collision_mask = 1 << (CAPA_RENDER_AISLADA - 1)
	var resultado := get_world_3d().direct_space_state.intersect_ray(consulta)
	# Con el corte activo, lo que está del lado quitado no se ve: el rayo sigue hasta lo visible
	var excluidos := []
	while not resultado.is_empty() and plano_corte.w < INF and excluidos.size() < 24 \
			and Vector3(plano_corte.x, plano_corte.y, plano_corte.z).dot(resultado.position) > plano_corte.w:
		excluidos.append(resultado.rid)
		consulta.exclude = excluidos
		resultado = get_world_3d().direct_space_state.intersect_ray(consulta)
	if resultado.is_empty() or not resultado.collider.has_meta("organo"):
		return null
	var choque := Choque.new()
	choque.organo = resultado.collider.get_meta("organo")
	choque.parte = resultado.collider.get_meta("parte") if resultado.collider.has_meta("parte") else null
	return choque


class Choque:
	var organo: Node3D
	var parte: Node3D


func _caja_de_mallas(mallas: Array[MeshInstance3D]) -> AABB:
	var resultado := AABB()
	for i in mallas.size():
		var caja: AABB = mallas[i].global_transform * mallas[i].get_aabb()
		resultado = caja if i == 0 else resultado.merge(caja)
	return resultado


func _actualizar_overlay_si(organo: Node3D) -> void:
	if organo != null:
		_actualizar_overlay(organo)


## Compone la capa superior de cada malla de un órgano: resaltado de selección (en la parte
## elegida o en todo el órgano) o, si no, el tinte de la simulación.
func _actualizar_overlay(organo: Node3D) -> void:
	var tinte: ShaderMaterial = _tintes.get(organo)
	var resaltadas: Array[MeshInstance3D] = []
	if organo == _organo_actual:
		resaltadas = mallas_de(_parte_actual if _parte_actual else organo)
	var resaltado: Material = _material_rayos_x if _parte_actual else _material_resaltado
	for malla in mallas_de(organo):
		if malla in resaltadas:
			malla.material_overlay = resaltado
		else:
			malla.material_overlay = _tintes.get(malla, tinte)
