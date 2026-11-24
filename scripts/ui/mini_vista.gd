class_name MiniVista
extends PanelContainer

@onready var _contenedor: Node3D = %Personaje
@onready var _etiqueta: Label = %EtiquetaActividad

var _personaje: Node
var _actividad := ""
var _nombres_actividad: Dictionary = {}


func _ready() -> void:
	var ruta: String = Datos.visuales.get("personaje", {}).get("escena", "res://scenes/maniqui.tscn")
	var escena := load(ruta) as PackedScene
	if escena == null:
		push_error("MiniVista: no se pudo cargar el personaje %s" % ruta)
		return
	_personaje = escena.instantiate()
	_contenedor.add_child(_personaje)
	_nombres_actividad = Datos.simulacion.get("actividades", {})
	jlrl_al_actualizar_estado({"actividad": "reposo"})


var _vitales: Label


func jlrl_al_actualizar_estado(estado: Dictionary) -> void:
	if _vitales == null and _etiqueta:
		_vitales = Label.new()
		_vitales.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vitales.add_theme_font_size_override("font_size", 12)
		_vitales.add_theme_color_override("font_color", Color(0.557, 0.639, 0.69, 1))
		_etiqueta.get_parent().add_child(_vitales)
		_etiqueta.get_parent().move_child(_vitales, _etiqueta.get_index() + 1)
	if _vitales and estado.has("frecuencia_cardiaca"):
		_vitales.text = "♥ %d lpm   ·   🫁 %d rpm" % [roundi(estado["frecuencia_cardiaca"]),
				roundi(estado.get("frecuencia_respiratoria", 14))]
	var actividad: String = estado.get("actividad", "reposo")
	if actividad == _actividad or _personaje == null:
		return
	_actividad = actividad
	_personaje.jlrl_fijar_actividad(actividad)
	_etiqueta.text = _nombres_actividad.get(actividad, actividad)


func jlrl_al_cambiar_factor_tiempo(factor: float) -> void:
	if _personaje:
		_personaje.jlrl_fijar_factor_tiempo(factor)
