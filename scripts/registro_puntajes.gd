class_name RegistroPuntajes
extends RefCounted

const RUTA := "user://puntajes.json"
const MAXIMO_HISTORIAL := 20


static func dymj_cargar() -> Dictionary:
	if not FileAccess.file_exists(RUTA):
		return {"mejor_puntaje": 0, "mejor_total": 0, "historial": []}
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if not datos is Dictionary:
		push_warning("puntajes.json dañado; se empieza de cero")
		return {"mejor_puntaje": 0, "mejor_total": 0, "historial": []}
	return datos


static func dymj_registrar(puntaje: int, total: int, nivel := "facil") -> bool:
	var datos := dymj_cargar()
	var historial: Array = datos.get("historial", [])
	historial.push_front({
		"fecha": Time.get_datetime_string_from_system(false, true),
		"puntaje": puntaje,
		"total": total,
		"nivel": nivel,
	})
	datos["historial"] = historial.slice(0, MAXIMO_HISTORIAL)
	var mejores: Dictionary = datos.get("mejores", {"facil": {"puntaje": datos.get("mejor_puntaje", 0),
			"total": datos.get("mejor_total", 0)}})
	var record := puntaje > int(mejores.get(nivel, {}).get("puntaje", 0))
	if record:
		mejores[nivel] = {"puntaje": puntaje, "total": total}
	datos["mejores"] = mejores
	var archivo := FileAccess.open(RUTA, FileAccess.WRITE)
	if archivo == null:
		push_error("No se pudo guardar %s: %s" % [RUTA, error_string(FileAccess.get_open_error())])
		return record
	archivo.store_string(JSON.stringify(datos, "  "))
	return record


static func dymj_mejor_puntaje(nivel := "facil") -> Dictionary:
	var datos := dymj_cargar()
	var mejores: Dictionary = datos.get("mejores", {"facil": {"puntaje": datos.get("mejor_puntaje", 0),
			"total": datos.get("mejor_total", 0)}})
	var m: Dictionary = mejores.get(nivel, {})
	return {"puntaje": int(m.get("puntaje", 0)), "total": int(m.get("total", 0))}
