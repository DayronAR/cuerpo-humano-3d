class_name RielNavegacion
extends PanelContainer
## Barra vertical de navegación (izquierda): logo, un botón con ícono por sección y, abajo, el
## botón para volver al inicio. Solo emite señales; la escena principal cambia de sección.

signal seccion_elegida(indice: int)
signal inicio_pulsado

const ANCHO := 64
const ACENTO := Color(0.173, 0.773, 0.71)

var _botones: Array[Button] = []


func _ready() -> void:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.055, 0.08, 0.11, 0.96)
	estilo.set_corner_radius_all(16)
	estilo.border_color = Color(1, 1, 1, 0.06)
	estilo.set_border_width_all(1)
	estilo.content_margin_top = 14
	estilo.content_margin_bottom = 14
	estilo.shadow_color = Color(0, 0, 0, 0.35)
	estilo.shadow_size = 10
	add_theme_stylebox_override("panel", estilo)
	custom_minimum_size = Vector2(ANCHO, 0)


## secciones: [[nombre, ruta del ícono], ...] en el orden de las pestañas.
func configurar(secciones: Array) -> void:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	caja.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(caja)
	var logo := TextureRect.new()
	logo.texture = load("res://ui/iconos/icono_64.png")
	logo.custom_minimum_size = Vector2(38, 38)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.tooltip_text = "Cuerpo Humano 3D"
	caja.add_child(logo)
	var separador := Control.new()
	separador.custom_minimum_size = Vector2(0, 10)
	caja.add_child(separador)
	var grupo := ButtonGroup.new()
	for i in secciones.size():
		var b := _boton(secciones[i][0], secciones[i][1])
		b.toggle_mode = true
		b.button_group = grupo
		b.pressed.connect(seccion_elegida.emit.bind(i))
		caja.add_child(b)
		_botones.append(b)
	var espacio := Control.new()
	espacio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(espacio)
	var inicio := _boton("Volver a la pantalla de inicio", "res://ui/iconos/barra/inicio.svg")
	inicio.pressed.connect(inicio_pulsado.emit)
	caja.add_child(inicio)


func marcar(indice: int) -> void:
	if indice >= 0 and indice < _botones.size():
		_botones[indice].set_pressed_no_signal(true)


func _boton(ayuda: String, icono: String) -> Button:
	var b := Button.new()
	b.icon = load(icono)
	b.expand_icon = true
	b.tooltip_text = ayuda
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_constant_override("icon_max_width", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.06)
	var activo := normal.duplicate()
	activo.bg_color = Color(ACENTO, 0.16)
	activo.border_color = ACENTO
	activo.border_width_left = 3
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", activo)
	b.add_theme_stylebox_override("hover_pressed", activo)
	b.add_theme_color_override("icon_normal_color", Color(0.56, 0.64, 0.69))
	b.add_theme_color_override("icon_hover_color", Color(0.89, 0.93, 0.95))
	b.add_theme_color_override("icon_pressed_color", ACENTO)
	b.add_theme_color_override("icon_hover_pressed_color", ACENTO)
	return b
