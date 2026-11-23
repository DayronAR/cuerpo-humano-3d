class_name PanelFicha
extends PanelContainer
## Panel lateral derecho con la ficha del órgano seleccionado.
## Solo muestra datos que recibe; no busca ni carga nada por sí mismo.

signal cerrado
signal aislar_cambiado(activo: bool)
signal parte_elegida(id_parte: String)

@onready var _titulo: Label = %Titulo
@onready var _sistema: Label = %Sistema
@onready var _marca_color: ColorRect = %MarcaColor
@onready var _funcion: Label = %Funcion
@onready var _curiosos: Label = %Curiosos
@onready var _boton_cerrar: Button = %BotonCerrar
@onready var _boton_aislar: Button = %BotonAislar
@onready var _etiqueta_partes: Label = %EtiquetaPartes
@onready var _lista_partes: ItemList = %ListaPartes
var _enfermedades: Label
var _etiqueta_edad: Label
var _texto_edad: Label
var _desplazable: ScrollContainer
var _ficha_actual: Dictionary = {}
var _edad := 30.0

const MARGEN := 16.0
const ARRIBA := 58.0   ## Debajo de la barra de vistas (Frente, Espalda, ..., Centrar)
const ANCHO := 360.0

const ETAPAS := [[2.0, "bebe", "EN EL BEBÉ"], [12.0, "nino", "EN LA INFANCIA"], [60.0, "", ""], [999.0, "anciano", "EN EL ADULTO MAYOR"]]


func _ready() -> void:
	hide()
	_armar_secciones()
	get_viewport().size_changed.connect(_ajustar_alto)
	_boton_cerrar.pressed.connect(_on_cerrar)
	_boton_aislar.toggled.connect(aislar_cambiado.emit)
	_lista_partes.item_clicked.connect(func(i, _pos, _boton): parte_elegida.emit(_lista_partes.get_item_metadata(i)))


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
	_ficha_actual = ficha
	var enf := PackedStringArray()
	for e in ficha.get("enfermedades", []):
		enf.append("•  " + str(e))
	_enfermedades.text = "\n".join(enf)
	_enfermedades.get_meta("titulo").visible = not enf.is_empty()
	_enfermedades.visible = not enf.is_empty()
	_mostrar_edad()
	_desplazable.scroll_vertical = 0
	show()
	_ajustar_alto()


## La ficha muestra cómo es el órgano en la etapa de la edad elegida en la barra.
func fijar_edad(anios: float, _final := false) -> void:
	_edad = anios
	if visible:
		_mostrar_edad()


func _mostrar_edad() -> void:
	var clave := ""
	var titulo := ""
	for e in ETAPAS:
		if _edad < e[0]:
			clave = e[1]
			titulo = e[2]
			break
	var texto: String = _ficha_actual.get("edad", {}).get(clave, "") if not clave.is_empty() else ""
	_etiqueta_edad.text = titulo
	_texto_edad.text = texto
	_etiqueta_edad.visible = not texto.is_empty()
	_texto_edad.visible = not texto.is_empty()


## Las secciones de texto van dentro de un contenedor con barra de desplazamiento, para que la
## ficha no se salga de la pantalla aunque tenga mucho contenido.
func _armar_secciones() -> void:
	var contenido: VBoxContainer = $Contenido
	_desplazable = ScrollContainer.new()
	_desplazable.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var secciones := VBoxContainer.new()
	secciones.add_theme_constant_override("separation", 8)
	secciones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desplazable.add_child(secciones)
	var titulo_funcion := contenido.get_node("EtiquetaFuncion")
	contenido.add_child(_desplazable)
	contenido.move_child(_desplazable, titulo_funcion.get_index())
	for nodo in [titulo_funcion, _funcion, contenido.get_node("EtiquetaCuriosos"), _curiosos]:
		nodo.reparent(secciones)
	var t_enf := _titulo_seccion("ENFERMEDADES FRECUENTES", Color(1.0, 0.5, 0.47))
	secciones.add_child(t_enf)
	_enfermedades = _texto()
	_enfermedades.set_meta("titulo", t_enf)
	secciones.add_child(_enfermedades)
	_etiqueta_edad = _titulo_seccion("", Color(0.72, 0.6, 0.98))
	secciones.add_child(_etiqueta_edad)
	_texto_edad = _texto()
	secciones.add_child(_texto_edad)


func _titulo_seccion(texto: String, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _texto() -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(320, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.89, 0.925, 0.945, 1))
	return l


func _ajustar_alto() -> void:
	var alto_pantalla := get_viewport_rect().size.y
	var reservado := 260.0 + (150.0 if _lista_partes.visible else 0.0)
	var contenido_alto: float = _desplazable.get_child(0).get_combined_minimum_size().y
	_desplazable.custom_minimum_size.y = minf(contenido_alto, maxf(160.0, alto_pantalla - reservado))
	# Siempre pegada al borde derecho y debajo de la barra de vistas. (reset_size() conservaba la
	# esquina superior izquierda: al cambiar el ancho, la ficha se iba corriendo hacia el centro.)
	var minimo := get_combined_minimum_size()
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -MARGEN
	offset_left = -MARGEN - maxf(minimo.x, ANCHO)
	offset_top = ARRIBA
	offset_bottom = ARRIBA + minf(minimo.y, alto_pantalla - ARRIBA - MARGEN)


## partes: [[id, nombre], ...] del órgano seleccionado ([] = no tiene partes; se oculta la lista).
func mostrar_partes(partes: Array, id_seleccionada: String) -> void:
	_lista_partes.clear()
	_etiqueta_partes.visible = not partes.is_empty()
	_lista_partes.visible = not partes.is_empty()
	_etiqueta_partes.text = "PARTES (%d) — elige una para marcarla" % partes.size()
	for p in partes:
		var i := _lista_partes.add_item(p[1])
		_lista_partes.set_item_metadata(i, p[0])
		if p[0] == id_seleccionada:
			_lista_partes.select(i)
			_lista_partes.ensure_current_is_visible()
	_ajustar_alto()


func mostrar_aislado(activo: bool) -> void:
	_boton_aislar.set_pressed_no_signal(activo)
	_boton_aislar.text = "Mostrar todo" if activo else "Aislar"


func ocultar() -> void:
	hide()


func _on_cerrar() -> void:
	hide()
	cerrado.emit()
