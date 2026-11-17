class_name BarraVistas
extends HBoxContainer
## Botones de vista rápida (Frente, Espalda, ...). Se generan desde la lista de vistas de
## res://data/camara.json y emiten una señal; no controlan la cámara directamente.

signal vista_solicitada(id_vista: String)


func configurar(vistas: Array) -> void:
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
