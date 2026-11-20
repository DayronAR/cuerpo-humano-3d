extends Node
## Autoload "Datos": carga los JSON de res://data/ una sola vez y los expone al resto del proyecto.
## Ningún otro script lee archivos de datos directamente; así hay un único punto de acceso.

const RUTA_SISTEMAS := "res://data/sistemas.json"
const RUTA_ORGANOS := "res://data/organos.json"
const RUTA_CAMARA := "res://data/camara.json"
const RUTA_ESCENARIOS := "res://data/escenarios.json"
const RUTA_VISUALES := "res://data/visuales.json"

var sistemas: Array = []          ## Lista ordenada de sistemas (cada uno es un Dictionary)
var orden_capas: Array = []       ## ids de sistema de afuera hacia adentro
var animacion_capas: Dictionary = {}
var organos: Dictionary = {}      ## id de nodo del órgano -> ficha
var camara: Dictionary = {}       ## Configuración de la cámara orbital
var simulacion: Dictionary = {}   ## Modelo de simulación: variables, estados, escenarios
var visuales: Dictionary = {}     ## Órganos, trayectorias y personaje de las visualizaciones

var _sistemas_por_id: Dictionary = {}


func _init() -> void:
	var datos_sistemas := _cargar_json(RUTA_SISTEMAS)
	sistemas = datos_sistemas.get("sistemas", [])
	orden_capas = datos_sistemas.get("orden_capas", [])
	animacion_capas = datos_sistemas.get("animacion_capas", {})
	organos = _cargar_json(RUTA_ORGANOS).get("organos", {})
	camara = _cargar_json(RUTA_CAMARA)
	simulacion = _cargar_json(RUTA_ESCENARIOS)
	visuales = _cargar_json(RUTA_VISUALES)
	for s in sistemas:
		_sistemas_por_id[s.get("id", "")] = s


## Ficha de un órgano. Si no existe, devuelve una ficha mínima para no romper la interfaz.
func ficha_organo(id: String) -> Dictionary:
	if organos.has(id):
		return organos[id]
	push_warning("No hay ficha para el órgano '%s' en %s" % [id, RUTA_ORGANOS])
	return {"nombre": id, "funcion": "Sin información disponible.", "datos_curiosos": []}


func sistema(id: String) -> Dictionary:
	return _sistemas_por_id.get(id, {})


func nombre_sistema(id: String) -> String:
	return sistema(id).get("nombre", id)


## Capas (ids de sistema) que hay que retirar para ver el sistema indicado.
func cubierto_por(id: String) -> Array:
	return sistema(id).get("cubierto_por", [])


func color_sistema(id: String) -> Color:
	return Color.from_string(sistema(id).get("color", "#888888"), Color.GRAY)


func _cargar_json(ruta: String) -> Dictionary:
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
