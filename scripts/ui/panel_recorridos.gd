class_name PanelRecorridos
extends VBoxContainer

signal recorrido_elegido(indice: int)


func dymj_configurar(recorridos: Array) -> void:
	for hijo in get_children():
		hijo.queue_free()
	add_theme_constant_override("separation", 10)
	var intro := Label.new()
	intro.text = "Elige un recorrido: la cámara te lleva de órgano en órgano con una explicación corta."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(250, 0)
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", Color(0.557, 0.639, 0.69, 1))
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
		estilo.bg_color = Color(0.11, 0.153, 0.2)
		estilo.set_corner_radius_all(8)
		estilo.content_margin_left = 14
		estilo.content_margin_right = 8
		var hover := estilo.duplicate()
		hover.bg_color = Color(0.141, 0.196, 0.255)
		boton.add_theme_stylebox_override("normal", estilo)
		boton.add_theme_stylebox_override("hover", hover)
		boton.add_theme_stylebox_override("pressed", hover)
		boton.add_theme_color_override("font_color", Color(0.89, 0.925, 0.945, 1))
		boton.add_theme_color_override("font_hover_color", Color(0.89, 0.925, 0.945, 1))
		boton.pressed.connect(recorrido_elegido.emit.bind(i))
		add_child(boton)
