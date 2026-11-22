extends Node
## Autoload "App": navegación entre pantallas y ajustes de la ventana.
##   - Recuerda con qué modo abrir la pantalla principal (explorar, simular, cuestionario).
##   - F11 alterna pantalla completa (útil en la sustentación).

const ESCENA_INICIO := "res://scenes/inicio.tscn"
const ESCENA_PRINCIPAL := "res://scenes/main.tscn"
const TAMANO_MINIMO := Vector2i(1024, 600)

var modo_inicial := "explorar"   ## "explorar", "simular" o "cuestionario"
var estado_vista: Dictionary = {} ## Lo que se conserva al cambiar de cuerpo (edad, sección)

signal tema_cambiado(claro: bool)


func _ready() -> void:
	DisplayServer.window_set_min_size(TAMANO_MINIMO)
	Tema.cargar()
	Tema.aplicar.call_deferred(get_tree(), "oscuro")


## Alterna entre el tema claro y el oscuro (y lo recuerda para la próxima vez).
func alternar_tema() -> void:
	var anterior := Tema.modo
	Tema.modo = "oscuro" if Tema.es_claro() else "claro"
	Tema.guardar()
	Tema.aplicar(get_tree(), anterior)
	tema_cambiado.emit(Tema.es_claro())


## Cambia entre el cuerpo masculino y el femenino sin pasar por el inicio: recarga la pantalla
## principal conservando la sección y la edad.
func cambiar_cuerpo(id: String, estado: Dictionary) -> void:
	Datos.cuerpo_elegido = id
	estado_vista = estado
	modo_inicial = estado.get("modo", modo_inicial)
	SimulationEngine.reiniciar()
	SimulationEngine.seleccionar_escenario("")
	get_tree().change_scene_to_file(ESCENA_PRINCIPAL)


func ir_a_principal(modo: String) -> void:
	modo_inicial = modo
	get_tree().change_scene_to_file(ESCENA_PRINCIPAL)


func volver_al_inicio() -> void:
	SimulationEngine.reiniciar()
	SimulationEngine.seleccionar_escenario("")
	get_tree().change_scene_to_file(ESCENA_INICIO)


func salir() -> void:
	get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var modo := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED
				if modo == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
