extends Node

const RUTA_SISTEMAS := "res://data/sistemas.json"
const RUTA_ORGANOS := "res://data/organos.json"
const RUTA_CAMARA := "res://data/camara.json"
const RUTA_ESCENARIOS := "res://data/escenarios.json"
const RUTA_VISUALES := "res://data/visuales.json"
const RUTA_CUESTIONARIO := "res://data/cuestionario.json"
const RUTA_PARTES := "res://data/partes.json"
const RUTA_PARTES_FICHAS := "res://data/partes_fichas.json"
const RUTA_EDAD := "res://data/edad.json"

var sistemas: Array = []
var orden_capas: Array = []
var animacion_capas: Dictionary = {}
var organos: Dictionary = {}
var camara: Dictionary = {}
var simulacion: Dictionary = {}
var visuales: Dictionary = {}
var cuestionario: Dictionary = {}
var partes: Dictionary = {}
var partes_fichas: Dictionary = {}
var edad: Dictionary = {}
var recorridos: Array = []

var _sistemas_por_id: Dictionary = {}


func _init() -> void:
	var datos_sistemas := _dymj_cargar_json(RUTA_SISTEMAS)
	sistemas = datos_sistemas.get("sistemas", [])
	orden_capas = datos_sistemas.get("orden_capas", [])
	animacion_capas = datos_sistemas.get("animacion_capas", {})
	organos = _dymj_cargar_json(RUTA_ORGANOS).get("organos", {})
	camara = _dymj_cargar_json(RUTA_CAMARA)
	simulacion = _dymj_cargar_json(RUTA_ESCENARIOS)
	visuales = _dymj_cargar_json(RUTA_VISUALES)
	cuestionario = _dymj_cargar_json(RUTA_CUESTIONARIO)
	if FileAccess.file_exists(RUTA_PARTES):
		partes = _dymj_cargar_json(RUTA_PARTES).get("partes", {})
	if FileAccess.file_exists(RUTA_PARTES_FICHAS):
		partes_fichas = _dymj_cargar_json(RUTA_PARTES_FICHAS).get("partes", {})
	edad = _dymj_cargar_json(RUTA_EDAD)
	if FileAccess.file_exists("res://data/recorridos.json"):
		recorridos = _dymj_cargar_json("res://data/recorridos.json").get("recorridos", [])
	for s in sistemas:
		_sistemas_por_id[s.get("id", "")] = s


var cuerpo_elegido := ""


func dymj_cuerpo_activo() -> Dictionary:
	var cuerpos: Dictionary = visuales.get("cuerpos", {})
	var activo: String = cuerpo_elegido if not cuerpo_elegido.is_empty() else visuales.get("cuerpo_activo", "")
	if cuerpos.has(activo):
		return cuerpos[activo]
	return cuerpos.values()[0] if not cuerpos.is_empty() else {}


func dymj_ficha_organo(id: String) -> Dictionary:
	if organos.has(id):
		return organos[id]
	push_warning("No hay ficha para el órgano '%s' en %s" % [id, RUTA_ORGANOS])
	return {"nombre": id, "funcion": "Sin información disponible.", "datos_curiosos": []}


func dymj_nombre_parte(id_parte: String) -> String:
	return partes.get(id_parte, {}).get("nombre", "")


func dymj_ficha_parte(id_parte: String) -> Dictionary:
	if id_parte.is_empty():
		return {}
	for prefijo in partes_fichas:
		if id_parte.begins_with(prefijo):
			return partes_fichas[prefijo]
	return {}


func dymj_curva_edad(nombre: String, anios: float) -> float:
	var tabla: Array = edad.get(nombre, [[0, 0]])
	if anios <= tabla[0][0]:
		return tabla[0][1]
	for k in tabla.size() - 1:
		if anios <= tabla[k + 1][0]:
			return lerpf(tabla[k][1], tabla[k + 1][1], (anios - tabla[k][0]) / maxf(tabla[k + 1][0] - tabla[k][0], 1e-6))
	return tabla[-1][1]


func dymj_etapa_edad(anios: float) -> String:
	var nombre := ""
	for e in edad.get("etapas", []):
		if anios >= e[0]:
			nombre = e[1]
	return nombre


func dymj_sistema(id: String) -> Dictionary:
	return _sistemas_por_id.get(id, {})


func dymj_nombre_sistema(id: String) -> String:
	return dymj_sistema(id).get("nombre", id)


func dymj_cubierto_por(id: String) -> Array:
	return dymj_sistema(id).get("cubierto_por", [])


func dymj_color_sistema(id: String) -> Color:
	return Color.from_string(dymj_sistema(id).get("color", "#888888"), Color.GRAY)


func _dymj_cargar_json(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		push_error("No existe el archivo de datos: %s" % ruta)
		return {}
	var json := JSON.new()
	var error := json.parse(FileAccess.get_file_as_string(ruta))
	if error != OK:
		push_error("JSON inválido en %s (línea %d): %s" % [ruta, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("Se esperaba un objeto JSON en la raíz de %s" % ruta)
		return {}
	return json.data
