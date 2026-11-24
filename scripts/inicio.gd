extends Node

const VELOCIDAD_GIRO := 0.25

@onready var _giro: Node3D = $Fondo/Giro
@onready var _record: Label = %Record


const CUERPOS := {"masculino": "zanatomy", "femenino": "zanatomy_femenino"}


func _ready() -> void:
	var grupo := ButtonGroup.new()
	%BotonMasculino.button_group = grupo
	%BotonFemenino.button_group = grupo
	%BotonMasculino.pressed.connect(_dymj_elegir_cuerpo.bind(CUERPOS.masculino))
	%BotonFemenino.pressed.connect(_dymj_elegir_cuerpo.bind(CUERPOS.femenino))
	var actual: String = Datos.cuerpo_elegido if not Datos.cuerpo_elegido.is_empty() \
			else Datos.visuales.get("cuerpo_activo", "")
	(%BotonFemenino if actual == CUERPOS.femenino else %BotonMasculino).button_pressed = true
	_dymj_mostrar_cuerpo()
	%BotonExplorar.pressed.connect(App.dymj_ir_a_principal.bind("explorar"))
	%BotonSimular.pressed.connect(App.dymj_ir_a_principal.bind("simular"))
	%BotonCuestionario.pressed.connect(App.dymj_ir_a_principal.bind("cuestionario"))
	%BotonSalir.pressed.connect(App.dymj_salir)
	var mejor := RegistroPuntajes.dymj_mejor_puntaje()
	_record.text = "Mejor puntaje en el cuestionario: %d de %d" % [mejor.puntaje, mejor.total] \
			if mejor.total > 0 else "Aún no hay puntajes en el cuestionario"
	_dymj_armar_fondo_y_ayuda()


func _dymj_armar_fondo_y_ayuda() -> void:
	var capa := CanvasLayer.new()
	capa.layer = -1
	add_child(capa)
	var degradado := Gradient.new()
	_degradado = degradado
	_dymj_pintar_fondo()
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.7, 0.45)
	textura.fill_to = Vector2(1.25, 1.1)
	var rect := TextureRect.new()
	rect.texture = textura
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa.add_child(rect)
	var entorno: Environment = $Fondo/Entorno.environment
	entorno.background_mode = Environment.BG_CANVAS
	entorno.background_canvas_max_layer = -1
	var ayuda := Label.new()
	ayuda.text = "Arrastra para girar · Rueda o pellizco para acercar · Clic derecho para desplazar · C para centrar"
	ayuda.theme_type_variation = "TextoSuave"
	ayuda.add_theme_font_size_override("font_size", 12)
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ayuda.custom_minimum_size = Vector2(360, 0)
	var contenido := %BotonSalir.get_parent()
	contenido.add_child(ayuda)
	contenido.move_child(ayuda, %Record.get_index() + 1)
	_boton_tema = Button.new()
	_boton_tema.focus_mode = Control.FOCUS_NONE
	_boton_tema.custom_minimum_size = Vector2(150, 36)
	_boton_tema.add_theme_constant_override("icon_max_width", 18)
	_boton_tema.anchor_left = 1.0
	_boton_tema.anchor_right = 1.0
	_boton_tema.offset_left = -170
	_boton_tema.offset_right = -20
	_boton_tema.offset_top = 20
	_boton_tema.offset_bottom = 56
	_boton_tema.pressed.connect(App.dymj_alternar_tema)
	$UI.add_child(_boton_tema)
	App.tema_cambiado.connect(func(_c): _dymj_pintar_fondo())
	_dymj_pintar_fondo()


var _degradado: Gradient
var _boton_tema: Button


func _dymj_pintar_fondo() -> void:
	_degradado.set_color(0, Tema.dymj_fondo("centro"))
	_degradado.set_color(1, Tema.dymj_fondo("borde"))
	if _boton_tema:
		_boton_tema.text = "Tema oscuro" if Tema.dymj_es_claro() else "Tema claro"
		_boton_tema.icon = load("res://ui/iconos/barra/%s.svg" % ("luna" if Tema.dymj_es_claro() else "sol"))


func _dymj_elegir_cuerpo(id: String) -> void:
	Datos.cuerpo_elegido = id
	_dymj_mostrar_cuerpo()


func _dymj_mostrar_cuerpo() -> void:
	for hijo in _giro.get_children():
		hijo.queue_free()
	var cuerpo := BodyViewer.drar_instanciar_cuerpo()
	_giro.add_child(cuerpo)
	%Creditos.text = Datos.dymj_cuerpo_activo().get("creditos", "")
	for sistema in ["Piel", "Muscular"]:
		var nodo := cuerpo.get_node_or_null(sistema)
		if nodo:
			nodo.visible = false


func _process(delta: float) -> void:
	_giro.rotate_y(VELOCIDAD_GIRO * delta)
