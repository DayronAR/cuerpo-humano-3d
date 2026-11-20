class_name PanelFicha
extends PanelContainer
## Panel lateral derecho con la ficha del órgano seleccionado.
## Solo muestra datos que recibe; no busca ni carga nada por sí mismo.

signal cerrado
signal aislar_cambiado(activo: bool)

@onready var _titulo: Label = %Titulo
@onready var _sistema: Label = %Sistema
@onready var _marca_color: ColorRect = %MarcaColor
@onready var _funcion: Label = %Funcion
@onready var _curiosos: Label = %Curiosos
@onready var _boton_cerrar: Button = %BotonCerrar
@onready var _boton_aislar: Button = %BotonAislar


func _ready() -> void:
	hide()
	_boton_cerrar.pressed.connect(_on_cerrar)
	_boton_aislar.toggled.connect(aislar_cambiado.emit)


## ficha: {nombre, funcion, datos_curiosos[]} del órgano · nombre_sistema/color_sistema para la
## etiqueta · nombre_parte: si se eligió una parte del órgano (p. ej. "Estribo"), es el título.
## ficha_parte: ficha propia de la parte (opcional); reemplaza función y datos del órgano.
func mostrar(ficha: Dictionary, nombre_sistema: String, color_sistema: Color, nombre_parte := "",
		ficha_parte: Dictionary = {}) -> void:
	if nombre_parte.is_empty():
		_titulo.text = ficha.get("nombre", "")
		_sistema.text = nombre_sistema
	else:
		_titulo.text = nombre_parte
		_sistema.text = "Parte de: %s · %s" % [ficha.get("nombre", ""), nombre_sistema]
	mostrar_aislado(false)
	_marca_color.color = color_sistema
	if not ficha_parte.is_empty():
		ficha = ficha_parte
	_funcion.text = ficha.get("funcion", "")
	var lineas := PackedStringArray()
	for dato in ficha.get("datos_curiosos", []):
		lineas.append("•  " + str(dato))
	_curiosos.text = "\n".join(lineas) if not lineas.is_empty() else "—"
	show()


func mostrar_aislado(activo: bool) -> void:
	_boton_aislar.set_pressed_no_signal(activo)
	_boton_aislar.text = "Mostrar todo" if activo else "Aislar"


func ocultar() -> void:
	hide()


func _on_cerrar() -> void:
	hide()
	cerrado.emit()
