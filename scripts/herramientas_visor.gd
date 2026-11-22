class_name HerramientasVisor
extends Node
## Herramientas de exploración del cuerpo, sobre el visor 3D:
##   - Corte: un plano (transversal, sagital o coronal) que se mueve y deja ver el interior.
##   - Despiece: separa los órganos del sistema que se está viendo, hacia afuera de su centro.
##   - Etiquetas: puntos (nombre + posición en pantalla) de los órganos del sistema visible.
##   - Comparar: muestra el otro cuerpo (masculino o femenino) al lado, con la misma edad.
## No tiene interfaz propia: la escena principal conecta el panel de herramientas con estas
## funciones.

const SHADER_CORTE := preload("res://shaders/corte.gdshader")
const PLANOS := {
	"transversal": Vector3.UP,      ## Corte horizontal: se quita la parte de arriba
	"sagital": Vector3.RIGHT,       ## De lado: se quita la mitad izquierda del cuerpo
	"coronal": Vector3.BACK,        ## De frente: se quita la parte delantera
}
const SEPARACION_COMPARAR := 0.95   ## Distancia (m) entre los dos cuerpos al compararlos
const MAX_ETIQUETAS := 18

var _visor: BodyViewer
var _corte_activo := false
var _plano_id := "coronal"
var _posicion := 0.5
var _materiales_corte := {}          ## Material original -> ShaderMaterial de corte
var _originales := {}                ## MeshInstance3D -> Array de materiales de superficie (override)
var _shader_opaco: Shader
var _shader_transparente: Shader

var _despiece := 0.0
var _posiciones_despiece := {}       ## Node3D -> [posición original, dirección de separación]

var _comparado: Node3D = null        ## El otro cuerpo, al compararlos
var _formas_comparado: Array = []
var _objetivo_antes := Vector3.ZERO


func configurar(visor: BodyViewer) -> void:
	_visor = visor
	_shader_transparente = SHADER_CORTE
	_shader_opaco = Shader.new()
	# Variante opaca: sin escribir ALPHA (si no, Godot dibujaría todo como transparente)
	var codigo := SHADER_CORTE.code
	var i := codigo.find("\tif (color.a < 0.99)")
	_shader_opaco.code = codigo.substr(0, i) + "}\n" if i > 0 else codigo


# --- Corte ------------------------------------------------------------------------------

func corte_activo() -> bool:
	return _corte_activo


func fijar_corte(activo: bool, plano_id := "", posicion := -1.0) -> void:
	if not plano_id.is_empty():
		_plano_id = plano_id
	if posicion >= 0.0:
		_posicion = posicion
	if activo != _corte_activo:
		_corte_activo = activo
		if activo:
			_aplicar_materiales_corte()
		else:
			_restaurar_materiales()
		_visor.mostrar_interior_forzado(activo)
		if _comparado:   # Con el corte se ve todo el interior también en el cuerpo comparado
			if activo:
				for sistema in _comparado.get_children():
					sistema.visible = true
			else:
				al_cambiar_sistema(_visor.sistema_actual())
	_actualizar_plano()


## Plano actual en coordenadas del mundo: (normal, distancia). Sin corte: distancia infinita.
func plano() -> Vector4:
	if not _corte_activo:
		return Vector4(0, 0, 0, INF)
	var normal: Vector3 = PLANOS.get(_plano_id, Vector3.BACK)
	var caja := _caja_visible()
	var a := caja.position.dot(normal)
	var b := caja.end.dot(normal)
	# 0 = todo cortado, 1 = nada cortado (el corte avanza desde el lado que se quita)
	var d := lerpf(minf(a, b), maxf(a, b), _posicion)
	return Vector4(normal.x, normal.y, normal.z, d)


func _caja_visible() -> AABB:
	var caja := _caja_piel(_visor.cuerpo)
	if _comparado:
		caja = caja.merge(_caja_piel(_comparado))
	return caja


var _cajas_piel := {}   ## MeshInstance3D -> AABB local de sus vértices reales


## Caja de la piel según sus vértices (la AABB de las mallas incluye el espacio de todas las
## formas de edad y sería mucho más grande que el cuerpo).
func _caja_piel(raiz: Node3D) -> AABB:
	var piel := raiz.find_child("Piel", false, false) as Node3D
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.mallas_de(piel if piel else raiz):
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


func _actualizar_plano() -> void:
	var p := plano()
	_visor.plano_corte = p
	for m in _materiales_corte.values():
		m.set_shader_parameter("plano", p if _corte_activo else Vector4(0, 0, 1, 1e9))


func _aplicar_materiales_corte() -> void:
	for raiz in _cuerpos():
		for malla in BodyViewer.mallas_de(raiz):
			if _originales.has(malla) or malla.mesh == null:
				continue
			var guardados := []
			for s in malla.get_surface_override_material_count():
				guardados.append(malla.get_surface_override_material(s))
				var activo := malla.get_active_material(s)
				var corte := _material_corte(activo)
				if corte:
					malla.set_surface_override_material(s, corte)
			_originales[malla] = guardados


func _restaurar_materiales() -> void:
	for malla in _originales:
		if not is_instance_valid(malla):
			continue
		var guardados: Array = _originales[malla]
		for s in guardados.size():
			malla.set_surface_override_material(s, guardados[s])
	_originales.clear()


func _material_corte(original: Material) -> ShaderMaterial:
	if MaterialVivo.es_vivo(original):   # Ya admite el plano de corte: se usa el mismo
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


func _cuerpos() -> Array:
	return [_visor.cuerpo] + ([_comparado] if _comparado else [])


# --- Despiece ----------------------------------------------------------------------------

## Separa los órganos del sistema visible (factor 0 = juntos, 1 = muy separados). Si el sistema
## tiene pocos órganos, se separan sus partes (p. ej. los huesos del esqueleto).
func fijar_despiece(factor: float) -> void:
	var sistema := _visor.sistema_actual()
	if factor > 0.0 and _posiciones_despiece.is_empty():
		if sistema.is_empty():
			return
		_preparar_despiece(sistema)
	_despiece = factor
	for nodo in _posiciones_despiece:
		if is_instance_valid(nodo):
			var datos: Array = _posiciones_despiece[nodo]
			nodo.position = datos[0] + datos[1] * factor
	if factor <= 0.0:
		_posiciones_despiece.clear()


func reiniciar_despiece() -> void:
	fijar_despiece(0.0)
	_posiciones_despiece.clear()


func _preparar_despiece(sistema: String) -> void:
	var nodo_sistema := _visor.obtener_sistema(sistema)
	var organos := _visor.organos_de_sistema(sistema).map(func(id): return _visor.obtener_organo(id))
	var piezas: Array = organos
	if organos.size() < 4:   # Pocos órganos (p. ej. el esqueleto): se separan sus partes
		piezas = []
		for o in organos:
			piezas.append_array(BodyViewer.mallas_de(o).filter(func(m): return m != o))
	if piezas.is_empty():
		return
	var centro := _caja_de(nodo_sistema).get_center()
	var tamano := _caja_de(nodo_sistema).size.length()
	for pieza: Node3D in piezas:
		var desde := _caja_de(pieza).get_center() - centro
		desde.y *= 0.6   # Más hacia los costados y el frente que hacia arriba y abajo
		var mundo := desde.normalized() * minf(desde.length() * 1.6, tamano * 0.35) if desde.length() > 1e-4 \
				else Vector3.FORWARD * tamano * 0.1
		var padre := pieza.get_parent() as Node3D
		var local := padre.global_basis.inverse() * mundo if padre else mundo
		_posiciones_despiece[pieza] = [pieza.position, local]


# --- Etiquetas -------------------------------------------------------------------------

## [[nombre, posición en el mundo], ...] de los órganos más grandes del sistema visible.
func puntos_etiquetas() -> Array:
	var sistema := _visor.sistema_actual()
	if sistema.is_empty():
		return []
	var lista := []
	for id in _visor.organos_de_sistema(sistema):
		var organo := _visor.obtener_organo(id)
		if organo == null or not organo.is_visible_in_tree():
			continue
		var caja := _caja_de(organo)
		var nombre: String = Datos.ficha_organo(id).get("nombre", id)
		lista.append([nombre, caja.get_center(), caja.size.length()])
	lista.sort_custom(func(a, b): return a[2] > b[2])
	return lista.slice(0, MAX_ETIQUETAS)


# --- Comparar ---------------------------------------------------------------------------

func comparando() -> bool:
	return _comparado != null


## Muestra el otro cuerpo a la derecha (masculino <-> femenino) con la misma edad.
func fijar_comparacion(activo: bool) -> void:
	if activo == comparando():
		return
	var corte := _corte_activo
	if corte:
		fijar_corte(false)
	if activo:
		var otro := _id_otro_cuerpo()
		if otro.is_empty():
			return
		var escena := load(Datos.visuales.get("cuerpos", {})[otro].get("escena", "")) as PackedScene
		if escena == null:
			return
		_comparado = escena.instantiate()
		_comparado.name = "CuerpoComparado"
		_visor.add_child(_comparado)
		_comparado.position = Vector3(SEPARACION_COMPARAR, 0, 0)
		_formas_comparado = _visor.preparar_formas(_comparado)
		_visor.aplicar_edad_a(_comparado, _formas_comparado, _visor.edad_actual())
		al_cambiar_sistema(_visor.sistema_actual())
		_objetivo_antes = _visor.camara.objetivo
		encuadrar_comparacion()
	else:
		_comparado.queue_free()
		_comparado = null
		_formas_comparado.clear()
		_visor.camara.encuadrar(_visor.camara.objetivo_inicial(), _visor.camara.distancia_inicial())
	if corte:
		fijar_corte(true)


## El cuerpo comparado muestra el mismo sistema que el principal (o solo la piel).
## Encuadra los dos cuerpos de frente.
func encuadrar_comparacion() -> void:
	var c := _visor.camara
	var v := c.obtener_vista("frente")
	c.animar_a(v.get("yaw", 0.0), v.get("pitch", 5.0), c.distancia_inicial() * 1.35,
			c.objetivo_inicial() + Vector3(SEPARACION_COMPARAR * 0.5, 0, 0))


func al_cambiar_sistema(id_sistema: String) -> void:
	if _comparado == null:
		return
	for sistema in _comparado.get_children():
		if sistema is Node3D:
			sistema.visible = String(sistema.name) == (id_sistema if not id_sistema.is_empty() else "Piel")


## Al cambiar la edad, el cuerpo comparado también cambia.
func al_cambiar_edad(anios: float, _final := false) -> void:
	if _comparado:
		_visor.aplicar_edad_a(_comparado, _formas_comparado, anios)
	if _corte_activo:
		_actualizar_plano()


func nombre_comparado() -> String:
	var otro := _id_otro_cuerpo()
	return Datos.visuales.get("cuerpos", {}).get(otro, {}).get("nombre", "")


func _id_otro_cuerpo() -> String:
	var actual: String = Datos.cuerpo_elegido if not Datos.cuerpo_elegido.is_empty() \
			else Datos.visuales.get("cuerpo_activo", "")
	if actual == "zanatomy":
		return "zanatomy_femenino"
	if actual == "zanatomy_femenino":
		return "zanatomy"
	return ""


static func _caja_de(nodo: Node3D) -> AABB:
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.mallas_de(nodo):
		if malla.mesh == null:
			continue
		var caja: AABB = malla.global_transform * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado
