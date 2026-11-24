class_name PanelSimulacion
extends VBoxContainer

signal escenario_elegido(id_escenario: String)
signal iniciar_pulsado
signal pausar_pulsado
signal reiniciar_pulsado
signal velocidad_elegida(velocidad: float)
signal intensidad_elegida(id_intensidad: String)
signal anios_cambiados(anios: float)

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

var _datos_escenarios: Dictionary = {}
var _botones_escenario: Dictionary = {}
var _botones_intensidad: Dictionary = {}
var _botones_velocidad: Dictionary = {}
var _etiquetas_valor: Dictionary = {}
var _variables: Dictionary = {}
var _info_estados: Dictionary = {}
var _actividades: Dictionary = {}
var _escenario := ""
var _intensidad := ""
var _activo := false
var _pausado := false
var _deterioro: VBoxContainer
var _barra_anios: HSlider
var _valor_anios: Label
var _lista_danos: VBoxContainer
var _danos: Array = []


func _ready() -> void:
	_boton_iniciar.pressed.connect(iniciar_pulsado.emit)
	_boton_pausar.pressed.connect(pausar_pulsado.emit)
	_boton_reiniciar.pressed.connect(reiniciar_pulsado.emit)
	var grupo := ButtonGroup.new()
	for v in VELOCIDADES:
		var b := _jlrl_boton("x%d" % v, true, grupo)
		b.tooltip_text = "Velocidad de la simulación"
		b.pressed.connect(velocidad_elegida.emit.bind(v))
		_velocidades.add_child(b)
		_botones_velocidad[v] = b
	_botones_velocidad[1.0].button_pressed = true


func jlrl_configurar(datos: Dictionary) -> void:
	_variables = datos.get("variables", {})
	_actividades = datos.get("actividades", {})
	for e in datos.get("estados", []):
		_info_estados[e.get("id")] = e
	var grupo := ButtonGroup.new()
	for e in datos.get("escenarios", []):
		var id: String = e.get("id")
		_datos_escenarios[id] = e
		var b := _jlrl_boton(e.get("nombre", id), true, grupo)
		b.tooltip_text = e.get("descripcion", "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(escenario_elegido.emit.bind(id))
		_escenarios.add_child(b)
		_botones_escenario[id] = b
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
	jlrl_mostrar_escenario("", false)
	jlrl_mostrar_estados([])


func jlrl_mostrar_estado(estado: Dictionary) -> void:
	for id in _etiquetas_valor:
		var info: Dictionary = _variables[id]
		var formato := "%." + str(int(info.get("decimales", 0))) + "f %s"
		_etiquetas_valor[id].text = formato % [float(estado.get(id, 0.0)), info.get("unidad", "")]
	_actividad.text = "Actividad: " + _actividades.get(estado.get("actividad", "reposo"), "")


func jlrl_mostrar_estados(estados: Array) -> void:
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


func jlrl_mostrar_escenario(id: String, activo: bool) -> void:
	for clave in _botones_escenario:
		_botones_escenario[clave].set_pressed_no_signal(clave == id)
	var e: Dictionary = _datos_escenarios.get(id, {})
	_descripcion.text = e.get("descripcion", "Elige un escenario y pulsa Iniciar.")
	var cambio := id != _escenario or _botones_intensidad.is_empty()
	_escenario = id
	_activo = activo
	_jlrl_actualizar_botones()
	if not cambio:
		return
	for hijo in _intensidades.get_children():
		hijo.queue_free()
	_botones_intensidad.clear()
	var intensidades: Array = e.get("intensidades", [])
	_fila_intensidad.visible = not intensidades.is_empty()
	var grupo := ButtonGroup.new()
	for i in intensidades:
		var b := _jlrl_boton(i.get("nombre", i.get("id")), true, grupo)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(intensidad_elegida.emit.bind(i.get("id")))
		_intensidades.add_child(b)
		_botones_intensidad[i.get("id")] = b
	jlrl_mostrar_intensidad(_intensidad)
	_jlrl_armar_deterioro(e.get("deterioro", {}))


func _jlrl_armar_deterioro(d: Dictionary) -> void:
	if _deterioro:
		_deterioro.queue_free()
		_deterioro = null
	_danos = d.get("danos", [])
	anios_cambiados.emit(0.0)
	if d.is_empty():
		return
	_deterioro = VBoxContainer.new()
	_deterioro.add_theme_constant_override("separation", 6)
	add_child(_deterioro)
	move_child(_deterioro, _fila_intensidad.get_index() + 1)
	var fila := HBoxContainer.new()
	_deterioro.add_child(fila)
	var titulo := Label.new()
	titulo.text = d.get("titulo", "AÑOS")
	titulo.add_theme_color_override("font_color", COLOR_ACENTO)
	titulo.add_theme_font_size_override("font_size", 15)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(titulo)
	_valor_anios = Label.new()
	_valor_anios.add_theme_color_override("font_color", COLOR_TEXTO)
	fila.add_child(_valor_anios)
	var ayuda := Label.new()
	ayuda.text = d.get("ayuda", "")
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.custom_minimum_size = Vector2(240, 0)
	ayuda.add_theme_color_override("font_color", COLOR_SUAVE)
	ayuda.add_theme_font_size_override("font_size", 12)
	_deterioro.add_child(ayuda)
	_barra_anios = HSlider.new()
	_barra_anios.min_value = 0
	_barra_anios.max_value = float(d.get("anios_max", 40))
	_barra_anios.step = 1
	_barra_anios.focus_mode = Control.FOCUS_NONE
	_barra_anios.custom_minimum_size = Vector2(0, 24)
	_barra_anios.value_changed.connect(_jlrl_al_cambiar_anios)
	_deterioro.add_child(_barra_anios)
	_lista_danos = VBoxContainer.new()
	_lista_danos.add_theme_constant_override("separation", 4)
	_deterioro.add_child(_lista_danos)
	var dejar := Label.new()
	dejar.text = d.get("dejar", "")
	dejar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dejar.custom_minimum_size = Vector2(240, 0)
	dejar.add_theme_color_override("font_color", Color(0.36, 0.85, 0.55))
	dejar.add_theme_font_size_override("font_size", 12)
	_deterioro.add_child(dejar)
	_jlrl_al_cambiar_anios(0.0)


func _jlrl_al_cambiar_anios(anios: float) -> void:
	_valor_anios.text = "Nunca" if anios <= 0.0 else ("%d año%s" % [anios, "" if anios == 1 else "s"])
	for hijo in _lista_danos.get_children():
		hijo.queue_free()
	for dano in _danos:
		if anios < float(dano.get("desde", 0)):
			continue
		var l := Label.new()
		l.text = "•  " + dano.get("texto", "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(240, 0)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(1.0, 0.5, 0.47) if dano.get("grave", false) else COLOR_TEXTO)
		_lista_danos.add_child(l)
	anios_cambiados.emit(anios)


func jlrl_mostrar_intensidad(id: String) -> void:
	_intensidad = id
	for clave in _botones_intensidad:
		_botones_intensidad[clave].set_pressed_no_signal(clave == id)


func jlrl_mostrar_pausa(pausado: bool) -> void:
	_pausado = pausado
	_jlrl_actualizar_botones()


func _jlrl_actualizar_botones() -> void:
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


func jlrl_mostrar_velocidad(velocidad: float) -> void:
	for v in _botones_velocidad:
		_botones_velocidad[v].set_pressed_no_signal(is_equal_approx(v, velocidad))


func _jlrl_boton(texto: String, alternable: bool, grupo: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = texto
	b.toggle_mode = alternable
	b.button_group = grupo
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	return b
