extends SceneTree
## Arma una escena de cuerpo (Cuerpo/<Sistema>/<Organo>) a partir de los .glb por sistema que
## exporta tools/procesar_modelo.py. Pensado para los modelos de Z-Anatomy.
##
## Uso (desde la raíz del proyecto):
##     godot --headless --path . --script res://tools/ensamblar_cuerpo_glb.gd
##     godot --headless --path . --script res://tools/ensamblar_cuerpo_glb.gd -- <carpeta_glb> <mapeo.json> <salida.tscn> <carpeta_mallas>
##
## Por defecto:
##     carpeta_glb = res://assets_fuente/z-anatomy/glb   (fuera de la importación de Godot: .gdignore)
##     mapeo       = res://tools/mapeo_zanatomy.json     (orden de sistemas y materiales)
##     salida      = res://scenes/cuerpo_zanatomy.tscn
##
## Qué hace:
##   - Lee cada .glb con GLTFDocument (no hace falta que Godot lo importe).
##   - Genera niveles de detalle (LOD) para cada órgano.
##   - Asigna los materiales de la paleta del proyecto (models/prueba/materiales/).
##   - Guarda las mallas en res://models/zanatomy/ y la escena final.
##   - Solo piel, músculos y huesos proyectan sombra (rendimiento).

var CARPETA_MALLAS := "res://models/zanatomy"
const CARPETA_MATERIALES := "res://models/prueba/materiales"
const SISTEMAS_CON_SOMBRA := ["Piel"]   ## Con cientos de partes, solo la piel proyecta sombra


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var carpeta_glb: String = args[0] if args.size() > 0 else "res://assets_fuente/z-anatomy/glb"
	var ruta_mapeo: String = args[1] if args.size() > 1 else "res://tools/mapeo_zanatomy.json"
	var salida: String = args[2] if args.size() > 2 else "res://scenes/cuerpo_zanatomy.tscn"
	if args.size() > 3:
		CARPETA_MALLAS = args[3]

	var mapeo = JSON.parse_string(FileAccess.get_file_as_string(ruta_mapeo))
	if not mapeo is Dictionary:
		push_error("No se pudo leer el mapeo " + ruta_mapeo)
		quit(1)
		return
	if mapeo.has("hereda"):   # Mapeo derivado (p. ej. el femenino): se combina con su base
		mapeo = _mezclar(JSON.parse_string(FileAccess.get_file_as_string("res://" + mapeo["hereda"])), mapeo)
	var materiales: Dictionary = mapeo.get("materiales", {})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA_MALLAS))

	var raiz := Node3D.new()
	raiz.name = "Cuerpo"
	var total := 0
	for sistema in mapeo.get("sistemas", {}):
		var ruta_glb := ProjectSettings.globalize_path(carpeta_glb.path_join(sistema + ".glb"))
		if not FileAccess.file_exists(ruta_glb):
			push_warning("No existe %s; se omite el sistema" % ruta_glb)
			continue
		var documento := GLTFDocument.new()
		var estado := GLTFState.new()
		if documento.append_from_file(ruta_glb, estado) != OK:
			push_error("No se pudo leer " + ruta_glb)
			continue
		var nodo_sistema := Node3D.new()
		nodo_sistema.name = sistema
		raiz.add_child(nodo_sistema)
		nodo_sistema.owner = raiz

		var nodos_gltf := estado.get_nodes()
		for i in nodos_gltf.size():
			if nodos_gltf[i].parent == -1:
				total += _crear_nodo(estado, i, nodo_sistema, raiz, sistema, materiales, materiales.get(sistema, ""))

	var escena := PackedScene.new()
	var error := escena.pack(raiz)
	if error == OK:
		error = ResourceSaver.save(escena, salida)
	raiz.free()
	if error != OK:
		push_error("No se pudo guardar %s (%d)" % [salida, error])
		quit(1)
		return
	print("Cuerpo ensamblado en %s · %d triángulos" % [salida, total])
	quit()


## Crea el nodo glTF i (órgano o parte) bajo "padre" y, recursivamente, sus hijos.
## Un nodo sin malla es un órgano con partes (Node3D en el centro del órgano).
## Devuelve los triángulos agregados.
func _crear_nodo(estado: GLTFState, i: int, padre: Node3D, raiz: Node3D, sistema: String,
		materiales: Dictionary, material_heredado: String) -> int:
	var nodo_gltf: GLTFNode = estado.get_nodes()[i]
	var nombre: String = nodo_gltf.original_name if not nodo_gltf.original_name.is_empty() \
			else nodo_gltf.resource_name
	# Material: el del órgano si está en la lista; si no, el heredado (sistema u órgano padre)
	var nombre_organo := nombre.get_slice("__", 0)
	var material_nombre: String = materiales.get(nombre_organo, material_heredado)
	for clave in materiales:   # Material propio de una parte: clave "Organo__prefijo_de_parte"
		if String(clave).contains("__") and nombre.begins_with(clave):
			material_nombre = materiales[clave]
	var nodo: Node3D
	var tris := 0
	if nodo_gltf.mesh >= 0:
		var importador: ImporterMesh = estado.get_meshes()[nodo_gltf.mesh].mesh
		var material := _material(material_nombre)
		for s in importador.get_surface_count():
			importador.set_surface_material(s, material)
		importador.generate_lods(25.0, 60.0, [])
		var malla := importador.get_mesh()
		var ruta_malla := "%s/%s_%s.res" % [CARPETA_MALLAS, sistema, nombre]
		ResourceSaver.save(malla, ruta_malla, ResourceSaver.FLAG_COMPRESS)
		# Se recarga desde disco para que la escena la referencie (y no la incruste)
		malla = ResourceLoader.load(ruta_malla, "", ResourceLoader.CACHE_MODE_REPLACE)
		var mi := MeshInstance3D.new()
		mi.mesh = malla
		if not sistema in SISTEMAS_CON_SOMBRA:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodo = mi
		for s in malla.get_surface_count():
			tris += malla.surface_get_array_index_len(s) / 3
	else:
		nodo = Node3D.new()
	nodo.name = nombre
	nodo.transform = nodo_gltf.xform
	padre.add_child(nodo)
	nodo.owner = raiz
	for hijo in nodo_gltf.children:
		tris += _crear_nodo(estado, hijo, nodo, raiz, sistema, materiales, material_nombre)
	if padre.get_parent() == raiz:
		print("  %-14s %-26s %4d partes %8d triángulos" % [sistema, nombre, nodo_gltf.children.size(), tris])
	return tris


## Igual que mezclar() de tools/procesar_modelo.py: diccionarios se combinan, null elimina la clave.
func _mezclar(base: Dictionary, cambios: Dictionary) -> Dictionary:
	var resultado := base.duplicate()
	for k in cambios:
		if cambios[k] == null:
			resultado.erase(k)
		elif cambios[k] is Dictionary and resultado.get(k) is Dictionary and not String(k).begins_with("_"):
			resultado[k] = _mezclar(resultado[k], cambios[k])
		else:
			resultado[k] = cambios[k]
	return resultado


func _material(nombre: String) -> Material:
	var ruta := "%s/%s.tres" % [CARPETA_MATERIALES, nombre]
	if nombre.is_empty() or not ResourceLoader.exists(ruta):
		push_warning("Material no encontrado: '%s'" % nombre)
		return null
	return load(ruta)
