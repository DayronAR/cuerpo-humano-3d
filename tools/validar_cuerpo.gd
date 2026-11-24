extends SceneTree

const ESCENA_POR_DEFECTO := "res://scenes/cuerpo_prueba.tscn"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ruta: String = args[0] if args.size() > 0 else ESCENA_POR_DEFECTO
	var errores := 0
	var avisos := 0

	var sistemas := {}
	for s in _json("res://data/sistemas.json").get("sistemas", []):
		sistemas[s.get("id")] = s
	var fichas: Dictionary = _json("res://data/organos.json").get("organos", {})

	var escena: PackedScene = load(ruta)
	if escena == null:
		printerr("ERROR: no se pudo cargar ", ruta)
		quit(1)
		return
	var cuerpo := escena.instantiate()
	print("Validando ", ruta)

	var vistos_sistemas := {}
	var vistos_organos := {}
	for sistema in cuerpo.get_children():
		var id_s := String(sistema.name)
		vistos_sistemas[id_s] = true
		if not sistemas.has(id_s):
			printerr("  ERROR: sistema '%s' no está en data/sistemas.json" % id_s)
			errores += 1
		for organo in sistema.get_children():
			var id_o := String(organo.name)
			if vistos_organos.has(id_o):
				printerr("  ERROR: órgano repetido '%s' (en %s y %s)" % [id_o, vistos_organos[id_o], id_s])
				errores += 1
			vistos_organos[id_o] = id_s
			if not fichas.has(id_o):
				printerr("  ERROR: órgano '%s/%s' no tiene ficha en data/organos.json" % [id_s, id_o])
				errores += 1
			var mallas := organo.find_children("*", "MeshInstance3D", true, false)
			if not organo is MeshInstance3D and mallas.is_empty():
				printerr("  ERROR: órgano '%s/%s' no contiene ninguna MeshInstance3D" % [id_s, id_o])
				errores += 1

	for id_s in sistemas:
		if not vistos_sistemas.has(id_s):
			print("  AVISO: el sistema '%s' de sistemas.json no existe en la escena" % id_s)
			avisos += 1
	for id_o in fichas:
		if not vistos_organos.has(id_o):
			print("  AVISO: la ficha '%s' no corresponde a ningún nodo de la escena" % id_o)
			avisos += 1

	var visuales := _json("res://data/visuales.json")
	for clave in ["corazon", "pulmones"]:
		for id_o in visuales.get(clave, {}).get("organos", []):
			if not vistos_organos.has(id_o):
				printerr("  ERROR: visuales.json/%s usa el órgano '%s', que no existe" % [clave, id_o])
				errores += 1
	var sistema_musculos: String = visuales.get("musculos", {}).get("sistema", "")
	if not sistema_musculos.is_empty() and not vistos_sistemas.has(sistema_musculos):
		printerr("  ERROR: visuales.json/musculos usa el sistema '%s', que no existe" % sistema_musculos)
		errores += 1
	var simulacion := _json("res://data/escenarios.json")
	for esc in simulacion.get("escenarios", []):
		var vista: Dictionary = esc.get("vista", {})
		var usados: Array = vista.get("capas_retiradas", []) + vista.get("capas_fantasma", {}).keys()
		if vista.get("encuadre", "cuerpo") != "cuerpo":
			usados.append(vista["encuadre"])
		for id_s in usados:
			if not vistos_sistemas.has(id_s):
				printerr("  ERROR: escenario '%s' usa el sistema '%s', que no existe" % [esc.get("id"), id_s])
				errores += 1

	print("Sistemas: %d · Órganos: %d · Errores: %d · Avisos: %d" % [vistos_sistemas.size(), vistos_organos.size(), errores, avisos])
	cuerpo.free()
	quit(1 if errores > 0 else 0)


func _json(ruta: String) -> Dictionary:
	var datos = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return datos if datos is Dictionary else {}
