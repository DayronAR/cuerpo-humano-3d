class_name BodyViewer
extends Node3D
## Visor 3D del cuerpo: cámara, luces y el nodo "Cuerpo".
##
## Responsabilidades:
##   - Indexar el cuerpo según la convención Cuerpo/<Sistema>/<Organo>.
##   - Crear colisiones en tiempo de ejecución para poder seleccionar con un rayo
##     (funciona igual con primitivas que con modelos .glb).
##   - Detectar clics (sin confundirlos con arrastres de cámara) y resaltar el órgano elegido.
## No sabe nada de la interfaz: solo emite señales que escucha la escena principal.

signal organo_seleccionado(id_organo: String, id_sistema: String)
signal seleccion_limpiada

## Distancia máxima (en píxeles) entre presionar y soltar para considerar que fue un clic
const UMBRAL_CLIC := 6.0
const LARGO_RAYO := 100.0
const SHADER_RESALTADO := preload("res://shaders/resaltado.gdshader")

@onready var camara: CamaraOrbital = $Camara
@onready var cuerpo: Node3D = $Cuerpo

var _organos: Dictionary = {}       ## id -> Node3D del órgano
var _sistemas: Dictionary = {}      ## id -> Node3D del sistema
var _organo_actual: Node3D = null
var _material_resaltado: ShaderMaterial
var _pos_presion := Vector2.INF


func _ready() -> void:
	_material_resaltado = ShaderMaterial.new()
	_material_resaltado.shader = SHADER_RESALTADO
	camara.configurar(Datos.camara)
	_indexar_cuerpo()


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
		_sistemas[String(sistema.name)] = sistema
		for organo in sistema.get_children():
			if not organo is Node3D:
				continue
			organo.set_meta("sistema", String(sistema.name))
			_organos[String(organo.name)] = organo
			_crear_colisiones(organo)


func _crear_colisiones(organo: Node3D) -> void:
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
