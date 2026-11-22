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
## Compresión de vértices: con formas de mezcla hace fallar a Godot 4.7 (get_mesh): desactivada.
var COMPRIMIR := OS.get_environment("COMPRIMIR") == "1"
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
	if es_piel:   # Solo cambian la piel: en los órganos serían copias iguales a la base (peso inútil)
		nuevo.add_blend_shape("SinMamas")   # Pecho plano de la infancia (cuerpo femenino)
		nuevo.add_blend_shape("Liso")       # Abdomen sin definición muscular (infancia)
	nuevo.add_blend_shape("Encogido")   # Recién nacido en posición fetal (forma "Bebe" + postura)
	nuevo.add_blend_shape("Sentado")    # Bebé de un año sentado (forma "Bebe" + postura)
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
		for forma in ([] if not formas.is_empty() else ["bebe", "anciano", "encogido", "sentado"]):
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
		# Sin tangentes ni coordenadas UV: los materiales son triplanares (no usan UV y calculan sus
		# propias tangentes), y las tangentes se repetirían en cada forma de edad. Ocupa casi la mitad.
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_TEX_UV] = null
		arrays[Mesh.ARRAY_TEX_UV2] = null
		for a in formas:
			a[Mesh.ARRAY_TANGENT] = null
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
		# Compresión de vértices (posición en 16 bits respecto de la caja, normales octaédricas):
		# las mallas ocupan bastante menos en disco y en la memoria de video
		nuevo.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, formas, {}, material, origen.get_surface_name(s),
				Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES if COMPRIMIR else 0)
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

const FORMAS_PIEL := ["bebe", "anciano", "sin_mamas", "liso", "encogido", "sentado"]
const POSTURAS := ["encogido", "sentado"]   ## Formas de bebé con postura (ver _encoger)
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
	var brazo := []   # Vértices de la piel de brazos, codos, antebrazos y manos
	var codo := []
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
		var es_brazo := nombre.to_lower().contains("brazo") or nombre.contains("Codo") or nombre.contains("Mano")
		for s in malla.get_surface_count():
			var arr := malla.get_surface_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ids := PackedInt32Array()
			ids.resize(v.size())
			for k in v.size():
				ids[k] = _id_piel(g * v[k], true)
				frente[ids[k]] = (g.basis * nrm[k]).normalized().z
				if es_brazo:
					_ids_brazo[ids[k]] = true
					brazo.append(g * v[k])
					if nombre.contains("Codo"):
						codo.append(g * v[k])
			var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in ind.size():
				triangulos.append(ids[ind[k]])
	var n := _piel_ids.size()
	print("  piel unida: %d vértices, %d triángulos" % [n, triangulos.size() / 3])
	_medir_piernas()
	_preparar_encogido(brazo, codo)
	_marcar_brazos(triangulos)
	# Pecho de la infancia: la mama se rellena como una membrana tensa entre el tórax de alrededor
	var plano := _pecho_plano(triangulos, frente) if _femenino else _piel_ids
	if not _femenino:   # Pelo del niño: el cabello en mechones de la piel se alisa en el bebé
		plano = _pelo_liso(triangulos, frente)
	var vecinos := _vecinos_piel(triangulos)
	for forma in FORMAS_PIEL:
		var pos := PackedVector3Array()
		if forma == "liso":
			pos = _abdomen_liso(triangulos, frente)
		elif forma == "sin_mamas":
			pos = plano if _femenino else _piel_ids   # (en el niño "plano" lleva el pelo alisado)
		else:
			pos.resize(n)
			for k in n:
				if forma in POSTURAS:   # Bebé (pecho plano y abdomen liso) en posición fetal o sentado
					var liso: PackedVector3Array = _piel_pos["liso"]
					var q := _deformar(plano[k] + liso[k] - _piel_ids[k], "bebe_sin_aplanar")
					pos[k] = _encoger(_piel_ids[k], q, 1 if _ids_brazo.has(k) else 0, forma)
				else:
					pos[k] = _deformar(plano[k], "bebe_sin_aplanar") if forma == "bebe" \
							else _deformar(_piel_ids[k], forma)
			if forma in POSTURAS:   # Apoyado en el suelo (el punto más bajo en y = 0)
				var suelo := INF
				for k in n:
					suelo = minf(suelo, pos[k].y)
				_suelo[forma] = suelo
				for k in n:
					pos[k].y -= suelo
				print("  %s: el bebé se apoya %.3f m más abajo" % [forma, suelo])
				pos = _relajar_estirado(pos, _piel_pos["bebe"], vecinos)
			if forma == "bebe" or forma in POSTURAS:   # Piel de bebé: más suave en todo el cuerpo
				pos = _taubin_ids(pos, vecinos, 6)
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


func _vecinos_piel(tri: PackedInt32Array) -> Array:
	var conj := []
	conj.resize(_piel_ids.size())
	for k in conj.size():
		conj[k] = {}
	for k in range(0, tri.size(), 3):
		for e in 3:
			var a := tri[k + e]
			var b := tri[k + (e + 1) % 3]
			conj[a][b] = true
			conj[b][a] = true
	var lista := []
	lista.resize(conj.size())
	for k in conj.size():
		lista[k] = PackedInt32Array(conj[k].keys())
	return lista


## Alisado de Taubin (no encoge la forma) sobre toda la piel unida.
func _taubin_ids(pos: PackedVector3Array, vecinos: Array, iteraciones: int) -> PackedVector3Array:
	for _i in iteraciones:
		for factor in [0.5, -0.53]:
			var nueva := pos.duplicate()
			for k in pos.size():
				var lista: PackedInt32Array = vecinos[k]
				if lista.is_empty():
					continue
				var media := Vector3.ZERO
				for v in lista:
					media += pos[v]
				nueva[k] = pos[k] + (media / lista.size() - pos[k]) * factor
			pos = nueva
	return pos


## Donde la postura fetal estira la piel (axilas, costados del tórax) los triángulos quedan
## largos y se ve a través: esa zona se alisa en proporción a cuánto se estiró.
func _relajar_estirado(pos: PackedVector3Array, ref: PackedVector3Array, vecinos: Array) -> PackedVector3Array:
	var n := pos.size()
	var peso := PackedFloat32Array()
	peso.resize(n)
	var estirados := 0
	for k in n:
		var lista: PackedInt32Array = vecinos[k]
		var mayor := 0.0
		for v in lista:
			var l0 := ref[k].distance_to(ref[v])
			if l0 > 1e-6:
				mayor = maxf(mayor, pos[k].distance_to(pos[v]) / l0)
		peso[k] = clampf((mayor - 1.12) / 0.6, 0.0, 1.0)
		if peso[k] > 0.0:
			estirados += 1
	for _i in 5:   # La zona se extiende unos anillos para que el cambio sea gradual
		var w := peso.duplicate()
		for k in n:
			for v in vecinos[k]:
				w[k] = maxf(w[k], peso[v] * 0.7)
		peso = w
	for _i in 80:
		var nueva := pos.duplicate()
		for k in n:
			if peso[k] <= 0.0:
				continue
			var lista: PackedInt32Array = vecinos[k]
			var media := Vector3.ZERO
			for v in lista:
				media += pos[v]
			nueva[k] = pos[k].lerp(media / lista.size(), 0.5 * peso[k])
		pos = nueva
	print("  encogido: %d vértices estirados alisados" % estirados)
	return pos


## Cabello del cuerpo masculino (mechones modelados en la piel): para el bebé se alisa la parte
## alta y trasera de la cabeza hasta quedar como un casquete suave.
func _pelo_liso(tri: PackedInt32Array, frente: Dictionary) -> PackedVector3Array:
	var w := PackedFloat32Array()
	w.resize(_piel_ids.size())
	for k in w.size():
		var p := _piel_ids[k]
		var t := p.y / _altura
		var atras := smoothstep(0.0, -0.04 * _altura / ALTURA_BASE, p.z)
		w[k] = maxf(smoothstep(0.925, 0.95, t), smoothstep(0.885, 0.915, t) * atras)
	return _alisar(tri, w, 220, 0.8)


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


var _piernas := []                 ## Eje de cada pierna (|x| y z) por altura, medido en la piel
var _piernas_x := []
var _piernas_z := []


## Mide el eje de las piernas en la piel (para engrosarlas en la forma "Bebe").
func _medir_piernas() -> void:
	var bins := {}
	for p: Vector3 in _piel_ids:
		var t: float = p.y / _altura
		if t > 0.5 or absf(p.x) < 0.005 or absf(p.x) > 0.2 * _altura / ALTURA_BASE:
			continue
		var b := int(t / 0.02)
		if not bins.has(b):
			bins[b] = [INF, -INF, INF, -INF]
		var c: Array = bins[b]
		c[0] = minf(c[0], absf(p.x)); c[1] = maxf(c[1], absf(p.x))
		c[2] = minf(c[2], p.z); c[3] = maxf(c[3], p.z)
	var claves := bins.keys()
	claves.sort()
	for b in claves:
		var c: Array = bins[b]
		var t: float = (b + 0.5) * 0.02
		_piernas.append(t)
		_piernas_x.append([t, (c[0] + c[1]) * 0.5])
		_piernas_z.append([t, (c[2] + c[3]) * 0.5])


# --- Posición fetal (recién nacido encogido) -----------------------------------------------

var _brazos := [[], []]        ## Por lado (0: x > 0, 1: x < 0): [t, x, z, radio] cada PASO_BRAZO de t
var _brazo_t0 := [0.0, 0.0]
var _hombro_t := 0.8
var _codo_t := 0.62
var _pivotes := {}             ## Articulaciones en el espacio del bebé
var _suelo := {}               ## Postura -> cuánto se bajó para apoyarse en el suelo
var _angulo_brazo := [0.0, 0.0]   ## Separación del brazo respecto de la vertical (rad), por lado
var _ids_brazo := {}           ## Vértices de la piel que pertenecen a los brazos
const PASO_BRAZO := 0.01


## Mide el eje de cada brazo en la piel (centro y radio por altura) y calcula las articulaciones
## de la postura fetal, llevadas a las proporciones del bebé.
func _preparar_encogido(brazo: Array, codo: Array) -> void:
	var c: Dictionary = _edad.get("encogido", {})
	var t_codo := 0.0
	for p in codo:
		t_codo += p.y / _altura
	_codo_t = t_codo / maxf(1, codo.size())
	_hombro_t = 0.0
	for lado in 2:
		var bins := {}
		for p: Vector3 in brazo:
			if (p.x > 0) != (lado == 0):
				continue
			var b := int(p.y / _altura / PASO_BRAZO)
			if not bins.has(b):
				bins[b] = []
			bins[b].append(p)
		var claves := bins.keys()
		claves.sort()
		_brazo_t0[lado] = claves[0] * PASO_BRAZO
		_brazos[lado] = []
		for b in range(claves[0], claves[-1] + 1):
			var pts: Array = bins.get(b, [])
			if pts.is_empty():
				_brazos[lado].append(_brazos[lado][-1] if not _brazos[lado].is_empty() else [0, 0, 0, 0])
				continue
			var centro := Vector2.ZERO
			for p: Vector3 in pts:
				centro += Vector2(p.x, p.z)
			centro /= pts.size()
			var radio := 0.0
			for p: Vector3 in pts:
				radio = maxf(radio, Vector2(p.x, p.z).distance_to(centro))
			_brazos[lado].append([(b + 0.5) * PASO_BRAZO, centro.x, centro.y, radio])
		_hombro_t = maxf(_hombro_t, (claves[-1] + 1) * PASO_BRAZO)
	var h := _altura
	var bebe := func(v: Vector3) -> Vector3: return _deformar(v, "bebe_sin_aplanar")
	var tc: float = c.get("cadera_t", 0.5)
	var tr: float = c.get("rodilla_t", 0.285)
	var tt: float = c.get("tobillo_t", 0.045)
	_pivotes = {
		"cadera": bebe.call(Vector3(0, tc * h, _interpolar(_piernas_z, tc - 0.03))),
		"rodilla": bebe.call(Vector3(0, tr * h, _interpolar(_piernas_z, tr))),
		"tobillo": bebe.call(Vector3(0, tt * h, _interpolar(_piernas_z, tt + 0.02) - 0.02 * h / ALTURA_BASE)),
		"columna": bebe.call(Vector3(0, c.get("columna_t", 0.56) * h, -0.05 * h / ALTURA_BASE)),
		"cuello": bebe.call(Vector3(0, c.get("cuello_t", 0.865) * h, -0.01 * h / ALTURA_BASE)),
	}
	for lado in 2:
		var hombro := _eje_brazo(lado, _hombro_t - 0.025)
		var codo_c := _eje_brazo(lado, _codo_t)
		_pivotes["hombro%d" % lado] = bebe.call(Vector3(hombro.x, (_hombro_t - 0.025) * h, hombro.y))
		_pivotes["codo%d" % lado] = bebe.call(Vector3(codo_c.x, _codo_t * h, codo_c.y))
		_angulo_brazo[lado] = atan2(absf(codo_c.x - hombro.x), (_hombro_t - 0.025 - _codo_t) * h)
	print("  encogido: hombro t=%.3f, codo t=%.3f, brazo desde t=%.3f" % [_hombro_t, _codo_t, _brazo_t0[0]])


func _eje_brazo(lado: int, t: float) -> Vector2:
	var lista: Array = _brazos[lado]
	var i := clampi(int((t - _brazo_t0[lado]) / PASO_BRAZO), 0, lista.size() - 1)
	return Vector2(lista[i][1], lista[i][2])


## 1 dentro del brazo (cerca de su eje), 0 en el tronco y las piernas; suave en la axila.
func _peso_brazo(p: Vector3, t: float) -> float:
	var lado := 0 if p.x >= 0.0 else 1
	var lista: Array = _brazos[lado]
	if lista.is_empty():
		return 0.0
	var i := int((t - _brazo_t0[lado]) / PASO_BRAZO)
	if i < -2 or i >= lista.size():
		return 0.0
	var b: Array = lista[clampi(i, 0, lista.size() - 1)]
	var d := Vector2(p.x - b[1], p.z - b[2]).length()
	var margen := 0.01 * _altura / ALTURA_BASE
	return (1.0 - smoothstep(b[3] * 1.05, b[3] * 1.05 + margen, d)) \
			* (1.0 - smoothstep(_hombro_t - 0.06, _hombro_t - 0.01, t))


## Qué vértices de la piel son del brazo, siguiendo la superficie: desde el codo se recorre la
## malla por debajo de la axila (los puentes con el muslo ya se cortaron al procesarla), así no
## dependen de la etiqueta de cada pieza (cerca del muslo puede ser errónea).
func _marcar_brazos(tri: PackedInt32Array) -> void:
	var axila := _hombro_t - 0.10   # Por debajo del pliegue de la axila
	var vecinos := {}
	for k in range(0, tri.size(), 3):
		for e in 3:
			var a := tri[k + e]
			var b := tri[k + (e + 1) % 3]
			if _piel_ids[a].y / _altura < axila and _piel_ids[b].y / _altura < axila:
				if not vecinos.has(a): vecinos[a] = []
				if not vecinos.has(b): vecinos[b] = []
				vecinos[a].append(b)
				vecinos[b].append(a)
	var pila := []
	var nuevos := {}
	for id in _ids_brazo:
		var p := _piel_ids[id]
		var t := p.y / _altura
		if absf(t - _codo_t) < 0.03 and _peso_brazo(p, t) > 0.9:
			pila.append(id)
			nuevos[id] = true
	while not pila.is_empty():
		var a = pila.pop_back()
		for b in vecinos.get(a, []):
			if not nuevos.has(b):
				nuevos[b] = true
				pila.append(b)
	for id in _ids_brazo:
		if _piel_ids[id].y / _altura >= axila:
			nuevos[id] = true
	print("  brazos: %d vértices por etiqueta, %d siguiendo la superficie" % [_ids_brazo.size(), nuevos.size()])
	if nuevos.size() > _ids_brazo.size() * 1.5:
		push_warning("El recorrido de los brazos se escapó al tronco; se usan las etiquetas")
		return
	_ids_brazo = nuevos


static func _rotar_x(q: Vector3, pivote: Vector3, angulo: float) -> Vector3:
	if absf(angulo) < 1e-6:
		return q
	return pivote + Basis(Vector3.RIGHT, angulo) * (q - pivote)


## Postura fetal: p es el punto del adulto (decide a qué parte del cuerpo pertenece) y q el mismo
## punto con las proporciones del bebé (el que se mueve). Cada articulación dobla de forma suave
## (el ángulo crece en una franja), del hijo al padre: codo -> hombro -> columna.
func _encoger(p: Vector3, q: Vector3, piel := -1, postura := "encogido") -> Vector3:
	var c: Dictionary = _edad.get(postura, {})
	var t := p.y / _altura
	var r := q
	var wa := _peso_brazo(p, t)
	if piel == 0:   # Piel del tronco o de las piernas: solo se une al brazo en el hombro y la axila
		wa *= smoothstep(_hombro_t - 0.13, _hombro_t - 0.09, t)
	elif piel == 1 and t < _hombro_t - 0.10:   # Piel del brazo (por la superficie): se mueve entera
		wa = 1.0
	if wa > 0.0:
		var lado := 0 if p.x >= 0.0 else 1
		var we := wa * (1.0 - smoothstep(_codo_t - 0.015, _codo_t + 0.025, t))
		var hombro: Vector3 = _pivotes["hombro%d" % lado]
		var signo := 1.0 if lado == 0 else -1.0
		# Primero el brazo se lleva a la vertical (el cuerpo femenino está en pose "A")
		var vertical: float = -signo * _angulo_brazo[lado]
		r = hombro + Basis(Vector3.BACK, vertical * wa) * (r - hombro)
		var codo_p: Vector3 = hombro + Basis(Vector3.BACK, vertical) * (_pivotes["codo%d" % lado] - hombro)
		r = _rotar_x(r, codo_p, deg_to_rad(c.get("codo", -120.0)) * we)
		r = _rotar_x(r, hombro, deg_to_rad(c.get("hombro", -45.0)) * wa)
		# Aducción: las manos se juntan delante de la cara
		r = hombro + Basis(Vector3.UP, -signo * deg_to_rad(c.get("aduccion", 25.0)) * wa) * (r - hombro)
	var tc: float = c.get("cadera_t", 0.5)
	var tr: float = c.get("rodilla_t", 0.285)
	var tt: float = c.get("tobillo_t", 0.045)
	var wl := (1.0 - smoothstep(tc - 0.04, tc + 0.03, t)) * (1.0 - wa)
	if wl > 0.0:
		var wk := 1.0 - smoothstep(tr - 0.02, tr + 0.025, t)
		var wt := 1.0 - smoothstep(tt - 0.01, tt + 0.02, t)
		r = _rotar_x(r, _pivotes["tobillo"], deg_to_rad(c.get("tobillo", -20.0)) * wt * wl)
		r = _rotar_x(r, _pivotes["rodilla"], deg_to_rad(c.get("rodilla", 125.0)) * wk * wl)
		r = _rotar_x(r, _pivotes["cadera"], deg_to_rad(c.get("cadera", -95.0)) * wl)
	# Cabeza y columna (los brazos las siguen desde el hombro)
	var ts := lerpf(t, _hombro_t, wa)
	var tn: float = c.get("cuello_t", 0.865)
	r = _rotar_x(r, _pivotes["cuello"], deg_to_rad(c.get("cabeza", 25.0)) * smoothstep(tn - 0.02, tn + 0.02, ts))
	var tcol: float = c.get("columna_t", 0.56)
	r = _rotar_x(r, _pivotes["columna"], deg_to_rad(c.get("columna", 25.0)) * smoothstep(tcol, 0.82, ts))
	return r


func _deformar(p: Vector3, forma: String) -> Vector3:
	var t := p.y / _altura
	if forma in POSTURAS:
		return _encoger(p, _deformar(p, "bebe"), -1, forma) - Vector3(0, _suelo.get(forma, 0.0), 0)
	if forma == "sin_mamas":
		return _aplanar_pecho(p) if _femenino else p
	if forma == "bebe" or forma == "bebe_sin_aplanar":
		var d: Dictionary = _edad.get("bebe", {})
		if _femenino and forma == "bebe":   # Una niña no tiene mamas desarrolladas: se aplana el pecho
			p = _aplanar_pecho(p)
		var ancho := _interpolar(d.get("ancho", [[0, 1], [1, 1]]), t)
		var x := p.x * ancho
		var z := p.z * ancho
		# Piernas: se engruesan alrededor de su propio eje (no solo se separan)
		if not _piernas.is_empty() and t < 0.52:
			var cx := _interpolar(_piernas_x, t) * signf(p.x)
			var cz := _interpolar(_piernas_z, t)
			var en_pierna := (1.0 - smoothstep(0.40, 0.50, t)) * (1.0 - smoothstep(0.08, 0.12, absf(p.x - cx)))
			var k := _interpolar(d.get("grosor_piernas", [[0, 1], [1, 1]]), t)
			x = lerpf(x, cx * ancho + (p.x - cx) * k, en_pierna)
			z = lerpf(z, cz + (p.z - cz) * k, en_pierna)
		# Cara más plana y pequeña: lo que está delante del centro de la cabeza se acerca a él
		if t > 0.86 and p.z > 0.0:
			z = p.z * ancho * _interpolar(d.get("cara", [[0, 1], [1, 1]]), t)
		# Barriga redonda: el frente del abdomen sobresale
		if p.z > -0.02:
			z += maxf(0.0, p.z) * _interpolar(d.get("vientre", [[0, 0], [1, 0]]), t) * smoothstep(-0.02, 0.05, p.z)
		return Vector3(x, _interpolar(d.get("t", [[0, 0], [1, 1]]), t) * _altura, z)
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
