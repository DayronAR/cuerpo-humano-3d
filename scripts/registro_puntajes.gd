class_name RegistroPuntajes
extends RefCounted
## Guarda los puntajes del cuestionario en user://puntajes.json (carpeta de datos del usuario:
## en Windows %APPDATA%\Godot\app_userdata\Cuerpo Humano 3D, en macOS
## ~/Library/Application Support/Godot/app_userdata/Cuerpo Humano 3D).

const RUTA := "user://puntajes.json"
const MAXIMO_HISTORIAL := 20


static func cargar() -> Dictionary:
	if not FileAccess.file_exists(RUTA):
		return {"mejor_puntaje": 0, "mejor_total": 0, "historial": []}
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if not datos is Dictionary:
		push_warning("puntajes.json dañado; se empieza de cero")
		return {"mejor_puntaje": 0, "mejor_total": 0, "historial": []}
	return datos


## Registra una partida. Devuelve true si es un nuevo récord.
static func registrar(puntaje: int, total: int) -> bool:
	var datos := cargar()
	var historial: Array = datos.get("historial", [])
	historial.push_front({
		"fecha": Time.get_datetime_string_from_system(false, true),
		"puntaje": puntaje,
		"total": total,
	})
	datos["historial"] = historial.slice(0, MAXIMO_HISTORIAL)
	var record := puntaje > int(datos.get("mejor_puntaje", 0))
	if record:
		datos["mejor_puntaje"] = puntaje
		datos["mejor_total"] = total
	var archivo := FileAccess.open(RUTA, FileAccess.WRITE)
	if archivo == null:
		push_error("No se pudo guardar %s: %s" % [RUTA, error_string(FileAccess.get_open_error())])
		return record
	archivo.store_string(JSON.stringify(datos, "  "))
	return record


static func mejor_puntaje() -> Dictionary:
	var datos := cargar()
	return {"puntaje": int(datos.get("mejor_puntaje", 0)), "total": int(datos.get("mejor_total", 0))}
