class_name PanelRecorridos
extends VBoxContainer
## Pestaña "Recorridos": lista de recorridos guiados. Al elegir uno emite la señal; la escena
## principal lo ejecuta paso a paso (ver TarjetaRecorrido).

signal recorrido_elegido(indice: int)


func configurar(recorridos: Array) -> void:
	for hijo in get_children():
		hijo.queue_free()
	add_theme_constant_override("separation", 10)
	var intro := Label.new()
	intro.text = "Elige un recorrido: la cámara te lleva de órgano en órgano con una explicación corta."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(250, 0)
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", Color(0.3, 0.38, 0.42))
	add_child(intro)
	for i in recorridos.size():
		var r: Dictionary = recorridos[i]
		var boton := Button.new()
		boton.focus_mode = Control.FOCUS_NONE
		boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
		boton.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		boton.custom_minimum_size = Vector2(250, 62)
		boton.text = "%s\n%s" % [r.get("nombre", ""), r.get("descripcion", "")]
		boton.add_theme_font_size_override("font_size", 14)
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0.95, 0.97, 0.98)
		estilo.set_corner_radius_all(8)
		estilo.border_width_left = 5
		estilo.border_color = Color.from_string(r.get("color", "#2a7f9e"), Color.TEAL)
		estilo.content_margin_left = 14
		estilo.content_margin_right = 8
		var hover := estilo.duplicate()
		hover.bg_color = Color(0.88, 0.94, 0.97)
		boton.add_theme_stylebox_override("normal", estilo)
		boton.add_theme_stylebox_override("hover", hover)
		boton.add_theme_stylebox_override("pressed", hover)
		boton.add_theme_color_override("font_color", Color(0.12, 0.2, 0.25))
		boton.add_theme_color_override("font_hover_color", Color(0.12, 0.2, 0.25))
		boton.pressed.connect(recorrido_elegido.emit.bind(i))
		add_child(boton)
