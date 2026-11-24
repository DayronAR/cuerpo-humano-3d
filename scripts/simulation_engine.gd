extends Node

signal estado_actualizado(jlrl_estado: Dictionary)
signal escenario_cambiado(id_escenario: String, activo: bool)
signal estados_cambiados(estados: Array)
signal pausa_cambiada(pausado: bool)
signal velocidad_cambiada(velocidad: float)
signal intensidad_cambiada(id_intensidad: String)
signal simulacion_reiniciada

const PASO_MAXIMO := 0.1

var valores: Dictionary = {}
var tiempo := 0.0
var tiempo_escenario := 0.0
var velocidad := 1.0
var pausado := false
var escenario_id := ""
var escenario_activo := false
var intensidad_id := ""
var estados_activos: Array = []

var _variables: Dictionary = {}
var _escenarios: Dictionary = {}
var _estados: Array = []
var _acoplamientos: Array = []
var _actividades: Dictionary = {}


func _ready() -> void:
	var datos: Dictionary = Datos.simulacion
	_variables = datos.get("variables", {})
	_estados = datos.get("estados", [])
	_acoplamientos = datos.get("acoplamientos", [])
	_actividades = datos.get("actividades", {})
	for e in datos.get("escenarios", []):
		_escenarios[e.get("id")] = e
	_jlrl_poner_valores_base()


func jlrl_seleccionar_escenario(id: String) -> void:
	if id == escenario_id:
		return
	if not id.is_empty() and not _escenarios.has(id):
		push_warning("Escenario desconocido: %s" % id)
		return
	escenario_id = id
	escenario_activo = false
	intensidad_id = jlrl_escenario().get("intensidad_inicial", "")
	escenario_cambiado.emit(escenario_id, false)
	intensidad_cambiada.emit(intensidad_id)


func jlrl_iniciar() -> void:
	if not escenario_id.is_empty() and not escenario_activo:
		escenario_activo = true
		tiempo_escenario = 0.0
		escenario_cambiado.emit(escenario_id, true)
	if pausado:
		pausado = false
		pausa_cambiada.emit(false)


func jlrl_pausar() -> void:
	if not pausado:
		pausado = true
		pausa_cambiada.emit(true)


func jlrl_reiniciar() -> void:
	_jlrl_poner_valores_base()
	tiempo = 0.0
	tiempo_escenario = 0.0
	escenario_activo = false
	if not estados_activos.is_empty():
		estados_activos = []
		estados_cambiados.emit(estados_activos)
	if pausado:
		pausado = false
		pausa_cambiada.emit(false)
	simulacion_reiniciada.emit()
	escenario_cambiado.emit(escenario_id, false)
	estado_actualizado.emit(jlrl_estado())


func jlrl_fijar_velocidad(nueva: float) -> void:
	velocidad = maxf(nueva, 0.0)
	velocidad_cambiada.emit(velocidad)


func jlrl_fijar_intensidad(id: String) -> void:
	for i in jlrl_escenario().get("intensidades", []):
		if i.get("id") == id:
			intensidad_id = id
			intensidad_cambiada.emit(id)
			return


func jlrl_escenario() -> Dictionary:
	return _escenarios.get(escenario_id, {})


func jlrl_escenarios() -> Array:
	return _escenarios.values()


func jlrl_info_variable(id: String) -> Dictionary:
	return _variables.get(id, {})


func jlrl_actividad() -> String:
	if not escenario_activo:
		return "reposo"
	for e in _estados:
		if e.get("id") in estados_activos and e.has("actividad"):
			return e["actividad"]
	var intensidad := _jlrl_intensidad()
	return intensidad.get("actividad", jlrl_escenario().get("actividad", "reposo"))


func jlrl_nombre_actividad(id: String) -> String:
	return _actividades.get(id, id)


func jlrl_estado() -> Dictionary:
	var e := valores.duplicate()
	e["tiempo"] = tiempo
	e["tiempo_escenario"] = tiempo_escenario
	e["escenario"] = escenario_id
	e["activo"] = escenario_activo
	e["estados"] = estados_activos.duplicate()
	e["actividad"] = jlrl_actividad()
	return e


func _process(delta: float) -> void:
	if pausado or velocidad <= 0.0:
		return
	var restante := delta * velocidad
	while restante > 0.0:
		var dt := minf(restante, PASO_MAXIMO)
		_jlrl_paso(dt)
		restante -= dt
	estado_actualizado.emit(jlrl_estado())


func _jlrl_paso(dt: float) -> void:
	tiempo += dt
	if escenario_activo:
		tiempo_escenario += dt

	var objetivos := _jlrl_calcular_objetivos()
	var tasas := _jlrl_calcular_tasas()

	for id in _variables:
		var info: Dictionary = _variables[id]
		var v: float = valores[id]
		var tau = info.get("tau")
		if tau != null and tau > 0.0:
			v = objetivos[id] + (v - objetivos[id]) * exp(-dt / tau)
		v += tasas.get(id, 0.0) * dt
		valores[id] = clampf(v, info.get("min", -INF), info.get("max", INF))

	_jlrl_aplicar_rampas()
	_jlrl_actualizar_estados()


var ajustes_base: Dictionary = {}


func jlrl_fijar_ajustes_base(ajustes: Dictionary) -> void:
	ajustes_base = ajustes
	if not escenario_activo:
		var objetivos := _jlrl_calcular_objetivos()
		for id in ajustes:
			if valores.has(id):
				valores[id] = objetivos[id]
		estado_actualizado.emit(jlrl_estado())


func _jlrl_calcular_objetivos() -> Dictionary:
	var objetivos := {}
	for id in _variables:
		objetivos[id] = float(_variables[id].get("base", 0.0)) + float(ajustes_base.get(id, 0.0))
	for a in _acoplamientos:
		if objetivos.has(a.get("variable")) and valores.has(a.get("desde")):
			objetivos[a["variable"]] += a.get("factor", 0.0) * valores[a["desde"]]
	for efecto in _jlrl_efectos_activos():
		var id: String = efecto.get("variable", "")
		if not objetivos.has(id):
			continue
		match efecto.get("tipo"):
			"objetivo":
				objetivos[id] += efecto.get("delta", 0.0) * _jlrl_factor(efecto)
			"curva":
				var tp: float = maxf(efecto.get("tiempo_pico", 1.0), 0.001)
				var x := tiempo_escenario / tp
				objetivos[id] += efecto.get("pico", 0.0) * x * exp(1.0 - x) * _jlrl_factor(efecto)
	return objetivos


func _jlrl_calcular_tasas() -> Dictionary:
	var tasas := {}
	for efecto in _jlrl_efectos_activos():
		if efecto.get("tipo") == "tasa":
			var id: String = efecto.get("variable", "")
			tasas[id] = tasas.get(id, 0.0) + efecto.get("por_segundo", 0.0) * _jlrl_factor(efecto)
	return tasas


func _jlrl_aplicar_rampas() -> void:
	for efecto in _jlrl_efectos_activos():
		if efecto.get("tipo") == "rampa" and valores.has(efecto.get("variable")):
			var duracion: float = maxf(efecto.get("duracion", 1.0), 0.001)
			valores[efecto["variable"]] = clampf(tiempo_escenario / duracion, 0.0, 1.0)


func _jlrl_efectos_activos() -> Array:
	var lista := []
	if escenario_activo:
		for e in jlrl_escenario().get("efectos", []):
			lista.append(e)
	for estado_def in _estados:
		if estado_def.get("id") in estados_activos:
			for e in estado_def.get("efectos", []):
				var copia: Dictionary = e.duplicate()
				copia["_sin_intensidad"] = true
				lista.append(copia)
	return lista


func _jlrl_factor(efecto: Dictionary) -> float:
	if efecto.get("_sin_intensidad", false):
		return 1.0
	var factor: float = _jlrl_intensidad().get("factor", 1.0)
	return pow(factor, efecto.get("exponente", 1.0))


func _jlrl_intensidad() -> Dictionary:
	for i in jlrl_escenario().get("intensidades", []):
		if i.get("id") == intensidad_id:
			return i
	return {}


func _jlrl_actualizar_estados() -> void:
	var nuevos := []
	for e in _estados:
		var id: String = e.get("id")
		var activo: bool = id in estados_activos
		if activo:
			activo = not _jlrl_cumple(e.get("salir", {}))
		else:
			activo = _jlrl_cumple(e.get("entrar", {}))
		if activo:
			nuevos.append(id)
	if nuevos != estados_activos:
		estados_activos = nuevos
		estados_cambiados.emit(estados_activos)


func _jlrl_cumple(condicion: Dictionary) -> bool:
	var v = valores.get(condicion.get("variable", ""))
	if v == null:
		return false
	if condicion.has("mayor_que") and v > condicion["mayor_que"]:
		return true
	if condicion.has("menor_que") and v < condicion["menor_que"]:
		return true
	return false


func _jlrl_poner_valores_base() -> void:
	for id in _variables:
		valores[id] = float(_variables[id].get("base", 0.0))
