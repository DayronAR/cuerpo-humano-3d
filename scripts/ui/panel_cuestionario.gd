class_name PanelCuestionario
extends VBoxContainer
## Interfaz del cuestionario: muestra preguntas, retroalimentación y resultado.
## Solo emite lo que pulsa el usuario; la lógica está en Cuestionario.

signal comenzar_pulsado
signal siguiente_pulsado
signal saltar_pulsado

const VERDE := Color(0.17, 0.55, 0.35)
const ROJO := Color(0.74, 0.28, 0.29)
const ACENTO := Color(0.06, 0.43, 0.55)

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
		puntaje: int, restantes: int) -> void:
	_puntos.text = "Puntos: %d" % puntaje
	if correcta:
		_retro.text = "¡Correcto! +%d puntos" % puntos
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
	var mejor := RegistroPuntajes.mejor_puntaje()
	_record.text = "Mejor puntaje: %d de %d" % [mejor.puntaje, mejor.total] if mejor.total > 0 \
			else "Mejor puntaje: aún no hay partidas"
