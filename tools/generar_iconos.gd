extends SceneTree
## Rasteriza icon.svg en PNG de varios tamaños dentro de ui/iconos/ (para el .ico de Windows y
## el icono de macOS). Después tools/empaquetar_ico.py une los PNG en ui/icono.ico.
##
##     godot --headless --path . --script res://tools/generar_iconos.gd
##     python3 tools/empaquetar_ico.py

const TAMANOS := [16, 24, 32, 48, 64, 128, 256, 512, 1024]


func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/iconos"))
	for t in TAMANOS:
		var imagen := Image.new()
		var error := imagen.load_svg_from_string(svg, t / 128.0)
		if error != OK:
			push_error("No se pudo rasterizar el SVG (%d)" % error)
			quit(1)
			return
		imagen.save_png("res://ui/iconos/icono_%d.png" % t)
	print("Iconos generados en res://ui/iconos/")
	quit()
