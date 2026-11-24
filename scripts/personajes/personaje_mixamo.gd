extends Node3D

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
	for nombre in _reproductor.get_animation_list():
		_reproductor.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	jlrl_fijar_actividad("reposo")


func jlrl_fijar_actividad(actividad: String) -> void:
	if _reproductor == null or actividad == _actividad:
		return
	var nombre: String = _animaciones.get(actividad, "")
	var disponible := _jlrl_buscar_animacion(nombre)
	if disponible.is_empty() and actividad != "reposo":
		push_warning("personaje_mixamo: falta '%s' para '%s'; se usa la de reposo" % [nombre, actividad])
		disponible = _jlrl_buscar_animacion(_animaciones.get("reposo", ""))
	if disponible.is_empty():
		push_warning("personaje_mixamo: no hay animación para '%s' (buscada: '%s')" % [actividad, nombre])
		return
	_actividad = actividad
	_reproductor.play(disponible, _transicion)


func jlrl_fijar_factor_tiempo(factor: float) -> void:
	if _reproductor:
		_reproductor.speed_scale = factor


func _jlrl_buscar_animacion(nombre: String) -> String:
	if nombre.is_empty():
		return ""
	for a in _reproductor.get_animation_list():
		if a == nombre or a.ends_with("|" + nombre) or a.ends_with("/" + nombre):
			return a
	return ""
