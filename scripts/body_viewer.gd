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

## Distancia máxima (en píxeles) entre presionar y soltar para considerar que fue un clic
const UMBRAL_CLIC := 6.0
const LARGO_RAYO := 100.0
const SHADER_RESALTADO := preload("res://shaders/resaltado.gdshader")

@onready var camara: CamaraOrbital = $Camara
@onready var cuerpo: Node3D = $Cuerpo
@onready var capas: GestorCapas = $GestorCapas

var _organos: Dictionary = {}       ## id -> Node3D del órgano
var _sistemas: Dictionary = {}      ## id -> Node3D del sistema
var _colisiones: Dictionary = {}    ## id de sistema -> Array[StaticBody3D]
var _cajas_sistemas: Dictionary = {}  ## id de sistema -> AABB en el mundo (posición original)
var _caja_cuerpo := AABB()
var _sistema_actual := ""
var _organo_actual: Node3D = null
var _material_resaltado: ShaderMaterial
var _pos_presion := Vector2.INF


func _ready() -> void:
	_material_resaltado = ShaderMaterial.new()
	_material_resaltado.shader = SHADER_RESALTADO
	camara.configurar(Datos.camara)
	_indexar_cuerpo()
	capas.configurar(_sistemas, Datos.orden_capas, Datos.animacion_capas, camara, _caja_cuerpo.get_center())
	capas.capa_retirada.connect(_on_capa_retirada)
	capas.capa_restaurada.connect(_on_capa_restaurada)


# --- API pública --------------------------------------------------------------

func seleccionar_organo(id: String) -> void:
	var organo: Node3D = _organos.get(id)
	if organo == null:
		push_warning("Órgano desconocido: %s" % id)
		return
	if organo == _organo_actual:
		return
	_resaltar(_organo_actual, false)
	_organo_actual = organo
	_resaltar(organo, true)
	organo_seleccionado.emit(id, organo.get_meta("sistema"))


func limpiar_seleccion() -> void:
	if _organo_actual == null:
		return
	_resaltar(_organo_actual, false)
	_organo_actual = null
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


## Restaura todas las capas y vuelve a encuadrar el cuerpo entero.
func mostrar_cuerpo_completo() -> void:
	_sistema_actual = ""
	capas.restaurar_todo()
	camara.encuadrar(camara.objetivo_inicial(), camara.distancia_inicial())
	sistema_mostrado.emit("")


func establecer_modo_fantasma(activo: bool) -> void:
	capas.establecer_modo_fantasma(activo)


func sistema_actual() -> String:
	return _sistema_actual


func obtener_organo(id: String) -> Node3D:
	return _organos.get(id)


func obtener_sistema(id: String) -> Node3D:
	return _sistemas.get(id)


func ids_organos() -> Array:
	return _organos.keys()


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
func _encuadrar(caja: AABB) -> void:
	var radio := caja.size.length() * 0.5
	var margen: float = Datos.animacion_capas.get("margen_encuadre", 0.9)
	var distancia := radio / sin(deg_to_rad(camara.fov * 0.5)) * margen
	camara.encuadrar(caja.get_center(), distancia)


# --- Reacción a las capas ----------------------------------------------------------

func _on_capa_retirada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 0   # El rayo de selección ya no lo encuentra
	if _organo_actual and _organo_actual.get_meta("sistema") == id_sistema:
		limpiar_seleccion()


func _on_capa_restaurada(id_sistema: String) -> void:
	for cuerpo_fisico in _colisiones.get(id_sistema, []):
		cuerpo_fisico.collision_layer = 1


# --- Entrada -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed:
		if event.pressed:
			_pos_presion = event.position
		elif _pos_presion != Vector2.INF:
			if event.position.distance_to(_pos_presion) <= UMBRAL_CLIC:
				_seleccionar_en_pantalla(event.position)
			_pos_presion = Vector2.INF


func _seleccionar_en_pantalla(pos: Vector2) -> void:
	var desde := camara.project_ray_origin(pos)
	var hasta := desde + camara.project_ray_normal(pos) * LARGO_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	var choque := get_world_3d().direct_space_state.intersect_ray(consulta)
	if choque.is_empty() or not choque.collider.has_meta("organo"):
		limpiar_seleccion()
		return
	var organo: Node3D = choque.collider.get_meta("organo")
	seleccionar_organo(String(organo.name))


func _resaltar(organo: Node3D, activo: bool) -> void:
	if organo == null:
		return
	for malla in mallas_de(organo):
		malla.material_overlay = _material_resaltado if activo else null
