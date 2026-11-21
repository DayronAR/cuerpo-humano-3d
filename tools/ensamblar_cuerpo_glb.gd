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
	# Formas de mezcla por edad (data/edad.json): altura del adulto y si es el cuerpo femenino
	_edad = JSON.parse_string(FileAccess.get_file_as_string("res://data/edad.json")).get("deformacion", {})
	_altura = ALTURA_BASE * float(mapeo.get("escala", 1.0))
	_femenino = ruta_mapeo.contains("femenino")
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
				total += _crear_nodo(estado, i, nodo_sistema, raiz, sistema, materiales, materiales.get(sistema, ""),
						Transform3D.IDENTITY)

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
		materiales: Dictionary, material_heredado: String, global_padre: Transform3D) -> int:
	var nodo_gltf: GLTFNode = estado.get_nodes()[i]
	var global := global_padre * nodo_gltf.xform
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
		importador = _con_formas_de_edad(importador, material, global)
		if not SIN_LOD:
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
		tris += _crear_nodo(estado, hijo, nodo, raiz, sistema, materiales, material_nombre, global)
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


# --- Formas de mezcla por edad ----------------------------------------------------------

var SIN_LOD := OS.get_environment("SIN_LOD") == "1"
const ALTURA_BASE := 1.743   ## Estatura del cuerpo masculino de Z-Anatomy (m); se multiplica por la escala
var _edad: Dictionary = {}
var _altura := ALTURA_BASE
var _femenino := false


## Copia la malla agregando las formas "Bebe" y "Anciano" (posiciones deformadas de cada vértice).
## La deformación se calcula en coordenadas del cuerpo y se devuelve al espacio local de la malla.
func _con_formas_de_edad(origen: ImporterMesh, material: Material, global: Transform3D) -> ImporterMesh:
	var inversa := global.affine_inverse()
	var nuevo := ImporterMesh.new()
	nuevo.set_blend_shape_mode(Mesh.BLEND_SHAPE_MODE_NORMALIZED)   # Formas con posiciones absolutas
	nuevo.add_blend_shape("Bebe")
	nuevo.add_blend_shape("Anciano")
	nuevo.add_blend_shape("SinMamas")   # Pecho plano de la infancia (solo cambia en el cuerpo femenino)
	for s in origen.get_surface_count():
		var arrays := origen.get_surface_arrays(s)
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cantidad := base.size()
		var normales_base: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var rot := global.basis
		var rot_inv := rot.inverse()
		var formas := []
		for forma in ["bebe", "anciano", "sin_mamas"]:
			var v := PackedVector3Array()
			var nn := PackedVector3Array()
			v.resize(base.size())
			nn.resize(base.size())
			for k in base.size():
				var p := global * base[k]
				v[k] = inversa * _deformar(p, forma)
				# Normal: se transforma con la inversa transpuesta de la jacobiana de la deformación.
				# Depende solo del punto y de la normal original, así que es idéntica en los bordes
				# compartidos entre piezas (la piel no muestra costuras).
				var j := _jacobiana(p, forma)
				nn[k] = normales_base[k] if absf(j.determinant()) < 1e-6 \
						else (rot_inv * (j.inverse().transposed() * (rot * normales_base[k]))).normalized()
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = v
			a[Mesh.ARRAY_NORMAL] = nn
			a[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
			formas.append(a)
		# Godot comprime las formas de mezcla respecto de la caja (AABB) de la malla base: si un
		# vértice deformado sale de esa caja, queda recortado. Se agregan dos vértices sin usar
		# (no están en los índices) en las esquinas de la caja que incluye todas las formas.
		var caja := AABB(base[0], Vector3.ZERO)
		for v in base:
			caja = caja.expand(v)
		for a in formas:
			for v in a[Mesh.ARRAY_VERTEX]:
				caja = caja.expand(v)
		for tipo in range(Mesh.ARRAY_MAX):
			if tipo == Mesh.ARRAY_INDEX or arrays[tipo] == null:
				continue
			var datos = arrays[tipo]
			var por_vertice: int = datos.size() / cantidad
			for esquina in 2:
				for c in por_vertice:
					datos.append(datos[c])
			arrays[tipo] = datos
		var vb: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vb[cantidad] = caja.position
		vb[cantidad + 1] = caja.end
		arrays[Mesh.ARRAY_VERTEX] = vb
		for a in formas:
			var va: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			va.append(caja.position)
			va.append(caja.end)
			a[Mesh.ARRAY_VERTEX] = va
			var na: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			na.append(Vector3.UP)
			na.append(Vector3.UP)
			a[Mesh.ARRAY_NORMAL] = na
			a[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		nuevo.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, formas, {}, material, origen.get_surface_name(s))
	return nuevo


## Lo que sobresale por delante del plano del tórax se lleva hacia ese plano (máximo suave,
## sin cambios bruscos que distorsionen la iluminación).
func _aplanar_pecho(p: Vector3) -> Vector3:
	var d: Dictionary = _edad.get("bebe", {})
	var pared: float = d.get("pared_torax", 0.085)
	for pz in d.get("pezones", []):
		var dist := Vector2(absf(p.x) - absf(pz[0]), p.y - pz[1]).length()
		var exceso := p.z - pared
		exceso = 0.5 * (exceso + sqrt(exceso * exceso + 0.0004))
		p.z -= exceso * exp(-pow(dist / 0.075, 2.0))
	return p


func _jacobiana(p: Vector3, forma: String) -> Basis:
	const H := 0.001
	var cols := []
	for eje in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		cols.append((_deformar(p + eje * H, forma) - _deformar(p - eje * H, forma)) / (2.0 * H))
	return Basis(cols[0], cols[1], cols[2])


## Normales suaves por vértice a partir de los triángulos (ponderadas por área).
func _normales(v: PackedVector3Array, indices: PackedInt32Array, respaldo: PackedVector3Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	for k in range(0, indices.size(), 3):
		var a := indices[k]
		var b := indices[k + 1]
		var c := indices[k + 2]
		# Godot usa triángulos en sentido horario para la cara frontal
		var cara := (v[c] - v[a]).cross(v[b] - v[a])
		n[a] += cara
		n[b] += cara
		n[c] += cara
	for k in n.size():
		n[k] = n[k].normalized() if n[k].length_squared() > 0.0 else respaldo[k]
	return n


func _deformar(p: Vector3, forma: String) -> Vector3:
	var t := p.y / _altura
	if forma == "sin_mamas":
		return _aplanar_pecho(p) if _femenino else p
	if forma == "bebe":
		var d: Dictionary = _edad.get("bebe", {})
		if _femenino:   # Una niña no tiene mamas desarrolladas: se aplana el pecho
			p = _aplanar_pecho(p)
		var ancho := _interpolar(d.get("ancho", [[0, 1], [1, 1]]), t)
		return Vector3(p.x * ancho, _interpolar(d.get("t", [[0, 0], [1, 1]]), t) * _altura, p.z * ancho)
	var a: Dictionary = _edad.get("anciano", {})
	var s1 := pow(smoothstep(a.get("t_inicio", 0.6), a.get("t_hombro", 0.83), t), 1.5)
	var s2 := smoothstep(0.84, 0.93, t)
	return p + Vector3(0.0, -a.get("baja", 0.028) * s1 * _altura,
			(a.get("adelante", 0.045) * s1 + a.get("cabeza_extra", 0.03) * s2) * _altura)


static func _interpolar(tabla: Array, x: float) -> float:
	if x <= tabla[0][0]:
		return tabla[0][1]
	for k in tabla.size() - 1:
		var x0: float = tabla[k][0]
		var x1: float = tabla[k + 1][0]
		if x <= x1:
			return lerpf(tabla[k][1], tabla[k + 1][1], (x - x0) / maxf(x1 - x0, 1e-6))
	return tabla[-1][1]


func _material(nombre: String) -> Material:
	var ruta := "%s/%s.tres" % [CARPETA_MATERIALES, nombre]
	if nombre.is_empty() or not ResourceLoader.exists(ruta):
		push_warning("Material no encontrado: '%s'" % nombre)
		return null
	return load(ruta)
