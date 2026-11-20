extends Node
## Escena principal: conecta el visor 3D con la interfaz mediante señales.
## Es el único lugar donde se "cablean" los componentes; ninguno conoce a los demás.

@onready var _visor: BodyViewer = $BodyViewer
@onready var _panel_ficha: PanelFicha = $UI/PanelFicha
@onready var _barra_vistas: BarraVistas = $UI/BarraVistas
@onready var _barra_sistemas: BarraSistemas = $UI/BarraSistemas


func _ready() -> void:
	_barra_vistas.configurar(Datos.camara.get("vistas", []))
	_barra_vistas.vista_solicitada.connect(_visor.camara.ir_a_vista)

	_visor.organo_seleccionado.connect(_on_organo_seleccionado)
	_visor.seleccion_limpiada.connect(_panel_ficha.ocultar)
	_panel_ficha.cerrado.connect(_visor.limpiar_seleccion)

	_barra_sistemas.configurar(Datos.sistemas)
	_barra_sistemas.sistema_solicitado.connect(_on_sistema_solicitado)
	_barra_sistemas.modo_fantasma_cambiado.connect(_visor.establecer_modo_fantasma)
	_visor.sistema_mostrado.connect(_barra_sistemas.marcar)


func _on_sistema_solicitado(id_sistema: String) -> void:
	if id_sistema.is_empty():
		_visor.mostrar_cuerpo_completo()
	else:
		_visor.mostrar_sistema(id_sistema)


func _on_organo_seleccionado(id_organo: String, id_sistema: String) -> void:
	_panel_ficha.mostrar(Datos.ficha_organo(id_organo), Datos.nombre_sistema(id_sistema),
			Datos.color_sistema(id_sistema))
