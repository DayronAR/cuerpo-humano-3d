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
		if sistema == "Piel":
			_preparar_piel(estado)
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
		importador = _con_formas_de_edad(importador, material, global, nombre.begins_with("Epidermis__"))
		# La piel no lleva LOD: la malla simplificada comparte vértices con las formas de edad y, al
		# deformarse (niña sin mamas, abdomen liso), sus triángulos se pliegan y se ven ondas
		if not SIN_LOD and not nombre.begins_with("Epidermis__"):
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
func _con_formas_de_edad(origen: ImporterMesh, material: Material, global: Transform3D, es_piel := false) -> ImporterMesh:
	var inversa := global.affine_inverse()
	var nuevo := ImporterMesh.new()
	nuevo.set_blend_shape_mode(Mesh.BLEND_SHAPE_MODE_NORMALIZED)   # Formas con posiciones absolutas
	nuevo.add_blend_shape("Bebe")
	nuevo.add_blend_shape("Anciano")
	nuevo.add_blend_shape("SinMamas")   # Pecho plano de la infancia (solo cambia en el cuerpo femenino)
	nuevo.add_blend_shape("Liso")       # Abdomen sin definición muscular (infancia)
	for s in origen.get_surface_count():
		var arrays := origen.get_surface_arrays(s)
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cantidad := base.size()
		var normales_base: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var rot := global.basis
		var rot_inv := rot.inverse()
		var formas := []
		if es_piel and not _piel_ids.is_empty():
			formas = _formas_piel(base, normales_base, global)
		for forma in ([] if not formas.is_empty() else ["bebe", "anciano", "sin_mamas"]):
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
		# Forma "Liso": el abdomen de la piel alisado (sin los "cuadritos"); en otras mallas, sin cambio
		if formas.size() == 3:   # Fuera de la piel la forma "Liso" no cambia nada
			var liso := []
			liso.resize(Mesh.ARRAY_MAX)
			liso[Mesh.ARRAY_VERTEX] = base.duplicate()
			liso[Mesh.ARRAY_NORMAL] = normales_base.duplicate()
			formas.append(liso)
		for a in formas:
			a[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
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


# --- Piel completa: formas calculadas sobre toda la superficie (sin costuras entre piezas) -----

const FORMAS_PIEL := ["bebe", "anciano", "sin_mamas", "liso"]
const CELDA := 2000.0   ## Celdas de 0,5 mm para unir los vértices repetidos de piezas vecinas
var _piel_celdas := {}                  ## Vector3i -> Array de ids
var _piel_ids := PackedVector3Array()   ## Posición (cuerpo) de cada vértice unido
var _piel_pos := {}                     ## forma -> PackedVector3Array (por id)
var _piel_normal := {}                  ## forma (y "base") -> PackedVector3Array (por id)
var _piel_peso := {}                    ## forma alisada -> peso por id (zona que cambia)


## Id del vértice unido en la posición p (o -1). Busca en las celdas vecinas: tolera el error
## de redondeo entre piezas sin unir vértices distintos (la piel tiene aristas de milímetros).
func _id_piel(p: Vector3, crear := false) -> int:
	var c := Vector3i((p * CELDA).floor())
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for id in _piel_celdas.get(c + Vector3i(dx, dy, dz), []):
					if _piel_ids[id].distance_squared_to(p) < 1e-10:
						return id
	if not crear:
		return -1
	var nuevo := _piel_ids.size()
	_piel_ids.append(p)
	if not _piel_celdas.has(c):
		_piel_celdas[c] = []
	_piel_celdas[c].append(nuevo)
	return nuevo


## Une todas las piezas de la epidermis en una sola malla (en coordenadas del cuerpo) y calcula
## cada forma de edad con sus normales reales. Así la luz sigue a la forma (sin "cuadritos" ni
## pecho fantasma) y las piezas vecinas tienen exactamente la misma posición y normal en el borde.
func _preparar_piel(estado: GLTFState) -> void:
	var nodos := estado.get_nodes()
	var triangulos := PackedInt32Array()
	var frente := {}   # id -> componente z de la normal (hacia el frente)
	var pila := []
	for i in nodos.size():
		if nodos[i].parent == -1:
			pila.append([i, Transform3D.IDENTITY])
	while not pila.is_empty():
		var par = pila.pop_back()
		var g: Transform3D = par[1] * nodos[par[0]].xform
		for h in nodos[par[0]].children:
			pila.append([h, g])
		var nombre: String = nodos[par[0]].original_name
		if nodos[par[0]].mesh < 0 or not nombre.begins_with("Epidermis__"):
			continue
		var malla: ImporterMesh = estado.get_meshes()[nodos[par[0]].mesh].mesh
		for s in malla.get_surface_count():
			var arr := malla.get_surface_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ids := PackedInt32Array()
			ids.resize(v.size())
			for k in v.size():
				ids[k] = _id_piel(g * v[k], true)
				frente[ids[k]] = (g.basis * nrm[k]).normalized().z
			var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in ind.size():
				triangulos.append(ids[ind[k]])
	var n := _piel_ids.size()
	print("  piel unida: %d vértices, %d triángulos" % [n, triangulos.size() / 3])
	# Pecho de la infancia: la mama se rellena como una membrana tensa entre el tórax de alrededor
	var plano := _pecho_plano(triangulos, frente) if _femenino else _piel_ids
	for forma in FORMAS_PIEL:
		var pos := PackedVector3Array()
		if forma == "liso":
			pos = _abdomen_liso(triangulos, frente)
		elif forma == "sin_mamas":
			pos = plano
		else:
			pos.resize(n)
			for k in n:
				pos[k] = _deformar(plano[k], "bebe_sin_aplanar") if forma == "bebe" \
						else _deformar(_piel_ids[k], forma)
		_piel_pos[forma] = pos
		_piel_normal[forma] = _normales_ids(pos, triangulos)
		if _piel_peso.has(forma):   # Zona alisada: normales suaves (sin ondas de triángulos plegados)
			_piel_normal[forma] = _suavizar_normales(_piel_normal[forma], triangulos, _piel_peso[forma], 40)
	_piel_normal["base"] = _normales_ids(_piel_ids, triangulos)


func _normales_ids(pos: PackedVector3Array, tri: PackedInt32Array) -> PackedVector3Array:
	var nn := PackedVector3Array()
	nn.resize(pos.size())
	for k in range(0, tri.size(), 3):
		var a := tri[k]
		var b := tri[k + 1]
		var c := tri[k + 2]
		var cara := (pos[c] - pos[a]).cross(pos[b] - pos[a])   # Godot: sentido horario = frente
		nn[a] += cara
		nn[b] += cara
		nn[c] += cara
	for k in nn.size():
		nn[k] = nn[k].normalized()
	return nn


## Formas de edad de una pieza de piel, tomadas de la piel unida. La normal de cada forma es la
## normal original de la pieza más el cambio de la normal geométrica (conserva el sombreado suave).
func _formas_piel(base: PackedVector3Array, normales: PackedVector3Array, global: Transform3D) -> Array:
	var inversa := global.affine_inverse()
	var rot := global.basis
	var rot_inv := rot.inverse()
	var ids := PackedInt32Array()
	ids.resize(base.size())
	for k in base.size():
		ids[k] = _id_piel(global * base[k])
	var nb: PackedVector3Array = _piel_normal["base"]
	var formas := []
	for forma in FORMAS_PIEL:
		var pos: PackedVector3Array = _piel_pos[forma]
		var nf: PackedVector3Array = _piel_normal[forma]
		var v := PackedVector3Array()
		var nn := PackedVector3Array()
		v.resize(base.size())
		nn.resize(base.size())
		for k in base.size():
			var id := ids[k]
			if id < 0:
				v[k] = base[k]
				nn[k] = normales[k]
				continue
			v[k] = inversa * pos[id]
			var n_cuerpo := (rot * normales[k]).normalized() + nf[id] - nb[id]
			nn[k] = (rot_inv * n_cuerpo).normalized() if n_cuerpo.length_squared() > 1e-8 else normales[k]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = nn
		formas.append(a)
	return formas


## Forma "Liso": alisa la zona del abdomen (borra los surcos de los "cuadritos") sobre la piel
## unida. El efecto se desvanece suavemente hacia el pecho, la pelvis y los costados.
func _abdomen_liso(tri: PackedInt32Array, frente: Dictionary) -> PackedVector3Array:
	var w := PackedFloat32Array()
	w.resize(_piel_ids.size())
	for k in w.size():
		var p := _piel_ids[k]
		var t := p.y / _altura
		w[k] = smoothstep(0.50, 0.55, t) * (1.0 - smoothstep(0.69, 0.73, t)) \
				* (1.0 - smoothstep(0.08, 0.12, absf(p.x) / (_altura / ALTURA_BASE))) \
				* smoothstep(0.1, 0.4, frente.get(k, 0.0))
		if _femenino:   # Sin tocar las mamas: se sumaría al pecho aplanado y dejaría marcas
			for pz in _edad.get("bebe", {}).get("pezones", []):
				w[k] *= smoothstep(0.10, 0.14, Vector2(absf(p.x) - absf(pz[0]), p.y - pz[1]).length())
	_piel_peso["liso"] = w
	return _alisar(tri, w, 70, 0.6)


## Forma "SinMamas": alrededor de cada pezón la piel se alisa hasta quedar como una membrana
## tensa entre el tórax de alrededor (que no se mueve). No hunde el pecho ni deja contorno.
func _pecho_plano(tri: PackedInt32Array, frente: Dictionary) -> PackedVector3Array:
	var d: Dictionary = _edad.get("bebe", {})
	var w := PackedFloat32Array()
	w.resize(_piel_ids.size())
	for k in w.size():
		var p := _piel_ids[k]
		for pz in d.get("pezones", []):
			var dist := Vector2(absf(p.x) - absf(pz[0]), p.y - pz[1]).length()
			# Toda la mama (también su cara inferior), sin tocar la espalda ni el brazo
			var cerca := 1.0 - smoothstep(0.075, 0.11, dist)
			w[k] = maxf(w[k], cerca * smoothstep(-0.6, -0.2, frente.get(k, 0.0)) * smoothstep(0.0, 0.03, p.z))
	_piel_peso["sin_mamas"] = w
	var pos := _alisar(tri, w, 500, 1.0)
	# La cara inferior de la mama queda apiñada sobre la membrana: se reparten los vértices sobre
	# la superficie (solo en su plano tangente) para desplegar los triángulos plegados
	return _relajar(pos, tri, w, 150)


func _relajar(pos: PackedVector3Array, tri: PackedInt32Array, w: PackedFloat32Array, iteraciones: int) -> PackedVector3Array:
	var vecinos := {}
	for k in range(0, tri.size(), 3):
		for e in 3:
			var a := tri[k + e]
			var b := tri[k + (e + 1) % 3]
			if w[a] > 0.0:
				if not vecinos.has(a): vecinos[a] = {}
				vecinos[a][b] = true
			if w[b] > 0.0:
				if not vecinos.has(b): vecinos[b] = {}
				vecinos[b][a] = true
	var listas := {}
	for k in vecinos:
		listas[k] = PackedInt32Array(vecinos[k].keys())
	var normales := PackedVector3Array()
	for i in iteraciones:
		if i % 10 == 0:
			normales = _normales_ids(pos, tri)
		var nueva := pos.duplicate()
		for k in listas:
			var lista: PackedInt32Array = listas[k]
			var media := Vector3.ZERO
			for v in lista:
				media += pos[v]
			media /= lista.size()
			var paso := media - pos[k]
			paso -= normales[k] * paso.dot(normales[k])   # Solo tangencial: no cambia la forma
			nueva[k] = pos[k] + paso * 0.5 * w[k]
		pos = nueva
	return pos


func _suavizar_normales(nn: PackedVector3Array, tri: PackedInt32Array, w: PackedFloat32Array,
		iteraciones: int) -> PackedVector3Array:
	var res := nn.duplicate()
	for _i in iteraciones:
		var suma := PackedVector3Array()
		suma.resize(res.size())
		for k in range(0, tri.size(), 3):
			var a := tri[k]
			var b := tri[k + 1]
			var c := tri[k + 2]
			if w[a] > 0.0 or w[b] > 0.0 or w[c] > 0.0:
				var m := res[a] + res[b] + res[c]
				suma[a] += m
				suma[b] += m
				suma[c] += m
		for k in res.size():
			if w[k] > 0.0 and suma[k].length_squared() > 0.0:
				res[k] = res[k].lerp(suma[k].normalized(), minf(1.0, w[k] * 1.5)).normalized()
	return res


## Laplaciano ponderado sobre la piel unida: cada vértice se acerca al promedio de sus vecinos
## según su peso (0 = fijo).
func _alisar(tri: PackedInt32Array, w: PackedFloat32Array, iteraciones: int, factor: float) -> PackedVector3Array:
	var n := _piel_ids.size()
	var pos := _piel_ids.duplicate()
	var vecinos := []
	vecinos.resize(n)
	for k in range(0, tri.size(), 3):
		for e in 3:
			var a := tri[k + e]
			var b := tri[k + (e + 1) % 3]
			if w[a] > 0.0:
				if vecinos[a] == null: vecinos[a] = {}
				vecinos[a][b] = true
			if w[b] > 0.0:
				if vecinos[b] == null: vecinos[b] = {}
				vecinos[b][a] = true
	var activos := PackedInt32Array()
	var listas := {}
	for k in n:
		if w[k] > 0.0 and vecinos[k] != null:
			activos.append(k)
			listas[k] = PackedInt32Array(vecinos[k].keys())
	for _i in iteraciones:
		var nueva := pos.duplicate()
		for k in activos:
			var media := Vector3.ZERO
			var lista: PackedInt32Array = listas[k]
			for v in lista:
				media += pos[v]
			media /= lista.size()
			nueva[k] = pos[k] + (media - pos[k]) * factor * w[k]
		pos = nueva
	return pos


func _jacobiana(p: Vector3, forma: String) -> Basis:
	const H := 0.001
	var cols := []
	for eje in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		cols.append((_deformar(p + eje * H, forma) - _deformar(p - eje * H, forma)) / (2.0 * H))
	return Basis(cols[0], cols[1], cols[2])


func _deformar(p: Vector3, forma: String) -> Vector3:
	var t := p.y / _altura
	if forma == "sin_mamas":
		return _aplanar_pecho(p) if _femenino else p
	if forma == "bebe" or forma == "bebe_sin_aplanar":
		var d: Dictionary = _edad.get("bebe", {})
		if _femenino and forma == "bebe":   # Una niña no tiene mamas desarrolladas: se aplana el pecho
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
