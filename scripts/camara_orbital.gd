class_name CamaraOrbital
extends Camera3D
## Cámara que orbita alrededor de un punto objetivo.
##
## Controles:
##   Mouse    — clic izquierdo + arrastrar: girar · rueda: zoom · clic derecho/central + arrastrar: desplazar
##   Trackpad — clic + arrastrar: girar · pellizco: zoom · dos dedos: desplazar · ⌘/Ctrl + dos dedos: zoom
##   Mayús + clic izquierdo + arrastrar: desplazar (alternativa sin botón derecho)
##
## La cámara guarda un estado "deseado" (yaw, pitch, distancia, objetivo) que cambian la entrada
## y los Tween, y un estado "actual" que lo sigue con suavizado exponencial en _process.
## Toda la configuración (límites, sensibilidades, vistas) viene de res://data/camara.json.

signal transicion_terminada

# Estado deseado
var yaw := 0.0          ## Grados. 0 = frente del cuerpo (+Z)
var pitch := 5.0        ## Grados. Positivo = mirar desde arriba
var distancia := 2.6    ## Metros
var objetivo := Vector3(0, 1, 0)

# Estado actual (suavizado)
var _yaw_actual := 0.0
var _pitch_actual := 5.0
var _distancia_actual := 2.6
var _objetivo_actual := Vector3(0, 1, 0)

# Configuración (se sobrescribe con configurar())
var _cfg := {}
var _distancia_min := 0.35
var _distancia_max := 6.0
var _pitch_min := -80.0
var _pitch_max := 88.0
var _limite_min := Vector3(-1, 0, -1)
var _limite_max := Vector3(1, 2, 1)
var _sens_rotacion := 0.35
var _sens_desplazamiento := 0.0016
var _sens_gesto := 0.0015
var _invertir_gesto := false
var _paso_zoom := 0.1
var _suavizado := 14.0
var _duracion := 0.7
var _objetivo_inicial := Vector3(0, 1, 0)
var _distancia_inicial := 2.6

var _rotando := false
var _desplazando := false
var _tween: Tween


func configurar(cfg: Dictionary) -> void:
	_cfg = cfg
	_distancia_min = cfg.get("distancia_min", _distancia_min)
	_distancia_max = cfg.get("distancia_max", _distancia_max)
	_pitch_min = cfg.get("pitch_min", _pitch_min)
	_pitch_max = cfg.get("pitch_max", _pitch_max)
	_limite_min = _vec3(cfg.get("limite_objetivo_min"), _limite_min)
	_limite_max = _vec3(cfg.get("limite_objetivo_max"), _limite_max)
	_sens_rotacion = cfg.get("sensibilidad_rotacion", _sens_rotacion)
	_sens_desplazamiento = cfg.get("sensibilidad_desplazamiento", _sens_desplazamiento)
	_sens_gesto = cfg.get("sensibilidad_gesto_desplazamiento", _sens_gesto)
	_invertir_gesto = cfg.get("invertir_gesto_desplazamiento", _invertir_gesto)
	_paso_zoom = cfg.get("paso_zoom_rueda", _paso_zoom)
	_suavizado = cfg.get("suavizado", _suavizado)
	_duracion = cfg.get("duracion_transicion", _duracion)
	_objetivo_inicial = _vec3(cfg.get("objetivo_inicial"), _objetivo_inicial)
	_distancia_inicial = cfg.get("distancia_inicial", _distancia_inicial)

	# Estado inicial: vista de frente, sin animación
	var frente := obtener_vista("frente")
	yaw = frente.get("yaw", 0.0)
	pitch = frente.get("pitch", 5.0)
	distancia = _distancia_inicial
	objetivo = _objetivo_inicial
	_saltar_a_deseado()


## Permite acercarse mucho a estructuras diminutas (p. ej. el estribo, de ~3 mm) mientras
## están aisladas; al desactivarlo se restauran los límites de data/camara.json.
func permitir_acercamiento(activo: bool) -> void:
	_distancia_min = 0.03 if activo else float(_cfg.get("distancia_min", 0.35))
	near = 0.002 if activo else 0.02
	if not activo:
		distancia = maxf(distancia, _distancia_min)


## Cambia el encuadre de referencia ("Cuerpo completo" y vistas rápidas), p. ej. al cambiar la edad.
func fijar_referencia(nuevo_objetivo: Vector3, nueva_distancia: float) -> void:
	_objetivo_inicial = nuevo_objetivo
	_distancia_inicial = nueva_distancia


func objetivo_inicial() -> Vector3:
	return _objetivo_inicial


func distancia_inicial() -> float:
	return _distancia_inicial


## Devuelve la definición de una vista rápida por su id (o {} si no existe).
func obtener_vista(id: String) -> Dictionary:
	for v in _cfg.get("vistas", []):
		if v.get("id") == id:
			return v
	return {}


## Transición suave a una vista rápida (Frente, Espalda, ...). Recentra el objetivo.
func ir_a_vista(id: String) -> void:
	var v := obtener_vista(id)
	if v.is_empty():
		push_warning("Vista desconocida: %s" % id)
		return
	animar_a(v.get("yaw", 0.0), v.get("pitch", 0.0), _distancia_inicial, _objetivo_inicial)


## Encuadra un punto a cierta distancia conservando el ángulo actual (se usará en la Fase 2).
func encuadrar(centro: Vector3, nueva_distancia: float) -> void:
	animar_a(yaw, pitch, nueva_distancia, centro)


## Anima el estado deseado con un Tween. El yaw toma el camino más corto.
func animar_a(nuevo_yaw: float, nuevo_pitch: float, nueva_distancia: float, nuevo_objetivo: Vector3) -> void:
	_detener_tween()
	var yaw_destino := yaw + wrapf(nuevo_yaw - yaw, -180.0, 180.0)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "yaw", yaw_destino, _duracion)
	_tween.tween_property(self, "pitch", clampf(nuevo_pitch, _pitch_min, _pitch_max), _duracion)
	_tween.tween_property(self, "distancia", clampf(nueva_distancia, _distancia_min, _distancia_max), _duracion)
	_tween.tween_property(self, "objetivo", _limitar_objetivo(nuevo_objetivo), _duracion)
	_tween.chain().tween_callback(func(): transicion_terminada.emit())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_procesar_boton(event)
	elif event is InputEventMouseMotion:
		if _rotando:
			_detener_tween()
			yaw -= event.relative.x * _sens_rotacion
			pitch = clampf(pitch + event.relative.y * _sens_rotacion, _pitch_min, _pitch_max)
		elif _desplazando:
			_detener_tween()
			_desplazar(event.relative * _sens_desplazamiento * distancia)
	elif event is InputEventMagnifyGesture:
		# Pellizco en trackpad: factor > 1 = acercar
		_detener_tween()
		_aplicar_zoom(1.0 / event.factor)
	elif event is InputEventPanGesture:
		# Dos dedos en trackpad. Con ⌘/Ctrl hace zoom; si no, desplaza.
		_detener_tween()
		if event.is_command_or_control_pressed():
			_aplicar_zoom(1.0 + event.delta.y * _paso_zoom * 0.5)
		else:
			var signo := -1.0 if _invertir_gesto else 1.0
			_desplazar(event.delta * _sens_gesto * distancia * signo)


func _procesar_boton(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed and event.shift_pressed:
				_desplazando = true
			elif event.pressed:
				_rotando = true
			else:
				_rotando = false
				_desplazando = false
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_desplazando = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_detener_tween()
				_aplicar_zoom(pow(1.0 - _paso_zoom, _factor_rueda(event)))
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_detener_tween()
				_aplicar_zoom(pow(1.0 + _paso_zoom, _factor_rueda(event)))


func _process(delta: float) -> void:
	# Suavizado exponencial independiente de los FPS
	var t := 1.0 - exp(-_suavizado * delta)
	_yaw_actual = lerpf(_yaw_actual, yaw, t)
	_pitch_actual = lerpf(_pitch_actual, pitch, t)
	_distancia_actual = lerpf(_distancia_actual, distancia, t)
	_objetivo_actual = _objetivo_actual.lerp(objetivo, t)
	_actualizar_transform()


func _actualizar_transform() -> void:
	var y := deg_to_rad(_yaw_actual)
	var p := deg_to_rad(_pitch_actual)
	var dir := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	position = _objetivo_actual + dir * _distancia_actual
	# Cerca de la vista cenital se usa otro vector "arriba" para evitar que look_at falle
	var arriba := Vector3.UP if absf(_pitch_actual) < 89.0 else Vector3(-sin(y), 0, -cos(y))
	look_at(_objetivo_actual, arriba)


func _saltar_a_deseado() -> void:
	_yaw_actual = yaw
	_pitch_actual = pitch
	_distancia_actual = distancia
	_objetivo_actual = objetivo
	_actualizar_transform()


func _desplazar(delta_pantalla: Vector2) -> void:
	var b := global_transform.basis
	objetivo = _limitar_objetivo(objetivo - b.x * delta_pantalla.x + b.y * delta_pantalla.y)


func _aplicar_zoom(multiplicador: float) -> void:
	distancia = clampf(distancia * multiplicador, _distancia_min, _distancia_max)


func _factor_rueda(event: InputEventMouseButton) -> float:
	# Algunos dispositivos envían "factor" (desplazamiento fino); si no, vale 1
	return event.factor if event.factor > 0.0 else 1.0


func _limitar_objetivo(v: Vector3) -> Vector3:
	return v.clamp(_limite_min, _limite_max)


func _detener_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _vec3(valor, por_defecto: Vector3) -> Vector3:
	if valor is Array and valor.size() == 3:
		return Vector3(valor[0], valor[1], valor[2])
	return por_defecto
