extends Node3D
## Personaje de Mixamo para la mini vista (preparado para cuando tengamos el .glb).
##
## Cumple el mismo contrato que maniqui.gd:
##     fijar_actividad(actividad: String)  y  fijar_factor_tiempo(factor: float)
##
## Uso:
##   1. Importar el .glb con las animaciones (ver README, "Personaje de Mixamo").
##   2. Crear res://scenes/personaje_mixamo.tscn: un Node3D con ESTE script y, como hijo,
##      la escena del .glb (que contiene un AnimationPlayer).
##   3. En data/visuales.json -> personaje.escena = "res://scenes/personaje_mixamo.tscn" y
##      revisar personaje.animaciones (actividad -> nombre de la animación en el .glb).

var _reproductor: AnimationPlayer
var _animaciones: Dictionary = {}
var _transicion := 0.3
var _actividad := ""


func _ready() -> void:
	var cfg: Dictionary = Datos.visuales.get("personaje", {})
	_animaciones = cfg.get("animaciones", {})
	_transicion = cfg.get("transicion", 0.3)
	var encontrados := find_children("*", "AnimationPlayer", true, false)
	if encontrados.is_empty():
		push_error("personaje_mixamo: no se encontró un AnimationPlayer dentro del personaje")
		return
	_reproductor = encontrados[0]
	# Las animaciones de Mixamo deben repetirse en bucle
	for nombre in _reproductor.get_animation_list():
		_reproductor.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	fijar_actividad("reposo")


func fijar_actividad(actividad: String) -> void:
	if _reproductor == null or actividad == _actividad:
		return
	var nombre: String = _animaciones.get(actividad, "")
	var disponible := _buscar_animacion(nombre)
	if disponible.is_empty():
		push_warning("personaje_mixamo: no hay animación para '%s' (buscada: '%s')" % [actividad, nombre])
		return
	_actividad = actividad
	_reproductor.play(disponible, _transicion)


func fijar_factor_tiempo(factor: float) -> void:
	if _reproductor:
		_reproductor.speed_scale = factor


## Las animaciones importadas pueden venir como "Running" o "Armature|Running": se aceptan ambas.
func _buscar_animacion(nombre: String) -> String:
	if nombre.is_empty():
		return ""
	for a in _reproductor.get_animation_list():
		if a == nombre or a.ends_with("|" + nombre) or a.ends_with("/" + nombre):
			return a
	return ""
