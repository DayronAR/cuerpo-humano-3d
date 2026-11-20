class_name VisualesFisiologia
extends Node3D
## Visualizaciones del cuerpo ligadas a la simulación. SOLO escucha el estado que le llega por
## señales (conectadas en main.gd) y lo traduce a movimiento y color; no calcula fisiología.
##
##   Corazón      -> late (escala pulsante "lub-dub") al ritmo de la frecuencia cardiaca.
##   Pulmones     -> se expanden y contraen con la frecuencia respiratoria; se oscurecen con el daño.
##   Músculos     -> se tiñen de rojo intenso según el ácido láctico.
##   Bolo         -> recorre esófago, estómago e intestinos según "progreso_bolo".
##   Humo         -> partículas de la boca a los pulmones (escenario fumar).
##   Glóbulos     -> partículas que circulan más rápido cuanto mayor es la frecuencia cardiaca.
##
## Qué órganos, colores y trayectorias usar viene de res://data/visuales.json.

var _visor: BodyViewer
var _cfg: Dictionary
var _estado: Dictionary = {}
var _visuales_escenario: Dictionary = {}   ## Banderas "visuales" del escenario activo
var _factor_tiempo := 1.0                   ## Velocidad de la simulación (0 si está en pausa)
var _velocidad := 1.0
var _pausado := false
var _fase_corazon := 0.0
var _fase_respiracion := 0.0
var _musculos: Array = []

var _globulos: FlujoParticulas
var _humo: Array[FlujoParticulas] = []
var _bolo: MeshInstance3D
var _curva_bolo := Curve3D.new()


func configurar(visor: BodyViewer, cfg: Dictionary) -> void:
	_visor = visor
	_cfg = cfg
	var musculos: Dictionary = cfg.get("musculos", {})
	_musculos = musculos.get("organos", visor.organos_de_sistema(musculos.get("sistema", "")))
	var tray: Dictionary = Datos.cuerpo_activo().get("trayectorias", {})

	var g: Dictionary = cfg.get("globulos", {})
	_globulos = _crear_flujo("Globulos", tray.get("circulacion", []), true, g)

	var h: Dictionary = cfg.get("humo", {})
	for nombre in ["humo_izq", "humo_der"]:
		var mitad := h.duplicate()
		mitad["cantidad"] = int(h.get("cantidad", 30) / 2)
		var flujo := _crear_flujo(nombre.capitalize(), tray.get(nombre, []), false, mitad)
		flujo.velocidad = h.get("velocidad", 0.2)
		flujo.crecer = true
		_humo.append(flujo)

	var b: Dictionary = cfg.get("bolo", {})
	var temp := FlujoParticulas.new()   # Reutiliza el suavizado de curvas
	temp._construir_curva(tray.get("bolo", []))
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


# --- Receptores de señales del motor ------------------------------------------------

func al_actualizar_estado(estado: Dictionary) -> void:
	_estado = estado
	_actualizar_tintes()
	_actualizar_bolo()


func al_cambiar_escenario(id_escenario: String, activo: bool) -> void:
	_visuales_escenario = {}
	if activo:
		for e in Datos.simulacion.get("escenarios", []):
			if e.get("id") == id_escenario:
				_visuales_escenario = e.get("visuales", {})
	_globulos.emitiendo = _visuales_escenario.get("globulos", false)
	for flujo in _humo:
		flujo.emitiendo = _visuales_escenario.get("humo", false)
	_actualizar_bolo()


func al_cambiar_pausa(pausado: bool) -> void:
	_pausado = pausado
	_actualizar_factor_tiempo()


func al_cambiar_velocidad(velocidad: float) -> void:
	_velocidad = velocidad
	_actualizar_factor_tiempo()


# --- Animación continua -------------------------------------------------------------

func _process(delta: float) -> void:
	if _visor == null:
		return
	var dt := delta * _factor_tiempo

	# Corazón: dos golpes por ciclo ("lub-dub")
	var c: Dictionary = _cfg.get("corazon", {})
	_fase_corazon = fposmod(_fase_corazon + _valor(c.get("variable"), 70.0) / 60.0 * dt, 1.0)
	var f := _fase_corazon
	var latido := exp(-pow((f - 0.1) / 0.05, 2.0)) + 0.55 * exp(-pow((f - 0.32) / 0.06, 2.0))
	var escala_corazon: Vector3 = Vector3.ONE * (1.0 + c.get("amplitud_latido", 0.1) * latido)
	for id in c.get("organos", []):
		_visor.escalar_organo(id, escala_corazon)

	# Pulmones: inspiración y espiración suaves
	var p: Dictionary = _cfg.get("pulmones", {})
	_fase_respiracion = fposmod(_fase_respiracion + _valor(p.get("variable"), 14.0) / 60.0 * dt, 1.0)
	var aire := 0.5 - 0.5 * cos(TAU * _fase_respiracion)
	var h: float = p.get("amplitud_horizontal", 0.07) * aire
	var escala_pulmon: Vector3 = Vector3(1.0 + h, 1.0 + p.get("amplitud_vertical", 0.04) * aire, 1.0 + h)
	for id in p.get("organos", []):
		_visor.escalar_organo(id, escala_pulmon)

	# Glóbulos rojos: más rápidos con mayor frecuencia cardiaca
	var g: Dictionary = _cfg.get("globulos", {})
	_globulos.velocidad = _valor(c.get("variable"), 70.0) * g.get("velocidad_por_lpm", 0.006)


func _actualizar_tintes() -> void:
	var p: Dictionary = _cfg.get("pulmones", {})
	var dano := _valor(p.get("variable_dano"), 0.0) / 100.0
	var color_dano: Color = Color.from_string(p.get("color_dano", "#2f2622"), Color.BLACK)
	for id in p.get("organos", []):
		_visor.tenir_organo(id, color_dano, dano * p.get("opacidad_dano_max", 0.8))

	var m: Dictionary = _cfg.get("musculos", {})
	var lactato: float = inverse_lerp(m.get("valor_sin_tinte", 1.2), m.get("valor_tinte_max", 10.0),
			_valor(m.get("variable"), 1.0))
	var color_musculo: Color = Color.from_string(m.get("color", "#7a0010"), Color.DARK_RED)
	for id in _musculos:
		_visor.tenir_organo(id, color_musculo, clampf(lactato, 0.0, 1.0) * m.get("opacidad_max", 0.75))


func _actualizar_bolo() -> void:
	var progreso: float = _valor(_cfg.get("bolo", {}).get("variable"), 0.0)
	_bolo.visible = _visuales_escenario.get("bolo", false) and progreso > 0.0 and progreso < 1.0
	if _bolo.visible:
		_bolo.position = _curva_bolo.sample_baked(progreso * _curva_bolo.get_baked_length(), true)


func _actualizar_factor_tiempo() -> void:
	_factor_tiempo = 0.0 if _pausado else _velocidad
	_globulos.factor_tiempo = _factor_tiempo
	for flujo in _humo:
		flujo.factor_tiempo = _factor_tiempo


func _crear_flujo(nombre: String, puntos: Array, cerrada: bool, cfg: Dictionary) -> FlujoParticulas:
	var flujo := FlujoParticulas.new()
	flujo.name = nombre
	flujo.configurar(puntos, cerrada, cfg.get("cantidad", 30), cfg.get("tamano", 0.012),
			Color.from_string(cfg.get("color", "#ffffff"), Color.WHITE), cfg.get("dispersion", 0.01))
	add_child(flujo)
	return flujo


func _valor(variable, por_defecto: float) -> float:
	return float(_estado.get(variable, por_defecto)) if variable != null else por_defecto
