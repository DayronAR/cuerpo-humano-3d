class_name CamaraOrbital
extends Camera3D

signal transicion_terminada

var yaw := 0.0
var pitch := 5.0
var distancia := 2.6
var objetivo := Vector3(0, 1, 0)

var _yaw_actual := 0.0
var _pitch_actual := 5.0
var _distancia_actual := 2.6
var _objetivo_actual := Vector3(0, 1, 0)

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


func drar_configurar(cfg: Dictionary) -> void:
	_cfg = cfg
	_distancia_min = cfg.get("distancia_min", _distancia_min)
	_distancia_max = cfg.get("distancia_max", _distancia_max)
	_pitch_min = cfg.get("pitch_min", _pitch_min)
	_pitch_max = cfg.get("pitch_max", _pitch_max)
	_limite_min = _drar_vec3(cfg.get("limite_objetivo_min"), _limite_min)
	_limite_max = _drar_vec3(cfg.get("limite_objetivo_max"), _limite_max)
	_sens_rotacion = cfg.get("sensibilidad_rotacion", _sens_rotacion)
	_sens_desplazamiento = cfg.get("sensibilidad_desplazamiento", _sens_desplazamiento)
	_sens_gesto = cfg.get("sensibilidad_gesto_desplazamiento", _sens_gesto)
	_invertir_gesto = cfg.get("invertir_gesto_desplazamiento", _invertir_gesto)
	_paso_zoom = cfg.get("paso_zoom_rueda", _paso_zoom)
	_suavizado = cfg.get("suavizado", _suavizado)
	_duracion = cfg.get("duracion_transicion", _duracion)
	_objetivo_inicial = _drar_vec3(cfg.get("objetivo_inicial"), _objetivo_inicial)
	_distancia_inicial = cfg.get("distancia_inicial", _distancia_inicial)

	var frente := drar_obtener_vista("frente")
	yaw = frente.get("yaw", 0.0)
	pitch = frente.get("pitch", 5.0)
	distancia = _distancia_inicial
	objetivo = _objetivo_inicial
	_drar_saltar_a_deseado()


func drar_permitir_acercamiento(activo: bool) -> void:
	_distancia_min = 0.03 if activo else float(_cfg.get("distancia_min", 0.35))
	near = 0.002 if activo else 0.02
	if not activo:
		distancia = maxf(distancia, _distancia_min)


func drar_fijar_referencia(nuevo_objetivo: Vector3, nueva_distancia: float) -> void:
	_objetivo_inicial = nuevo_objetivo
	_distancia_inicial = nueva_distancia


func drar_objetivo_inicial() -> Vector3:
	return _objetivo_inicial


func drar_distancia_inicial() -> float:
	return _distancia_inicial


func drar_obtener_vista(id: String) -> Dictionary:
	for v in _cfg.get("vistas", []):
		if v.get("id") == id:
			return v
	return {}


func drar_ir_a_vista(id: String) -> void:
	var v := drar_obtener_vista(id)
	if v.is_empty():
		push_warning("Vista desconocida: %s" % id)
		return
	drar_animar_a(v.get("yaw", 0.0), v.get("pitch", 0.0), _distancia_inicial, _objetivo_inicial)


func drar_encuadrar(centro: Vector3, nueva_distancia: float) -> void:
	drar_animar_a(yaw, pitch, nueva_distancia, centro)


func drar_animar_a(nuevo_yaw: float, nuevo_pitch: float, nueva_distancia: float, nuevo_objetivo: Vector3) -> void:
	_drar_detener_tween()
	var yaw_destino := yaw + wrapf(nuevo_yaw - yaw, -180.0, 180.0)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "yaw", yaw_destino, _duracion)
	_tween.tween_property(self, "pitch", clampf(nuevo_pitch, _pitch_min, _pitch_max), _duracion)
	_tween.tween_property(self, "distancia", clampf(nueva_distancia, _distancia_min, _distancia_max), _duracion)
	_tween.tween_property(self, "objetivo", _drar_limitar_objetivo(nuevo_objetivo), _duracion)
	_tween.chain().tween_callback(func(): transicion_terminada.emit())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_drar_procesar_boton(event)
	elif event is InputEventMouseMotion:
		if _rotando:
			_drar_detener_tween()
			yaw -= event.relative.x * _sens_rotacion
			pitch = clampf(pitch + event.relative.y * _sens_rotacion, _pitch_min, _pitch_max)
		elif _desplazando:
			_drar_detener_tween()
			_drar_desplazar(event.relative * _sens_desplazamiento * distancia)
	elif event is InputEventMagnifyGesture:
		_drar_detener_tween()
		_drar_aplicar_zoom(1.0 / event.factor)
	elif event is InputEventPanGesture:
		_drar_detener_tween()
		if event.is_command_or_control_pressed():
			_drar_aplicar_zoom(1.0 + event.delta.y * _paso_zoom * 0.5)
		else:
			var signo := -1.0 if _invertir_gesto else 1.0
			_drar_desplazar(event.delta * _sens_gesto * distancia * signo)


func _drar_procesar_boton(event: InputEventMouseButton) -> void:
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
				_drar_detener_tween()
				_drar_aplicar_zoom(pow(1.0 - _paso_zoom, _drar_factor_rueda(event)))
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_drar_detener_tween()
				_drar_aplicar_zoom(pow(1.0 + _paso_zoom, _drar_factor_rueda(event)))


func _process(delta: float) -> void:
	var t := 1.0 - exp(-_suavizado * delta)
	_yaw_actual = lerpf(_yaw_actual, yaw, t)
	_pitch_actual = lerpf(_pitch_actual, pitch, t)
	_distancia_actual = lerpf(_distancia_actual, distancia, t)
	_objetivo_actual = _objetivo_actual.lerp(objetivo, t)
	_drar_actualizar_transform()


func _drar_actualizar_transform() -> void:
	var y := deg_to_rad(_yaw_actual)
	var p := deg_to_rad(_pitch_actual)
	var dir := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	position = _objetivo_actual + dir * _distancia_actual
	var arriba := Vector3.UP if absf(_pitch_actual) < 89.0 else Vector3(-sin(y), 0, -cos(y))
	look_at(_objetivo_actual, arriba)


func _drar_saltar_a_deseado() -> void:
	_yaw_actual = yaw
	_pitch_actual = pitch
	_distancia_actual = distancia
	_objetivo_actual = objetivo
	_drar_actualizar_transform()


func _drar_desplazar(delta_pantalla: Vector2) -> void:
	var b := global_transform.basis
	objetivo = _drar_limitar_objetivo(objetivo - b.x * delta_pantalla.x + b.y * delta_pantalla.y)


func _drar_aplicar_zoom(multiplicador: float) -> void:
	distancia = clampf(distancia * multiplicador, _distancia_min, _distancia_max)


func _drar_factor_rueda(event: InputEventMouseButton) -> float:
	return event.factor if event.factor > 0.0 else 1.0


func _drar_limitar_objetivo(v: Vector3) -> Vector3:
	return v.clamp(_limite_min, _limite_max)


func _drar_detener_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _drar_vec3(valor, por_defecto: Vector3) -> Vector3:
	if valor is Array and valor.size() == 3:
		return Vector3(valor[0], valor[1], valor[2])
	return por_defecto
