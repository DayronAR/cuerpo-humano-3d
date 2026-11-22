class_name Tema
extends RefCounted
## Tema visual claro u oscuro. El oscuro es el de diseño: los colores fijos de las escenas y los
## scripts están escritos para él. En modo claro:
##   - la ventana usa res://ui/tema_claro.tres (botones, campos, listas, pestañas...), y
##   - los colores puestos a mano en cada control (overrides de color y de estilo) se traducen con
##     la tabla PARES, también en los controles que se crean después (señal node_added).
## Los dibujos propios (gráfico, etiquetas) piden sus colores con Tema.color().
## La elección se guarda en user://preferencias.cfg.

const RUTA := "user://preferencias.cfg"
const TEMAS := {"oscuro": "res://ui/tema.tres", "claro": "res://ui/tema_claro.tres"}

## [color en modo oscuro, color en modo claro]
const PARES := [
	[Color(0.075, 0.105, 0.145, 0.94), Color(1, 1, 1, 0.94)],      # Fondo de paneles
	[Color(0.075, 0.105, 0.145, 0.97), Color(1, 1, 1, 0.97)],
	[Color(0.055, 0.08, 0.11, 0.96), Color(1, 1, 1, 0.96)],         # Barra de navegación
	[Color(0, 0, 0, 0.35), Color(0, 0.1, 0.2, 0.15)],               # Sombras
	[Color(0, 0, 0, 0.4), Color(0, 0.1, 0.2, 0.18)],
	[Color(1, 1, 1, 0.06), Color(0, 0.1, 0.2, 0.07)],               # Bordes finos y hover del riel
	[Color(0.89, 0.925, 0.945, 1), Color(0.12, 0.2, 0.26, 1)],      # Texto
	[Color(0.89, 0.93, 0.95, 1), Color(0.12, 0.2, 0.26, 1)],
	[Color(0.557, 0.639, 0.69, 1), Color(0.37, 0.45, 0.5, 1)],      # Texto suave
	[Color(0.56, 0.64, 0.69, 1), Color(0.45, 0.52, 0.58, 1)],       # Íconos del riel
	[Color(0.173, 0.773, 0.71, 1), Color(0.06, 0.43, 0.55, 1)],     # Acento
	[Color(0.173, 0.773, 0.71, 0.16), Color(0.06, 0.43, 0.55, 0.12)],
	[Color(0.173, 0.773, 0.71, 0.6), Color(0.06, 0.43, 0.55, 0.5)],
	[Color(0.173, 0.773, 0.71, 0.8), Color(0.06, 0.43, 0.55, 0.75)],
	[Color(0.36, 0.85, 0.55, 1), Color(0.17, 0.55, 0.35, 1)],       # Verde
	[Color(0.98, 0.45, 0.45, 1), Color(0.74, 0.28, 0.29, 1)],       # Rojo
	[Color(1.0, 0.5, 0.47, 1), Color(0.72, 0.22, 0.2, 1)],
	[Color(0.72, 0.6, 0.98, 1), Color(0.45, 0.3, 0.6, 1)],          # Violeta (ficha: edad)
	[Color(0.11, 0.153, 0.2, 1), Color(0.95, 0.97, 0.98, 1)],       # Fondos de tarjetas y botones propios
	[Color(0.141, 0.196, 0.255, 1), Color(0.9, 0.95, 0.97, 1)],
	[Color(0.086, 0.235, 0.25, 1), Color(0.86, 0.94, 0.97, 1)],
	[Color(0.06, 0.09, 0.125, 1), Color(0.97, 0.98, 0.99, 1)],      # Gráfico
	[Color(0.17, 0.22, 0.28, 1), Color(0.85, 0.89, 0.92, 1)],
	[Color(0.12, 0.16, 0.21, 1), Color(0.9, 0.93, 0.95, 1)],
]

## Colores de fondo del 3D y del degradado, por modo
const FONDOS := {
	"oscuro": {"centro": Color(0.11, 0.165, 0.22), "borde": Color(0.035, 0.05, 0.075),
			"plataforma": Color(0.13, 0.18, 0.23), "mini": Color(0.07, 0.1, 0.14), "suelo": Color(0.16, 0.21, 0.27)},
	"claro": {"centro": Color(0.97, 0.98, 0.99), "borde": Color(0.8, 0.86, 0.9),
			"plataforma": Color(0.74, 0.8, 0.85), "mini": Color(0.9, 0.94, 0.96), "suelo": Color(0.78, 0.84, 0.88)},
}

static var modo := "oscuro"
static var _conectado := false


static func cargar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	modo = cfg.get_value("apariencia", "tema", "oscuro")


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	cfg.set_value("apariencia", "tema", modo)
	cfg.save(RUTA)


static func es_claro() -> bool:
	return modo == "claro"


## Color de un dibujo propio: se escribe el del modo oscuro y se traduce si hace falta.
static func color(oscuro: Color) -> Color:
	return traducir(oscuro, "oscuro", modo)


static func fondo(clave: String) -> Color:
	return FONDOS[modo][clave]


static func traducir(c: Color, desde: String, hacia: String) -> Color:
	if desde == hacia:
		return c
	var i := 0 if desde == "oscuro" else 1
	for par in PARES:
		if _parecidos(par[i], c):
			return par[1 - i]
	return c


static func _parecidos(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.012 and absf(a.g - b.g) < 0.012 and absf(a.b - b.b) < 0.012 \
			and absf(a.a - b.a) < 0.012


## Aplica el modo a toda la ventana. anterior: modo en que están pintados los controles ahora.
static var _copia_oscuro: Theme


static func aplicar(arbol: SceneTree, anterior: String) -> void:
	# La interfaz está en CanvasLayer, que corta la herencia del tema de la ventana: se cambia el
	# contenido del tema del proyecto (el mismo objeto que usan todos los controles)
	var proyecto := ThemeDB.get_project_theme()
	if proyecto:
		if _copia_oscuro == null:
			_copia_oscuro = proyecto.duplicate(true)
		proyecto.merge_with(load(TEMAS[modo]) if modo == "claro" else _copia_oscuro)
	else:
		arbol.root.theme = load(TEMAS[modo])
	if not _conectado:
		_conectado = true
		arbol.node_added.connect(func(n: Node):
			if modo != "oscuro" and n is Control:
				_traducir_control.call_deferred(n, "oscuro", modo))
	_recorrer(arbol.root, anterior, modo)


static func _recorrer(nodo: Node, desde: String, hacia: String) -> void:
	if nodo is Control:
		_traducir_control(nodo, desde, hacia)
	for hijo in nodo.get_children():
		_recorrer(hijo, desde, hacia)


## Traduce los colores y estilos puestos a mano en un control.
static func _traducir_control(c: Control, desde: String, hacia: String) -> void:
	if not is_instance_valid(c) or desde == hacia or c.get_meta("tema", "oscuro") == hacia:
		return
	c.set_meta("tema", hacia)
	for p in c.get_property_list():
		var nombre: String = p.name
		if nombre.begins_with("theme_override_colors/"):
			var item := nombre.get_slice("/", 1)
			if c.has_theme_color_override(item):
				c.add_theme_color_override(item, traducir(c.get_theme_color(item), desde, hacia))
		elif nombre.begins_with("theme_override_styles/"):
			var item := nombre.get_slice("/", 1)
			if c.has_theme_stylebox_override(item):
				var caja := c.get_theme_stylebox(item)
				if caja is StyleBoxFlat:
					var nueva: StyleBoxFlat = caja.duplicate()
					nueva.bg_color = traducir(nueva.bg_color, desde, hacia)
					nueva.border_color = traducir(nueva.border_color, desde, hacia)
					nueva.shadow_color = traducir(nueva.shadow_color, desde, hacia)
					c.add_theme_stylebox_override(item, nueva)
	if c is ColorRect and c.get_meta("tema_color", true):
		c.color = traducir(c.color, desde, hacia)
