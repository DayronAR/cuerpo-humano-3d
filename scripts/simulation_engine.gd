extends Node
## Autoload "SimulationEngine": motor fisiológico simplificado.
##
## No contiene números fisiológicos: interpreta las reglas de res://data/escenarios.json.
## Cada variable converge exponencialmente hacia un objetivo:
##
##     valor = objetivo + (valor - objetivo) · e^(-dt / tau)
##
## que es la solución exacta de  d(valor)/dt = (objetivo - valor) / tau,
## estable con cualquier paso de tiempo (importa al usar velocidad x4).
## El objetivo se recalcula en cada paso a partir de: valor base + acoplamientos + efectos del
## escenario activo (escalados por la intensidad) + efectos de los estados activos.
##
## La vista nunca calcula fisiología: escucha la señal estado_actualizado.

signal estado_actualizado(estado: Dictionary)
signal escenario_cambiado(id_escenario: String, activo: bool)
signal estados_cambiados(estados: Array)            ## ids de estados activos (p. ej. ["cansado"])
signal pausa_cambiada(pausado: bool)
signal velocidad_cambiada(velocidad: float)
signal intensidad_cambiada(id_intensidad: String)
signal simulacion_reiniciada

const PASO_MAXIMO := 0.1   ## Segundos simulados por subpaso (para que las tasas y estados sean precisos)

var valores: Dictionary = {}          ## id de variable -> valor actual
var tiempo := 0.0                     ## Tiempo simulado total (s)
var tiempo_escenario := 0.0           ## Tiempo simulado desde que se inició el escenario
var velocidad := 1.0
var pausado := false
var escenario_id := ""                ## Escenario elegido ("" = ninguno)
var escenario_activo := false         ## true si sus efectos se están aplicando
var intensidad_id := ""
var estados_activos: Array = []

var _variables: Dictionary = {}
var _escenarios: Dictionary = {}      ## id -> Dictionary
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
	_poner_valores_base()


# --- API de control --------------------------------------------------------------

func seleccionar_escenario(id: String) -> void:
	if id == escenario_id:
		return
	if not id.is_empty() and not _escenarios.has(id):
		push_warning("Escenario desconocido: %s" % id)
		return
	escenario_id = id
	escenario_activo = false
	intensidad_id = escenario().get("intensidad_inicial", "")
	escenario_cambiado.emit(escenario_id, false)
	intensidad_cambiada.emit(intensidad_id)


## Activa el escenario elegido (o reanuda si estaba en pausa).
func iniciar() -> void:
	if not escenario_id.is_empty() and not escenario_activo:
		escenario_activo = true
		tiempo_escenario = 0.0
		escenario_cambiado.emit(escenario_id, true)
	if pausado:
		pausado = false
		pausa_cambiada.emit(false)


func pausar() -> void:
	if not pausado:
		pausado = true
		pausa_cambiada.emit(true)


## Vuelve a los valores de reposo y desactiva el escenario (sigue elegido).
func reiniciar() -> void:
	_poner_valores_base()
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
	estado_actualizado.emit(estado())


func fijar_velocidad(nueva: float) -> void:
	velocidad = maxf(nueva, 0.0)
	velocidad_cambiada.emit(velocidad)


func fijar_intensidad(id: String) -> void:
	for i in escenario().get("intensidades", []):
		if i.get("id") == id:
			intensidad_id = id
			intensidad_cambiada.emit(id)
			return


# --- Consultas -------------------------------------------------------------------

func escenario() -> Dictionary:
	return _escenarios.get(escenario_id, {})


func escenarios() -> Array:
	return _escenarios.values()


func info_variable(id: String) -> Dictionary:
	return _variables.get(id, {})


## Actividad del personaje: la del estado activo si la define (p. ej. "cansado"),
## si no la de la intensidad o del escenario, y "reposo" si no hay escenario activo.
func actividad() -> String:
	if not escenario_activo:
		return "reposo"
	for e in _estados:
		if e.get("id") in estados_activos and e.has("actividad"):
			return e["actividad"]
	var intensidad := _intensidad()
	return intensidad.get("actividad", escenario().get("actividad", "reposo"))


func nombre_actividad(id: String) -> String:
	return _actividades.get(id, id)


## Instantánea del estado para la vista. Incluye todas las variables más datos de contexto.
func estado() -> Dictionary:
	var e := valores.duplicate()
	e["tiempo"] = tiempo
	e["tiempo_escenario"] = tiempo_escenario
	e["escenario"] = escenario_id
	e["activo"] = escenario_activo
	e["estados"] = estados_activos.duplicate()
	e["actividad"] = actividad()
	return e


# --- Bucle de simulación -------------------------------------------------------------

func _process(delta: float) -> void:
	if pausado or velocidad <= 0.0:
		return
	var restante := delta * velocidad
	while restante > 0.0:
		var dt := minf(restante, PASO_MAXIMO)
		_paso(dt)
		restante -= dt
	estado_actualizado.emit(estado())


func _paso(dt: float) -> void:
	tiempo += dt
	if escenario_activo:
		tiempo_escenario += dt

	var objetivos := _calcular_objetivos()
	var tasas := _calcular_tasas()

	for id in _variables:
		var info: Dictionary = _variables[id]
		var v: float = valores[id]
		var tau = info.get("tau")
		if tau != null and tau > 0.0:
			v = objetivos[id] + (v - objetivos[id]) * exp(-dt / tau)
		v += tasas.get(id, 0.0) * dt
		valores[id] = clampf(v, info.get("min", -INF), info.get("max", INF))

	_aplicar_rampas()
	_actualizar_estados()


func _calcular_objetivos() -> Dictionary:
	var objetivos := {}
	for id in _variables:
		objetivos[id] = float(_variables[id].get("base", 0.0))
	for a in _acoplamientos:
		if objetivos.has(a.get("variable")) and valores.has(a.get("desde")):
			objetivos[a["variable"]] += a.get("factor", 0.0) * valores[a["desde"]]
	for efecto in _efectos_activos():
		var id: String = efecto.get("variable", "")
		if not objetivos.has(id):
			continue
		match efecto.get("tipo"):
			"objetivo":
				objetivos[id] += efecto.get("delta", 0.0) * _factor(efecto)
			"curva":
				var tp: float = maxf(efecto.get("tiempo_pico", 1.0), 0.001)
				var x := tiempo_escenario / tp
				objetivos[id] += efecto.get("pico", 0.0) * x * exp(1.0 - x) * _factor(efecto)
	return objetivos


func _calcular_tasas() -> Dictionary:
	var tasas := {}
	for efecto in _efectos_activos():
		if efecto.get("tipo") == "tasa":
			var id: String = efecto.get("variable", "")
			tasas[id] = tasas.get(id, 0.0) + efecto.get("por_segundo", 0.0) * _factor(efecto)
	return tasas


func _aplicar_rampas() -> void:
	for efecto in _efectos_activos():
		if efecto.get("tipo") == "rampa" and valores.has(efecto.get("variable")):
			var duracion: float = maxf(efecto.get("duracion", 1.0), 0.001)
			valores[efecto["variable"]] = clampf(tiempo_escenario / duracion, 0.0, 1.0)


## Efectos del escenario activo (marcados para escalar con la intensidad) y de los estados activos.
func _efectos_activos() -> Array:
	var lista := []
	if escenario_activo:
		for e in escenario().get("efectos", []):
			lista.append(e)
	for estado_def in _estados:
		if estado_def.get("id") in estados_activos:
			for e in estado_def.get("efectos", []):
				var copia: Dictionary = e.duplicate()
				copia["_sin_intensidad"] = true
				lista.append(copia)
	return lista


func _factor(efecto: Dictionary) -> float:
	if efecto.get("_sin_intensidad", false):
		return 1.0
	var factor: float = _intensidad().get("factor", 1.0)
	return pow(factor, efecto.get("exponente", 1.0))


func _intensidad() -> Dictionary:
	for i in escenario().get("intensidades", []):
		if i.get("id") == intensidad_id:
			return i
	return {}


func _actualizar_estados() -> void:
	var nuevos := []
	for e in _estados:
		var id: String = e.get("id")
		var activo: bool = id in estados_activos
		if activo:
			activo = not _cumple(e.get("salir", {}))
		else:
			activo = _cumple(e.get("entrar", {}))
		if activo:
			nuevos.append(id)
	if nuevos != estados_activos:
		estados_activos = nuevos
		estados_cambiados.emit(estados_activos)


func _cumple(condicion: Dictionary) -> bool:
	var v = valores.get(condicion.get("variable", ""))
	if v == null:
		return false
	if condicion.has("mayor_que") and v > condicion["mayor_que"]:
		return true
	if condicion.has("menor_que") and v < condicion["menor_que"]:
		return true
	return false


func _poner_valores_base() -> void:
	for id in _variables:
		valores[id] = float(_variables[id].get("base", 0.0))
