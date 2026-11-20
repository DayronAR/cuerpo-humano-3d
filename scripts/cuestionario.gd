class_name Cuestionario
extends Node
## Lógica del modo cuestionario (sin interfaz). Elige preguntas al azar de data/cuestionario.json,
## evalúa la respuesta (el órgano en el que se hizo clic), lleva el puntaje y lo guarda al final.
## La interfaz y el 3D reaccionan a sus señales.

signal pregunta_nueva(numero: int, total: int, texto: String, id_organo: String)
## correcta; id respondido ("" si se saltó); id correcto; puntos de esta respuesta; puntaje total;
## intentos que quedan (0 = la pregunta terminó)
signal respuesta_evaluada(correcta: bool, id_respondido: String, id_correcto: String, puntos: int,
		puntaje: int, intentos_restantes: int)
signal ronda_terminada(puntaje: int, maximo: int, es_record: bool)

var activo := false          ## Hay una ronda en curso
var esperando := false       ## La pregunta actual espera un clic

var _config: Dictionary = {}
var _preguntas: Array = []
var _ronda: Array = []
var _indice := -1
var _intentos_usados := 0
var _puntaje := 0


## ids_validos: órganos que existen en la escena (se ignoran preguntas de órganos que no estén)
func configurar(datos: Dictionary, ids_validos: Array) -> void:
	_config = datos
	_preguntas = datos.get("preguntas", []).filter(func(p): return p.get("organo") in ids_validos)


func iniciar() -> void:
	var mezcladas := _preguntas.duplicate()
	mezcladas.shuffle()
	_ronda.clear()
	var usados := {}
	for p in mezcladas:
		if not usados.has(p["organo"]):
			usados[p["organo"]] = true
			_ronda.append(p)
		if _ronda.size() >= int(_config.get("preguntas_por_ronda", 10)):
			break
	_indice = -1
	_puntaje = 0
	activo = true
	siguiente()


func siguiente() -> void:
	if not activo:
		return
	_indice += 1
	if _indice >= _ronda.size():
		_terminar()
		return
	_intentos_usados = 0
	esperando = true
	var p: Dictionary = _ronda[_indice]
	pregunta_nueva.emit(_indice + 1, _ronda.size(), p.get("texto", ""), p.get("organo", ""))


func responder(id_organo: String) -> void:
	if not esperando:
		return
	var correcto := organo_actual()
	_intentos_usados += 1
	var maximos := int(_config.get("intentos", 2))
	if id_organo == correcto:
		var tabla: Array = _config.get("puntos_por_intento", [10, 5])
		var puntos := int(tabla[mini(_intentos_usados - 1, tabla.size() - 1)])
		_puntaje += puntos
		esperando = false
		respuesta_evaluada.emit(true, id_organo, correcto, puntos, _puntaje, 0)
	else:
		var restantes := maxi(maximos - _intentos_usados, 0)
		esperando = restantes > 0
		respuesta_evaluada.emit(false, id_organo, correcto, 0, _puntaje, restantes)


func saltar() -> void:
	if not esperando:
		return
	esperando = false
	respuesta_evaluada.emit(false, "", organo_actual(), 0, _puntaje, 0)


func abandonar() -> void:
	activo = false
	esperando = false


func organo_actual() -> String:
	if _indice < 0 or _indice >= _ronda.size():
		return ""
	return _ronda[_indice].get("organo", "")


func mostrar_sistema() -> bool:
	return _config.get("mostrar_sistema", true)


func _terminar() -> void:
	activo = false
	esperando = false
	var maximo := _ronda.size() * int(_config.get("puntos_por_intento", [10])[0])
	var record := RegistroPuntajes.registrar(_puntaje, maximo)
	ronda_terminada.emit(_puntaje, maximo, record)
