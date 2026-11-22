class_name AvisoControles
extends PanelContainer
## Aviso con los controles de la cámara. Aparece solo la primera vez que se abre el visor (se
## recuerda en user://preferencias.cfg) o cuando se pide.

const RUTA := "user://preferencias.cfg"
const LINEAS := [
	["Clic", "seleccionar un órgano"],
	["Arrastrar", "girar el cuerpo"],
	["Rueda o pellizco", "acercar y alejar"],
	["Clic derecho o dos dedos", "desplazar"],
	["Centrar  (tecla C)", "volver a la vista inicial"],
]


func _ready() -> void:
	hide()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.075, 0.105, 0.145, 0.97)
	estilo.set_corner_radius_all(14)
	estilo.border_color = Color(0.173, 0.773, 0.71, 0.6)
	estilo.set_border_width_all(1)
	estilo.content_margin_left = 20
	estilo.content_margin_right = 20
	estilo.content_margin_top = 14
	estilo.content_margin_bottom = 14
	estilo.shadow_color = Color(0, 0, 0, 0.4)
	estilo.shadow_size = 12
	add_theme_stylebox_override("panel", estilo)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	add_child(caja)
	var titulo := Label.new()
	titulo.text = "Cómo moverte por el cuerpo"
	titulo.add_theme_font_size_override("font_size", 16)
	caja.add_child(titulo)
	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 18)
	rejilla.add_theme_constant_override("v_separation", 4)
	caja.add_child(rejilla)
	for l in LINEAS:
		var a := Label.new()
		a.text = l[0]
		a.theme_type_variation = "TextoAcento"
		rejilla.add_child(a)
		var b := Label.new()
		b.text = l[1]
		rejilla.add_child(b)
	var boton := Button.new()
	boton.text = "Entendido"
	boton.focus_mode = Control.FOCUS_NONE
	boton.size_flags_horizontal = Control.SIZE_SHRINK_END
	boton.pressed.connect(_cerrar)
	caja.add_child(boton)


func mostrar_si_es_la_primera_vez() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	if not cfg.get_value("ayuda", "vista_vista", false):
		mostrar()


func mostrar() -> void:
	show()
	reset_size()
	var pantalla := get_viewport_rect().size
	position = Vector2((pantalla.x - size.x) * 0.5, pantalla.y - size.y - 90)


func _cerrar() -> void:
	hide()
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	cfg.set_value("ayuda", "vista_vista", true)
	cfg.save(RUTA)
