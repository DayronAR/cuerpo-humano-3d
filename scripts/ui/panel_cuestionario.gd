class_name PanelCuestionario
extends VBoxContainer
## Interfaz del cuestionario: muestra preguntas, retroalimentación y resultado.
## Solo emite lo que pulsa el usuario; la lógica está en Cuestionario.

signal comenzar_pulsado
signal siguiente_pulsado
signal saltar_pulsado
signal nivel_elegido(id_nivel: String)

const VERDE := Color(0.36, 0.85, 0.55)
const ROJO := Color(0.98, 0.45, 0.45)
const ACENTO := Color(0.173, 0.773, 0.71, 1)

@onready var _record: Label = %Record
@onready var _inicio: VBoxContainer = %Inicio
@onready var _juego: VBoxContainer = %Juego
@onready var _progreso: Label = %Progreso
@onready var _barra: ProgressBar = %Barra
@onready var _pregunta: Label = %Pregunta
@onready var _retro: Label = %Retro
@onready var _puntos: Label = %Puntos
@onready var _boton_saltar: Button = %BotonSaltar
@onready var _boton_siguiente: Button = %BotonSiguiente
@onready var _boton_comenzar: Button = %BotonComenzar


var _nivel := "facil"
var _botones_nivel := {}
var _descripcion_nivel: Label


## niveles: [{id, nombre, descripcion}, ...] (data/cuestionario.json). Crea los botones de nivel.
func configurar_niveles(niveles: Array) -> void:
	if niveles.is_empty():
		return
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	var grupo := ButtonGroup.new()
	for n in niveles:
		var b := Button.new()
		b.text = n.get("nombre", n.get("id"))
		b.toggle_mode = true
		b.button_group = grupo
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.pressed.connect(_elegir_nivel.bind(n))
		fila.add_child(b)
		_botones_nivel[n.get("id")] = b
	_descripcion_nivel = Label.new()
	_descripcion_nivel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_descripcion_nivel.custom_minimum_size = Vector2(240, 0)
	_descripcion_nivel.add_theme_font_size_override("font_size", 13)
	_descripcion_nivel.add_theme_color_override("font_color", Color(0.557, 0.639, 0.69, 1))
	_inicio.add_child(fila)
	_inicio.add_child(_descripcion_nivel)
	_inicio.move_child(fila, _boton_comenzar.get_index())
	_inicio.move_child(_descripcion_nivel, _boton_comenzar.get_index())
	_botones_nivel[niveles[0].get("id")].button_pressed = true
	_elegir_nivel(niveles[0])


func _elegir_nivel(n: Dictionary) -> void:
	_nivel = n.get("id", "facil")
	_descripcion_nivel.text = n.get("descripcion", "")
	nivel_elegido.emit(_nivel)
	_actualizar_record()


func _ready() -> void:
	_boton_comenzar.pressed.connect(comenzar_pulsado.emit)
	_boton_siguiente.pressed.connect(siguiente_pulsado.emit)
	_boton_saltar.pressed.connect(saltar_pulsado.emit)
	mostrar_inicio()


func mostrar_inicio() -> void:
	_inicio.visible = true
	_juego.visible = false
	_boton_comenzar.text = "Comenzar"
	_actualizar_record()


func mostrar_pregunta(numero: int, total: int, texto: String, puntaje: int) -> void:
	_inicio.visible = false
	_juego.visible = true
	_progreso.text = "Pregunta %d de %d" % [numero, total]
	_barra.max_value = total
	_barra.value = numero - 1
	_pregunta.text = texto
	_puntos.text = "Puntos: %d" % puntaje
	_retro.text = "Haz clic sobre el órgano en el cuerpo."
	_retro.add_theme_color_override("font_color", ACENTO)
	_boton_saltar.visible = true
	_boton_siguiente.visible = false


func mostrar_resultado(correcta: bool, nombre_respondido: String, nombre_correcto: String, puntos: int,
		puntaje: int, restantes: int, racha := 0) -> void:
	_puntos.text = "Puntos: %d" % puntaje
	if correcta:
		_retro.text = "¡Correcto! +%d puntos" % puntos
		if racha >= 3:
			_retro.text += "\n🔥 Racha de %d aciertos seguidos" % racha
		_retro.add_theme_color_override("font_color", VERDE)
	elif restantes > 0:
		_retro.text = "Ese es: %s. Inténtalo otra vez (%d intento%s más)." % [nombre_respondido, restantes,
				"" if restantes == 1 else "s"]
		_retro.add_theme_color_override("font_color", ROJO)
		return
	elif nombre_respondido.is_empty():
		_retro.text = "Pregunta saltada. La respuesta era: %s (resaltado)." % nombre_correcto
		_retro.add_theme_color_override("font_color", ROJO)
	else:
		_retro.text = "Era: %s (resaltado en el cuerpo)." % nombre_correcto
		_retro.add_theme_color_override("font_color", ROJO)
	_barra.value += 1
	_boton_saltar.visible = false
	_boton_siguiente.visible = true


func mostrar_final(puntaje: int, maximo: int, es_record: bool) -> void:
	_inicio.visible = true
	_juego.visible = false
	_boton_comenzar.text = "Jugar otra vez"
	_actualizar_record()
	var texto := "Obtuviste %d de %d puntos." % [puntaje, maximo]
	if es_record:
		texto += "\n¡Nuevo récord!"
	%Resultado.text = texto
	%Resultado.visible = true


func _actualizar_record() -> void:
	var mejor := RegistroPuntajes.mejor_puntaje(_nivel)
	var nombre: String = _botones_nivel[_nivel].text if _botones_nivel.has(_nivel) else ""
	var sufijo := " (%s)" % nombre if not nombre.is_empty() else ""
	_record.text = "Mejor puntaje%s: %d de %d" % [sufijo, mejor.puntaje, mejor.total] if mejor.total > 0 \
			else "Mejor puntaje%s: aún no hay partidas" % sufijo
