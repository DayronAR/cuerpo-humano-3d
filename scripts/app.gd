extends Node

const ESCENA_INICIO := "res://scenes/inicio.tscn"
const ESCENA_PRINCIPAL := "res://scenes/main.tscn"
const TAMANO_MINIMO := Vector2i(1024, 600)

var modo_inicial := "explorar"
var estado_vista: Dictionary = {}

signal tema_cambiado(claro: bool)


func _ready() -> void:
	DisplayServer.window_set_min_size(TAMANO_MINIMO)
	Tema.dymj_cargar()
	Tema.dymj_aplicar.call_deferred(get_tree(), "oscuro")


func dymj_alternar_tema() -> void:
	var anterior := Tema.modo
	Tema.modo = "oscuro" if Tema.dymj_es_claro() else "claro"
	Tema.dymj_guardar()
	Tema.dymj_aplicar(get_tree(), anterior)
	tema_cambiado.emit(Tema.dymj_es_claro())


func dymj_cambiar_cuerpo(id: String, estado: Dictionary) -> void:
	Datos.cuerpo_elegido = id
	estado_vista = estado
	modo_inicial = estado.get("modo", modo_inicial)
	SimulationEngine.jlrl_reiniciar()
	SimulationEngine.jlrl_seleccionar_escenario("")
	get_tree().change_scene_to_file(ESCENA_PRINCIPAL)


func dymj_ir_a_principal(modo: String) -> void:
	modo_inicial = modo
	get_tree().change_scene_to_file(ESCENA_PRINCIPAL)


func dymj_volver_al_inicio() -> void:
	SimulationEngine.jlrl_reiniciar()
	SimulationEngine.jlrl_seleccionar_escenario("")
	get_tree().change_scene_to_file(ESCENA_INICIO)


func dymj_salir() -> void:
	get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var modo := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED
				if modo == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
