class_name PanelHerramientas
extends PanelContainer

signal corte_cambiado(activo: bool, plano: String, posicion: float)
signal despiece_cambiado(factor: float)
signal etiquetas_cambiadas(activas: bool)
signal comparar_cambiado(activo: bool)

const PLANOS := [["coronal", "De frente (coronal)"], ["sagital", "De lado (sagital)"],
		["transversal", "Horizontal (transversal)"]]

var _corte: CheckButton
var _plano: OptionButton
var _posicion: HSlider
var _fila_corte: Control
var _despiece: HSlider
var _aviso_despiece: Label
var _etiquetas: CheckButton
var _comparar: CheckButton


func _ready() -> void:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.075, 0.105, 0.145, 0.94)
	estilo.set_corner_radius_all(12)
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	estilo.content_margin_top = 8
	estilo.content_margin_bottom = 10
	estilo.shadow_color = Color(0, 0, 0, 0.35)
	estilo.shadow_size = 6
	add_theme_stylebox_override("panel", estilo)
	custom_minimum_size = Vector2(250, 0)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	add_child(caja)
	caja.add_child(_drar_titulo("Herramientas"))

	_corte = _drar_interruptor("Corte", "Corta el cuerpo con un plano para ver su interior")
	caja.add_child(_corte)
	_fila_corte = VBoxContainer.new()
	_fila_corte.visible = false
	caja.add_child(_fila_corte)
	_plano = OptionButton.new()
	_plano.focus_mode = Control.FOCUS_NONE
	for p in PLANOS:
		_plano.add_item(p[1])
	_fila_corte.add_child(_plano)
	_posicion = _drar_deslizador(0.5, "Mueve el plano de corte")
	_fila_corte.add_child(_posicion)
	_corte.toggled.connect(func(v): _fila_corte.visible = v; _drar_emitir_corte())
	_plano.item_selected.connect(func(_i): _drar_emitir_corte())
	_posicion.value_changed.connect(func(_v): _drar_emitir_corte())

	caja.add_child(_drar_etiqueta("Despiece"))
	_despiece = _drar_deslizador(0.0, "Separa los órganos del sistema que estás viendo")
	_despiece.value_changed.connect(func(v): despiece_cambiado.emit(v))
	caja.add_child(_despiece)
	_aviso_despiece = _drar_etiqueta("Elige un sistema para separarlo", 12, Color(0.557, 0.639, 0.69, 1))
	caja.add_child(_aviso_despiece)

	_etiquetas = _drar_interruptor("Etiquetas", "Nombres de los órganos del sistema visible")
	_etiquetas.toggled.connect(func(v): etiquetas_cambiadas.emit(v))
	caja.add_child(_etiquetas)

	_comparar = _drar_interruptor("Comparar", "Muestra el otro cuerpo al lado")
	_comparar.toggled.connect(func(v): comparar_cambiado.emit(v))
	caja.add_child(_comparar)


func drar_configurar_comparar(nombre: String) -> void:
	_comparar.visible = not nombre.is_empty()
	_comparar.text = "Comparar con " + nombre.to_lower() if not nombre.is_empty() else "Comparar"


func drar_al_cambiar_sistema(id_sistema: String) -> void:
	_despiece.set_value_no_signal(0.0)
	_despiece.editable = not id_sistema.is_empty()
	_aviso_despiece.visible = id_sistema.is_empty()


func drar_apagar_corte() -> void:
	if _corte.button_pressed:
		_corte.button_pressed = false


func _drar_emitir_corte() -> void:
	corte_cambiado.emit(_corte.button_pressed, PLANOS[_plano.selected][0], _posicion.value)


func _drar_titulo(texto: String) -> Label:
	var l := _drar_etiqueta(texto, 17, Color(0.89, 0.925, 0.945, 1))
	return l


func _drar_etiqueta(texto: String, tamano := 14, color := Color(0.89, 0.925, 0.945, 1)) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tamano)
	l.add_theme_color_override("font_color", color)
	return l


func _drar_interruptor(texto: String, ayuda: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = texto
	b.tooltip_text = ayuda
	b.focus_mode = Control.FOCUS_NONE
	return b


func _drar_deslizador(valor: float, ayuda: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = valor
	s.tooltip_text = ayuda
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 22)
	return s
