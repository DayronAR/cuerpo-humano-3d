extends SceneTree


const PALETAS := {
	"oscuro": {
		"primario": Color("2cc5b5"), "primario_oscuro": Color("1f9d91"), "primario_suave": Color("163c40"),
		"fondo_boton": Color("1c2733"), "fondo_boton_hover": Color("243241"), "borde": Color("2c3a49"),
		"texto": Color("e4ecf1"), "texto_suave": Color("8ea3b0"), "deshabilitado": Color("526371"),
		"sobre_primario": Color("0b1219"), "panel": Color(0.075, 0.105, 0.145, 0.94),
		"boton_deshabilitado": Color("161f29"), "borde_deshabilitado": Color("222d39"),
		"pestana_inactiva": Color(0.075, 0.105, 0.145, 0.6), "pestana_hover": Color(0.1, 0.14, 0.19, 0.8),
		"tooltip": Color("243241"), "barra": Color("33445a"), "barra_hover": Color("4a5f76"),
		"campo": Color("101821"), "guia": Color("1c2733"), "riel": Color("26333f"),
		"sombra": Color(0, 0, 0, 0.35), "borde_panel": Color(1, 1, 1, 0.06),
	},
	"claro": {
		"primario": Color("0f6e8c"), "primario_oscuro": Color("0b5670"), "primario_suave": Color("dcedf3"),
		"fondo_boton": Color("eef4f7"), "fondo_boton_hover": Color("e1eef3"), "borde": Color("c9d9e1"),
		"texto": Color("1f3340"), "texto_suave": Color("5d7280"), "deshabilitado": Color("a9b8c1"),
		"sobre_primario": Color("ffffff"), "panel": Color(1, 1, 1, 0.94),
		"boton_deshabilitado": Color("f3f6f8"), "borde_deshabilitado": Color("e1e8ec"),
		"pestana_inactiva": Color(1, 1, 1, 0.55), "pestana_hover": Color(1, 1, 1, 0.8),
		"tooltip": Color("1f3340"), "barra": Color("c3d3dc"), "barra_hover": Color("9fb6c2"),
		"campo": Color("ffffff"), "guia": Color("e6edf1"), "riel": Color("dbe5ea"),
		"sombra": Color(0, 0.1, 0.2, 0.15), "borde_panel": Color(0, 0, 0, 0.06),
	},
}
const SALIDAS := {"oscuro": "res://ui/tema.tres", "claro": "res://ui/tema_claro.tres"}
var P: Dictionary


func _init() -> void:
	for modo in PALETAS:
		P = PALETAS[modo]
		if ResourceSaver.save(_generar(), SALIDAS[modo]) != OK:
			push_error("No se pudo guardar el tema " + modo)
			quit(1)
			return
		print("Tema generado en ", SALIDAS[modo])
	quit()


func _generar() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	t.set_stylebox("normal", "Button", _caja(P.fondo_boton, P.borde))
	t.set_stylebox("hover", "Button", _caja(P.fondo_boton_hover, P.primario.lerp(P.borde, 0.5)))
	t.set_stylebox("pressed", "Button", _caja(P.primario, P.primario_oscuro))
	t.set_stylebox("hover_pressed", "Button", _caja(P.primario_oscuro, P.primario_oscuro))
	t.set_stylebox("disabled", "Button", _caja(P.boton_deshabilitado, P.borde_deshabilitado))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", P.texto)
	t.set_color("font_hover_color", "Button", P.primario)
	t.set_color("font_pressed_color", "Button", P.sobre_primario)
	t.set_color("font_hover_pressed_color", "Button", P.sobre_primario)
	t.set_color("font_disabled_color", "Button", P.deshabilitado)
	t.set_color("font_focus_color", "Button", P.texto)
	t.set_color("icon_normal_color", "Button", P.texto)
	t.set_color("icon_hover_color", "Button", P.primario)
	t.set_color("icon_pressed_color", "Button", P.sobre_primario)
	t.set_color("icon_hover_pressed_color", "Button", P.sobre_primario)
	t.set_color("icon_focus_color", "Button", P.texto)

	t.set_color("font_color", "CheckButton", P.texto)
	t.set_color("font_pressed_color", "CheckButton", P.primario)
	t.set_color("font_hover_color", "CheckButton", P.primario)
	t.set_color("font_hover_pressed_color", "CheckButton", P.primario)
	for estado in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(estado, "CheckButton", _caja(P.fondo_boton if not estado.begins_with("hover") else P.fondo_boton_hover, P.borde))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	t.set_color("font_color", "Label", P.texto)

	t.set_stylebox("panel", "PanelContainer", _caja(P.panel, Color(0, 0, 0, 0), 12, 12, true))
	t.set_stylebox("panel", "Panel", _caja(P.panel, Color(0, 0, 0, 0), 12, 12, true))

	t.set_stylebox("panel", "TabContainer", _caja(P.panel, Color(0, 0, 0, 0), 12, 12, true))
	t.set_stylebox("tab_selected", "TabContainer", _pestana(P.panel, P.primario))
	t.set_stylebox("tab_unselected", "TabContainer", _pestana(P.pestana_inactiva, Color(0, 0, 0, 0)))
	t.set_stylebox("tab_hovered", "TabContainer", _pestana(P.pestana_hover, Color(0, 0, 0, 0)))
	t.set_color("font_selected_color", "TabContainer", P.primario)
	t.set_color("font_unselected_color", "TabContainer", P.texto_suave)
	t.set_color("font_hovered_color", "TabContainer", P.texto)
	t.set_font_size("font_size", "TabContainer", 13)

	var tip := _caja(P.tooltip, P.primario_oscuro, 6, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	t.set_font_size("font_size", "TooltipLabel", 13)

	var barra := _caja(P.barra, P.barra, 4, 0)
	barra.content_margin_left = 3
	barra.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", barra)
	t.set_stylebox("grabber_highlight", "VScrollBar", _caja(P.barra_hover, P.barra_hover, 4, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _caja(P.primario, P.primario, 4, 0))
	t.set_stylebox("scroll", "VScrollBar", _caja(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0))

	t.set_stylebox("normal", "LineEdit", _caja(P.campo, P.borde))
	t.set_stylebox("focus", "LineEdit", _caja(Color(0, 0, 0, 0), P.primario))
	t.set_color("selection_color", "LineEdit", P.primario_suave)
	t.set_color("font_color", "LineEdit", P.texto)
	t.set_color("font_placeholder_color", "LineEdit", P.texto_suave)
	t.set_color("clear_button_color", "LineEdit", P.texto_suave)
	t.set_color("clear_button_color_pressed", "LineEdit", P.primario)
	t.set_color("caret_color", "LineEdit", P.primario)

	t.set_stylebox("panel", "ItemList", _caja(P.campo, P.borde, 8, 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("hovered", "ItemList", _caja(P.fondo_boton_hover, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("selected", "ItemList", _caja(P.primario_suave, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("selected_focus", "ItemList", _caja(P.primario_suave, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", P.texto)
	t.set_color("font_hovered_color", "ItemList", P.primario)
	t.set_color("font_selected_color", "ItemList", P.primario)
	t.set_color("guide_color", "ItemList", P.guia)

	t.set_stylebox("background", "ProgressBar", _caja(P.guia, Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("fill", "ProgressBar", _caja(P.primario, Color(0, 0, 0, 0), 4, 0))

	var linea := StyleBoxLine.new()
	linea.color = P.riel
	linea.thickness = 1
	t.set_stylebox("separator", "HSeparator", linea)

	var riel := _caja(P.riel, Color(0, 0, 0, 0), 3, 0)
	riel.content_margin_top = 3
	riel.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", riel)
	var lleno := _caja(P.primario_oscuro, Color(0, 0, 0, 0), 3, 0)
	lleno.content_margin_top = 3
	lleno.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", lleno)
	t.set_stylebox("grabber_area_highlight", "HSlider", lleno)

	t.set_stylebox("panel", "PopupMenu", _caja(P.fondo_boton, P.borde, 8, 6))
	t.set_stylebox("hover", "PopupMenu", _caja(P.primario_suave, Color(0, 0, 0, 0), 6, 4))
	t.set_color("font_color", "PopupMenu", P.texto)
	t.set_color("font_hover_color", "PopupMenu", P.primario)
	t.set_color("font_color", "OptionButton", P.texto)
	t.set_color("font_hover_color", "OptionButton", P.primario)
	t.set_color("font_pressed_color", "OptionButton", P.texto)

	t.set_color("font_color", "TextoSuave", P.texto_suave)
	t.set_type_variation("TextoSuave", "Label")
	t.set_color("font_color", "TextoAcento", P.primario)
	t.set_type_variation("TextoAcento", "Label")

	return t


func _caja(fondo: Color, borde: Color, radio := 8, margen := 8, sombra := false) -> StyleBoxFlat:
	var c := StyleBoxFlat.new()
	c.bg_color = fondo
	c.border_color = borde
	c.set_border_width_all(1 if borde.a > 0.0 else 0)
	c.set_corner_radius_all(radio)
	c.content_margin_left = margen + 4
	c.content_margin_right = margen + 4
	c.content_margin_top = margen
	c.content_margin_bottom = margen
	if sombra:
		c.shadow_color = P.sombra
		c.shadow_size = 10
		c.border_color = P.borde_panel
		c.set_border_width_all(1)
	return c


func _pestana(fondo: Color, linea_superior: Color) -> StyleBoxFlat:
	var c := StyleBoxFlat.new()
	c.bg_color = fondo
	c.border_color = linea_superior
	c.border_width_top = 3 if linea_superior.a > 0.0 else 0
	c.corner_radius_top_left = 8
	c.corner_radius_top_right = 8
	c.content_margin_left = 9
	c.content_margin_right = 9
	c.content_margin_top = 6
	c.content_margin_bottom = 6
	return c
