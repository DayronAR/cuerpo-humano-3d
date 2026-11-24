class_name Tema
extends RefCounted

const RUTA := "user://preferencias.cfg"
const TEMAS := {"oscuro": "res://ui/tema.tres", "claro": "res://ui/tema_claro.tres"}

const PARES := [
	[Color(0.075, 0.105, 0.145, 0.94), Color(1, 1, 1, 0.94)],
	[Color(0.075, 0.105, 0.145, 0.97), Color(1, 1, 1, 0.97)],
	[Color(0.055, 0.08, 0.11, 0.96), Color(1, 1, 1, 0.96)],
	[Color(0, 0, 0, 0.35), Color(0, 0.1, 0.2, 0.15)],
	[Color(0, 0, 0, 0.4), Color(0, 0.1, 0.2, 0.18)],
	[Color(1, 1, 1, 0.06), Color(0, 0.1, 0.2, 0.07)],
	[Color(0.89, 0.925, 0.945, 1), Color(0.12, 0.2, 0.26, 1)],
	[Color(0.89, 0.93, 0.95, 1), Color(0.12, 0.2, 0.26, 1)],
	[Color(0.557, 0.639, 0.69, 1), Color(0.37, 0.45, 0.5, 1)],
	[Color(0.56, 0.64, 0.69, 1), Color(0.45, 0.52, 0.58, 1)],
	[Color(0.173, 0.773, 0.71, 1), Color(0.06, 0.43, 0.55, 1)],
	[Color(0.173, 0.773, 0.71, 0.16), Color(0.06, 0.43, 0.55, 0.12)],
	[Color(0.173, 0.773, 0.71, 0.6), Color(0.06, 0.43, 0.55, 0.5)],
	[Color(0.173, 0.773, 0.71, 0.8), Color(0.06, 0.43, 0.55, 0.75)],
	[Color(0.36, 0.85, 0.55, 1), Color(0.17, 0.55, 0.35, 1)],
	[Color(0.98, 0.45, 0.45, 1), Color(0.74, 0.28, 0.29, 1)],
	[Color(1.0, 0.5, 0.47, 1), Color(0.72, 0.22, 0.2, 1)],
	[Color(0.72, 0.6, 0.98, 1), Color(0.45, 0.3, 0.6, 1)],
	[Color(0.11, 0.153, 0.2, 1), Color(0.95, 0.97, 0.98, 1)],
	[Color(0.141, 0.196, 0.255, 1), Color(0.9, 0.95, 0.97, 1)],
	[Color(0.086, 0.235, 0.25, 1), Color(0.86, 0.94, 0.97, 1)],
	[Color(0.06, 0.09, 0.125, 1), Color(0.97, 0.98, 0.99, 1)],
	[Color(0.17, 0.22, 0.28, 1), Color(0.85, 0.89, 0.92, 1)],
	[Color(0.12, 0.16, 0.21, 1), Color(0.9, 0.93, 0.95, 1)],
]

const FONDOS := {
	"oscuro": {"centro": Color(0.11, 0.165, 0.22), "borde": Color(0.035, 0.05, 0.075),
			"plataforma": Color(0.13, 0.18, 0.23), "mini": Color(0.07, 0.1, 0.14), "suelo": Color(0.16, 0.21, 0.27)},
	"claro": {"centro": Color(0.97, 0.98, 0.99), "borde": Color(0.8, 0.86, 0.9),
			"plataforma": Color(0.74, 0.8, 0.85), "mini": Color(0.9, 0.94, 0.96), "suelo": Color(0.78, 0.84, 0.88)},
}

static var modo := "oscuro"
static var _conectado := false


static func dymj_cargar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	modo = cfg.get_value("apariencia", "tema", "oscuro")


static func dymj_guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)
	cfg.set_value("apariencia", "tema", modo)
	cfg.save(RUTA)


static func dymj_es_claro() -> bool:
	return modo == "claro"


static func dymj_color(oscuro: Color) -> Color:
	return dymj_traducir(oscuro, "oscuro", modo)


static func dymj_fondo(clave: String) -> Color:
	return FONDOS[modo][clave]


static func dymj_traducir(c: Color, desde: String, hacia: String) -> Color:
	if desde == hacia:
		return c
	var i := 0 if desde == "oscuro" else 1
	for par in PARES:
		if _dymj_parecidos(par[i], c):
			return par[1 - i]
	return c


static func _dymj_parecidos(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.012 and absf(a.g - b.g) < 0.012 and absf(a.b - b.b) < 0.012 \
			and absf(a.a - b.a) < 0.012


static var _copia_oscuro: Theme


static func dymj_aplicar(arbol: SceneTree, anterior: String) -> void:
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
				_dymj_traducir_control.call_deferred(n, "oscuro", modo))
	_dymj_recorrer(arbol.root, anterior, modo)


static func _dymj_recorrer(nodo: Node, desde: String, hacia: String) -> void:
	if nodo is Control:
		_dymj_traducir_control(nodo, desde, hacia)
	for hijo in nodo.get_children():
		_dymj_recorrer(hijo, desde, hacia)


static func _dymj_traducir_control(c: Control, desde: String, hacia: String) -> void:
	if not is_instance_valid(c) or desde == hacia or c.get_meta("tema", "oscuro") == hacia:
		return
	c.set_meta("tema", hacia)
	for p in c.get_property_list():
		var nombre: String = p.name
		if nombre.begins_with("theme_override_colors/"):
			var item := nombre.get_slice("/", 1)
			if c.has_theme_color_override(item):
				c.add_theme_color_override(item, dymj_traducir(c.get_theme_color(item), desde, hacia))
		elif nombre.begins_with("theme_override_styles/"):
			var item := nombre.get_slice("/", 1)
			if c.has_theme_stylebox_override(item):
				var caja := c.get_theme_stylebox(item)
				if caja is StyleBoxFlat:
					var nueva: StyleBoxFlat = caja.duplicate()
					nueva.bg_color = dymj_traducir(nueva.bg_color, desde, hacia)
					nueva.border_color = dymj_traducir(nueva.border_color, desde, hacia)
					nueva.shadow_color = dymj_traducir(nueva.shadow_color, desde, hacia)
					c.add_theme_stylebox_override(item, nueva)
	if c is ColorRect and c.get_meta("tema_color", true):
		c.color = dymj_traducir(c.color, desde, hacia)
