extends Node
## Escena principal: conecta el visor 3D, la interfaz y el motor de simulación mediante señales.
## Es el único lugar donde se "cablean" los componentes; ninguno conoce a los demás.

@onready var _visor: BodyViewer = $BodyViewer
@onready var _panel_ficha: PanelFicha = $UI/PanelFicha
@onready var _barra_vistas: BarraVistas = $UI/BarraVistas
@onready var _pestanas: TabContainer = $UI/PanelIzquierdo
@onready var _barra_sistemas: BarraSistemas = $UI/PanelIzquierdo/BarraSistemas
@onready var _panel_simulacion: PanelSimulacion = $UI/PanelIzquierdo/Simulacion/PanelSimulacion
@onready var _panel_grafico: PanelContainer = $UI/PanelGrafico
@onready var _grafico: GraficoVivo = $UI/PanelGrafico/Grafico
@onready var _mini_vista: MiniVista = $UI/MiniVista

const PESTANA_SIMULACION := 1


func _ready() -> void:
	_pestanas.set_tab_title(0, "Sistemas")
	_pestanas.set_tab_title(PESTANA_SIMULACION, "Simulación")
	_pestanas.tab_changed.connect(func(_i): _actualizar_grafico_visible())

	_conectar_atlas()
	_conectar_simulacion()


# --- Atlas: cámara, selección y capas ------------------------------------------------

func _conectar_atlas() -> void:
	_barra_vistas.configurar(Datos.camara.get("vistas", []))
	_barra_vistas.vista_solicitada.connect(_visor.camara.ir_a_vista)

	_visor.organo_seleccionado.connect(_on_organo_seleccionado)
	_visor.seleccion_limpiada.connect(_panel_ficha.ocultar)
	_panel_ficha.cerrado.connect(_visor.limpiar_seleccion)

	_barra_sistemas.configurar(Datos.sistemas)
	_barra_sistemas.sistema_solicitado.connect(_on_sistema_solicitado)
	_barra_sistemas.modo_fantasma_cambiado.connect(_visor.establecer_modo_fantasma)
	_visor.sistema_mostrado.connect(_barra_sistemas.marcar)


func _on_organo_seleccionado(id_organo: String, id_sistema: String) -> void:
	_panel_ficha.mostrar(Datos.ficha_organo(id_organo), Datos.nombre_sistema(id_sistema),
			Datos.color_sistema(id_sistema))


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
