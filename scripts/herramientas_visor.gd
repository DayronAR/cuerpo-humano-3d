class_name HerramientasVisor
extends Node

const SHADER_CORTE := preload("res://shaders/corte.gdshader")
const PLANOS := {
	"transversal": Vector3.UP,
	"sagital": Vector3.RIGHT,
	"coronal": Vector3.BACK,
}
const SEPARACION_COMPARAR := 0.95
const MAX_ETIQUETAS := 30

var _visor: BodyViewer
var _corte_activo := false
var _plano_id := "coronal"
var _posicion := 0.5
var _materiales_corte := {}
var _originales := {}
var _shader_opaco: Shader
var _shader_transparente: Shader

var _despiece := 0.0
var _posiciones_despiece := {}

var _comparado: Node3D = null
var _formas_comparado: Array = []
var _objetivo_antes := Vector3.ZERO


func drar_configurar(visor: BodyViewer) -> void:
	_visor = visor
	_shader_transparente = SHADER_CORTE
	_shader_opaco = Shader.new()
	var codigo := SHADER_CORTE.code
	var i := codigo.find("\tif (color.a < 0.99)")
	_shader_opaco.code = codigo.substr(0, i) + "}\n" if i > 0 else codigo


func drar_corte_activo() -> bool:
	return _corte_activo


func drar_fijar_corte(activo: bool, plano_id := "", posicion := -1.0) -> void:
	if not plano_id.is_empty():
		_plano_id = plano_id
	if posicion >= 0.0:
		_posicion = posicion
	if activo != _corte_activo:
		_corte_activo = activo
		if activo:
			_visor.drar_completar_colisiones()
			_drar_aplicar_materiales_corte()
		else:
			_drar_restaurar_materiales()
		_visor.drar_mostrar_interior_forzado(activo)
		if _comparado:
			if activo:
				for sistema in _comparado.get_children():
					sistema.visible = true
			else:
				drar_al_cambiar_sistema(_visor.drar_sistema_actual())
	_drar_actualizar_plano()


func drar_plano() -> Vector4:
	if not _corte_activo:
		return Vector4(0, 0, 0, INF)
	var normal: Vector3 = PLANOS.get(_plano_id, Vector3.BACK)
	var caja := _drar_caja_visible()
	var a := caja.position.dot(normal)
	var b := caja.end.dot(normal)
	var d := lerpf(minf(a, b), maxf(a, b), _posicion)
	return Vector4(normal.x, normal.y, normal.z, d)


func _drar_caja_visible() -> AABB:
	var caja := _drar_caja_piel(_visor.cuerpo)
	if _comparado:
		caja = caja.merge(_drar_caja_piel(_comparado))
	return caja


var _cajas_piel := {}


func _drar_caja_piel(raiz: Node3D) -> AABB:
	var piel := raiz.find_child("Piel", false, false) as Node3D
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.drar_mallas_de(piel if piel else raiz):
		if malla.mesh == null or malla.mesh.get_surface_count() == 0:
			continue
		if not _cajas_piel.has(malla):
			var v: PackedVector3Array = malla.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var cantidad := v.size() - 2 if malla.mesh.get_blend_shape_count() > 0 else v.size()
			var caja := AABB(v[0], Vector3.ZERO)
			for k in cantidad:
				caja = caja.expand(v[k])
			_cajas_piel[malla] = caja
		var g: AABB = malla.global_transform * _cajas_piel[malla]
		resultado = g if primero else resultado.merge(g)
		primero = false
	return resultado


func _drar_actualizar_plano() -> void:
	var p := drar_plano()
	_visor.plano_corte = p
	for m in _materiales_corte.values():
		m.set_shader_parameter("plano", p if _corte_activo else Vector4(0, 0, 1, 1e9))


func _drar_aplicar_materiales_corte() -> void:
	for raiz in _drar_cuerpos():
		for malla in BodyViewer.drar_mallas_de(raiz):
			if _originales.has(malla) or malla.mesh == null:
				continue
			var guardados := []
			for s in malla.get_surface_override_material_count():
				guardados.append(malla.get_surface_override_material(s))
				var activo := malla.get_active_material(s)
				var corte := _drar_material_corte(activo)
				if corte:
					malla.set_surface_override_material(s, corte)
			_originales[malla] = guardados


func _drar_restaurar_materiales() -> void:
	for malla in _originales:
		if not is_instance_valid(malla):
			continue
		var guardados: Array = _originales[malla]
		for s in guardados.size():
			malla.set_surface_override_material(s, guardados[s])
	_originales.clear()


func _drar_material_corte(original: Material) -> ShaderMaterial:
	if MaterialVivo.jlrl_es_vivo(original):
		_materiales_corte[original] = original
		return original
	if not original is BaseMaterial3D:
		return null
	if _materiales_corte.has(original):
		return _materiales_corte[original]
	var b := original as BaseMaterial3D
	var transparente := b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var m := ShaderMaterial.new()
	m.shader = _shader_transparente if transparente else _shader_opaco
	m.set_shader_parameter("color", b.albedo_color)
	m.set_shader_parameter("rugosidad", b.roughness)
	m.set_shader_parameter("especular", b.metallic_specular)
	m.set_shader_parameter("borde", b.rim if b.rim_enabled else 0.0)
	m.set_shader_parameter("tinte_borde", b.rim_tint)
	m.set_shader_parameter("brillo", b.clearcoat if b.clearcoat_enabled else 0.0)
	_materiales_corte[original] = m
	return m


func _drar_cuerpos() -> Array:
	return [_visor.cuerpo] + ([_comparado] if _comparado else [])


func drar_fijar_despiece(factor: float) -> void:
	var sistema := _visor.drar_sistema_actual()
	if factor > 0.0 and _posiciones_despiece.is_empty():
		if sistema.is_empty():
			return
		_drar_preparar_despiece(sistema)
	_despiece = factor
	for nodo in _posiciones_despiece:
		if is_instance_valid(nodo):
			var datos: Array = _posiciones_despiece[nodo]
			nodo.position = datos[0] + datos[1] * factor
	if factor <= 0.0:
		_posiciones_despiece.clear()


func drar_reiniciar_despiece() -> void:
	drar_fijar_despiece(0.0)
	_posiciones_despiece.clear()


func _drar_preparar_despiece(sistema: String) -> void:
	var nodo_sistema := _visor.drar_obtener_sistema(sistema)
	var organos := _visor.drar_organos_de_sistema(sistema).map(func(id): return _visor.drar_obtener_organo(id))
	var piezas: Array = organos
	if organos.size() < 4:
		piezas = []
		for o in organos:
			piezas.append_array(BodyViewer.drar_mallas_de(o).filter(func(m): return m != o))
	if piezas.is_empty():
		return
	var centro := _drar_caja_de(nodo_sistema).get_center()
	var tamano := _drar_caja_de(nodo_sistema).size.length()
	for pieza: Node3D in piezas:
		var desde := _drar_caja_de(pieza).get_center() - centro
		desde.y *= 0.6
		var mundo := desde.normalized() * minf(desde.length() * 1.6, tamano * 0.35) if desde.length() > 1e-4 \
				else Vector3.FORWARD * tamano * 0.1
		var padre := pieza.get_parent() as Node3D
		var local := padre.global_basis.inverse() * mundo if padre else mundo
		_posiciones_despiece[pieza] = [pieza.position, local]


func drar_puntos_etiquetas() -> Array:
	var sistema := _visor.drar_sistema_actual()
	if sistema.is_empty():
		return []
	var lista := []
	for id in _visor.drar_organos_de_sistema(sistema):
		var organo := _visor.drar_obtener_organo(id)
		if organo == null or not organo.is_visible_in_tree():
			continue
		if not _anclas.has(organo):
			_anclas[organo] = _drar_calcular_ancla(organo)
		var ancla: Array = _anclas[organo]
		if ancla.is_empty():
			continue
		var nombre: String = Datos.dymj_ficha_organo(id).get("nombre", id)
		lista.append([nombre, _visor.drar_punto_deformado(ancla[0], ancla[1]), ancla[2]])
	lista.sort_custom(func(a, b): return a[2] > b[2])
	return lista.slice(0, MAX_ETIQUETAS)


var _anclas: Dictionary = {}


func _drar_calcular_ancla(organo: Node3D) -> Array:
	var muestras := []
	for t in _visor.drar_trabajos_de(organo):
		var indices: PackedInt32Array = t[2]
		var paso := maxi(1, indices.size() / 400)
		for k in range(0, indices.size(), paso):
			var i := indices[k]
			muestras.append([t, i, _visor.drar_punto_deformado(t, i)])
	if muestras.is_empty():
		return []
	var centro := Vector3.ZERO
	var caja := AABB(muestras[0][2], Vector3.ZERO)
	for m in muestras:
		centro += m[2]
		caja = caja.expand(m[2])
	centro /= muestras.size()
	var mejor: Array = muestras[0]
	for m in muestras:
		if (m[2] as Vector3).distance_squared_to(centro) < (mejor[2] as Vector3).distance_squared_to(centro):
			mejor = m
	return [mejor[0], mejor[1], caja.size.length()]


func drar_comparando() -> bool:
	return _comparado != null


func drar_fijar_comparacion(activo: bool) -> void:
	if activo == drar_comparando():
		return
	var corte := _corte_activo
	if corte:
		drar_fijar_corte(false)
	if activo:
		var otro := _drar_id_otro_cuerpo()
		if otro.is_empty():
			return
		var escena := load(Datos.visuales.get("cuerpos", {})[otro].get("escena", "")) as PackedScene
		if escena == null:
			return
		_comparado = escena.instantiate()
		_comparado.name = "CuerpoComparado"
		_visor.add_child(_comparado)
		_comparado.position = Vector3(SEPARACION_COMPARAR, 0, 0)
		_formas_comparado = _visor.drar_preparar_formas(_comparado)
		_visor.drar_aplicar_edad_a(_comparado, _formas_comparado, _visor.drar_edad_actual())
		drar_al_cambiar_sistema(_visor.drar_sistema_actual())
		_objetivo_antes = _visor.camara.objetivo
		drar_encuadrar_comparacion()
	else:
		_comparado.queue_free()
		_comparado = null
		_formas_comparado.clear()
		_visor.camara.drar_encuadrar(_visor.camara.drar_objetivo_inicial(), _visor.camara.drar_distancia_inicial())
	if corte:
		drar_fijar_corte(true)


func drar_encuadrar_comparacion() -> void:
	var c := _visor.camara
	var v := c.drar_obtener_vista("frente")
	c.drar_animar_a(v.get("yaw", 0.0), v.get("pitch", 5.0), c.drar_distancia_inicial() * 1.35,
			c.drar_objetivo_inicial() + Vector3(SEPARACION_COMPARAR * 0.5, 0, 0))


func drar_al_cambiar_sistema(id_sistema: String) -> void:
	if _comparado == null:
		return
	for sistema in _comparado.get_children():
		if sistema is Node3D:
			sistema.visible = String(sistema.name) == (id_sistema if not id_sistema.is_empty() else "Piel")


func drar_al_cambiar_edad(anios: float, final := false) -> void:
	if final:
		_anclas.clear()
	if _comparado:
		_visor.drar_aplicar_edad_a(_comparado, _formas_comparado, anios)
	if _corte_activo:
		_drar_actualizar_plano()


func drar_nombre_comparado() -> String:
	var otro := _drar_id_otro_cuerpo()
	return Datos.visuales.get("cuerpos", {}).get(otro, {}).get("nombre", "")


func _drar_id_otro_cuerpo() -> String:
	var actual: String = Datos.cuerpo_elegido if not Datos.cuerpo_elegido.is_empty() \
			else Datos.visuales.get("cuerpo_activo", "")
	if actual == "zanatomy":
		return "zanatomy_femenino"
	if actual == "zanatomy_femenino":
		return "zanatomy"
	return ""


static func _drar_caja_de(nodo: Node3D) -> AABB:
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.drar_mallas_de(nodo):
		if malla.mesh == null:
			continue
		var caja: AABB = malla.global_transform * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado
