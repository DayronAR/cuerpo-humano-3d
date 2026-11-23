class_name EtiquetasFlotantes
extends Control
## Nombres de los órganos alrededor del cuerpo, unidos con una línea al punto que señalan.
## Las etiquetas se ordenan en dos columnas (izquierda y derecha de la pantalla) para que no se
## tapen entre sí. La fuente de los puntos es una función (ver HerramientasVisor.puntos_etiquetas).

const ALTO := 24.0
const MARGEN := 14.0
const SEPARACION := 4.0
const TAMANO := 13          ## Tamaño de letra
const DISTANCIA := 70.0     ## Separación entre la columna y el punto más cercano del cuerpo
const CODO := 14.0
const COLOR_LINEA := Color(0.173, 0.773, 0.71, 0.8)
const COLOR_FONDO := Color(0.075, 0.105, 0.145, 0.94)
const COLOR_TEXTO := Color(0.89, 0.925, 0.945, 1)

var fuente_puntos: Callable   ## () -> [[nombre, Vector3], ...]
var camara: Camera3D
var zona := Rect2()           ## Zona libre de la pantalla (sin paneles) para las columnas


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if not fuente_puntos.is_valid() or camara == null:
		return
	var area := zona if zona.has_area() else get_viewport_rect()
	var paso := ALTO + SEPARACION
	var capacidad := maxi(1, int((area.size.y - MARGEN * 2) / paso))
	# Puntos en pantalla (vienen ordenados por tamaño: si no entran todos, quedan los más grandes)
	var visibles := []
	for p in fuente_puntos.call():
		var mundo: Vector3 = p[1]
		if camara.is_position_behind(mundo):
			continue
		var pantalla := camara.unproject_position(mundo)
		if area.grow(40).has_point(pantalla):
			visibles.append([p[0], pantalla])
	visibles = visibles.slice(0, capacidad * 2)
	if visibles.is_empty():
		return
	# Dos columnas parejas: los puntos de la mitad izquierda del cuerpo a la izquierda y el resto a
	# la derecha (se divide por la mediana, no por el centro de la pantalla)
	var xs := visibles.map(func(e): return e[1].x)
	xs.sort()
	var mediana: float = xs[xs.size() / 2]
	var izquierda := []
	var derecha := []
	for e in visibles:
		if e[1].x < mediana or (e[1].x == mediana and izquierda.size() < derecha.size()):
			izquierda.append(e)
		else:
			derecha.append(e)
	var fuente := get_theme_default_font()
	for lado in [[izquierda, true], [derecha, false]]:
		var lista: Array = lado[0]
		if lista.is_empty():
			continue
		var es_izq: bool = lado[1]
		lista.sort_custom(func(a, b): return a[1].y < b[1].y)
		var ys := _repartir(lista.map(func(e): return e[1].y - ALTO * 0.5), area)
		# La columna se acerca al cuerpo (líneas cortas), sin salir de la zona libre
		var anchos := lista.map(func(e): return fuente.get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO).x + 16)
		var borde: float
		if es_izq:
			var min_x: float = lista.map(func(e): return e[1].x).min()
			borde = clampf(min_x - DISTANCIA, area.position.x + MARGEN + anchos.max(), area.end.x)
		else:
			var max_x: float = lista.map(func(e): return e[1].x).max()
			borde = clampf(max_x + DISTANCIA, area.position.x, area.end.x - MARGEN - anchos.max())
		for i in lista.size():
			var texto: String = lista[i][0]
			var ancho: float = anchos[i]
			var caja := Rect2(borde - ancho if es_izq else borde, ys[i], ancho, ALTO)
			var ancla := Vector2(caja.end.x if es_izq else caja.position.x, caja.get_center().y)
			var punto: Vector2 = lista[i][1]
			# Línea con un codo: horizontal desde la etiqueta y luego al punto
			var codo := Vector2(ancla.x + (CODO if es_izq else -CODO), ancla.y)
			draw_polyline(PackedVector2Array([ancla, codo, punto]), Tema.color(COLOR_LINEA), 1.5, true)
			draw_circle(punto, 3.5, Tema.color(COLOR_LINEA))
			draw_style_box(_estilo(), caja)
			draw_string(fuente, Vector2(caja.position.x + 8, caja.position.y + 17), texto,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO, Tema.color(COLOR_TEXTO))


## Alturas de las etiquetas: cada una lo más cerca posible de su punto, sin pisarse y sin salir de
## la zona (se empujan hacia abajo y, si se pasan del borde, hacia arriba).
func _repartir(deseadas: Array, area: Rect2) -> Array:
	var paso := ALTO + SEPARACION
	var ys := []
	var minimo := area.position.y + MARGEN
	for y in deseadas:
		var v: float = maxf(y, minimo)
		ys.append(v)
		minimo = v + paso
	var maximo := area.end.y - MARGEN - ALTO
	for i in range(ys.size() - 1, -1, -1):
		ys[i] = minf(ys[i], maximo)
		maximo = ys[i] - paso
	return ys


var _estilo_cache: StyleBoxFlat


func _estilo() -> StyleBoxFlat:
	if _estilo_cache == null or _estilo_cache.get_meta("tema", "") != Tema.modo:
		_estilo_cache = StyleBoxFlat.new()
		_estilo_cache.set_meta("tema", Tema.modo)
		_estilo_cache.bg_color = Tema.color(COLOR_FONDO)
		_estilo_cache.set_corner_radius_all(6)
		_estilo_cache.border_color = Tema.color(COLOR_LINEA)
		_estilo_cache.set_border_width_all(1)
	return _estilo_cache
