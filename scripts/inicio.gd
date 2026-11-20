extends Node
## Pantalla de inicio: elegir modo (explorar, simulaciones, cuestionario) o salir.
## De fondo gira el cuerpo de prueba sin piel ni músculos.

const VELOCIDAD_GIRO := 0.25   ## Radianes por segundo

@onready var _giro: Node3D = $Fondo/Giro
@onready var _record: Label = %Record


const CUERPOS := {"masculino": "zanatomy", "femenino": "zanatomy_femenino"}


func _ready() -> void:
	var grupo := ButtonGroup.new()
	%BotonMasculino.button_group = grupo
	%BotonFemenino.button_group = grupo
	%BotonMasculino.pressed.connect(_elegir_cuerpo.bind(CUERPOS.masculino))
	%BotonFemenino.pressed.connect(_elegir_cuerpo.bind(CUERPOS.femenino))
	var actual: String = Datos.cuerpo_elegido if not Datos.cuerpo_elegido.is_empty() \
			else Datos.visuales.get("cuerpo_activo", "")
	(%BotonFemenino if actual == CUERPOS.femenino else %BotonMasculino).button_pressed = true
	_mostrar_cuerpo()
	%BotonExplorar.pressed.connect(App.ir_a_principal.bind("explorar"))
	%BotonSimular.pressed.connect(App.ir_a_principal.bind("simular"))
	%BotonCuestionario.pressed.connect(App.ir_a_principal.bind("cuestionario"))
	%BotonSalir.pressed.connect(App.salir)
	var mejor := RegistroPuntajes.mejor_puntaje()
	_record.text = "Mejor puntaje en el cuestionario: %d de %d" % [mejor.puntaje, mejor.total] \
			if mejor.total > 0 else "Aún no hay puntajes en el cuestionario"


func _elegir_cuerpo(id: String) -> void:
	Datos.cuerpo_elegido = id
	_mostrar_cuerpo()


## Cuerpo de fondo (esqueleto con órganos) del modelo elegido.
func _mostrar_cuerpo() -> void:
	for hijo in _giro.get_children():
		hijo.queue_free()
	var cuerpo := BodyViewer.instanciar_cuerpo()
	_giro.add_child(cuerpo)
	%Creditos.text = Datos.cuerpo_activo().get("creditos", "")
	for sistema in ["Piel", "Muscular"]:
		var nodo := cuerpo.get_node_or_null(sistema)
		if nodo:
			nodo.visible = false


func _process(delta: float) -> void:
	_giro.rotate_y(VELOCIDAD_GIRO * delta)
