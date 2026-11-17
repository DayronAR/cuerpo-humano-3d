extends SceneTree
## Valida que la escena del cuerpo cumpla la convención de nombres y que los datos JSON coincidan.
## Úsalo cada vez que cambies data/*.json o reemplaces primitivas por modelos .glb.
##
##     godot --headless --path . --script res://tools/validar_cuerpo.gd
##     godot --headless --path . --script res://tools/validar_cuerpo.gd -- res://scenes/otro_cuerpo.tscn
##
## Termina con código 1 si hay errores (útil para automatizar).

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

	print("Sistemas: %d · Órganos: %d · Errores: %d · Avisos: %d" % [vistos_sistemas.size(), vistos_organos.size(), errores, avisos])
	cuerpo.free()
	quit(1 if errores > 0 else 0)


func _json(ruta: String) -> Dictionary:
	var datos = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return datos if datos is Dictionary else {}
