class_name MiniVista
extends PanelContainer
## Ventana pequeña (SubViewport con su propio mundo 3D) con una figura humana que camina o corre
## según la actividad que indica la simulación. La escena del personaje se lee de
## data/visuales.json (personaje.escena), así se cambia el maniquí por Mixamo sin tocar código.

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
	al_actualizar_estado({"actividad": "reposo"})


var _vitales: Label


## El maniquí cambia de animación según la actividad y debajo se muestran el pulso y la
## respiración que la simulación calcula para esa actividad (cambian juntos).
func al_actualizar_estado(estado: Dictionary) -> void:
	if _vitales == null and _etiqueta:
		_vitales = Label.new()
		_vitales.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vitales.add_theme_font_size_override("font_size", 12)
		_vitales.add_theme_color_override("font_color", Color(0.35, 0.42, 0.46))
		_etiqueta.get_parent().add_child(_vitales)
		_etiqueta.get_parent().move_child(_vitales, _etiqueta.get_index() + 1)
	if _vitales and estado.has("frecuencia_cardiaca"):
		_vitales.text = "♥ %d lpm   ·   🫁 %d rpm" % [roundi(estado["frecuencia_cardiaca"]),
				roundi(estado.get("frecuencia_respiratoria", 14))]
	var actividad: String = estado.get("actividad", "reposo")
	if actividad == _actividad or _personaje == null:
		return
	_actividad = actividad
	_personaje.fijar_actividad(actividad)
	_etiqueta.text = _nombres_actividad.get(actividad, actividad)


func al_cambiar_factor_tiempo(factor: float) -> void:
	if _personaje:
		_personaje.fijar_factor_tiempo(factor)
