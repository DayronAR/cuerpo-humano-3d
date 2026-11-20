extends SceneTree
## Arma una escena de cuerpo (Cuerpo/<Sistema>/<Organo>) a partir de los .glb por sistema que
## exporta tools/procesar_modelo.py. Pensado para los modelos de Z-Anatomy.
##
## Uso (desde la raíz del proyecto):
##     godot --headless --path . --script res://tools/ensamblar_cuerpo_glb.gd
##     godot --headless --path . --script res://tools/ensamblar_cuerpo_glb.gd -- <carpeta_glb> <mapeo.json> <salida.tscn>
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

const CARPETA_MALLAS := "res://models/zanatomy"
const CARPETA_MATERIALES := "res://models/prueba/materiales"
const SISTEMAS_CON_SOMBRA := ["Piel", "Muscular", "Oseo"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var carpeta_glb: String = args[0] if args.size() > 0 else "res://assets_fuente/z-anatomy/glb"
	var ruta_mapeo: String = args[1] if args.size() > 1 else "res://tools/mapeo_zanatomy.json"
	var salida: String = args[2] if args.size() > 2 else "res://scenes/cuerpo_zanatomy.tscn"

	var mapeo = JSON.parse_string(FileAccess.get_file_as_string(ruta_mapeo))
	if not mapeo is Dictionary:
		push_error("No se pudo leer el mapeo " + ruta_mapeo)
		quit(1)
		return
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

		var mallas_gltf := estado.get_meshes()
		for nodo_gltf in estado.get_nodes():
			if nodo_gltf.mesh < 0:
				continue
			var nombre: String = nodo_gltf.original_name if not nodo_gltf.original_name.is_empty() \
					else nodo_gltf.resource_name
			var importador: ImporterMesh = mallas_gltf[nodo_gltf.mesh].mesh
			var material := _material(materiales.get(nombre, materiales.get(sistema, "")))
			for s in importador.get_surface_count():
				importador.set_surface_material(s, material)
			importador.generate_lods(25.0, 60.0, [])
			var malla := importador.get_mesh()
			var ruta_malla := "%s/%s_%s.res" % [CARPETA_MALLAS, sistema, nombre]
			ResourceSaver.save(malla, ruta_malla, ResourceSaver.FLAG_COMPRESS)
			# Se recarga desde disco para que la escena la referencie (y no la incruste)
			malla = ResourceLoader.load(ruta_malla, "", ResourceLoader.CACHE_MODE_REPLACE)

			var mi := MeshInstance3D.new()
			mi.name = nombre
			mi.mesh = malla
			mi.transform = nodo_gltf.xform
			if not sistema in SISTEMAS_CON_SOMBRA:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodo_sistema.add_child(mi)
			mi.owner = raiz
			var tris := 0
			for s in malla.get_surface_count():
				tris += malla.surface_get_array_index_len(s) / 3
			total += tris
			print("  %-14s %-24s %7d triángulos" % [sistema, nombre, tris])

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


func _material(nombre: String) -> Material:
	var ruta := "%s/%s.tres" % [CARPETA_MATERIALES, nombre]
	if nombre.is_empty() or not ResourceLoader.exists(ruta):
		push_warning("Material no encontrado: '%s'" % nombre)
		return null
	return load(ruta)
