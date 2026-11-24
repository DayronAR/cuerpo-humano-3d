class_name TarjetaRecorrido
extends PanelContainer
## Tarjeta de un recorrido en curso (abajo al centro): título, paso actual, explicación y botones
## Anterior / Siguiente / Salir. Solo muestra y emite señales.

signal anterior
signal siguiente
signal salir

var _titulo: Label
var _paso: Label
var _texto: Label
var _boton_anterior: Button
var _boton_siguiente: Button
var _barra_color: ColorRect


func _ready() -> void:
	hide()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.075, 0.105, 0.145, 0.94)
	estilo.set_corner_radius_all(12)
	estilo.content_margin_left = 18
	estilo.content_margin_right = 18
	estilo.content_margin_top = 12
	estilo.content_margin_bottom = 12
	estilo.shadow_color = Color(0, 0, 0, 0.35)
	estilo.shadow_size = 8
	add_theme_stylebox_override("panel", estilo)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	add_child(caja)
	var fila := HBoxContainer.new()
	caja.add_child(fila)
	_barra_color = ColorRect.new()
	_barra_color.custom_minimum_size = Vector2(6, 22)
	_barra_color.visible = false
	fila.add_child(_barra_color)
	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 17)
	_titulo.add_theme_color_override("font_color", Color(0.89, 0.925, 0.945, 1))
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(_titulo)
	_paso = Label.new()
	_paso.add_theme_font_size_override("font_size", 13)
	_paso.add_theme_color_override("font_color", Color(0.557, 0.639, 0.69, 1))
	fila.add_child(_paso)
	_texto = Label.new()
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(520, 0)
	_texto.add_theme_font_size_override("font_size", 15)
	_texto.add_theme_color_override("font_color", Color(0.89, 0.925, 0.945, 1))
	caja.add_child(_texto)
	var botones := HBoxContainer.new()
	botones.alignment = BoxContainer.ALIGNMENT_END
	botones.add_theme_constant_override("separation", 8)
	caja.add_child(botones)
	var b_salir := _boton("Salir", salir)
	botones.add_child(b_salir)
	var espacio := Control.new()
	espacio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	botones.add_child(espacio)
	_boton_anterior = _boton("◀  Anterior", anterior)
	botones.add_child(_boton_anterior)
	_boton_siguiente = _boton("Siguiente  ▶", siguiente)
	botones.add_child(_boton_siguiente)


func mostrar_paso(nombre: String, color: Color, numero: int, total: int, organo: String, texto: String) -> void:
	_titulo.text = nombre
	_barra_color.color = color
	_paso.text = "Paso %d de %d · %s" % [numero, total, organo]
	_texto.text = texto
	_boton_anterior.disabled = numero <= 1
	_boton_siguiente.text = "Terminar" if numero >= total else "Siguiente  ▶"
	show()
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, get_viewport_rect().size.y - size.y - 70)


func _boton(texto: String, senal: Signal) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 34)
	b.pressed.connect(func(): senal.emit())
	return b
