class_name BodyViewer
extends Node3D

signal organo_seleccionado(id_organo: String, id_sistema: String, id_parte: String)
signal seleccion_limpiada
signal sistema_mostrado(id_sistema: String)
signal organo_bajo_cursor(id_organo: String, id_parte: String)
signal aislamiento_cambiado(activo: bool)

const UMBRAL_CLIC := 6.0
const LARGO_RAYO := 100.0
const CAPA_CERRADA := "Piel"
const CAPA_RENDER_AISLADA := 2
const TRANSPARENCIA_CONTEXTO := 0.9
const SHADER_RESALTADO := preload("res://shaders/resaltado.gdshader")
const SHADER_TINTE := preload("res://shaders/tinte.gdshader")
const SHADER_RAYOS_X := preload("res://shaders/resaltado_rayos_x.gdshader")
const RADIO_MINIMO_CONTEXTO := 0.12
const RADIO_PARTE_PEQUENA := 0.03
const COLOR_MARCADOR := Color(1.0, 0.82, 0.15)

@onready var camara: CamaraOrbital = $Camara
var cuerpo: Node3D
@onready var capas: GestorCapas = $GestorCapas
@onready var visuales: VisualesFisiologia = $Visuales

var _organos: Dictionary = {}
var _sistemas: Dictionary = {}
var _colisiones: Dictionary = {}
var _cajas_sistemas: Dictionary = {}
var _caja_cuerpo := AABB()
var _sistema_actual := ""
var _tintes: Dictionary = {}
var _organo_actual: Node3D = null
var _parte_actual: Node3D = null
var _aislado: Array[MeshInstance3D] = []
var _colisiones_aisladas: Dictionary = {}
var _parte_bajo_cursor := ""
var _vista_antes_de_aislar: Array = []
var _material_resaltado: ShaderMaterial
var _material_rayos_x: ShaderMaterial
var _marcador: MeshInstance3D
var _pos_presion := Vector2.INF
var _pos_cursor_pendiente := Vector2.INF
var _organo_bajo_cursor := ""


func _ready() -> void:
	_material_resaltado = ShaderMaterial.new()
	_material_resaltado.shader = SHADER_RESALTADO
	_material_rayos_x = ShaderMaterial.new()
	_material_rayos_x.shader = SHADER_RAYOS_X
	_material_rayos_x.render_priority = 100
	_drar_crear_marcador()
	camara.drar_configurar(Datos.camara)
	cuerpo = BodyViewer.drar_instanciar_cuerpo()
	add_child(cuerpo)
	_drar_indexar_cuerpo()
	capas.drar_configurar(_sistemas, Datos.orden_capas, Datos.animacion_capas, camara, _caja_cuerpo.get_center())
	capas.capa_retirada.connect(_drar_on_capa_retirada)
	capas.capa_restaurada.connect(_drar_on_capa_restaurada)
	visuales.jlrl_configurar(self, Datos.visuales)
	_drar_mostrar_interior(false)
	_drar_preparar_edad()
	_drar_completar_colisiones([CAPA_CERRADA])


func drar_seleccionar_organo(id: String, emitir := true, parte: Node3D = null) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		push_warning("Órgano desconocido: %s" % id)
		return
	if organo == _organo_actual and parte == _parte_actual:
		return
	if not _aislado.is_empty():
		drar_aislar(false)
	var anterior := _organo_actual
	_organo_actual = organo
	_parte_actual = parte
	_drar_actualizar_overlay_si(anterior)
	_drar_actualizar_overlay(organo)
	_drar_actualizar_marcador()
	if emitir:
		organo_seleccionado.emit(id, organo.get_meta("sistema"), String(parte.name) if parte else "")


func drar_limpiar_seleccion() -> void:
	if _organo_actual == null:
		return
	if not _aislado.is_empty():
		drar_aislar(false)
	var anterior := _organo_actual
	_organo_actual = null
	_parte_actual = null
	_drar_actualizar_overlay(anterior)
	_drar_actualizar_marcador()
	seleccion_limpiada.emit()


func drar_ir_a_estructura(id_organo: String, id_parte := "", aislar_ := false) -> void:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null:
		return
	if not _aislado.is_empty():
		drar_aislar(false)
	var sistema: String = organo.get_meta("sistema")
	if sistema == CAPA_CERRADA:
		if not _sistema_actual.is_empty():
			drar_mostrar_cuerpo_completo()
	elif _sistema_actual != sistema:
		drar_mostrar_sistema(sistema)
	var parte: Node3D = null
	if not id_parte.is_empty():
		parte = organo.find_child(id_parte, true, false)
	drar_seleccionar_organo(id_organo, true, parte)
	if aislar_:
		drar_aislar(true)
	else:
		var caja := _drar_caja_de_mallas(drar_mallas_de(parte if parte else organo))
		var radio := maxf(caja.size.length() * 0.5, RADIO_MINIMO_CONTEXTO)
		_drar_encuadrar(AABB(caja.get_center() - Vector3.ONE * radio, Vector3.ONE * radio * 2.0), 0.75)


func _drar_crear_marcador() -> void:
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


func _drar_actualizar_marcador() -> void:
	if _parte_actual == null or not _aislado.is_empty():
		_marcador.visible = false
		return
	var caja := _drar_caja_de_mallas(drar_mallas_de(_parte_actual))
	var radio := caja.size.length() * 0.5
	_marcador.visible = radio < RADIO_PARTE_PEQUENA
	_marcador.global_position = caja.get_center()
	_marcador.scale = Vector3.ONE * maxf(radio * 3.0, 0.012)


var _formas_edad: Array = []
var _objetivo_adulto := Vector3.ZERO
var _distancia_adulto := 0.0
var _color_cabello := Color.BLACK
var _material_cabello: BaseMaterial3D
var _edad_actual := -1.0
var _pesos_colision: Array = []


func _drar_preparar_edad() -> void:
	_objetivo_adulto = camara.drar_objetivo_inicial()
	_distancia_adulto = camara.drar_distancia_inicial()
	_formas_edad = drar_preparar_formas(cuerpo)
	for f in _formas_edad:
		_forma_de_malla[f[0]] = f
	var cabello: Node3D = _organos.get("Cabello")
	if cabello:
		var malla := drar_mallas_de(cabello)[0]
		_material_cabello = malla.get_active_material(0) as BaseMaterial3D
		if _material_cabello:
			_color_cabello = _material_cabello.albedo_color
	_pesos_colision = [0.0, 0.0, 0.0, 0.0, 0.0]


func drar_preparar_formas(raiz: Node3D) -> Array:
	var lista := []
	for mi in drar_mallas_de(raiz):
		var m := mi.mesh as ArrayMesh
		if m and m.get_blend_shape_count() >= 2:
			lista.append([mi, mi.find_blend_shape_by_name("Bebe"), mi.find_blend_shape_by_name("Anciano"),
					mi.find_blend_shape_by_name("SinMamas"), mi.find_blend_shape_by_name("Liso"),
					mi.find_blend_shape_by_name("Encogido"), mi.find_blend_shape_by_name("Sentado")])
	return lista


func _drar_pesos_edad(anios: float) -> Array:
	var bebe := Datos.dymj_curva_edad("peso_bebe", anios)
	var anciano := Datos.dymj_curva_edad("peso_anciano", anios)
	var sin_mamas := maxf(0.0, Datos.dymj_curva_edad("peso_sin_mamas", anios) - bebe)
	var liso := Datos.dymj_curva_edad("peso_liso", anios)
	var encogido := bebe * Datos.dymj_curva_edad("peso_encogido", anios)
	var sentado := (bebe - encogido) * Datos.dymj_curva_edad("peso_sentado", anios)
	bebe -= encogido + sentado
	liso *= 1.0 - encogido - sentado
	return [[bebe, anciano, sin_mamas, encogido, sentado], liso]


func _drar_aplicar_pesos(formas: Array, pesos: Array, liso: float) -> void:
	for f in formas:
		var bebe: float = pesos[0]
		for i in [3, 4]:
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


func _drar_detalles_edad(raiz: Node3D, anios: float) -> void:
	var cabello := raiz.find_child("Cabello", true, false)
	if cabello:
		for malla in drar_mallas_de(cabello):
			if String(malla.name).contains("hair_loose"):
				malla.visible = anios >= float(Datos.edad.get("melena_desde", 3))
	var mamas := raiz.find_child("Mamas", true, false) as Node3D
	if mamas:
		mamas.visible = anios >= float(Datos.edad.get("mamas_desde", 11))


func drar_aplicar_edad_a(raiz: Node3D, formas: Array, anios: float) -> void:
	var pesos := _drar_pesos_edad(anios)
	_drar_aplicar_pesos(formas, pesos[0], pesos[1])
	raiz.scale = Vector3.ONE * Datos.dymj_curva_edad("altura_relativa", anios)
	_drar_detalles_edad(raiz, anios)


func drar_fijar_edad(anios: float, final := false) -> void:
	_edad_actual = anios
	var pesos := _drar_pesos_edad(anios)
	pesos_actuales = pesos[0]
	_drar_aplicar_pesos(_formas_edad, pesos[0], pesos[1])
	var escala := Datos.dymj_curva_edad("altura_relativa", anios)
	cuerpo.scale = Vector3.ONE * escala
	visuales.scale = Vector3.ONE * escala
	if _material_cabello:
		var gris := Color.from_string(Datos.edad.get("color_canas", "#cfcfcc"), Color.GRAY)
		_material_cabello.albedo_color = _color_cabello.lerp(gris, Datos.dymj_curva_edad("canas", anios))
	_drar_detalles_edad(cuerpo, anios)
	camara.drar_fijar_referencia(Vector3(_objetivo_adulto.x, _objetivo_adulto.y * escala, _objetivo_adulto.z),
			maxf(_distancia_adulto * lerpf(0.55, 1.0, escala), 0.8))
	for id in _sistemas:
		_cajas_sistemas[id] = _drar_caja_mundo(_sistemas[id])
	if final:
		_drar_actualizar_colisiones_edad(pesos[0])
		if _sistema_actual.is_empty() and _aislado.is_empty():
			camara.drar_encuadrar(camara.drar_objetivo_inicial(), camara.drar_distancia_inicial())
		elif _aislado.is_empty():
			_drar_encuadrar(_cajas_sistemas[_sistema_actual])


func drar_edad_actual() -> float:
	return _edad_actual


var _tarea_colisiones := -1
var _pendiente_colisiones: Array = []
var _trabajos: Array = []
var _resultados: Array = []
var _pesos_en_calculo: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


func _drar_actualizar_colisiones_edad(pesos: Array) -> void:
	if pesos == _pesos_colision:
		return
	if _tarea_colisiones != -1:
		_pendiente_colisiones = pesos
		return
	if not _cola_colisiones.is_empty():
		_pendiente_colisiones = pesos
		return
	_pesos_en_calculo = pesos
	_resultados.resize(_trabajos.size())
	_tarea_colisiones = WorkerThreadPool.add_group_task(_drar_calcular_colision, _trabajos.size(), -1, true,
			"Colisiones por edad")


var _cola_colisiones: Array = []
var _forma_de_malla: Dictionary = {}
const PRESUPUESTO_COLA_US := 10000


func _drar_procesar_cola(limite_us: int) -> void:
	var fin := Time.get_ticks_usec() + limite_us
	while not _cola_colisiones.is_empty() and Time.get_ticks_usec() < fin:
		_drar_crear_forma(_cola_colisiones.pop_back())
	if _cola_colisiones.is_empty() and not _pendiente_colisiones.is_empty():
		var p := _pendiente_colisiones
		_pendiente_colisiones = []
		_drar_actualizar_colisiones_edad(p)


func drar_completar_colisiones(ids: Array = []) -> void:
	_drar_completar_colisiones(ids)


func _drar_completar_colisiones(ids: Array) -> void:
	var resto := []
	for item in _cola_colisiones:
		if ids.is_empty() or item[2] in ids:
			_drar_crear_forma(item)
		else:
			resto.append(item)
	_cola_colisiones = resto
	if _cola_colisiones.is_empty() and not _pendiente_colisiones.is_empty():
		var p := _pendiente_colisiones
		_pendiente_colisiones = []
		_drar_actualizar_colisiones_edad(p)


func _drar_crear_forma(item: Array) -> void:
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
	nodo.shape = _drar_forma_con_pesos(trabajo, _pesos_colision)


func _drar_calcular_colision(k: int) -> void:
	_resultados[k] = _drar_forma_con_pesos(_trabajos[k], _pesos_en_calculo)


var pesos_actuales: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


func drar_trabajos_de(organo: Node3D) -> Array:
	var sistema: String = organo.get_meta("sistema", "")
	_drar_completar_colisiones([sistema])
	var mallas := drar_mallas_de(organo)
	return _trabajos.filter(func(t): return is_instance_valid(t[0]) and t[0].get_parent().get_parent() in mallas)


func drar_punto_deformado(t: Array, i: int) -> Vector3:
	var base: PackedVector3Array = t[1]
	var p := pesos_actuales
	var wb: float = p[0] + (p[3] if t[6] == base else 0.0) + (p[4] if t[7] == base else 0.0)
	var v: Vector3 = base[i] + (t[3][i] - base[i]) * wb + (t[4][i] - base[i]) * p[1] + (t[5][i] - base[i]) * p[2] \
			+ (t[6][i] - base[i]) * p[3] + (t[7][i] - base[i]) * p[4]
	var malla: MeshInstance3D = t[0].get_parent().get_parent()
	return malla.global_transform * v


func _drar_forma_con_pesos(t: Array, pesos: Array) -> ConcavePolygonShape3D:
	var base: PackedVector3Array = t[1]
	var indices: PackedInt32Array = t[2]
	var vb: PackedVector3Array = t[3]
	var va: PackedVector3Array = t[4]
	var vs: PackedVector3Array = t[5]
	var ve: PackedVector3Array = t[6]
	var vt: PackedVector3Array = t[7]
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


func _drar_revisar_tarea_colisiones() -> void:
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
		_drar_actualizar_colisiones_edad(p)


func drar_partes_de(id_organo: String) -> Array:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null or organo is MeshInstance3D:
		return []
	var lista := []
	for malla in drar_mallas_de(organo):
		var id := String(malla.name)
		var nombre := Datos.dymj_nombre_parte(id)
		lista.append([id, nombre if not nombre.is_empty() else id])
	lista.sort_custom(func(a, b): return a[1].naturalnocasecmp_to(b[1]) < 0)
	return lista


func drar_aislar(activo: bool) -> void:
	if activo and _organo_actual == null:
		return
	if activo == not _aislado.is_empty():
		return
	var bit := 1 << (CAPA_RENDER_AISLADA - 1)
	if activo:
		var objetivo: Node3D = _parte_actual if _parte_actual else _organo_actual
		_aislado = drar_mallas_de(objetivo)
		for malla in _aislado:
			malla.layers = bit
			malla.material_overlay = null
			for hijo in malla.get_children():
				if hijo is StaticBody3D:
					_colisiones_aisladas[hijo] = hijo.collision_layer
					hijo.collision_layer = bit
		camara.cull_mask = bit
		_vista_antes_de_aislar = [camara.yaw, camara.pitch, camara.distancia, camara.objetivo]
		camara.drar_permitir_acercamiento(true)
		_drar_encuadrar(_drar_caja_de_mallas(_aislado), 1.8)
	else:
		for malla in _aislado:
			if is_instance_valid(malla):
				malla.layers = 1
		for cuerpo_fisico in _colisiones_aisladas:
			if is_instance_valid(cuerpo_fisico):
				cuerpo_fisico.collision_layer = _colisiones_aisladas[cuerpo_fisico]
		_aislado.clear()
		_colisiones_aisladas.clear()
		_drar_actualizar_overlay_si(_organo_actual)
		camara.cull_mask = 0xFFFFF
		camara.drar_permitir_acercamiento(false)
		if not _vista_antes_de_aislar.is_empty():
			var v := _vista_antes_de_aislar
			camara.drar_animar_a(v[0], v[1], v[2], v[3])
			_vista_antes_de_aislar = []
	_drar_actualizar_marcador()
	aislamiento_cambiado.emit(activo)


func drar_esta_aislado() -> bool:
	return not _aislado.is_empty()


func drar_mostrar_sistema(id: String) -> void:
	drar_enfocar_sistema(id, TRANSPARENCIA_CONTEXTO)


func drar_enfocar_sistema(id: String, transparencia := TRANSPARENCIA_CONTEXTO) -> void:
	if not _sistemas.has(id):
		push_warning("Sistema desconocido: %s" % id)
		return
	_sistema_actual = id
	var retirar: Array = Datos.dymj_cubierto_por(id).duplicate()
	var dentro := []
	for otro in _sistemas:
		if otro != id and id in Datos.dymj_cubierto_por(otro) and not otro in retirar:
			dentro.append(otro)
	var fantasmas := {}
	for otro in _sistemas:
		if otro != id and not otro in retirar and not otro in dentro:
			fantasmas[otro] = transparencia
	_drar_completar_colisiones([id] + fantasmas.keys())
	capas.drar_retirar_solo(retirar + dentro, fantasmas, dentro)
	_drar_encuadrar(_cajas_sistemas[id])
	sistema_mostrado.emit(id)


func drar_mostrar_cuerpo_completo() -> void:
	_sistema_actual = ""
	capas.drar_restaurar_todo()
	camara.drar_encuadrar(camara.drar_objetivo_inicial(), camara.drar_distancia_inicial())
	sistema_mostrado.emit("")


func drar_mostrar_vista(vista: Dictionary) -> void:
	_sistema_actual = ""
	_drar_completar_colisiones(_sistemas.keys().filter(func(x): return not x in vista.get("capas_retiradas", [])))
	capas.drar_retirar_solo(vista.get("capas_retiradas", []), vista.get("capas_fantasma", {}))
	var encuadre: String = vista.get("encuadre", "cuerpo")
	var caja: AABB = _cajas_sistemas.get(encuadre, _caja_cuerpo)
	_drar_encuadrar(caja, vista.get("margen", 1.4), vista.get("subir_en_pantalla", 0.12))
	sistema_mostrado.emit("")


func drar_escalar_organo(id: String, escala: Vector3) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		return
	if organo is MeshInstance3D:
		capas.drar_fijar_escala_extra(organo, escala)
	else:
		organo.scale = escala


func drar_tenir_organo(id: String, color: Color, cantidad: float, manchas := 0.0) -> void:
	var organo: Node3D = _organos.get(id)
	if organo != null:
		_drar_tenir(organo, organo, color, cantidad, manchas)


func drar_tenir_partes(id_organo: String, claves: Array, color: Color, cantidad: float, manchas := 0.0) -> void:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null:
		return
	for malla in drar_mallas_de(organo):
		var nombre := String(malla.name).to_lower()
		if malla != organo and claves.any(func(c): return nombre.contains(String(c).to_lower())):
			_drar_tenir(malla, organo, color, cantidad, manchas)


func _drar_tenir(clave: Node3D, organo: Node3D, color: Color, cantidad: float, manchas: float) -> void:
	var tinte: ShaderMaterial = _tintes.get(clave)
	if cantidad <= 0.001:
		if tinte != null:
			_tintes.erase(clave)
			_drar_actualizar_overlay(organo)
		return
	if tinte == null:
		tinte = ShaderMaterial.new()
		tinte.shader = SHADER_TINTE
		_tintes[clave] = tinte
		_drar_actualizar_overlay(organo)
	tinte.set_shader_parameter("color_tinte", color)
	tinte.set_shader_parameter("cantidad", clampf(cantidad, 0.0, 1.0))
	tinte.set_shader_parameter("manchas", manchas)


func drar_organos_de_sistema(id_sistema: String) -> Array:
	var sistema: Node3D = _sistemas.get(id_sistema)
	if sistema == null:
		return []
	return sistema.get_children().filter(func(n): return _organos.has(String(n.name))) \
			.map(func(n): return String(n.name))


func drar_establecer_modo_fantasma(activo: bool) -> void:
	capas.drar_establecer_modo_fantasma(activo)


func drar_sistema_actual() -> String:
	return _sistema_actual


func drar_obtener_organo(id: String) -> Node3D:
	return _organos.get(id)


func drar_obtener_sistema(id: String) -> Node3D:
	return _sistemas.get(id)


func drar_sistema_de(id_organo: String) -> String:
	var organo: Node3D = _organos.get(id_organo)
	return organo.get_meta("sistema") if organo else ""


func drar_ids_organos() -> Array:
	return _organos.keys()


func drar_ids_partes() -> Array:
	var ids := []
	for organo in _organos.values():
		if not organo is MeshInstance3D:
			for malla in drar_mallas_de(organo):
				ids.append(String(malla.name))
	return ids


func drar_buscar_parte(id_organo: String, prefijo: String) -> Node3D:
	var organo: Node3D = _organos.get(id_organo)
	if organo == null or prefijo.is_empty():
		return null
	for malla in drar_mallas_de(organo):
		var n := String(malla.name)
		if n.begins_with(prefijo):
			return malla
	return null


static func drar_instanciar_cuerpo() -> Node3D:
	var ruta: String = Datos.dymj_cuerpo_activo().get("escena", "res://scenes/cuerpo_prueba.tscn")
	var escena := load(ruta) as PackedScene
	if escena == null:
		push_error("No se pudo cargar el cuerpo %s; se usa el procedural" % ruta)
		escena = load("res://scenes/cuerpo_prueba.tscn")
	var nodo: Node3D = escena.instantiate()
	nodo.name = "Cuerpo"
	return nodo


static func drar_mallas_de(nodo: Node) -> Array[MeshInstance3D]:
	var resultado: Array[MeshInstance3D] = []
	if nodo is MeshInstance3D:
		resultado.append(nodo)
	for n in nodo.find_children("*", "MeshInstance3D", true, false):
		resultado.append(n)
	return resultado


func _drar_indexar_cuerpo() -> void:
	for sistema in cuerpo.get_children():
		if not sistema is Node3D:
			continue
		if Datos.dymj_sistema(sistema.name).is_empty():
			push_warning("El nodo '%s' no está declarado en sistemas.json" % sistema.name)
		var id_sistema := String(sistema.name)
		_sistemas[id_sistema] = sistema
		_colisiones[id_sistema] = []
		for organo in sistema.get_children():
			if not organo is Node3D:
				continue
			organo.set_meta("sistema", id_sistema)
			_organos[String(organo.name)] = organo
			_colisiones[id_sistema].append_array(_drar_crear_colisiones(organo))
		_cajas_sistemas[id_sistema] = _drar_caja_mundo(sistema)
		_caja_cuerpo = _cajas_sistemas[id_sistema] if _caja_cuerpo.size == Vector3.ZERO \
				else _caja_cuerpo.merge(_cajas_sistemas[id_sistema])


func _drar_crear_colisiones(organo: Node3D) -> Array:
	var creados := []
	for malla in drar_mallas_de(organo):
		if malla.mesh == null or _drar_es_transparente(malla):
			continue
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


static func _drar_es_transparente(malla: MeshInstance3D) -> bool:
	var m := malla.get_active_material(0)
	return m is BaseMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


func _drar_caja_mundo(nodo: Node3D) -> AABB:
	var resultado := AABB()
	var primero := true
	for malla in drar_mallas_de(nodo):
		var caja: AABB = malla.global_transform * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado


func _drar_encuadrar(caja: AABB, margen_extra := 1.0, subir_en_pantalla := 0.0) -> void:
	var radio := caja.size.length() * 0.5
	var margen: float = Datos.animacion_capas.get("margen_encuadre", 0.9) * margen_extra
	var distancia := radio / sin(deg_to_rad(camara.fov * 0.5)) * margen
	camara.drar_encuadrar(caja.get_center() - Vector3(0, distancia * subir_en_pantalla, 0), distancia)


func _drar_on_capa_retirada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 0
	if id_sistema == CAPA_CERRADA:
		_drar_mostrar_interior(true)
	if _organo_actual and _organo_actual.get_meta("sistema") == id_sistema and _aislado.is_empty():
		drar_limpiar_seleccion()


func _drar_on_capa_restaurada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 1
	if id_sistema == CAPA_CERRADA:
		_drar_mostrar_interior(false)


var plano_corte := Vector4(0, 0, 0, INF)
var _interior_forzado := false


func drar_mostrar_interior_forzado(activo: bool) -> void:
	_interior_forzado = activo
	_drar_mostrar_interior(activo or CAPA_CERRADA in capas.drar_capas_retiradas())


func drar_caja_cuerpo_actual() -> AABB:
	return _drar_caja_mundo(cuerpo)


func _drar_mostrar_interior(visible_: bool) -> void:
	visible_ = visible_ or _interior_forzado
	for id in _sistemas:
		if id != CAPA_CERRADA:
			_sistemas[id].visible = visible_


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pos_cursor_pendiente = event.position if event.button_mask == 0 else Vector2.INF
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed:
		if event.pressed:
			_pos_presion = event.position
		elif _pos_presion != Vector2.INF:
			if event.position.distance_to(_pos_presion) <= UMBRAL_CLIC:
				_drar_seleccionar_en_pantalla(event.position)
			_pos_presion = Vector2.INF


func _process(_delta: float) -> void:
	if not _cola_colisiones.is_empty():
		_drar_procesar_cola(PRESUPUESTO_COLA_US)
	_drar_revisar_tarea_colisiones()
	var id := _organo_bajo_cursor
	var id_parte := _parte_bajo_cursor
	if get_viewport().gui_get_hovered_control() != null:
		id = ""
		id_parte = ""
	elif _pos_cursor_pendiente != Vector2.INF:
		var choque := _drar_objetivo_en(_pos_cursor_pendiente)
		id = String(choque.organo.name) if choque else ""
		id_parte = String(choque.parte.name) if choque and choque.parte else ""
		_pos_cursor_pendiente = Vector2.INF
	if id != _organo_bajo_cursor or id_parte != _parte_bajo_cursor:
		_organo_bajo_cursor = id
		_parte_bajo_cursor = id_parte
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id != "" else Input.CURSOR_ARROW)
		organo_bajo_cursor.emit(id, id_parte)


func _drar_seleccionar_en_pantalla(pos: Vector2) -> void:
	var choque := _drar_objetivo_en(pos)
	if choque == null:
		if _aislado.is_empty():
			drar_limpiar_seleccion()
		return
	drar_seleccionar_organo(String(choque.organo.name), true, choque.parte)


func _drar_objetivo_en(pos: Vector2) -> Choque:
	var desde := camara.project_ray_origin(pos)
	var hasta := desde + camara.project_ray_normal(pos) * LARGO_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	if not _aislado.is_empty():
		consulta.collision_mask = 1 << (CAPA_RENDER_AISLADA - 1)
	var resultado := get_world_3d().direct_space_state.intersect_ray(consulta)
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


func _drar_caja_de_mallas(mallas: Array[MeshInstance3D]) -> AABB:
	var resultado := AABB()
	var primero := true
	for malla in mallas:
		var caja := _drar_caja_real(malla)
		if caja.size == Vector3.ZERO and caja.position == Vector3.ZERO:
			continue
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado


func _drar_caja_real(malla: MeshInstance3D) -> AABB:
	for hijo in malla.get_children():
		if hijo is StaticBody3D and hijo.get_child_count() > 0:
			var forma = (hijo.get_child(0) as CollisionShape3D).shape
			if forma is ConcavePolygonShape3D:
				var caras: PackedVector3Array = forma.get_faces()
				if not caras.is_empty():
					var caja := AABB(caras[0], Vector3.ZERO)
					for k in range(0, caras.size(), maxi(1, caras.size() / 2000)):
						caja = caja.expand(caras[k])
					return malla.global_transform * caja
	return malla.global_transform * malla.get_aabb()


func _drar_actualizar_overlay_si(organo: Node3D) -> void:
	if organo != null:
		_drar_actualizar_overlay(organo)


func _drar_actualizar_overlay(organo: Node3D) -> void:
	var tinte: ShaderMaterial = _tintes.get(organo)
	var resaltadas: Array[MeshInstance3D] = []
	if organo == _organo_actual:
		resaltadas = drar_mallas_de(_parte_actual if _parte_actual else organo)
	var resaltado: Material = _material_rayos_x if _parte_actual else _material_resaltado
	for malla in drar_mallas_de(organo):
		if malla in resaltadas:
			malla.material_overlay = resaltado
		else:
			malla.material_overlay = _tintes.get(malla, tinte)
