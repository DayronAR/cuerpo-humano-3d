extends SceneTree

var _iniciado := false


func _process(_d: float) -> bool:
	if not _iniciado:
		_iniciado = true
		_probar()
	return false


func _esp(t: float) -> void:
	await create_timer(t).timeout


func _probar() -> void:
	var cuerpo := OS.get_environment("CUERPO")
	root.get_node("Datos").cuerpo_elegido = cuerpo if not cuerpo.is_empty() else "zanatomy"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main._aviso_controles.hide()
	var v = main.get_node("BodyViewer")
	await _esp(1.0)
	for e in [0, 1, 6, 85, 30]:
		v.drar_fijar_edad(e, true)
		await _esp(0.3)
	print("edad ok")
	for s in ["Oseo", "Digestivo", "Nervioso", ""]:
		main._dymj_on_sistema_solicitado(s)
		await _esp(1.5)
	print("sistemas ok")
	for p in [["Estomago", "Estomago__Piloro"], ["Higado", "Higado__LobuloDerecho"], ["FemurDer", "FemurDer__Proximal"],
			["Tiroides", "Tiroides__Istmo"], ["IntestinoDelgado", "IntestinoDelgado__Ileon"]]:
		v.drar_ir_a_estructura(p[0], p[1])
		await _esp(1.0)
		if main._panel_ficha._titulo.text.is_empty():
			push_error("Sin ficha para " + p[1])
	v.drar_limpiar_seleccion()
	print("partes ok")
	var h = main._panel_herramientas
	h._corte.button_pressed = true
	await _esp(0.8)
	h.drar_apagar_corte()
	main._dymj_on_sistema_solicitado("Digestivo")
	await _esp(1.5)
	h._despiece.value = 0.6
	h._etiquetas.button_pressed = true
	await _esp(0.5)
	h._etiquetas.button_pressed = false
	main._dymj_on_sistema_solicitado("")
	await _esp(1.5)
	h._comparar.button_pressed = true
	await _esp(2.0)
	h._comparar.button_pressed = false
	print("herramientas ok")
	main._pestanas.current_tab = main._pestana_recorridos
	for i in Datos_recorridos(main):
		main._dymj_iniciar_recorrido(i)
		for _k in 3:
			main._tarjeta_recorrido.siguiente.emit()
		await _esp(0.6)
	main._dymj_terminar_recorrido()
	print("recorridos ok")
	main._pestanas.current_tab = 2
	var q = main._cuestionario
	for nivel in ["facil", "medio", "dificil"]:
		q.nivel = nivel
		q.dymj_iniciar()
		q.dymj_abandonar()
	print("preguntas ok")
	main._pestanas.current_tab = 1
	root.get_node("SimulationEngine").jlrl_seleccionar_escenario("fumar")
	main._panel_simulacion._barra_anios.value = 40
	await _esp(1.0)
	print("fumar ok")
	print("PRUEBA GENERAL: OK")
	quit()


func Datos_recorridos(_main) -> Array:
	return range(root.get_node("Datos").recorridos.size())
