class_name PanelFicha
extends PanelContainer
## Panel lateral derecho con la ficha del órgano seleccionado.
## Solo muestra datos que recibe; no busca ni carga nada por sí mismo.

signal cerrado

@onready var _titulo: Label = %Titulo
@onready var _sistema: Label = %Sistema
@onready var _marca_color: ColorRect = %MarcaColor
@onready var _funcion: Label = %Funcion
@onready var _curiosos: Label = %Curiosos
@onready var _boton_cerrar: Button = %BotonCerrar


func _ready() -> void:
	hide()
	_boton_cerrar.pressed.connect(_on_cerrar)


## ficha: {nombre, funcion, datos_curiosos[]} · nombre_sistema/color_sistema para la etiqueta
func mostrar(ficha: Dictionary, nombre_sistema: String, color_sistema: Color) -> void:
	_titulo.text = ficha.get("nombre", "")
	_sistema.text = nombre_sistema
	_marca_color.color = color_sistema
	_funcion.text = ficha.get("funcion", "")
	var lineas := PackedStringArray()
	for dato in ficha.get("datos_curiosos", []):
		lineas.append("•  " + str(dato))
	_curiosos.text = "\n".join(lineas) if not lineas.is_empty() else "—"
	show()


func ocultar() -> void:
	hide()


func _on_cerrar() -> void:
	hide()
	cerrado.emit()
