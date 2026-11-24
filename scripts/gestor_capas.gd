class_name GestorCapas
extends Node

signal capa_retirada(id_sistema: String)
signal capa_restaurada(id_sistema: String)
signal secuencia_terminada

class Capa:
	var id := ""
	var piezas: Array[Pieza] = []
	var progreso := 0.0
	var destino := 0.0
	var retirada := false
	var tween: Tween
	var fantasma_propio := -1.0
	var desplazamiento_actual := 0.0
	var escala_actual := 1.0

class Pieza:
	var nodo: Node3D
	var id_capa := ""
	var escala_extra := Vector3.ONE
	var transform_original: Transform3D
	var pivote := Vector3.ZERO
	var direccion := Vector3.ZERO
	var usar_vista := false
	var mallas: Array[MeshInstance3D] = []
	var sombras: Array[int] = []
	var materiales_originales: Array = []
	var materiales_transparentes: Array = []

var _capas: Dictionary = {}
var _piezas_por_nodo: Dictionary = {}
var _orden: Array = []
var _camara: Camera3D
var _generacion := 0
var _mezcla_fantasma := 0.0
var _tween_fantasma: Tween

var _duracion := 0.45
var _pausa := 0.06
var _desplazamiento := 0.12
var _escala_final := 0.82
var _transparencia_fantasma := 0.82
var _duracion_fantasma := 0.3


func drar_configurar(sistemas: Dictionary, orden: Array, cfg: Dictionary, camara: Camera3D, eje: Vector3) -> void:
	_orden = orden
	_camara = camara
	_duracion = cfg.get("duracion", _duracion)
	_pausa = cfg.get("pausa_entre_capas", _pausa)
	_desplazamiento = cfg.get("desplazamiento", _desplazamiento)
	_escala_final = cfg.get("escala_final", _escala_final)
	_transparencia_fantasma = cfg.get("transparencia_fantasma", _transparencia_fantasma)
	_duracion_fantasma = cfg.get("duracion_cambio_fantasma", _duracion_fantasma)
	for id in sistemas:
		var capa := Capa.new()
		capa.id = id
		for organo in sistemas[id].get_children():
			var nodos := []
			if organo is MeshInstance3D:
				nodos = [organo]
			elif organo is Node3D:
				nodos = organo.get_children().filter(func(n): return n is Node3D)
			for n in nodos:
				var pieza := _drar_crear_pieza(n, eje)
				pieza.id_capa = id
				capa.piezas.append(pieza)
				_piezas_por_nodo[n] = pieza
		_capas[id] = capa


func drar_retirar_solo(ids_retirar: Array, fantasmas: Dictionary = {}, simultaneas: Array = []) -> void:
	_generacion += 1
	var generacion := _generacion
	var ids := ids_retirar.duplicate()
	for id in fantasmas:
		if _capas.has(id) and not id in ids:
			ids.append(id)
	for id in ids:
		if not _capas.has(id):
			continue
		var capa: Capa = _capas[id]
		var nuevo: float = fantasmas.get(id, -1.0)
		if nuevo != capa.fantasma_propio:
			capa.fantasma_propio = nuevo
			if capa.progreso > 0.0:
				_drar_aplicar(capa.progreso, capa)
	var restaurar := _drar_ordenados(_capas.keys().filter(func(id): return _capas[id].destino > 0.0 and not id in ids))
	restaurar.reverse()
	var retirar := _drar_ordenados(ids.filter(func(id): return _capas.has(id) and _capas[id].destino < 1.0))

	var de_contexto := retirar.filter(func(id): return fantasmas.has(id) or id in simultaneas)
	var en_orden := restaurar + retirar.filter(func(id): return not de_contexto.has(id))
	for id in en_orden:
		var destino := 0.0 if id in restaurar else 1.0
		var duracion := _drar_animar(_capas[id], destino)
		await get_tree().create_timer(duracion + _pausa).timeout
		if generacion != _generacion:
			return
	var mayor := 0.0
	for id in de_contexto:
		mayor = maxf(mayor, _drar_animar(_capas[id], 1.0))
	if mayor > 0.0:
		await get_tree().create_timer(mayor).timeout
		if generacion != _generacion:
			return
	secuencia_terminada.emit()


func drar_restaurar_todo() -> void:
	drar_retirar_solo([])


func drar_fijar_escala_extra(nodo: Node3D, escala: Vector3) -> void:
	var pieza: Pieza = _piezas_por_nodo.get(nodo)
	if pieza == null:
		return
	pieza.escala_extra = escala
	_drar_transformar(pieza)


func drar_capas_retiradas() -> Array:
	return _capas.keys().filter(func(id): return _capas[id].destino > 0.0)


func drar_establecer_modo_fantasma(activo: bool) -> void:
	if _tween_fantasma and _tween_fantasma.is_valid():
		_tween_fantasma.kill()
	_tween_fantasma = create_tween()
	_tween_fantasma.tween_method(_drar_cambiar_mezcla_fantasma, _mezcla_fantasma, 1.0 if activo else 0.0,
			_duracion_fantasma)


func _drar_animar(capa: Capa, destino: float) -> float:
	if capa.tween and capa.tween.is_valid():
		capa.tween.kill()
	capa.destino = destino
	var duracion := _duracion * absf(destino - capa.progreso)
	if duracion <= 0.001:
		_drar_aplicar(destino, capa)
		return 0.0
	capa.tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	capa.tween.tween_method(_drar_aplicar.bind(capa), capa.progreso, destino, duracion)
	return duracion


func _drar_cambiar_mezcla_fantasma(valor: float) -> void:
	_mezcla_fantasma = valor
	for capa in _capas.values():
		if capa.progreso > 0.0:
			_drar_aplicar(capa.progreso, capa)


func _drar_aplicar(progreso: float, capa: Capa) -> void:
	capa.progreso = progreso
	var mezcla := 1.0 if capa.fantasma_propio >= 0.0 else _mezcla_fantasma
	var transparencia_fantasma := capa.fantasma_propio if capa.fantasma_propio >= 0.0 else _transparencia_fantasma
	var normal := 1.0 - mezcla
	capa.desplazamiento_actual = progreso * _desplazamiento * normal
	capa.escala_actual = lerpf(1.0, _escala_final, progreso * normal)
	var transparencia := lerpf(progreso, progreso * transparencia_fantasma, mezcla)
	var oculta := progreso >= 0.999 and normal >= 0.999

	for pieza in capa.piezas:
		_drar_transformar(pieza)
		pieza.nodo.visible = not oculta
		for i in pieza.mallas.size():
			_drar_fijar_transparencia(pieza, i, transparencia)
			pieza.mallas[i].cast_shadow = pieza.sombras[i] if progreso <= 0.0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var retirada := progreso > 0.0
	if retirada != capa.retirada:
		capa.retirada = retirada
		if retirada:
			capa_retirada.emit(capa.id)
		else:
			capa_restaurada.emit(capa.id)


func _drar_transformar(pieza: Pieza) -> void:
	var capa: Capa = _capas[pieza.id_capa]
	var escala := capa.escala_actual
	var direccion := pieza.direccion
	if pieza.usar_vista and _camara:
		direccion = _drar_direccion_vista(pieza)
	var ajuste := Transform3D(Basis.from_scale(Vector3.ONE * escala),
			pieza.pivote - pieza.pivote * escala + direccion * capa.desplazamiento_actual)
	pieza.nodo.transform = ajuste * pieza.transform_original.scaled_local(pieza.escala_extra)


func _drar_fijar_transparencia(pieza: Pieza, indice: int, transparencia: float) -> void:
	var malla := pieza.mallas[indice]
	var originales: Array = pieza.materiales_originales[indice]
	if transparencia <= 0.0:
		for s in originales.size():
			malla.set_surface_override_material(s, originales[s])
		return
	var copias: Array = pieza.materiales_transparentes[indice]
	if copias.is_empty():
		for s in originales.size():
			var base := malla.get_active_material(s)
			var copia: Material = null
			if base is BaseMaterial3D:
				copia = base.duplicate()
				copia.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				copia.set_meta("alfa_original", base.albedo_color.a)
			elif MaterialVivo.jlrl_es_vivo(base):
				copia = MaterialVivo.jlrl_transparente(base)
			copias.append(copia)
	for s in copias.size():
		var copia: Material = copias[s]
		if copia == null:
			continue
		if copia is ShaderMaterial:
			copia.set_shader_parameter("alfa", 1.0 - transparencia)
		else:
			var color: Color = copia.albedo_color
			color.a = copia.get_meta("alfa_original") * (1.0 - transparencia)
			copia.albedo_color = color
		malla.set_surface_override_material(s, copia)


func _drar_crear_pieza(nodo: Node3D, eje: Vector3) -> Pieza:
	var pieza := Pieza.new()
	pieza.nodo = nodo
	pieza.transform_original = nodo.transform
	pieza.mallas = BodyViewer.drar_mallas_de(nodo)
	for m in pieza.mallas:
		pieza.sombras.append(m.cast_shadow)
		var originales := []
		for s in m.get_surface_override_material_count():
			originales.append(m.get_surface_override_material(s))
		pieza.materiales_originales.append(originales)
		pieza.materiales_transparentes.append([])

	var padre := nodo.get_parent() as Node3D
	var aabb := _drar_aabb_en(nodo, padre)
	pieza.pivote = aabb.get_center()
	var centro_mundo := padre.global_transform * pieza.pivote
	var horizontal := Vector3(centro_mundo.x - eje.x, 0.0, centro_mundo.z - eje.z)
	if horizontal.length() < 0.04:
		pieza.usar_vista = true
	else:
		pieza.direccion = (padre.global_basis.inverse() * horizontal.normalized()).normalized()
	return pieza


func _drar_direccion_vista(pieza: Pieza) -> Vector3:
	var padre := pieza.nodo.get_parent() as Node3D
	var hacia_camara: Vector3 = _camara.global_position - padre.global_transform * pieza.pivote
	hacia_camara.y = 0.0
	if hacia_camara.length() < 0.001:
		return Vector3.ZERO
	return (padre.global_basis.inverse() * hacia_camara.normalized()).normalized()


static func _drar_aabb_en(nodo: Node3D, referencia: Node3D) -> AABB:
	var inversa := referencia.global_transform.affine_inverse()
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.drar_mallas_de(nodo):
		var caja: AABB = (inversa * malla.global_transform) * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado


func _drar_ordenados(ids: Array) -> Array:
	var resultado := ids.duplicate()
	resultado.sort_custom(func(a, b): return _orden.find(a) < _orden.find(b))
	return resultado
