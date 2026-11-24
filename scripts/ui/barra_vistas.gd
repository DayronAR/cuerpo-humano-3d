class_name BarraVistas
extends HBoxContainer

signal vista_solicitada(id_vista: String)
signal centrar_solicitado

const AYUDA := "Clic: seleccionar órgano\nArrastrar: girar\nRueda o pellizco: zoom\nClic derecho, Mayús+arrastrar o dos dedos: desplazar"


func drar_configurar(vistas: Array) -> void:
	for hijo in get_children():
		hijo.queue_free()
	for v in vistas:
		var boton := Button.new()
		boton.text = v.get("nombre", v.get("id", "?"))
		boton.tooltip_text = v.get("tooltip", "")
		boton.focus_mode = Control.FOCUS_NONE
		boton.custom_minimum_size = Vector2(86, 34)
		boton.pressed.connect(vista_solicitada.emit.bind(v.get("id", "")))
		add_child(boton)
	var centrar := Button.new()
	centrar.text = "Centrar"
	centrar.icon = load("res://ui/iconos/barra/centrar.svg")
	centrar.expand_icon = false
	centrar.add_theme_constant_override("icon_max_width", 18)
	centrar.tooltip_text = "Vuelve a la vista inicial del cuerpo (también con la tecla C)"
	centrar.focus_mode = Control.FOCUS_NONE
	centrar.custom_minimum_size = Vector2(104, 34)
	centrar.pressed.connect(centrar_solicitado.emit)
	add_child(centrar)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		centrar_solicitado.emit()
