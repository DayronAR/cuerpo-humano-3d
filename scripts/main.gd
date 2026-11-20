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

const MODOS := {"explorar": PESTANA_SISTEMAS, "simular": PESTANA_SIMULACION, "cuestionario": PESTANA_CUESTIONARIO}


func _ready() -> void:
	_pestanas.set_tab_title(PESTANA_SISTEMAS, "Sistemas")
	_pestanas.set_tab_title(PESTANA_SIMULACION, "Simulación")
	_pestanas.set_tab_title(PESTANA_CUESTIONARIO, "Cuestionario")
	_pestanas.set_tab_tooltip(PESTANA_SISTEMAS, "Explorar los sistemas y desarmar las capas")
	_pestanas.set_tab_tooltip(PESTANA_SIMULACION, "Simular correr, fumar o comer")
	_pestanas.set_tab_tooltip(PESTANA_CUESTIONARIO, "Encontrar órganos y sumar puntos")
	_pestanas.tab_changed.connect(_on_pestana_cambiada)
	$UI/BotonInicio.pressed.connect(App.volver_al_inicio)

	_conectar_atlas()
	_conectar_simulacion()
	_conectar_cuestionario()
	_pestanas.current_tab = MODOS.get(App.modo_inicial, PESTANA_SISTEMAS)


func _process(_delta: float) -> void:
	if _etiqueta_organo.visible:
		_etiqueta_organo.position = get_viewport().get_mouse_position() + Vector2(16, 18)


func _on_pestana_cambiada(pestana: int) -> void:
	_actualizar_grafico_visible()
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
	_visor.aislamiento_cambiado.connect(_panel_ficha.mostrar_aislado)

	_barra_sistemas.configurar(Datos.sistemas)
	_barra_sistemas.configurar_buscador(Datos.organos, Datos.partes, _visor.ids_organos() + _visor.ids_partes())
	_barra_sistemas.estructura_elegida.connect(_visor.ir_a_estructura)
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


func _on_sistema_solicitado(id_sistema: String) -> void:
	if id_sistema.is_empty():
		_visor.mostrar_cuerpo_completo()
	else:
		_visor.mostrar_sistema(id_sistema)


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


## Al iniciar un escenario, el cuerpo se desarma para mostrar los sistemas relevantes.
func _on_escenario_cambiado(_id: String, activo: bool) -> void:
	if activo:
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
			puntaje, restantes)


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
