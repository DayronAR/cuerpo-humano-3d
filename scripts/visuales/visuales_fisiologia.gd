class_name VisualesFisiologia
extends Node3D

var _visor: BodyViewer
var _cfg: Dictionary
var _estado: Dictionary = {}
var _visuales_escenario: Dictionary = {}
var _factor_tiempo := 1.0
var _velocidad := 1.0
var _pausado := false
var _fase_corazon := 0.0
var _fase_respiracion := 0.0
var _musculos: Array = []

var _globulos: FlujoParticulas
var _humo: Array[FlujoParticulas] = []
var _bolo: MeshInstance3D
var _curva_bolo := Curve3D.new()
var _fase_peristaltismo := 0.0
var _anios_fumando := 0.0
var _tumor: MeshInstance3D


func jlrl_configurar(visor: BodyViewer, cfg: Dictionary) -> void:
	_visor = visor
	_cfg = cfg
	var musculos: Dictionary = cfg.get("musculos", {})
	_musculos = musculos.get("organos", visor.drar_organos_de_sistema(musculos.get("sistema", "")))
	var tray: Dictionary = Datos.dymj_cuerpo_activo().get("trayectorias", {})

	var g: Dictionary = cfg.get("globulos", {})
	_globulos = _jlrl_crear_flujo("Globulos", tray.get("circulacion", []), true, g)

	var h: Dictionary = cfg.get("humo", {})
	for nombre in ["humo_izq", "humo_der"]:
		var mitad := h.duplicate()
		mitad["cantidad"] = int(h.get("cantidad", 30) / 2)
		var flujo := _jlrl_crear_flujo(nombre.capitalize(), tray.get(nombre, []), false, mitad)
		flujo.velocidad = h.get("velocidad", 0.2)
		flujo.crecer = true
		_humo.append(flujo)

	var b: Dictionary = cfg.get("bolo", {})
	var temp := FlujoParticulas.new()
	temp._jlrl_construir_curva(tray.get("bolo", []))
	_curva_bolo = temp.curva
	temp.free()
	_bolo = MeshInstance3D.new()
	_bolo.name = "Bolo"
	var esfera := SphereMesh.new()
	esfera.radius = b.get("tamano", 0.017)
	esfera.height = esfera.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_string(b.get("color", "#b5651d"), Color.BROWN)
	material.no_depth_test = true
	esfera.material = material
	_bolo.mesh = esfera
	_bolo.visible = false
	add_child(_bolo)
	_jlrl_preparar_peristaltismo(visor.cuerpo)


func _jlrl_preparar_peristaltismo(raiz: Node3D) -> void:
	var p: Dictionary = _cfg.get("peristaltismo", {})
	for id in p.get("organos", []):
		var organo := raiz.find_child(id, true, false)
		if organo == null:
			continue
		for malla in BodyViewer.drar_mallas_de(organo):
			if malla.mesh == null:
				continue
			for s in malla.mesh.get_surface_count():
				var base := malla.mesh.surface_get_material(s)
				if base is BaseMaterial3D and base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					var vivo := MaterialVivo.jlrl_desde(base)
					vivo.set_shader_parameter("longitud", p.get("longitud", 0.045))
					malla.mesh.surface_set_material(s, vivo)


func jlrl_al_actualizar_estado(estado: Dictionary) -> void:
	_estado = estado
	_jlrl_actualizar_tintes()
	_jlrl_actualizar_bolo()


func jlrl_al_cambiar_escenario(id_escenario: String, activo: bool) -> void:
	_visuales_escenario = {}
	if activo:
		for e in Datos.simulacion.get("escenarios", []):
			if e.get("id") == id_escenario:
				_visuales_escenario = e.get("visuales", {})
	_globulos.emitiendo = _visuales_escenario.get("globulos", false)
	for flujo in _humo:
		flujo.emitiendo = _visuales_escenario.get("humo", false)
	_jlrl_actualizar_bolo()


func jlrl_al_cambiar_pausa(pausado: bool) -> void:
	_pausado = pausado
	_jlrl_actualizar_factor_tiempo()


func jlrl_al_cambiar_velocidad(velocidad: float) -> void:
	_velocidad = velocidad
	_jlrl_actualizar_factor_tiempo()


func _process(delta: float) -> void:
	if _visor == null:
		return
	var dt := delta * _factor_tiempo
	_jlrl_animar_peristaltismo(dt)

	var c: Dictionary = _cfg.get("corazon", {})
	_fase_corazon = fposmod(_fase_corazon + _jlrl_valor(c.get("variable"), 70.0) / 60.0 * dt, 1.0)
	var f := _fase_corazon
	var latido := exp(-pow((f - 0.1) / 0.05, 2.0)) + 0.55 * exp(-pow((f - 0.32) / 0.06, 2.0))
	var escala_corazon: Vector3 = Vector3.ONE * (1.0 + c.get("amplitud_latido", 0.1) * latido)
	for id in c.get("organos", []):
		_visor.drar_escalar_organo(id, escala_corazon)

	var p: Dictionary = _cfg.get("pulmones", {})
	_fase_respiracion = fposmod(_fase_respiracion + _jlrl_valor(p.get("variable"), 14.0) / 60.0 * dt, 1.0)
	var aire := 0.5 - 0.5 * cos(TAU * _fase_respiracion)
	var h: float = p.get("amplitud_horizontal", 0.07) * aire
	var escala_pulmon: Vector3 = Vector3(1.0 + h, 1.0 + p.get("amplitud_vertical", 0.04) * aire, 1.0 + h)
	for id in p.get("organos", []):
		_visor.drar_escalar_organo(id, escala_pulmon)

	var g: Dictionary = _cfg.get("globulos", {})
	_globulos.velocidad = _jlrl_valor(c.get("variable"), 70.0) * g.get("velocidad_por_lpm", 0.006)


func _jlrl_animar_peristaltismo(dt: float) -> void:
	var p: Dictionary = _cfg.get("peristaltismo", {})
	var comiendo: bool = _visuales_escenario.get("bolo", false)
	_fase_peristaltismo = fposmod(_fase_peristaltismo + TAU * p.get("ondas_por_segundo", 0.35)
			* (p.get("factor_comer", 2.0) if comiendo else 1.0) * dt, TAU * 1000.0)
	RenderingServer.global_shader_parameter_set("peristaltismo_fase", _fase_peristaltismo)
	RenderingServer.global_shader_parameter_set("peristaltismo_onda",
			p.get("amplitud", 0.0015) * (p.get("factor_comer", 2.0) if comiendo else 1.0))


func jlrl_fijar_anios_fumando(anios: float) -> void:
	_anios_fumando = anios
	_jlrl_actualizar_tintes()


static func _jlrl_progreso(d: Dictionary, anios: float) -> float:
	return smoothstep(float(d.get("desde", 0.0)), float(d.get("hasta", 40.0)), anios)


func _jlrl_actualizar_tintes() -> void:
	var p: Dictionary = _cfg.get("pulmones", {})
	var tabaco: Dictionary = _cfg.get("tabaco", {})
	var dano: float = _jlrl_valor(p.get("variable_dano"), 0.0) / 100.0 * p.get("opacidad_dano_max", 0.8)
	var t_pulmon: Dictionary = tabaco.get("pulmones", {})
	var dano_anios := _jlrl_progreso(t_pulmon, _anios_fumando) * float(t_pulmon.get("max", 0.85))
	var color_dano: Color = Color.from_string(p.get("color_dano", "#2f2622"), Color.BLACK)
	for id in p.get("organos", []):
		_visor.drar_tenir_organo(id, color_dano, maxf(dano, dano_anios),
				float(t_pulmon.get("manchas", 0.0)) if dano_anios > dano else 0.0)
	for d in tabaco.get("danos", []):
		var color := Color.from_string(d.get("color", "#000000"), Color.BLACK)
		var cantidad := _jlrl_progreso(d, _anios_fumando) * float(d.get("max", 0.5))
		if d.has("partes"):
			_visor.drar_tenir_partes(d.get("organo", ""), d["partes"], color, cantidad, d.get("manchas", 0.0))
		else:
			for id in d.get("organos", []):
				_visor.drar_tenir_organo(id, color, cantidad, d.get("manchas", 0.0))
	_jlrl_actualizar_tumor(tabaco.get("tumor", {}))

	var m: Dictionary = _cfg.get("musculos", {})
	var lactato: float = inverse_lerp(m.get("valor_sin_tinte", 1.2), m.get("valor_tinte_max", 10.0),
			_jlrl_valor(m.get("variable"), 1.0))
	var color_musculo: Color = Color.from_string(m.get("color", "#7a0010"), Color.DARK_RED)
	for id in _musculos:
		_visor.drar_tenir_organo(id, color_musculo, clampf(lactato, 0.0, 1.0) * m.get("opacidad_max", 0.75))


func _jlrl_actualizar_tumor(t: Dictionary) -> void:
	var visible_ := not t.is_empty() and _anios_fumando >= float(t.get("desde", 30))
	if not visible_:
		if _tumor:
			_tumor.visible = false
		return
	if _tumor == null:
		var pulmon := _visor.drar_obtener_organo(t.get("organo", ""))
		if pulmon == null:
			return
		_tumor = MeshInstance3D.new()
		_tumor.name = "Tumor"
		var esfera := SphereMesh.new()
		esfera.radius = 1.0
		esfera.height = 2.0
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_string(t.get("color", "#3a2a36"), Color.DIM_GRAY)
		m.roughness = 0.75
		m.rim_enabled = true
		m.rim = 0.3
		esfera.material = m
		_tumor.mesh = esfera
		pulmon.add_child(_tumor)
		_tumor.global_position = _jlrl_punto_frontal(pulmon, float(t.get("altura", 0.2)))
	var avance := inverse_lerp(float(t.get("desde", 30)), float(_cfg.get("tabaco", {}).get("anios_max", 40)), _anios_fumando)
	var radio := lerpf(t.get("radio_min", 0.007), t.get("radio_max", 0.016), clampf(avance, 0.0, 1.0))
	_tumor.scale = Vector3.ONE * radio / maxf(_tumor.get_parent().global_basis.get_scale().x, 1e-4)
	_tumor.visible = true


func _jlrl_punto_frontal(organo: Node3D, altura: float) -> Vector3:
	var caja := AABB()
	var puntos := []
	for malla in BodyViewer.drar_mallas_de(organo):
		if malla.mesh == null or malla.name == "Tumor":
			continue
		var v: PackedVector3Array = malla.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var n := v.size() - (2 if malla.mesh.get_blend_shape_count() > 0 else 0)
		for k in range(0, n, 3):
			var g: Vector3 = malla.global_transform * v[k]
			puntos.append(g)
			caja = AABB(g, Vector3.ZERO) if caja.size == Vector3.ZERO and puntos.size() == 1 else caja.expand(g)
	var objetivo := caja.get_center() + Vector3(0, caja.size.y * altura, 0)
	var mejor := objetivo
	var mejor_z := -INF
	for g: Vector3 in puntos:
		if absf(g.y - objetivo.y) < 0.015 and absf(g.x - objetivo.x) < 0.02 and g.z > mejor_z:
			mejor_z = g.z
			mejor = g
	return mejor - Vector3(0, 0, 0.004)


func _jlrl_actualizar_bolo() -> void:
	var progreso: float = _jlrl_valor(_cfg.get("bolo", {}).get("variable"), 0.0)
	_bolo.visible = _visuales_escenario.get("bolo", false) and progreso > 0.0 and progreso < 1.0
	if _bolo.visible:
		_bolo.position = _curva_bolo.sample_baked(progreso * _curva_bolo.get_baked_length(), true)


func _jlrl_actualizar_factor_tiempo() -> void:
	_factor_tiempo = 0.0 if _pausado else _velocidad
	_globulos.factor_tiempo = _factor_tiempo
	for flujo in _humo:
		flujo.factor_tiempo = _factor_tiempo


func _jlrl_crear_flujo(nombre: String, puntos: Array, cerrada: bool, cfg: Dictionary) -> FlujoParticulas:
	var flujo := FlujoParticulas.new()
	flujo.name = nombre
	flujo.jlrl_configurar(puntos, cerrada, cfg.get("cantidad", 30), cfg.get("tamano", 0.012),
			Color.from_string(cfg.get("color", "#ffffff"), Color.WHITE), cfg.get("dispersion", 0.01))
	add_child(flujo)
	return flujo


func _jlrl_valor(variable, por_defecto: float) -> float:
	return float(_estado.get(variable, por_defecto)) if variable != null else por_defecto
