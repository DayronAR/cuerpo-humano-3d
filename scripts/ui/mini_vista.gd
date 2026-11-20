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


func al_actualizar_estado(estado: Dictionary) -> void:
	var actividad: String = estado.get("actividad", "reposo")
	if actividad == _actividad or _personaje == null:
		return
	_actividad = actividad
	_personaje.fijar_actividad(actividad)
	_etiqueta.text = _nombres_actividad.get(actividad, actividad)


func al_cambiar_factor_tiempo(factor: float) -> void:
	if _personaje:
		_personaje.fijar_factor_tiempo(factor)
