class_name GraficoVivo
extends Control
## Gráfico de líneas en vivo dibujado con _draw(): muestra los últimos N segundos SIMULADOS de
## varias variables. Cada variable se normaliza a su propio rango [min, max] de escenarios.json,
## así caben en el mismo gráfico; la leyenda muestra el valor actual con su unidad.

@export var ventana := 60.0           ## Segundos simulados visibles
@export var intervalo_muestra := 0.25 ## Cada cuánto tiempo simulado se guarda un punto

var _series: Dictionary = {}          ## id -> PackedVector2Array (tiempo, valor)
var _info: Dictionary = {}            ## id -> info de la variable
var _ids: Array = []
var _ultimo_tiempo := -INF
var _tiempo_actual := 0.0
var _valores_actuales: Dictionary = {}

const MARGEN_IZQ := 12.0
const MARGEN_DER := 12.0
const ALTO_LEYENDA := 22.0
const ALTO_EJE := 16.0


## variables: diccionario de escenarios.json; se grafican las que tienen "grafico": true
func configurar(variables: Dictionary) -> void:
	_ids.clear()
	for id in variables:
		if variables[id].get("grafico", false):
			_ids.append(id)
			_info[id] = variables[id]
			_series[id] = PackedVector2Array()
	queue_redraw()


func agregar(estado: Dictionary) -> void:
	var t: float = estado.get("tiempo", 0.0)
	_tiempo_actual = t
	for id in _ids:
		_valores_actuales[id] = estado.get(id, 0.0)
	if t - _ultimo_tiempo < intervalo_muestra:
		return
	_ultimo_tiempo = t
	for id in _ids:
		var serie: PackedVector2Array = _series[id]
		serie.append(Vector2(t, estado.get(id, 0.0)))
		# Descartar puntos fuera de la ventana
		var corte := 0
		while corte < serie.size() and serie[corte].x < t - ventana:
			corte += 1
		if corte > 0:
			serie = serie.slice(corte)
		_series[id] = serie
	queue_redraw()


func limpiar() -> void:
	for id in _ids:
		_series[id] = PackedVector2Array()
	_ultimo_tiempo = -INF
	queue_redraw()


func _draw() -> void:
	var fuente := get_theme_default_font()
	var area := Rect2(MARGEN_IZQ, ALTO_LEYENDA, size.x - MARGEN_IZQ - MARGEN_DER,
			size.y - ALTO_LEYENDA - ALTO_EJE)
	# Fondo y cuadrícula
	draw_rect(area, Color(0.97, 0.98, 0.99))
	for i in 5:
		var y := area.position.y + area.size.y * i / 4.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(0.85, 0.89, 0.92), 1.0)
	for i in 7:
		var x := area.position.x + area.size.x * i / 6.0
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(0.9, 0.93, 0.95), 1.0)
	# Eje de tiempo
	for etiqueta in [[0.0, "-%d s" % int(ventana)], [0.5, "-%d s" % int(ventana / 2)], [1.0, "ahora"]]:
		var x: float = area.position.x + area.size.x * etiqueta[0]
		var ancho := fuente.get_string_size(etiqueta[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		x = clampf(x - ancho / 2.0, area.position.x, area.end.x - ancho)
		draw_string(fuente, Vector2(x, size.y - 3), etiqueta[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.45, 0.52, 0.58))
	# Líneas
	for id in _ids:
		var info: Dictionary = _info[id]
		var color := Color.from_string(info.get("color", "#888888"), Color.GRAY)
		var minimo: float = info.get("min", 0.0)
		var maximo: float = info.get("max", 1.0)
		var puntos := PackedVector2Array()
		for p in _series[id]:
			var x: float = area.position.x + area.size.x * (1.0 - (_tiempo_actual - p.x) / ventana)
			var y: float = area.end.y - area.size.y * clampf(inverse_lerp(minimo, maximo, p.y), 0.0, 1.0)
			puntos.append(Vector2(x, y))
		if puntos.size() >= 2:
			draw_polyline(puntos, color, 2.0, true)
	# Leyenda: abreviatura + valor actual
	var x_leyenda := MARGEN_IZQ
	for id in _ids:
		var info: Dictionary = _info[id]
		var color := Color.from_string(info.get("color", "#888888"), Color.GRAY)
		var formato := "%s %." + str(int(info.get("decimales", 0))) + "f %s"
		var texto := formato % [info.get("abreviatura", id),
				float(_valores_actuales.get(id, info.get("base", 0.0))), info.get("unidad", "")]
		draw_rect(Rect2(x_leyenda, 6, 10, 10), color)
		draw_string(fuente, Vector2(x_leyenda + 14, 16), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(0.15, 0.22, 0.28))
		x_leyenda += 20 + fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
