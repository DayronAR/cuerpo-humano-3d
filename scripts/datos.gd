extends Node
## Autoload "Datos": carga los JSON de res://data/ una sola vez y los expone al resto del proyecto.
## Ningún otro script lee archivos de datos directamente; así hay un único punto de acceso.

const RUTA_SISTEMAS := "res://data/sistemas.json"
const RUTA_ORGANOS := "res://data/organos.json"
const RUTA_CAMARA := "res://data/camara.json"
const RUTA_ESCENARIOS := "res://data/escenarios.json"
const RUTA_VISUALES := "res://data/visuales.json"
const RUTA_CUESTIONARIO := "res://data/cuestionario.json"
const RUTA_PARTES := "res://data/partes.json"
const RUTA_PARTES_FICHAS := "res://data/partes_fichas.json"
const RUTA_EDAD := "res://data/edad.json"

var sistemas: Array = []          ## Lista ordenada de sistemas (cada uno es un Dictionary)
var orden_capas: Array = []       ## ids de sistema de afuera hacia adentro
var animacion_capas: Dictionary = {}
var organos: Dictionary = {}      ## id de nodo del órgano -> ficha
var camara: Dictionary = {}       ## Configuración de la cámara orbital
var simulacion: Dictionary = {}   ## Modelo de simulación: variables, estados, escenarios
var visuales: Dictionary = {}     ## Órganos, trayectorias y personaje de las visualizaciones
var cuestionario: Dictionary = {} ## Preguntas y reglas del modo cuestionario
var partes: Dictionary = {}       ## id de nodo de la parte -> {nombre, nombre_en, organo} (generado)
var partes_fichas: Dictionary = {} ## prefijo de id de parte -> {funcion, datos_curiosos} (opcional)
var edad: Dictionary = {}         ## Barra de edad: curvas de altura, pesos de las formas, etapas

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
	cuestionario = _cargar_json(RUTA_CUESTIONARIO)
	if FileAccess.file_exists(RUTA_PARTES):
		partes = _cargar_json(RUTA_PARTES).get("partes", {})
	if FileAccess.file_exists(RUTA_PARTES_FICHAS):
		partes_fichas = _cargar_json(RUTA_PARTES_FICHAS).get("partes", {})
	edad = _cargar_json(RUTA_EDAD)
	for s in sistemas:
		_sistemas_por_id[s.get("id", "")] = s


## Ficha de un órgano. Si no existe, devuelve una ficha mínima para no romper la interfaz.
## Cuerpo elegido en la pantalla de inicio ("" = el de data/visuales.json → cuerpo_activo).
var cuerpo_elegido := ""


## Modelo 3D activo (data/visuales.json → cuerpos[...]): escena, créditos y trayectorias.
func cuerpo_activo() -> Dictionary:
	var cuerpos: Dictionary = visuales.get("cuerpos", {})
	var activo: String = cuerpo_elegido if not cuerpo_elegido.is_empty() else visuales.get("cuerpo_activo", "")
	if cuerpos.has(activo):
		return cuerpos[activo]
	return cuerpos.values()[0] if not cuerpos.is_empty() else {}


func ficha_organo(id: String) -> Dictionary:
	if organos.has(id):
		return organos[id]
	push_warning("No hay ficha para el órgano '%s' en %s" % [id, RUTA_ORGANOS])
	return {"nombre": id, "funcion": "Sin información disponible.", "datos_curiosos": []}


## Nombre en español de una parte (p. ej. "Estribo (lado derecho)"); "" si no tiene ficha de parte.
func nombre_parte(id_parte: String) -> String:
	return partes.get(id_parte, {}).get("nombre", "")


## Ficha propia de una parte (por id exacto o por su comienzo), o {} si no tiene.
func ficha_parte(id_parte: String) -> Dictionary:
	if id_parte.is_empty():
		return {}
	for prefijo in partes_fichas:
		if id_parte.begins_with(prefijo):
			return partes_fichas[prefijo]
	return {}


## Valor de una curva [[x, y], ...] de data/edad.json para la edad dada (interpolación lineal).
func curva_edad(nombre: String, anios: float) -> float:
	var tabla: Array = edad.get(nombre, [[0, 0]])
	if anios <= tabla[0][0]:
		return tabla[0][1]
	for k in tabla.size() - 1:
		if anios <= tabla[k + 1][0]:
			return lerpf(tabla[k][1], tabla[k + 1][1], (anios - tabla[k][0]) / maxf(tabla[k + 1][0] - tabla[k][0], 1e-6))
	return tabla[-1][1]


func etapa_edad(anios: float) -> String:
	var nombre := ""
	for e in edad.get("etapas", []):
		if anios >= e[0]:
			nombre = e[1]
	return nombre


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
