class_name EtiquetasFlotantes
extends Control
## Nombres de los órganos alrededor del cuerpo, unidos con una línea al punto que señalan.
## Las etiquetas se ordenan en dos columnas (izquierda y derecha de la pantalla) para que no se
## tapen entre sí. La fuente de los puntos es una función (ver HerramientasVisor.puntos_etiquetas).

const ALTO := 24.0
const MARGEN := 14.0
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
	var medio := area.get_center().x
	var izquierda := []
	var derecha := []
	for p in fuente_puntos.call():
		var mundo: Vector3 = p[1]
		if camara.is_position_behind(mundo):
			continue
		var pantalla := camara.unproject_position(mundo)
		if not area.grow(80).has_point(pantalla):
			continue
		(izquierda if pantalla.x < medio else derecha).append([p[0], pantalla])
	var fuente := get_theme_default_font()
	var tamano := 13
	for lado in [[izquierda, true], [derecha, false]]:
		var lista: Array = lado[0]
		lista.sort_custom(func(a, b): return a[1].y < b[1].y)
		var y_min := area.position.y + MARGEN
		var ys := []
		for e in lista:   # Cada etiqueta a la altura de su punto, sin pisar a la anterior
			var y := clampf(e[1].y - ALTO * 0.5, y_min, area.end.y - ALTO)
			ys.append(y)
			y_min = y + ALTO + 4
		for i in range(lista.size() - 2, -1, -1):   # Si se pasó del borde, se suben las de arriba
			ys[i] = minf(ys[i], ys[i + 1] - ALTO - 4)
		for i in lista.size():
			var texto: String = lista[i][0]
			var ancho := fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamano).x + 16
			var x := area.position.x + MARGEN if lado[1] else area.end.x - MARGEN - ancho
			var caja := Rect2(x, ys[i], ancho, ALTO)
			var ancla := Vector2(caja.end.x if lado[1] else caja.position.x, caja.get_center().y)
			var punto: Vector2 = lista[i][1]
			draw_line(ancla, punto, COLOR_LINEA, 1.5, true)
			draw_circle(punto, 3.5, COLOR_LINEA)
			draw_style_box(_estilo(), caja)
			draw_string(fuente, Vector2(caja.position.x + 8, caja.position.y + 17), texto,
					HORIZONTAL_ALIGNMENT_LEFT, -1, tamano, COLOR_TEXTO)


var _estilo_cache: StyleBoxFlat


func _estilo() -> StyleBoxFlat:
	if _estilo_cache == null:
		_estilo_cache = StyleBoxFlat.new()
		_estilo_cache.bg_color = COLOR_FONDO
		_estilo_cache.set_corner_radius_all(6)
		_estilo_cache.border_color = COLOR_LINEA
		_estilo_cache.set_border_width_all(1)
	return _estilo_cache
