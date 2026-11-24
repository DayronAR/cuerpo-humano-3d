class_name BarraSistemas
extends PanelContainer

signal sistema_solicitado(id_sistema: String)
signal modo_fantasma_cambiado(activo: bool)
signal estructura_elegida(id_organo: String, id_parte: String)
signal edad_cambiada(anios: float, final: bool)

const MAX_RESULTADOS := 40

const ALTO_ELEMENTO := 66

@onready var _lista: VBoxContainer = %Lista
@onready var _boton_completo: Button = %BotonCompleto
@onready var _fantasma: CheckButton = %Fantasma
@onready var _buscador: LineEdit = %Buscador
@onready var _resultados: ItemList = %Resultados

var _indice_busqueda: Array = []

const COLOR_TEXTO := Color(0.89, 0.925, 0.945, 1)
const COLOR_TEXTO_SUAVE := Color(0.557, 0.639, 0.69, 1)
const COLOR_ACENTO := Color(0.173, 0.773, 0.71, 1)

var _grupo := ButtonGroup.new()
var _botones: Dictionary = {}


func _ready() -> void:
	_dymj_aplicar_estilo(_boton_completo)
	_boton_completo.button_group = _grupo
	_boton_completo.toggle_mode = true
	_boton_completo.button_pressed = true
	_boton_completo.pressed.connect(sistema_solicitado.emit.bind(""))
	_botones[""] = _boton_completo
	_fantasma.toggled.connect(modo_fantasma_cambiado.emit)
	_buscador.text_changed.connect(_dymj_buscar)
	_buscador.text_submitted.connect(func(_t): _dymj_elegir(0))
	_resultados.item_clicked.connect(func(i, _pos, _boton): _dymj_elegir(i))
	%BarraEdad.value_changed.connect(func(v): _dymj_mostrar_edad(v); edad_cambiada.emit(v, false))
	%BarraEdad.drag_ended.connect(func(cambio): if cambio: edad_cambiada.emit(%BarraEdad.value, true))


func dymj_configurar_edad(cfg: Dictionary) -> void:
	%BarraEdad.min_value = cfg.get("edad_min", 0)
	%BarraEdad.max_value = cfg.get("edad_max", 90)
	%BarraEdad.set_value_no_signal(cfg.get("edad_inicial", 30))
	_dymj_mostrar_edad(%BarraEdad.value)


func dymj_fijar_edad_sin_senal(anios: float) -> void:
	%BarraEdad.set_value_no_signal(anios)
	_dymj_mostrar_edad(anios)


func _dymj_mostrar_edad(anios: float) -> void:
	var texto := "Recién nacido" if anios < 1 else ("1 año" if anios < 2 else "%d años" % int(anios))
	%ValorEdad.text = "%s · %s" % [texto, Datos.dymj_etapa_edad(anios)] if anios >= 1 else texto


func dymj_configurar(sistemas: Array) -> void:
	for hijo in _lista.get_children():
		hijo.queue_free()
	for s in sistemas:
		var boton := _dymj_crear_elemento(s)
		_lista.add_child(boton)
		_botones[s.get("id", "")] = boton


func dymj_marcar(id_sistema: String) -> void:
	for id in _botones:
		_botones[id].set_pressed_no_signal(id == id_sistema)


func _dymj_crear_elemento(s: Dictionary) -> Button:
	var id: String = s.get("id", "")
	var boton := Button.new()
	boton.name = "Sistema" + id
	boton.toggle_mode = true
	boton.button_group = _grupo
	boton.focus_mode = Control.FOCUS_NONE
	boton.custom_minimum_size = Vector2(0, ALTO_ELEMENTO)
	boton.tooltip_text = s.get("descripcion", "")
	boton.pressed.connect(sistema_solicitado.emit.bind(id))
	_dymj_aplicar_estilo(boton)

	var margen := MarginContainer.new()
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 8 if lado in ["top", "bottom"] else 10)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.add_theme_constant_override("separation", 0)
	var nombre := Label.new()
	nombre.text = s.get("nombre", id)
	nombre.add_theme_font_size_override("font_size", 15)
	nombre.add_theme_color_override("font_color", COLOR_TEXTO)
	var descripcion := Label.new()
	descripcion.text = s.get("descripcion", "")
	descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descripcion.max_lines_visible = 2
	descripcion.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	descripcion.add_theme_font_size_override("font_size", 11)
	descripcion.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	textos.add_child(nombre)
	textos.add_child(descripcion)
	fila.add_child(textos)
	margen.add_child(fila)
	for c in [margen, fila, textos, nombre, descripcion]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boton.add_child(margen)
	return boton


func _dymj_aplicar_estilo(boton: Button) -> void:
	var estados := {
		"normal": [Color(0.11, 0.153, 0.2), Color(0, 0, 0, 0)],
		"hover": [Color(0.141, 0.196, 0.255), Color(0, 0, 0, 0)],
		"pressed": [Color(0.086, 0.235, 0.25), COLOR_ACENTO],
		"hover_pressed": [Color(0.086, 0.235, 0.25), COLOR_ACENTO],
	}
	for estado in estados:
		var caja := StyleBoxFlat.new()
		caja.bg_color = estados[estado][0]
		caja.border_color = estados[estado][1]
		caja.set_border_width_all(2)
		caja.set_corner_radius_all(8)
		boton.add_theme_stylebox_override(estado, caja)
	for estado in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		boton.add_theme_color_override(estado, COLOR_ACENTO if "pressed" in estado else COLOR_TEXTO)


func dymj_configurar_buscador(organos: Dictionary, partes: Dictionary, existentes: Array) -> void:
	_indice_busqueda.clear()
	var hay := {}
	for id in existentes:
		hay[id] = true
	for id in organos:
		if hay.has(id):
			var nombre: String = organos[id].get("nombre", id)
			_indice_busqueda.append([_dymj_normalizar(nombre), nombre, id, ""])
	for id in partes:
		if hay.has(id):
			var p: Dictionary = partes[id]
			var nombre: String = p.get("nombre", id)
			var organo: String = p.get("organo", "")
			var texto := "%s  ·  %s" % [nombre, organos.get(organo, {}).get("nombre", organo)]
			_indice_busqueda.append([_dymj_normalizar(nombre + " " + p.get("nombre_en", "")), texto, organo, id])


func _dymj_buscar(texto: String) -> void:
	_resultados.clear()
	var consulta := _dymj_normalizar(texto.strip_edges())
	_resultados.visible = consulta.length() >= 2
	if not _resultados.visible:
		return
	var palabras := consulta.split(" ", false)
	var empiezan := []
	var contienen := []
	for entrada in _indice_busqueda:
		var ok := true
		for palabra in palabras:
			if not entrada[0].contains(palabra):
				ok = false
				break
		if ok:
			(empiezan if entrada[0].begins_with(palabras[0]) else contienen).append(entrada)
	for entrada in (empiezan + contienen).slice(0, MAX_RESULTADOS):
		var i := _resultados.add_item(entrada[1])
		_resultados.set_item_metadata(i, [entrada[2], entrada[3]])
		_resultados.set_item_tooltip(i, entrada[1])
	if _resultados.item_count == 0:
		_resultados.add_item("Sin resultados")
		_resultados.set_item_disabled(0, true)


func _dymj_elegir(indice: int) -> void:
	if indice < 0 or indice >= _resultados.item_count or _resultados.is_item_disabled(indice):
		return
	var datos: Array = _resultados.get_item_metadata(indice)
	estructura_elegida.emit(datos[0], datos[1])


static func _dymj_normalizar(texto: String) -> String:
	var t := texto.to_lower()
	for par in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		t = t.replace(par[0], par[1])
	return t
