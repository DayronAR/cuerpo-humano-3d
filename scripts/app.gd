extends Node
## Autoload "App": navegación entre pantallas y ajustes de la ventana.
##   - Recuerda con qué modo abrir la pantalla principal (explorar, simular, cuestionario).
##   - F11 alterna pantalla completa (útil en la sustentación).

const ESCENA_INICIO := "res://scenes/inicio.tscn"
const ESCENA_PRINCIPAL := "res://scenes/main.tscn"
const TAMANO_MINIMO := Vector2i(1024, 600)

var modo_inicial := "explorar"   ## "explorar", "simular" o "cuestionario"


func _ready() -> void:
	DisplayServer.window_set_min_size(TAMANO_MINIMO)


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
