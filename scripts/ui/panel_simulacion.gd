class_name PanelSimulacion
extends VBoxContainer
## Controles de la simulación (escenario, iniciar/pausar/reiniciar, velocidad, intensidad) y
## lectura de los valores actuales. Emite señales con lo que pide el usuario y muestra lo que
## le llega; no modifica el motor directamente.

signal escenario_elegido(id_escenario: String)
signal iniciar_pulsado
signal pausar_pulsado
signal reiniciar_pulsado
signal velocidad_elegida(velocidad: float)
signal intensidad_elegida(id_intensidad: String)

const VELOCIDADES := [1.0, 2.0, 4.0]
const COLOR_TEXTO := Color(0.89, 0.925, 0.945, 1)
const COLOR_SUAVE := Color(0.557, 0.639, 0.69, 1)
const COLOR_ACENTO := Color(0.173, 0.773, 0.71, 1)

@onready var _escenarios: HBoxContainer = %Escenarios
@onready var _descripcion: Label = %Descripcion
@onready var _fila_intensidad: VBoxContainer = %FilaIntensidad
@onready var _intensidades: HBoxContainer = %Intensidades
@onready var _boton_iniciar: Button = %BotonIniciar
@onready var _boton_pausar: Button = %BotonPausar
@onready var _boton_reiniciar: Button = %BotonReiniciar
@onready var _velocidades: HBoxContainer = %Velocidades
@onready var _valores: GridContainer = %Valores
@onready var _estados: Label = %Estados
@onready var _actividad: Label = %Actividad

var _datos_escenarios: Dictionary = {}     ## id -> Dictionary
var _botones_escenario: Dictionary = {}
var _botones_intensidad: Dictionary = {}
var _botones_velocidad: Dictionary = {}
var _etiquetas_valor: Dictionary = {}     ## id de variable -> Label
var _variables: Dictionary = {}
var _info_estados: Dictionary = {}
var _actividades: Dictionary = {}
var _escenario := ""
var _intensidad := ""
var _activo := false
var _pausado := false


func _ready() -> void:
	_boton_iniciar.pressed.connect(iniciar_pulsado.emit)
	_boton_pausar.pressed.connect(pausar_pulsado.emit)
	_boton_reiniciar.pressed.connect(reiniciar_pulsado.emit)
	var grupo := ButtonGroup.new()
	for v in VELOCIDADES:
		var b := _boton("x%d" % v, true, grupo)
		b.tooltip_text = "Velocidad de la simulación"
		b.pressed.connect(velocidad_elegida.emit.bind(v))
		_velocidades.add_child(b)
		_botones_velocidad[v] = b
	_botones_velocidad[1.0].button_pressed = true


## datos: contenido de escenarios.json
func configurar(datos: Dictionary) -> void:
	_variables = datos.get("variables", {})
	_actividades = datos.get("actividades", {})
	for e in datos.get("estados", []):
		_info_estados[e.get("id")] = e
	var grupo := ButtonGroup.new()
	for e in datos.get("escenarios", []):
		var id: String = e.get("id")
		_datos_escenarios[id] = e
		var b := _boton(e.get("nombre", id), true, grupo)
		b.tooltip_text = e.get("descripcion", "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(escenario_elegido.emit.bind(id))
		_escenarios.add_child(b)
		_botones_escenario[id] = b
	# Una fila por variable visible: nombre (con su color) y valor
	for id in _variables:
		var info: Dictionary = _variables[id]
		if info.get("interna", false):
			continue
		var nombre := Label.new()
		nombre.text = info.get("nombre", id)
		nombre.tooltip_text = "%s (%s)" % [info.get("nombre", id), info.get("unidad", "")]
		nombre.mouse_filter = Control.MOUSE_FILTER_PASS
		nombre.add_theme_color_override("font_color", COLOR_SUAVE)
		nombre.add_theme_font_size_override("font_size", 13)
		nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var marca := ColorRect.new()
		marca.color = Color.from_string(info.get("color", "#888888"), Color.GRAY)
		marca.custom_minimum_size = Vector2(8, 8)
		marca.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var valor := Label.new()
		valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		valor.add_theme_color_override("font_color", COLOR_TEXTO)
		valor.add_theme_font_size_override("font_size", 14)
		_valores.add_child(marca)
		_valores.add_child(nombre)
		_valores.add_child(valor)
		_etiquetas_valor[id] = valor
	mostrar_escenario("", false)
	mostrar_estados([])


func mostrar_estado(estado: Dictionary) -> void:
	for id in _etiquetas_valor:
		var info: Dictionary = _variables[id]
		var formato := "%." + str(int(info.get("decimales", 0))) + "f %s"
		_etiquetas_valor[id].text = formato % [float(estado.get(id, 0.0)), info.get("unidad", "")]
	_actividad.text = "Actividad: " + _actividades.get(estado.get("actividad", "reposo"), "")


func mostrar_estados(estados: Array) -> void:
	if estados.is_empty():
		_estados.text = "Estado: normal"
		_estados.add_theme_color_override("font_color", Color(0.36, 0.85, 0.55))
		_estados.tooltip_text = ""
		return
	var nombres := []
	var descripciones := []
	for id in estados:
		nombres.append(_info_estados.get(id, {}).get("nombre", id))
		descripciones.append(_info_estados.get(id, {}).get("descripcion", ""))
	_estados.text = "Estado: " + ", ".join(nombres)
	_estados.tooltip_text = "\n".join(descripciones)
	var color: String = _info_estados.get(estados[0], {}).get("color", "#bc4749")
	_estados.add_theme_color_override("font_color", Color.from_string(color, Color.RED))


func mostrar_escenario(id: String, activo: bool) -> void:
	for clave in _botones_escenario:
		_botones_escenario[clave].set_pressed_no_signal(clave == id)
	var e: Dictionary = _datos_escenarios.get(id, {})
	_descripcion.text = e.get("descripcion", "Elige un escenario y pulsa Iniciar.")
	var cambio := id != _escenario or _botones_intensidad.is_empty()
	_escenario = id
	_activo = activo
	_actualizar_botones()
	if not cambio:
		return
	# Botones de intensidad del escenario (caminar / trotar / correr)
	for hijo in _intensidades.get_children():
		hijo.queue_free()
	_botones_intensidad.clear()
	var intensidades: Array = e.get("intensidades", [])
	_fila_intensidad.visible = not intensidades.is_empty()
	var grupo := ButtonGroup.new()
	for i in intensidades:
		var b := _boton(i.get("nombre", i.get("id")), true, grupo)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(intensidad_elegida.emit.bind(i.get("id")))
		_intensidades.add_child(b)
		_botones_intensidad[i.get("id")] = b
	mostrar_intensidad(_intensidad)


func mostrar_intensidad(id: String) -> void:
	_intensidad = id
	for clave in _botones_intensidad:
		_botones_intensidad[clave].set_pressed_no_signal(clave == id)


func mostrar_pausa(pausado: bool) -> void:
	_pausado = pausado
	_actualizar_botones()


func _actualizar_botones() -> void:
	_boton_pausar.disabled = _pausado
	_boton_pausar.text = "⏸  En pausa" if _pausado else "⏸  Pausar"
	if _pausado:
		_boton_iniciar.disabled = false
		_boton_iniciar.text = "▶  Reanudar"
	elif _activo:
		_boton_iniciar.disabled = true
		_boton_iniciar.text = "▶  En curso"
	else:
		_boton_iniciar.disabled = _escenario.is_empty()
		_boton_iniciar.text = "▶  Iniciar"


func mostrar_velocidad(velocidad: float) -> void:
	for v in _botones_velocidad:
		_botones_velocidad[v].set_pressed_no_signal(is_equal_approx(v, velocidad))


func _boton(texto: String, alternable: bool, grupo: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = texto
	b.toggle_mode = alternable
	b.button_group = grupo
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	return b
