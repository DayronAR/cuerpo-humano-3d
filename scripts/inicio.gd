extends Node
## Pantalla de inicio: elegir modo (explorar, simulaciones, cuestionario) o salir.
## De fondo gira el cuerpo de prueba sin piel ni músculos.

const VELOCIDAD_GIRO := 0.25   ## Radianes por segundo

@onready var _giro: Node3D = $Fondo/Giro
@onready var _record: Label = %Record


func _ready() -> void:
	_giro.add_child(BodyViewer.instanciar_cuerpo())
	%Creditos.text = Datos.cuerpo_activo().get("creditos", "")
	for sistema in ["Piel", "Muscular"]:
		var nodo := _giro.get_node_or_null("Cuerpo/" + sistema)
		if nodo:
			nodo.visible = false
	%BotonExplorar.pressed.connect(App.ir_a_principal.bind("explorar"))
	%BotonSimular.pressed.connect(App.ir_a_principal.bind("simular"))
	%BotonCuestionario.pressed.connect(App.ir_a_principal.bind("cuestionario"))
	%BotonSalir.pressed.connect(App.salir)
	var mejor := RegistroPuntajes.mejor_puntaje()
	_record.text = "Mejor puntaje en el cuestionario: %d de %d" % [mejor.puntaje, mejor.total] \
			if mejor.total > 0 else "Aún no hay puntajes en el cuestionario"


func _process(delta: float) -> void:
	_giro.rotate_y(VELOCIDAD_GIRO * delta)
