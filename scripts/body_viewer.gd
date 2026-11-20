class_name BodyViewer
extends Node3D
## Visor 3D del cuerpo: cámara, luces y el nodo "Cuerpo".
##
## Responsabilidades:
##   - Indexar el cuerpo según la convención Cuerpo/<Sistema>/<Organo>.
##   - Crear colisiones en tiempo de ejecución para poder seleccionar con un rayo
##     (funciona igual con primitivas que con modelos .glb).
##   - Detectar clics (sin confundirlos con arrastres de cámara) y resaltar el órgano elegido.
##   - Mostrar un sistema: pedir al GestorCapas que retire las capas que lo cubren, desactivar
##     la selección de las capas retiradas y encuadrar el sistema con la cámara.
## No sabe nada de la interfaz: solo emite señales que escucha la escena principal.

signal organo_seleccionado(id_organo: String, id_sistema: String)
signal seleccion_limpiada
signal sistema_mostrado(id_sistema: String)   ## "" = cuerpo completo
signal organo_bajo_cursor(id_organo: String)  ## "" = ninguno (para mostrar su nombre al pasar)

## Distancia máxima (en píxeles) entre presionar y soltar para considerar que fue un clic
const UMBRAL_CLIC := 6.0
const LARGO_RAYO := 100.0
const CAPA_CERRADA := "Piel"   ## Capa que envuelve todo el cuerpo (ver _mostrar_interior)
const SHADER_RESALTADO := preload("res://shaders/resaltado.gdshader")
const SHADER_TINTE := preload("res://shaders/tinte.gdshader")

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
var _tintes: Dictionary = {}          ## Node3D del órgano -> ShaderMaterial de tinte
var _organo_actual: Node3D = null
var _material_resaltado: ShaderMaterial
var _pos_presion := Vector2.INF
var _pos_cursor_pendiente := Vector2.INF   ## Última posición del mouse aún sin consultar
var _organo_bajo_cursor := ""


func _ready() -> void:
	_material_resaltado = ShaderMaterial.new()
	_material_resaltado.shader = SHADER_RESALTADO
	camara.configurar(Datos.camara)
	cuerpo = BodyViewer.instanciar_cuerpo()
	add_child(cuerpo)
	_indexar_cuerpo()
	capas.configurar(_sistemas, Datos.orden_capas, Datos.animacion_capas, camara, _caja_cuerpo.get_center())
	capas.capa_retirada.connect(_on_capa_retirada)
	capas.capa_restaurada.connect(_on_capa_restaurada)
	visuales.configurar(self, Datos.visuales)
	_mostrar_interior(false)


# --- API pública --------------------------------------------------------------

## emitir = false: solo resalta (lo usa el cuestionario para mostrar la respuesta correcta).
func seleccionar_organo(id: String, emitir := true) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		push_warning("Órgano desconocido: %s" % id)
		return
	if organo == _organo_actual:
		return
	var anterior := _organo_actual
	_organo_actual = organo
	_actualizar_overlay_si(anterior)
	_actualizar_overlay(organo)
	if emitir:
		organo_seleccionado.emit(id, organo.get_meta("sistema"))


func limpiar_seleccion() -> void:
	if _organo_actual == null:
		return
	var anterior := _organo_actual
	_organo_actual = null
	_actualizar_overlay(anterior)
	seleccion_limpiada.emit()


## Retira las capas que cubren el sistema (según sistemas.json) y lo encuadra con la cámara.
func mostrar_sistema(id: String) -> void:
	if not _sistemas.has(id):
		push_warning("Sistema desconocido: %s" % id)
		return
	_sistema_actual = id
	capas.retirar_solo(Datos.cubierto_por(id))
	_encuadrar(_cajas_sistemas[id])
	sistema_mostrado.emit(id)


## Muestra un sistema dejando todos los demás sistemas internos como fantasma, para que nada
## tape a sus órganos (lo usa el cuestionario). Los fantasmas no se pueden seleccionar.
func enfocar_sistema(id: String, transparencia := 0.85) -> void:
	if not _sistemas.has(id):
		return
	_sistema_actual = id
	var retirar: Array = Datos.cubierto_por(id)
	var fantasmas := {}
	for otro in _sistemas:
		if otro != id and not otro in retirar:
			fantasmas[otro] = transparencia
	capas.retirar_solo(retirar, fantasmas)
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
		for parte in organo.get_children():
			if parte is Node3D:
				capas.fijar_escala_extra(parte, escala)


## Tiñe un órgano con un color semitransparente encima de su material (cantidad 0 = sin tinte).
func tenir_organo(id: String, color: Color, cantidad: float) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		return
	var tinte: ShaderMaterial = _tintes.get(organo)
	if cantidad <= 0.001:
		if tinte != null:
			_tintes.erase(organo)
			_actualizar_overlay(organo)
		return
	if tinte == null:
		tinte = ShaderMaterial.new()
		tinte.shader = SHADER_TINTE
		_tintes[organo] = tinte
		_actualizar_overlay(organo)
	tinte.set_shader_parameter("color_tinte", color)
	tinte.set_shader_parameter("cantidad", clampf(cantidad, 0.0, 1.0))


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
		if malla.mesh == null:
			continue
		var cuerpo_fisico := StaticBody3D.new()
		cuerpo_fisico.name = "Colision"
		cuerpo_fisico.set_meta("organo", organo)
		var forma := CollisionShape3D.new()
		forma.shape = malla.mesh.create_trimesh_shape()
		cuerpo_fisico.add_child(forma)
		malla.add_child(cuerpo_fisico)
		creados.append(cuerpo_fisico)
	return creados


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
	if _organo_actual and _organo_actual.get_meta("sistema") == id_sistema:
		limpiar_seleccion()


func _on_capa_restaurada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 1
	if id_sistema == CAPA_CERRADA:
		_mostrar_interior(false)


## Optimización: mientras la piel (superficie cerrada y opaca) está completa, nada de su interior
## se ve, así que no se dibuja. Reduce mucho los triángulos por cuadro en GPU integradas.
func _mostrar_interior(visible_: bool) -> void:
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
	# Una consulta por cuadro como máximo, aunque lleguen muchos eventos de movimiento
	var id := _organo_bajo_cursor
	if get_viewport().gui_get_hovered_control() != null:
		id = ""
	elif _pos_cursor_pendiente != Vector2.INF:
		var organo := _organo_en(_pos_cursor_pendiente)
		id = String(organo.name) if organo else ""
		_pos_cursor_pendiente = Vector2.INF
	if id != _organo_bajo_cursor:
		_organo_bajo_cursor = id
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id != "" else Input.CURSOR_ARROW)
		organo_bajo_cursor.emit(id)


func _seleccionar_en_pantalla(pos: Vector2) -> void:
	var organo := _organo_en(pos)
	if organo == null:
		limpiar_seleccion()
		return
	seleccionar_organo(String(organo.name))


## Órgano visible bajo un punto de la pantalla (rayo físico), o null.
func _organo_en(pos: Vector2) -> Node3D:
	var desde := camara.project_ray_origin(pos)
	var hasta := desde + camara.project_ray_normal(pos) * LARGO_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	var choque := get_world_3d().direct_space_state.intersect_ray(consulta)
	if choque.is_empty() or not choque.collider.has_meta("organo"):
		return null
	return choque.collider.get_meta("organo")


func _actualizar_overlay_si(organo: Node3D) -> void:
	if organo != null:
		_actualizar_overlay(organo)


## Compone la capa superior de un órgano: tinte de simulación y/o resaltado de selección.
## Si hay ambos, el resaltado se encadena como "next_pass" del tinte.
func _actualizar_overlay(organo: Node3D) -> void:
	var tinte: ShaderMaterial = _tintes.get(organo)
	var seleccionado := organo == _organo_actual
	var overlay: Material = null
	if tinte != null:
		tinte.next_pass = _material_resaltado if seleccionado else null
		overlay = tinte
	elif seleccionado:
		overlay = _material_resaltado
	for malla in mallas_de(organo):
		malla.material_overlay = overlay
