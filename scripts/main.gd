extends Node
## Escena principal: conecta el visor 3D, la interfaz y el motor de simulación mediante señales.
## Es el único lugar donde se "cablean" los componentes; ninguno conoce a los demás.

@onready var _visor: BodyViewer = $BodyViewer
@onready var _panel_ficha: PanelFicha = $UI/PanelFicha
@onready var _barra_vistas: BarraVistas = $UI/BarraVistas
@onready var _pestanas: TabContainer = $UI/PanelIzquierdo
@onready var _barra_sistemas: BarraSistemas = $UI/PanelIzquierdo/BarraSistemas
@onready var _panel_simulacion: PanelSimulacion = $UI/PanelIzquierdo/Simulacion/Margen/PanelSimulacion
@onready var _panel_grafico: PanelContainer = $UI/PanelGrafico
@onready var _grafico: GraficoVivo = $UI/PanelGrafico/Grafico
@onready var _mini_vista: MiniVista = $UI/MiniVista
@onready var _cuestionario: Cuestionario = $Cuestionario
@onready var _panel_cuestionario: PanelCuestionario = $UI/PanelIzquierdo/Cuestionario/Margen/PanelCuestionario
@onready var _etiqueta_organo: PanelContainer = $UI/EtiquetaOrgano

const PESTANA_SISTEMAS := 0
const PESTANA_SIMULACION := 1
const PESTANA_CUESTIONARIO := 2
var _puntaje_actual := 0
var _organo_en_ficha := ""   ## Órgano mostrado en la ficha (para su lista de partes)
var _herramientas: HerramientasVisor
var _panel_herramientas: PanelHerramientas
var _etiquetas: EtiquetasFlotantes
var _tarjeta_recorrido: TarjetaRecorrido
var _recorrido: Dictionary = {}   ## Recorrido en curso ({} = ninguno)
var _pasos: Array = []            ## Pasos del recorrido que existen en el cuerpo elegido
var _paso := 0
var _pestana_recorridos := -1

const SECCIONES := [
	["Sistemas del cuerpo", "res://ui/iconos/barra/sistemas.svg"],
	["Simular: correr, fumar o comer", "res://ui/iconos/barra/simular.svg"],
	["Preguntas: encuentra los órganos", "res://ui/iconos/barra/preguntas.svg"],
	["Recorridos guiados", "res://ui/iconos/barra/recorridos.svg"],
]
var _riel: RielNavegacion
var _aviso_controles: AvisoControles

const MODOS := {"explorar": PESTANA_SISTEMAS, "simular": PESTANA_SIMULACION, "cuestionario": PESTANA_CUESTIONARIO}


func _ready() -> void:
	_pestanas.set_tab_title(PESTANA_SISTEMAS, "Sistemas")
	_pestanas.set_tab_title(PESTANA_SIMULACION, "Simular")
	_pestanas.set_tab_title(PESTANA_CUESTIONARIO, "Preguntas")
	_pestanas.add_theme_font_size_override("font_size", 13)
	_pestanas.add_theme_constant_override("side_margin", 0)
	for estilo in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled", "tab_focus"]:
		var caja := _pestanas.get_theme_stylebox(estilo)
		if caja:   # Pestañas más angostas: entran las cuatro sin flechas
			caja = caja.duplicate()
			caja.content_margin_left = 7
			caja.content_margin_right = 7
			_pestanas.add_theme_stylebox_override(estilo, caja)
	_pestanas.set_tab_tooltip(PESTANA_SISTEMAS, "Explorar los sistemas y desarmar las capas")
	_pestanas.set_tab_tooltip(PESTANA_SIMULACION, "Simular correr, fumar o comer")
	_pestanas.set_tab_tooltip(PESTANA_CUESTIONARIO, "Encontrar órganos y sumar puntos")
	_pestanas.tab_changed.connect(_on_pestana_cambiada)
	$UI/BotonInicio.pressed.connect(App.volver_al_inicio)
	_armar_diseno()

	_conectar_atlas()
	_conectar_herramientas()
	_conectar_recorridos()
	_conectar_simulacion()
	_conectar_cuestionario()
	_pestanas.current_tab = MODOS.get(App.modo_inicial, PESTANA_SISTEMAS)
	_riel.configurar(SECCIONES.slice(0, _pestanas.get_tab_count()))
	_riel.marcar(_pestanas.current_tab)
	_aviso_controles.mostrar_si_es_la_primera_vez.call_deferred()


## Diseño: barra de navegación con íconos a la izquierda (en lugar de pestañas), el panel de la
## sección a su lado, fondo con degradado y el aviso de controles.
func _armar_diseno() -> void:
	_riel = RielNavegacion.new()
	_riel.name = "Riel"
	$UI.add_child(_riel)
	_riel.anchor_bottom = 1.0
	_riel.offset_left = 12
	_riel.offset_top = 12
	_riel.offset_right = 12 + RielNavegacion.ANCHO
	_riel.offset_bottom = -12
	_riel.seccion_elegida.connect(func(i): _pestanas.current_tab = i)
	_riel.inicio_pulsado.connect(App.volver_al_inicio)
	$UI/BotonInicio.hide()
	_pestanas.tabs_visible = false
	_pestanas.offset_left = 88
	_pestanas.offset_right = 88 + 302
	_pestanas.offset_top = 12
	$UI/Aviso.offset_left = 92
	$UI/Aviso.offset_right = 492
	_barra_vistas.centrar_solicitado.connect(_centrar)
	# La barra de vistas se centra en el espacio libre (a la derecha del panel izquierdo)
	_barra_vistas.offset_left += 100
	_barra_vistas.offset_right += 100

	# Fondo: degradado radial azul noche detrás del cuerpo (el 3D se dibuja encima)
	var fondo := CanvasLayer.new()
	fondo.layer = -1
	add_child(fondo)
	var degradado := Gradient.new()
	degradado.set_color(0, Color(0.11, 0.165, 0.22))
	degradado.set_color(1, Color(0.035, 0.05, 0.075))
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.42)
	textura.fill_to = Vector2(1.05, 1.05)
	var rect := TextureRect.new()
	rect.texture = textura
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.add_child(rect)
	var entorno: Environment = _visor.get_node("Entorno").environment
	entorno.background_mode = Environment.BG_CANVAS
	entorno.background_canvas_max_layer = -1

	_aviso_controles = AvisoControles.new()
	_aviso_controles.name = "AvisoControles"
	$UI.add_child(_aviso_controles)


## Vuelve a la vista inicial (de frente, todo el cuerpo), aunque se haya hecho mucho zoom.
func _centrar() -> void:
	if _herramientas.comparando():
		_herramientas.encuadrar_comparacion()
	else:
		_visor.camara.ir_a_vista("frente")


func _process(_delta: float) -> void:
	if _etiqueta_organo.visible:
		_etiqueta_organo.position = get_viewport().get_mouse_position() + Vector2(16, 18)


func _on_pestana_cambiada(pestana: int) -> void:
	_riel.marcar(pestana)
	_aviso_controles.hide()
	_actualizar_grafico_visible()
	if pestana != _pestana_recorridos and not _recorrido.is_empty():
		_terminar_recorrido()
	_panel_herramientas.apagar_corte()
	if pestana != PESTANA_CUESTIONARIO and _cuestionario.activo:
		_cuestionario.abandonar()
		_panel_cuestionario.mostrar_inicio()
		_visor.limpiar_seleccion()
		_visor.mostrar_cuerpo_completo()


# --- Atlas: cámara, selección y capas ------------------------------------------------

func _conectar_atlas() -> void:
	_barra_vistas.configurar(Datos.camara.get("vistas", []))
	_barra_vistas.vista_solicitada.connect(_visor.camara.ir_a_vista)

	_visor.organo_seleccionado.connect(_on_organo_seleccionado)
	_visor.seleccion_limpiada.connect(_panel_ficha.ocultar)
	_panel_ficha.cerrado.connect(_visor.limpiar_seleccion)
	_panel_ficha.aislar_cambiado.connect(_visor.aislar)
	_panel_ficha.parte_elegida.connect(func(id_parte): _visor.ir_a_estructura(_organo_en_ficha, id_parte))
	_visor.aislamiento_cambiado.connect(_panel_ficha.mostrar_aislado)

	_barra_sistemas.configurar(Datos.sistemas)
	_barra_sistemas.configurar_buscador(Datos.organos, Datos.partes, _visor.ids_organos() + _visor.ids_partes())
	_barra_sistemas.estructura_elegida.connect(_visor.ir_a_estructura)
	_barra_sistemas.configurar_edad(Datos.edad)
	_barra_sistemas.edad_cambiada.connect(_visor.fijar_edad)
	_visor.fijar_edad(Datos.edad.get("edad_inicial", 30), true)
	_barra_sistemas.sistema_solicitado.connect(_on_sistema_solicitado)
	_barra_sistemas.modo_fantasma_cambiado.connect(_visor.establecer_modo_fantasma)
	_visor.sistema_mostrado.connect(_barra_sistemas.marcar)
	_visor.organo_bajo_cursor.connect(_on_organo_bajo_cursor)


## Muestra el nombre del órgano junto al cursor (no durante el cuestionario: daría la respuesta).
func _on_organo_bajo_cursor(id_organo: String, id_parte: String) -> void:
	var mostrar := id_organo != "" and not _cuestionario.activo
	_etiqueta_organo.visible = mostrar
	if mostrar:
		var nombre := Datos.nombre_parte(id_parte)
		$UI/EtiquetaOrgano/Texto.text = nombre if not nombre.is_empty() \
				else Datos.ficha_organo(id_organo).get("nombre", id_organo)
		_etiqueta_organo.reset_size()


func _on_organo_seleccionado(id_organo: String, id_sistema: String, id_parte: String) -> void:
	if _cuestionario.activo:
		_cuestionario.responder(id_organo, id_parte)
		return
	_panel_ficha.mostrar(Datos.ficha_organo(id_organo), Datos.nombre_sistema(id_sistema),
			Datos.color_sistema(id_sistema), Datos.nombre_parte(id_parte), Datos.ficha_parte(id_parte))
	_organo_en_ficha = id_organo
	_panel_ficha.mostrar_partes(_visor.partes_de(id_organo), id_parte)


func _on_sistema_solicitado(id_sistema: String) -> void:
	# El corte reemplaza los materiales y el despiece mueve los órganos: se quitan antes de
	# que las capas se animen para mostrar otro sistema
	_panel_herramientas.apagar_corte()
	_herramientas.reiniciar_despiece()
	if id_sistema.is_empty():
		_visor.mostrar_cuerpo_completo()
	else:
		_visor.mostrar_sistema(id_sistema)


# --- Herramientas: corte, despiece, etiquetas y comparar --------------------------------

func _conectar_herramientas() -> void:
	_herramientas = HerramientasVisor.new()
	_herramientas.name = "Herramientas"
	add_child(_herramientas)
	_herramientas.configurar(_visor)

	_etiquetas = EtiquetasFlotantes.new()
	_etiquetas.name = "Etiquetas"
	_etiquetas.visible = false
	_etiquetas.camara = _visor.camara
	_etiquetas.fuente_puntos = _herramientas.puntos_etiquetas
	$UI.add_child(_etiquetas)
	$UI.move_child(_etiquetas, 0)   # Debajo de los paneles

	_panel_herramientas = PanelHerramientas.new()
	_panel_herramientas.name = "PanelHerramientas"
	$UI.add_child(_panel_herramientas)
	_panel_herramientas.anchor_left = 1.0
	_panel_herramientas.anchor_right = 1.0
	_panel_herramientas.offset_left = -282
	_panel_herramientas.offset_right = -16
	_panel_herramientas.offset_top = 54
	_panel_herramientas.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel_herramientas.configurar_comparar(_herramientas.nombre_comparado())
	_panel_herramientas.al_cambiar_sistema("")

	_panel_herramientas.corte_cambiado.connect(_herramientas.fijar_corte)
	_panel_herramientas.despiece_cambiado.connect(_herramientas.fijar_despiece)
	_panel_herramientas.etiquetas_cambiadas.connect(func(v): _etiquetas.visible = v)
	_panel_herramientas.comparar_cambiado.connect(_herramientas.fijar_comparacion)
	_visor.sistema_mostrado.connect(_panel_herramientas.al_cambiar_sistema)
	_visor.sistema_mostrado.connect(_herramientas.al_cambiar_sistema)
	_barra_sistemas.edad_cambiada.connect(_panel_ficha.fijar_edad)
	_panel_ficha.fijar_edad(_visor.edad_actual())
	# La ficha y las herramientas comparten la esquina derecha: mientras hay ficha no se ven
	_panel_ficha.visibility_changed.connect(func(): _panel_herramientas.visible = not _panel_ficha.visible)
	_barra_sistemas.edad_cambiada.connect(_herramientas.al_cambiar_edad)
	get_viewport().size_changed.connect(_actualizar_zona_etiquetas)
	_actualizar_zona_etiquetas()


## Las etiquetas se acomodan entre el panel izquierdo y el de herramientas.
func _actualizar_zona_etiquetas() -> void:
	var tam := get_viewport().get_visible_rect().size
	var izquierda := _pestanas.position.x + _pestanas.size.x + 12
	var derecha := tam.x - 290
	_etiquetas.zona = Rect2(izquierda, 60, maxf(200, derecha - izquierda), tam.y - 130)


# --- Recorridos guiados ------------------------------------------------------------------

func _conectar_recorridos() -> void:
	if Datos.recorridos.is_empty():
		return
	var desplazable := ScrollContainer.new()
	desplazable.name = "Recorridos"
	desplazable.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margen := MarginContainer.new()
	margen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 12)
	desplazable.add_child(margen)
	var lista := PanelRecorridos.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margen.add_child(lista)
	_pestanas.add_child(desplazable)
	_pestana_recorridos = desplazable.get_index()
	_pestanas.set_tab_title(_pestana_recorridos, "Recorridos")
	_pestanas.set_tab_tooltip(_pestana_recorridos, "Recorridos guiados por el cuerpo")
	lista.configurar(Datos.recorridos)
	lista.recorrido_elegido.connect(_iniciar_recorrido)

	_tarjeta_recorrido = TarjetaRecorrido.new()
	_tarjeta_recorrido.name = "TarjetaRecorrido"
	$UI.add_child(_tarjeta_recorrido)
	_tarjeta_recorrido.anterior.connect(func(): _ir_a_paso(_paso - 1))
	_tarjeta_recorrido.siguiente.connect(func():
		if _paso + 1 >= _pasos.size():
			_terminar_recorrido()
		else:
			_ir_a_paso(_paso + 1))
	_tarjeta_recorrido.salir.connect(_terminar_recorrido)


func _iniciar_recorrido(indice: int) -> void:
	_recorrido = Datos.recorridos[indice]
	_pasos = _recorrido.get("pasos", []).filter(func(p): return _visor.obtener_organo(p.get("organo", "")) != null)
	if _pasos.is_empty():
		_recorrido = {}
		return
	_panel_herramientas.apagar_corte()
	_herramientas.reiniciar_despiece()
	_ir_a_paso(0)


func _ir_a_paso(i: int) -> void:
	_paso = clampi(i, 0, _pasos.size() - 1)
	var p: Dictionary = _pasos[_paso]
	var id_organo: String = p.get("organo", "")
	_visor.ir_a_estructura(id_organo, p.get("parte", ""))
	_panel_ficha.ocultar()   # La explicación va en la tarjeta del recorrido
	var nombre_parte := Datos.nombre_parte(p.get("parte", ""))
	var nombre: String = nombre_parte if not nombre_parte.is_empty() else Datos.ficha_organo(id_organo).get("nombre", id_organo)
	_tarjeta_recorrido.mostrar_paso(_recorrido.get("nombre", ""), Color.from_string(_recorrido.get("color", "#2a7f9e"), Color.TEAL),
			_paso + 1, _pasos.size(), nombre, p.get("texto", ""))


func _terminar_recorrido() -> void:
	_recorrido = {}
	_pasos = []
	_tarjeta_recorrido.hide()
	_visor.limpiar_seleccion()
	_visor.mostrar_cuerpo_completo()


# --- Simulación ------------------------------------------------------------------------

func _conectar_simulacion() -> void:
	var motor := SimulationEngine
	_panel_simulacion.configurar(Datos.simulacion)
	_grafico.configurar(Datos.simulacion.get("variables", {}))

	# Interfaz -> motor
	_panel_simulacion.escenario_elegido.connect(motor.seleccionar_escenario)
	_panel_simulacion.iniciar_pulsado.connect(motor.iniciar)
	_panel_simulacion.pausar_pulsado.connect(motor.pausar)
	_panel_simulacion.reiniciar_pulsado.connect(motor.reiniciar)
	_panel_simulacion.velocidad_elegida.connect(motor.fijar_velocidad)
	_panel_simulacion.intensidad_elegida.connect(motor.fijar_intensidad)
	_panel_simulacion.anios_cambiados.connect(_al_cambiar_anios)

	# Motor -> vistas (todas solo escuchan)
	for receptor in [_panel_simulacion.mostrar_estado, _grafico.agregar,
			_visor.visuales.al_actualizar_estado, _mini_vista.al_actualizar_estado]:
		motor.estado_actualizado.connect(receptor)
	motor.estados_cambiados.connect(_panel_simulacion.mostrar_estados)
	motor.escenario_cambiado.connect(_panel_simulacion.mostrar_escenario)
	motor.escenario_cambiado.connect(_visor.visuales.al_cambiar_escenario)
	motor.escenario_cambiado.connect(_on_escenario_cambiado)
	motor.intensidad_cambiada.connect(_panel_simulacion.mostrar_intensidad)
	motor.pausa_cambiada.connect(_panel_simulacion.mostrar_pausa)
	motor.pausa_cambiada.connect(_visor.visuales.al_cambiar_pausa)
	motor.pausa_cambiada.connect(func(_p): _actualizar_tiempo_personaje())
	motor.velocidad_cambiada.connect(_panel_simulacion.mostrar_velocidad)
	motor.velocidad_cambiada.connect(_visor.visuales.al_cambiar_velocidad)
	motor.velocidad_cambiada.connect(func(_v): _actualizar_tiempo_personaje())
	motor.simulacion_reiniciada.connect(_grafico.limpiar)


## Barra de deterioro (años fumando): el cuerpo se daña y los signos vitales en reposo empeoran.
func _al_cambiar_anios(anios: float) -> void:
	_visor.visuales.fijar_anios_fumando(anios)
	var d: Dictionary = SimulationEngine.escenario().get("deterioro", {})
	var ajustes := {}
	var fraccion := anios / maxf(float(d.get("anios_max", 40)), 1.0)
	for id in d.get("vitales", {}):
		ajustes[id] = float(d["vitales"][id]) * fraccion
	SimulationEngine.fijar_ajustes_base(ajustes)


## Al iniciar un escenario, el cuerpo se desarma para mostrar los sistemas relevantes.
func _on_escenario_cambiado(_id: String, activo: bool) -> void:
	# Los escenarios con deterioro (Fumar) muestran su vista apenas se eligen: la barra de años
	# se puede mover sin iniciar la simulación
	if activo or SimulationEngine.escenario().has("deterioro"):
		_visor.mostrar_vista(SimulationEngine.escenario().get("vista", {}))
	_actualizar_grafico_visible()


func _actualizar_grafico_visible() -> void:
	_panel_grafico.visible = _pestanas.current_tab == PESTANA_SIMULACION or SimulationEngine.escenario_activo


func _actualizar_tiempo_personaje() -> void:
	var motor := SimulationEngine
	_mini_vista.al_cambiar_factor_tiempo(0.0 if motor.pausado else motor.velocidad)


# --- Cuestionario --------------------------------------------------------------------

func _conectar_cuestionario() -> void:
	_cuestionario.configurar(Datos.cuestionario, _visor.ids_organos(), _visor.ids_partes())
	_panel_cuestionario.nivel_elegido.connect(func(n): _cuestionario.nivel = n)
	_panel_cuestionario.configurar_niveles(_cuestionario.niveles())
	_panel_cuestionario.comenzar_pulsado.connect(_cuestionario.iniciar)
	_panel_cuestionario.siguiente_pulsado.connect(_cuestionario.siguiente)
	_panel_cuestionario.saltar_pulsado.connect(_cuestionario.saltar)
	_cuestionario.pregunta_nueva.connect(_on_pregunta_nueva)
	_cuestionario.respuesta_evaluada.connect(_on_respuesta_evaluada)
	_cuestionario.ronda_terminada.connect(_on_ronda_terminada)


func _on_pregunta_nueva(numero: int, total: int, texto: String, id_organo: String) -> void:
	_panel_ficha.ocultar()
	_visor.limpiar_seleccion()
	_etiqueta_organo.visible = false
	if _cuestionario.mostrar_sistema():
		_visor.enfocar_sistema(_visor.sistema_de(id_organo))
	_panel_cuestionario.mostrar_pregunta(numero, total, texto, _puntaje_actual)



func _on_respuesta_evaluada(correcta: bool, id_respondido: String, id_correcto: String, puntos: int,
		puntaje: int, restantes: int) -> void:
	_puntaje_actual = puntaje
	if not correcta and restantes == 0:
		# Mostrar dónde estaba (la parte exacta si la pregunta pedía una)
		_visor.seleccionar_organo(id_correcto, false, _visor.buscar_parte(id_correcto, _cuestionario.parte_actual()))
	var pedida := _cuestionario.parte_actual()
	var parte_correcta := _visor.buscar_parte(id_correcto, pedida)
	var nombre_correcto := _nombre(String(parte_correcta.name)) if parte_correcta else _nombre(id_correcto)
	_panel_cuestionario.mostrar_resultado(correcta, _nombre(id_respondido), nombre_correcto, puntos,
			puntaje, restantes, _cuestionario.racha())


func _on_ronda_terminada(puntaje: int, maximo: int, es_record: bool) -> void:
	_puntaje_actual = 0
	_visor.limpiar_seleccion()
	_visor.mostrar_cuerpo_completo()
	_panel_cuestionario.mostrar_final(puntaje, maximo, es_record)


func _nombre(id: String) -> String:
	if id.is_empty():
		return ""
	var parte := Datos.nombre_parte(id)
	return parte if not parte.is_empty() else Datos.ficha_organo(id).get("nombre", id)
