extends SceneTree
## Genera res://ui/tema.tres: el tema visual de toda la aplicación (paleta médica limpia).
## Se asigna en Proyecto > Configuración > GUI > Tema (gui/theme/custom).
##
##     godot --headless --path . --script res://tools/generar_tema.gd
##
## Cambiar aquí la paleta y volver a ejecutar; no editar el .tres a mano.

const SALIDA := "res://ui/tema.tres"

# Paleta (tema oscuro: azul noche con acento turquesa, como una consola médica)
const PRIMARIO := Color("2cc5b5")        # turquesa (acento principal)
const PRIMARIO_OSCURO := Color("1f9d91")
const PRIMARIO_SUAVE := Color("163c40")  # fondo de elementos seleccionados
const FONDO_BOTON := Color("1c2733")
const FONDO_BOTON_HOVER := Color("243241")
const BORDE := Color("2c3a49")
const TEXTO := Color("e4ecf1")
const TEXTO_SUAVE := Color("8ea3b0")
const DESHABILITADO := Color("526371")
const BLANCO := Color("ffffff")
const OSCURO := Color("0b1219")          # texto sobre el acento
const PANEL := Color(0.075, 0.105, 0.145, 0.94)


func _init() -> void:
	var t := Theme.new()
	t.default_font_size = 14

	# --- Botones ---
	t.set_stylebox("normal", "Button", _caja(FONDO_BOTON, BORDE))
	t.set_stylebox("hover", "Button", _caja(FONDO_BOTON_HOVER, PRIMARIO.lerp(BORDE, 0.5)))
	t.set_stylebox("pressed", "Button", _caja(PRIMARIO, PRIMARIO_OSCURO))
	t.set_stylebox("hover_pressed", "Button", _caja(PRIMARIO_OSCURO, PRIMARIO_OSCURO))
	t.set_stylebox("disabled", "Button", _caja(Color("161f29"), Color("222d39")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXTO)
	t.set_color("font_hover_color", "Button", PRIMARIO)
	t.set_color("font_pressed_color", "Button", OSCURO)
	t.set_color("font_hover_pressed_color", "Button", OSCURO)
	t.set_color("font_disabled_color", "Button", DESHABILITADO)
	t.set_color("font_focus_color", "Button", TEXTO)

	# --- CheckButton (interruptor) ---
	t.set_color("font_color", "CheckButton", TEXTO)
	t.set_color("font_pressed_color", "CheckButton", PRIMARIO)
	t.set_color("font_hover_color", "CheckButton", PRIMARIO)
	t.set_color("font_hover_pressed_color", "CheckButton", PRIMARIO)
	# El interruptor encendido no pinta el fondo del botón (el texto turquesa ya lo indica)
	for estado in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(estado, "CheckButton", _caja(FONDO_BOTON if not estado.begins_with("hover") else FONDO_BOTON_HOVER, BORDE))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	# --- Textos ---
	t.set_color("font_color", "Label", TEXTO)

	# --- Paneles ---
	t.set_stylebox("panel", "PanelContainer", _caja(PANEL, Color(0, 0, 0, 0), 12, 12, true))
	t.set_stylebox("panel", "Panel", _caja(PANEL, Color(0, 0, 0, 0), 12, 12, true))

	# --- Pestañas ---
	t.set_stylebox("panel", "TabContainer", _caja(PANEL, Color(0, 0, 0, 0), 12, 12, true))
	t.set_stylebox("tab_selected", "TabContainer", _pestana(PANEL, PRIMARIO))
	t.set_stylebox("tab_unselected", "TabContainer", _pestana(Color(0.075, 0.105, 0.145, 0.6), Color(0, 0, 0, 0)))
	t.set_stylebox("tab_hovered", "TabContainer", _pestana(Color(0.1, 0.14, 0.19, 0.8), Color(0, 0, 0, 0)))
	t.set_color("font_selected_color", "TabContainer", PRIMARIO)
	t.set_color("font_unselected_color", "TabContainer", TEXTO_SUAVE)
	t.set_color("font_hovered_color", "TabContainer", TEXTO)
	t.set_font_size("font_size", "TabContainer", 13)

	# --- Tooltips ---
	var tip := _caja(Color("243241"), PRIMARIO_OSCURO, 6, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", BLANCO)
	t.set_font_size("font_size", "TooltipLabel", 13)

	# --- Barras de desplazamiento finas ---
	var barra := _caja(Color("33445a"), Color("33445a"), 4, 0)
	barra.content_margin_left = 3
	barra.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", barra)
	t.set_stylebox("grabber_highlight", "VScrollBar", _caja(Color("4a5f76"), Color("4a5f76"), 4, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _caja(PRIMARIO, PRIMARIO, 4, 0))
	t.set_stylebox("scroll", "VScrollBar", _caja(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0))

	# --- Campo de texto (buscador) ---
	t.set_stylebox("normal", "LineEdit", _caja(Color("101821"), BORDE))
	t.set_stylebox("focus", "LineEdit", _caja(Color(0, 0, 0, 0), PRIMARIO))
	t.set_color("selection_color", "LineEdit", PRIMARIO_SUAVE)
	t.set_color("font_color", "LineEdit", TEXTO)
	t.set_color("font_placeholder_color", "LineEdit", TEXTO_SUAVE)
	t.set_color("clear_button_color", "LineEdit", TEXTO_SUAVE)
	t.set_color("clear_button_color_pressed", "LineEdit", PRIMARIO)
	t.set_color("caret_color", "LineEdit", PRIMARIO)

	# --- Lista de resultados ---
	t.set_stylebox("panel", "ItemList", _caja(Color("101821"), BORDE, 8, 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("hovered", "ItemList", _caja(FONDO_BOTON_HOVER, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("selected", "ItemList", _caja(PRIMARIO_SUAVE, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("selected_focus", "ItemList", _caja(PRIMARIO_SUAVE, Color(0, 0, 0, 0), 6, 2))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXTO)
	t.set_color("font_hovered_color", "ItemList", PRIMARIO)
	t.set_color("font_selected_color", "ItemList", PRIMARIO)
	t.set_color("guide_color", "ItemList", Color("1c2733"))

	# --- Barra de progreso ---
	t.set_stylebox("background", "ProgressBar", _caja(Color("1c2733"), Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("fill", "ProgressBar", _caja(PRIMARIO, Color(0, 0, 0, 0), 4, 0))

	# --- Separadores ---
	var linea := StyleBoxLine.new()
	linea.color = Color("26333f")
	linea.thickness = 1
	t.set_stylebox("separator", "HSeparator", linea)

	# --- Deslizadores (barra de edad, corte, despiece...) ---
	var riel := _caja(Color("26333f"), Color(0, 0, 0, 0), 3, 0)
	riel.content_margin_top = 3
	riel.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", riel)
	var lleno := _caja(PRIMARIO_OSCURO, Color(0, 0, 0, 0), 3, 0)
	lleno.content_margin_top = 3
	lleno.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", lleno)
	t.set_stylebox("grabber_area_highlight", "HSlider", lleno)

	# --- Listas desplegables y menús ---
	t.set_stylebox("panel", "PopupMenu", _caja(Color("1c2733"), BORDE, 8, 6))
	t.set_stylebox("hover", "PopupMenu", _caja(PRIMARIO_SUAVE, Color(0, 0, 0, 0), 6, 4))
	t.set_color("font_color", "PopupMenu", TEXTO)
	t.set_color("font_hover_color", "PopupMenu", PRIMARIO)
	t.set_color("font_color", "OptionButton", TEXTO)
	t.set_color("font_hover_color", "OptionButton", PRIMARIO)
	t.set_color("font_pressed_color", "OptionButton", TEXTO)

	# --- Tipos con nombre (los usan los paneles por código) ---
	t.set_color("font_color", "TextoSuave", TEXTO_SUAVE)
	t.set_type_variation("TextoSuave", "Label")
	t.set_color("font_color", "TextoAcento", PRIMARIO)
	t.set_type_variation("TextoAcento", "Label")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui"))
	var error := ResourceSaver.save(t, SALIDA)
	if error != OK:
		push_error("No se pudo guardar el tema (%d)" % error)
		quit(1)
		return
	print("Tema generado en ", SALIDA)
	quit()


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
		c.shadow_color = Color(0, 0, 0, 0.35)
		c.shadow_size = 10
		c.border_color = Color(1, 1, 1, 0.06)   # Borde finito: separa el panel del fondo oscuro
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
