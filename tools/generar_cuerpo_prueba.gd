extends SceneTree
## Genera res://scenes/cuerpo_prueba.tscn: cuerpo humano de prueba con geometría ORGÁNICA hecha
## por código (sin descargar modelos). Sirve hasta integrar los modelos de Z-Anatomy.
##
## Uso (desde la raíz del proyecto; tarda ~1 minuto):
##     godot --headless --path . --script res://tools/generar_cuerpo_prueba.gd
##
## Técnicas:
##   - Superficies implícitas (SDF, "signed distance fields") malladas con "surface nets":
##     piel, cráneo, corazón, pulmones, hígado, cerebro, pelvis, músculos. Permiten unir formas
##     suavemente (smooth union) y restar huecos (órbitas, muesca cardiaca), como en escultura.
##   - Tubos a lo largo de curvas: intestinos, vasos, costillas, tráquea, esófago, estómago,
##     huesos largos (con perfil de radio: epífisis anchas y diáfisis delgada).
##
## Convención OBLIGATORIA (la misma que deben cumplir los .glb de Blender):
##     Cuerpo (Node3D) / <Sistema> (Node3D) / <Organo> (MeshInstance3D o Node3D con partes)
## Unidades en metros. Pies en y = 0, altura ~1,75 m. El cuerpo mira hacia +Z.
## El lado IZQUIERDO del paciente está en +X.
##
## Las mallas se guardan en res://models/prueba/ (binario .res) y los materiales en
## res://models/prueba/materiales/. Al final imprime las trayectorias del bolo, el humo y la
## circulación para copiarlas en data/visuales.json si se cambia la anatomía.

const SALIDA := "res://scenes/cuerpo_prueba.tscn"
const CARPETA := "res://models/prueba"

var _raiz: Node3D
var _materiales := {}
var _ruido := FastNoiseLite.new()
var _triangulos_total := 0
var _curvas := {}   ## Centros de los tubos digestivos y respiratorios, para las trayectorias
var _relieve := []  ## Formas (infladas) de músculos y huesos superficiales que la piel debe cubrir
var _registrar_relieve := false
const INFLADO_RELIEVE := 0.0035


func _init() -> void:
	var inicio := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA + "/materiales"))
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido.frequency = 55.0
	_ruido.seed = 7

	# Toda la paleta se guarda en disco (también la usa tools/ensamblar_cuerpo_glb.gd)
	for nombre in DEF_MATERIALES:
		_material(nombre)

	_raiz = Node3D.new()
	_raiz.name = "Cuerpo"
	# Los músculos (y algunos huesos superficiales) se construyen ANTES que la piel: cada uno
	# registra su forma inflada unos milímetros en _relieve, y la piel se genera envolviéndolos.
	# Así nada atraviesa la piel y la piel muestra el relieve muscular.
	_registrar_relieve = true
	_construir_muscular()
	_construir_oseo()
	_registrar_relieve = false
	_construir_piel()
	_raiz.move_child(_raiz.get_node("Piel"), 0)
	_construir_circulatorio()
	_construir_respiratorio()
	_construir_digestivo()
	_construir_nervioso()

	var escena := PackedScene.new()
	var error := escena.pack(_raiz)
	if error == OK:
		error = ResourceSaver.save(escena, SALIDA)
	if error != OK:
		push_error("No se pudo guardar %s (error %d)" % [SALIDA, error])
		quit(1)
		return
	print("Cuerpo generado en %s · %d triángulos · %.1f s" % [SALIDA, _triangulos_total,
			(Time.get_ticks_msec() - inicio) / 1000.0])
	_imprimir_trayectorias()
	_generar_maniqui()
	_raiz.free()
	quit()


# =============================================================================================
# ANATOMÍA
# =============================================================================================

# --- Piel ------------------------------------------------------------------------------------

## Primitivas del cuerpo: [tipo, ...]. "e" elipsoide (centro, radios), "c" cápsula cónica
## (a, b, radio_a, radio_b). Se unen con smooth union para que no se noten las uniones.
var _formas_piel := []


func _construir_piel() -> void:
	var f := _formas_piel
	f.append(["e", Vector3(0, 1.648, -0.006), Vector3(0.08, 0.1, 0.1)])     # cráneo
	f.append(["e", Vector3(0, 1.575, 0.034), Vector3(0.061, 0.07, 0.066)])     # cara y mandíbula
	f.append(["e", Vector3(0, 1.6, 0.098), Vector3(0.012, 0.022, 0.014)])      # nariz
	f.append(["c", Vector3(0, 1.42, -0.012), Vector3(0, 1.54, -0.006), 0.053, 0.05])  # cuello
	f.append(["e", Vector3(0, 1.3, 0.0), Vector3(0.172, 0.175, 0.122)])         # tórax
	f.append(["c", Vector3(-0.17, 1.4, -0.008), Vector3(0.17, 1.4, -0.008), 0.064, 0.064])  # hombros
	f.append(["e", Vector3(0, 1.07, 0.006), Vector3(0.143, 0.162, 0.106)])      # abdomen
	f.append(["e", Vector3(0, 1.175, 0.004), Vector3(0.152, 0.11, 0.112)])      # borde costal
	f.append(["e", Vector3(0, 0.93, -0.008), Vector3(0.17, 0.113, 0.112)])     # pelvis
	f.append(["e", Vector3(0, 0.895, -0.06), Vector3(0.135, 0.074, 0.076)])       # glúteos
	for s in [1.0, -1.0]:
		f.append(["c", Vector3(0.2 * s, 1.39, -0.012), Vector3(0.236 * s, 1.11, -0.018), 0.049, 0.039])  # brazo
		f.append(["c", Vector3(0.236 * s, 1.11, -0.018), Vector3(0.25 * s, 0.855, 0.0), 0.039, 0.026])  # antebrazo
		f.append(["e", Vector3(0.255 * s, 0.775, 0.008), Vector3(0.02, 0.062, 0.04)])                     # mano
		f.append(["c", Vector3(0.092 * s, 0.9, 0.0), Vector3(0.1 * s, 0.5, 0.006), 0.082, 0.052])         # muslo
		f.append(["c", Vector3(0.1 * s, 0.5, 0.006), Vector3(0.1 * s, 0.08, -0.012), 0.052, 0.031])       # pierna
		f.append(["e", Vector3(0.1 * s, 0.33, -0.028), Vector3(0.045, 0.09, 0.045)])                      # pantorrilla
		f.append(["c", Vector3(0.1 * s, 0.035, -0.03), Vector3(0.112 * s, 0.03, 0.12), 0.036, 0.03])    # pie
	var s := _sistema("Piel")
	var malla := _malla_sdf(_sdf_piel, Vector3(-0.33, -0.02, -0.16), Vector3(0.33, 1.77, 0.17), 0.0108)
	_organo(s, "Epidermis", malla, _material("piel"))


func _sdf_piel(p: Vector3) -> float:
	var cuerpo := _sdf_formas(p, _formas_piel, 0.035)
	var musculos := _sdf_formas(p, _relieve, 0.01)
	return _smin(cuerpo, musculos, 0.018)


func _sdf_formas(p: Vector3, formas: Array, k: float) -> float:
	var d := 1.0e9
	for f in formas:
		var df: float
		if f[0] == "e":
			df = _sd_elipsoide(p, f[1], f[2])
		else:
			df = _sd_capsula(p, f[1], f[2], f[3], f[4])
		d = _smin(d, df, k)
	return d


## Registra una forma para que la piel la cubra (solo mientras se construyen músculos y huesos).
func _relieve_elipsoide(c: Vector3, r: Vector3) -> void:
	if _registrar_relieve:
		_relieve.append(["e", c, r + Vector3.ONE * INFLADO_RELIEVE])


# --- Muscular --------------------------------------------------------------------------------

func _construir_muscular() -> void:
	var s := _sistema("Muscular")
	var mat := _material("musculo")
	var pect := _compuesto(s, "Pectorales")
	for lado in [1.0, -1.0]:
		var c := Vector3(0.066 * lado, 1.32, 0.082)
		var giro := Basis(Vector3.FORWARD, deg_to_rad(-16.0 * lado))
		_relieve_elipsoide(c, Vector3(0.07, 0.05, 0.016))
		var sdf := func(p: Vector3) -> float:
			var q := giro * (p - c)
			# Abanico: más grueso cerca del esternón y la axila
			return _sd_elipsoide(q, Vector3.ZERO, Vector3(0.072, 0.05, 0.016))
		_parte(pect, "PectoralIzq" if lado > 0 else "PectoralDer",
				_malla_sdf(sdf, c - Vector3(0.09, 0.08, 0.03), c + Vector3(0.09, 0.08, 0.03), 0.004), mat)

	_relieve_elipsoide(Vector3(0, 1.06, 0.08), Vector3(0.068, 0.142, 0.016))
	var abd := func(p: Vector3) -> float:
		var q := p - Vector3(0, 1.06, 0.08)
		var d := _sd_caja_redondeada(q, Vector3(0.048, 0.118, 0.008), 0.006)
		# Línea alba (surco vertical) e intersecciones tendinosas (los "cuadritos")
		d = maxf(d, -(_sd_caja_redondeada(q - Vector3(0, 0, 0.012), Vector3(0.003, 0.2, 0.006), 0.002)))
		for y in [0.045, -0.01, -0.06]:
			d = maxf(d, -(_sd_caja_redondeada(q - Vector3(0, y, 0.013), Vector3(0.06, 0.0025, 0.005), 0.002)))
		return d
	_organo(s, "Abdominales", _malla_sdf(abd, Vector3(-0.07, 0.92, 0.055), Vector3(0.07, 1.2, 0.105), 0.0035), mat)

	for lado in [1.0, -1.0]:
		var sufijo := "Izq" if lado > 0 else "Der"
		_organo(s, "Biceps" + sufijo, _malla_tubo(
				[Vector3(0.205 * lado, 1.345, 0.0), Vector3(0.222 * lado, 1.24, 0.004), Vector3(0.232 * lado, 1.15, 0.0)],
				_perfil_fusiforme(0.021, 0.004), 14, 0.004), mat)
		_organo(s, "Cuadriceps" + sufijo, _malla_tubo(
				[Vector3(0.088 * lado, 0.87, 0.012), Vector3(0.096 * lado, 0.7, 0.02), Vector3(0.1 * lado, 0.53, 0.016)],
				_perfil_fusiforme(0.041, 0.008), 16, 0.006), mat)
		_organo(s, "Gemelo" + sufijo, _malla_tubo(
				[Vector3(0.1 * lado, 0.46, -0.022), Vector3(0.1 * lado, 0.34, -0.034), Vector3(0.1 * lado, 0.19, -0.03)],
				_perfil_fusiforme(0.033, 0.006), 16, 0.006), mat)

	# Grupos bilaterales: un órgano con una parte por lado (sufijos Izq / Der)
	_bilateral(s, "Deltoides", mat, func(l: float) -> ArrayMesh: return _malla_combinada([
			_malla_tubo([Vector3(0.16 * l, 1.43, 0.018), Vector3(0.212 * l, 1.415, -0.002), Vector3(0.226 * l, 1.31, -0.012)],
					_perfil_fusiforme(0.026, 0.006), 14, 0.004),
			_malla_tubo([Vector3(0.16 * l, 1.43, -0.042), Vector3(0.212 * l, 1.412, -0.026), Vector3(0.226 * l, 1.31, -0.014)],
					_perfil_fusiforme(0.024, 0.006), 14, 0.004)]))
	_bilateral(s, "Triceps", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.206 * l, 1.36, -0.034), Vector3(0.222 * l, 1.24, -0.04), Vector3(0.234 * l, 1.135, -0.034)],
			_perfil_fusiforme(0.022, 0.005), 14, 0.004))
	_bilateral(s, "MusculosAntebrazo", mat, func(l: float) -> ArrayMesh: return _malla_combinada([
			_malla_tubo([Vector3(0.236 * l, 1.1, -0.002), Vector3(0.244 * l, 0.98, 0.006), Vector3(0.25 * l, 0.87, 0.006)],
					_perfil_fusiforme(0.018, 0.004), 12, 0.004),
			_malla_tubo([Vector3(0.24 * l, 1.09, -0.03), Vector3(0.247 * l, 0.98, -0.022), Vector3(0.251 * l, 0.875, -0.01)],
					_perfil_fusiforme(0.015, 0.004), 12, 0.004)]))
	_bilateral(s, "Gluteos", mat, func(l: float) -> ArrayMesh:
		var c := Vector3(0.072 * l, 0.905, -0.07)
		_relieve_elipsoide(c, Vector3(0.066, 0.078, 0.04))
		return _malla_sdf(func(p: Vector3) -> float: return _sd_elipsoide(p, c, Vector3(0.066, 0.078, 0.04)),
				c - Vector3(0.08, 0.09, 0.05), c + Vector3(0.08, 0.09, 0.05), 0.005))
	_bilateral(s, "Isquiotibiales", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.088 * l, 0.84, -0.026), Vector3(0.097 * l, 0.68, -0.028), Vector3(0.1 * l, 0.52, -0.02)],
			_perfil_fusiforme(0.032, 0.006), 14, 0.006))
	_bilateral(s, "TibialAnterior", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.11 * l, 0.46, 0.022), Vector3(0.108 * l, 0.3, 0.024), Vector3(0.102 * l, 0.11, 0.026)],
			_perfil_fusiforme(0.013, 0.004), 10, 0.006))
	_bilateral(s, "Trapecio", mat, func(l: float) -> ArrayMesh: return _malla_combinada([
			_malla_tubo([Vector3(0.0, 1.53, -0.042), Vector3(0.07 * l, 1.45, -0.05), Vector3(0.165 * l, 1.425, -0.03)],
					_perfil_fusiforme(0.014, 0.005), 12, 0.004, Vector2(1.0, 0.6)),
			_malla_tubo([Vector3(0.0, 1.27, -0.075), Vector3(0.06 * l, 1.37, -0.07), Vector3(0.15 * l, 1.42, -0.04)],
					_perfil_fusiforme(0.013, 0.004), 12, 0.004, Vector2(1.0, 0.6))]))
	_bilateral(s, "Dorsal", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.04 * l, 1.12, -0.08), Vector3(0.11 * l, 1.22, -0.074), Vector3(0.165 * l, 1.34, -0.04)],
			_perfil_fusiforme(0.016, 0.005), 12, 0.005, Vector2(1.0, 0.55)))
	_bilateral(s, "Oblicuos", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.112 * l, 1.15, 0.04), Vector3(0.124 * l, 1.05, 0.032), Vector3(0.112 * l, 0.96, 0.044)],
			_perfil_fusiforme(0.019, 0.006), 12, 0.005, Vector2(0.6, 1.0)))
	_bilateral(s, "Esternocleidomastoideo", mat, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.042 * l, 1.56, -0.02), Vector3(0.032 * l, 1.48, 0.016), Vector3(0.012 * l, 1.43, 0.045)],
			_perfil_fusiforme(0.009, 0.003), 10, 0.003))


# --- Óseo ------------------------------------------------------------------------------------

## Curva central de la columna (curvaturas cervical, dorsal y lumbar)
const ESPINA := [
	Vector3(0, 1.565, -0.03), Vector3(0, 1.48, -0.026), Vector3(0, 1.4, -0.04), Vector3(0, 1.3, -0.058),
	Vector3(0, 1.2, -0.062), Vector3(0, 1.1, -0.055), Vector3(0, 1.02, -0.046), Vector3(0, 0.96, -0.052),
]


func _construir_oseo() -> void:
	var s := _sistema("Oseo")
	var hueso := _material("hueso")
	_registrar_relieve = false   # Los huesos profundos no deforman la piel...

	var craneo := func(p: Vector3) -> float:
		var d := _sd_elipsoide(p, Vector3(0, 1.65, -0.008), Vector3(0.071, 0.088, 0.089))
		d = _smin(d, _sd_elipsoide(p, Vector3(0, 1.585, 0.036), Vector3(0.054, 0.056, 0.056)), 0.02)
		d = _smin(d, _sd_elipsoide(p, Vector3(0, 1.533, 0.03), Vector3(0.045, 0.022, 0.046)), 0.015)   # mandíbula
		for x in [0.029, -0.029]:
			d = maxf(d, -_sd_esfera(p, Vector3(x, 1.612, 0.087), 0.019))   # órbitas
		d = maxf(d, -_sd_elipsoide(p, Vector3(0, 1.582, 0.093), Vector3(0.008, 0.014, 0.012)))   # nariz
		return d
	_organo(s, "Craneo", _malla_sdf(craneo, Vector3(-0.09, 1.49, -0.11), Vector3(0.09, 1.75, 0.11), 0.0038), hueso)

	_organo(s, "ColumnaVertebral", _malla_columna(), hueso)

	var caja := _compuesto(s, "CajaToracica")
	for i in 10:
		var y := 1.41 - i * 0.028
		var ancho := 0.085 + 0.052 * sin(minf(1.0, (i + 1) / 6.0) * PI / 2.0)
		for lado in [1.0, -1.0]:
			var puntos := [Vector3(0.018 * lado, y, -0.062), Vector3(ancho * 0.8 * lado, y - 0.01, -0.058),
					Vector3(ancho * lado, y - 0.035, -0.012), Vector3(ancho * 0.78 * lado, y - 0.065, 0.06)]
			if i < 8:   # Las costillas 11 y 12 son flotantes: no llegan al esternón
				puntos.append(Vector3(0.024 * lado, y - 0.085 - i * 0.004, 0.088))
			_parte(caja, "Costilla%d%s" % [i + 1, "Izq" if lado > 0 else "Der"],
					_malla_tubo(puntos, _perfil_constante(0.0052), 8, 0.006), hueso)
	_parte(caja, "Esternon", _malla_tubo([Vector3(0, 1.405, 0.088), Vector3(0, 1.3, 0.095), Vector3(0, 1.2, 0.093)],
			_perfil_extremos_redondos(0.012), 12, 0.005, Vector2(1.5, 0.45)), hueso)

	var pelvis := func(p: Vector3) -> float:
		var d := 1.0e9
		for lado in [1.0, -1.0]:
			var c := Vector3(0.088 * lado, 0.965, -0.012)
			var q := Basis(Vector3.UP, deg_to_rad(38.0 * lado)) * (p - c)
			d = _smin(d, _sd_elipsoide(q, Vector3.ZERO, Vector3(0.056, 0.053, 0.012)), 0.02)   # ala ilíaca
			d = _smin(d, _sd_esfera(p, Vector3(0.075 * lado, 0.89, 0.004), 0.03), 0.02)          # acetábulo
		var anillo := Vector2(Vector2(p.x / 1.25, p.z - 0.01).length() - 0.06, (p.y - 0.875) * 1.3)
		d = _smin(d, anillo.length() - 0.014, 0.02)                                              # anillo pélvico
		d = _smin(d, _sd_elipsoide(p, Vector3(0, 0.93, -0.06), Vector3(0.036, 0.062, 0.02)), 0.02)   # sacro
		for lado in [1.0, -1.0]:
			d = maxf(d, -_sd_esfera(p, Vector3(0.042 * lado, 0.85, 0.035), 0.022))   # agujero obturador
		return d
	_organo(s, "Pelvis", _malla_sdf(pelvis, Vector3(-0.17, 0.8, -0.1), Vector3(0.17, 1.04, 0.09), 0.005), hueso)

	for lado in [1.0, -1.0]:
		var sufijo := "Izq" if lado > 0 else "Der"
		_organo(s, "Humero" + sufijo, _malla_combinada([
				_malla_tubo([Vector3(0.192 * lado, 1.375, -0.012), Vector3(0.214 * lado, 1.25, -0.016),
						Vector3(0.236 * lado, 1.118, -0.02)], _perfil_hueso(0.0085, 0.019), 12, 0.005),
				_malla_esfera(Vector3(0.186 * lado, 1.387, -0.01), 0.02)]), hueso)
		_organo(s, "Femur" + sufijo, _malla_combinada([
				_malla_tubo([Vector3(0.112 * lado, 0.875, 0.0), Vector3(0.106 * lado, 0.7, 0.008),
						Vector3(0.1 * lado, 0.505, 0.01)], _perfil_hueso(0.012, 0.026), 14, 0.006),
				_malla_tubo([Vector3(0.112 * lado, 0.872, 0.0), Vector3(0.078 * lado, 0.888, 0.004)],
						_perfil_constante(0.011), 10, 0.005),
				_malla_esfera(Vector3(0.074 * lado, 0.89, 0.004), 0.022)]), hueso)
		_organo(s, "Tibia" + sufijo, _malla_combinada([
				_malla_tubo([Vector3(0.097 * lado, 0.47, 0.012), Vector3(0.1 * lado, 0.28, 0.008),
						Vector3(0.1 * lado, 0.085, -0.004)], _perfil_hueso(0.0105, 0.024), 12, 0.006),
				_malla_tubo([Vector3(0.122 * lado, 0.45, -0.006), Vector3(0.124 * lado, 0.27, -0.01),
						Vector3(0.12 * lado, 0.085, -0.012)], _perfil_hueso(0.0045, 0.009), 8, 0.008)]), hueso)   # peroné

	_registrar_relieve = true    # ...pero los superficiales (clavículas, antebrazo, mano, pie) sí
	_bilateral(s, "Claviculas", hueso, func(l: float) -> ArrayMesh: return _malla_tubo(
			[Vector3(0.016 * l, 1.425, 0.065), Vector3(0.09 * l, 1.432, 0.05), Vector3(0.168 * l, 1.432, 0.002)],
			_perfil_hueso(0.0055, 0.008), 10, 0.004))
	_bilateral(s, "Escapulas", hueso, func(l: float) -> ArrayMesh:
		var c := Vector3(0.1 * l, 1.33, -0.074)
		var giro := Basis(Vector3.UP, deg_to_rad(-22.0 * l))
		return _malla_sdf(func(p: Vector3) -> float:
			var q := giro * (p - c)
			var d := _sd_elipsoide(q, Vector3(0, 0.0, 0), Vector3(0.045, 0.062, 0.007))
			d = maxf(d, q.y - 0.045)   # borde superior recto
			d = _smin(d, _sd_capsula(q, Vector3(-0.04 * l, 0.03, -0.006), Vector3(0.05 * l, 0.045, -0.006), 0.006, 0.008), 0.006)   # espina
			return d, c - Vector3(0.07, 0.08, 0.04), c + Vector3(0.07, 0.08, 0.04), 0.003))
	_bilateral(s, "RadioCubito", hueso, func(l: float) -> ArrayMesh: return _malla_combinada([
			_malla_tubo([Vector3(0.238 * l, 1.105, -0.008), Vector3(0.245 * l, 0.98, 0.002), Vector3(0.25 * l, 0.862, 0.008)],
					_perfil_hueso(0.0055, 0.011), 10, 0.005),   # radio
			_malla_tubo([Vector3(0.23 * l, 1.12, -0.03), Vector3(0.24 * l, 0.98, -0.022), Vector3(0.245 * l, 0.862, -0.012)],
					_perfil_hueso(0.005, 0.01), 10, 0.005)]))   # cúbito
	_bilateral(s, "HuesosMano", hueso, func(l: float) -> ArrayMesh:
		var dedos := [_malla_sdf(func(p: Vector3) -> float: return _sd_elipsoide(p, Vector3(0.251 * l, 0.838, 0.0),
				Vector3(0.011, 0.014, 0.024)), Vector3(0.22 * l - 0.03, 0.81, -0.04), Vector3(0.22 * l + 0.06, 0.87, 0.04), 0.003)]
		for z in [-0.024, -0.008, 0.008, 0.024]:
			dedos.append(_malla_tubo([Vector3(0.251 * l, 0.83, z * 0.7), Vector3(0.254 * l, 0.775, z), Vector3(0.257 * l, 0.72 + absf(z), z)],
					_perfil_hueso(0.0032, 0.0048), 6, 0.003))
		dedos.append(_malla_tubo([Vector3(0.25 * l, 0.84, 0.018), Vector3(0.253 * l, 0.805, 0.04), Vector3(0.255 * l, 0.78, 0.05)],
				_perfil_hueso(0.0036, 0.0052), 6, 0.003))   # pulgar
		return _malla_combinada(dedos))
	_bilateral(s, "HuesosPie", hueso, func(l: float) -> ArrayMesh:
		var partes := [_malla_esfera(Vector3(0.1 * l, 0.034, -0.032), 0.018), _malla_esfera(Vector3(0.1 * l, 0.058, -0.012), 0.014)]
		for k in 5:
			var x := 0.1 * l + (k - 2) * 0.011 * l
			partes.append(_malla_tubo([Vector3(0.1 * l, 0.04, -0.005), Vector3(x, 0.03, 0.06), Vector3(x + 0.004 * l, 0.018, 0.122 - absf(k - 1) * 0.008)],
					_perfil_hueso(0.0035, 0.0055), 6, 0.004))
		return _malla_combinada(partes))


# --- Circulatorio ----------------------------------------------------------------------------

func _construir_circulatorio() -> void:
	var s := _sistema("Circulatorio")
	var corazon := func(p: Vector3) -> float:
		var c := Vector3(0.02, 1.22, 0.035)
		var q := Basis(Vector3.FORWARD, deg_to_rad(-38.0)) * (p - c)   # punta hacia abajo y a la izquierda
		var d := _sd_elipsoide(q, Vector3(0, -0.008, 0), Vector3(0.046, 0.058, 0.04))      # ventrículos
		d = _smin(d, _sd_elipsoide(q, Vector3(0, -0.055, 0.003), Vector3(0.022, 0.025, 0.02)), 0.02)   # punta
		d = _smin(d, _sd_elipsoide(p, c + Vector3(-0.032, 0.03, -0.004), Vector3(0.024, 0.024, 0.022)), 0.012)  # aurícula der.
		d = _smin(d, _sd_elipsoide(p, c + Vector3(0.022, 0.04, -0.012), Vector3(0.02, 0.018, 0.02)), 0.012)    # aurícula izq.
		# Surco interventricular
		d = maxf(d, -(_sd_capsula(q, Vector3(-0.004, 0.04, 0.042), Vector3(0.006, -0.07, 0.04), 0.0035, 0.002)))
		return d
	_organo(s, "Corazon", _malla_sdf(corazon, Vector3(-0.06, 1.13, -0.03), Vector3(0.1, 1.3, 0.1), 0.003),
			_material("corazon"))

	var arteria := _material("arteria")
	var aorta := [Vector3(0.008, 1.255, 0.03), Vector3(0.004, 1.32, 0.018), Vector3(-0.004, 1.345, -0.008),
			Vector3(0.01, 1.33, -0.032), Vector3(0.015, 1.22, -0.04), Vector3(0.012, 1.08, -0.038),
			Vector3(0.006, 0.97, -0.03), Vector3(0.0, 0.93, -0.022)]
	_curvas["aorta"] = aorta
	var ramas := [_malla_tubo(aorta, _perfil_lineal(0.012, 0.009), 14, 0.004)]
	for lado in [1.0, -1.0]:
		ramas.append(_malla_tubo([Vector3(0, 0.935, -0.022), Vector3(0.04 * lado, 0.885, -0.004),
				Vector3(0.072 * lado, 0.84, 0.01)], _perfil_lineal(0.0065, 0.0055), 10, 0.004))   # ilíacas
		ramas.append(_malla_tubo([Vector3(0.004 * lado, 1.34, -0.004), Vector3(0.018 * lado, 1.43, 0.006),
				Vector3(0.022 * lado, 1.52, 0.012)], _perfil_constante(0.0042), 8, 0.004))       # carótidas
	_organo(s, "Aorta", _malla_combinada(ramas), arteria)

	var vena := _material("vena")
	var venas := [
		_malla_tubo([Vector3(-0.026, 1.4, 0.0), Vector3(-0.024, 1.32, 0.008), Vector3(-0.022, 1.255, 0.022)],
				_perfil_constante(0.0095), 12, 0.004),   # cava superior
		_malla_tubo([Vector3(-0.02, 1.19, 0.012), Vector3(-0.026, 1.1, -0.018), Vector3(-0.024, 1.02, -0.03),
				Vector3(-0.01, 0.94, -0.026)], _perfil_constante(0.0105), 12, 0.004),   # cava inferior
	]
	for lado in [1.0, -1.0]:
		venas.append(_malla_tubo([Vector3(-0.01, 0.94, -0.026), Vector3(0.045 * lado - 0.005, 0.882, -0.01),
				Vector3(0.074 * lado, 0.838, 0.002)], _perfil_constante(0.007), 10, 0.004))    # ilíacas
		venas.append(_malla_tubo([Vector3(0.03 * lado, 1.52, 0.004), Vector3(0.028 * lado, 1.45, 0.0),
				Vector3(-0.026, 1.4, 0.0)], _perfil_constante(0.0048), 8, 0.004))              # yugulares
	_organo(s, "VenaCava", _malla_combinada(venas), vena)


# --- Respiratorio ----------------------------------------------------------------------------

func _construir_respiratorio() -> void:
	var s := _sistema("Respiratorio")
	var traquea := [Vector3(0, 1.525, 0.022), Vector3(0, 1.45, 0.012), Vector3(0, 1.365, 0.002)]
	_curvas["traquea"] = traquea
	var anillos := func(t: float) -> float:   # Anillos de cartílago
		return 0.0105 * (1.0 + 0.1 * sin(t * TAU * 16.0)) * _redondeo(t, 0.02)
	var partes := [_malla_tubo(traquea, anillos, 14, 0.002)]
	for lado in [1.0, -1.0]:
		var bronquio := [Vector3(0, 1.367, 0.002), Vector3(0.035 * lado, 1.335, 0.0), Vector3(0.06 * lado, 1.3, 0.0)]
		_curvas["bronquio" + ("Izq" if lado > 0 else "Der")] = bronquio
		partes.append(_malla_tubo(bronquio, _perfil_lineal(0.0075, 0.005), 10, 0.003))
	_organo(s, "Traquea", _malla_combinada(partes), _material("traquea"))

	var pulmon := _material("pulmon")
	for lado in [1.0, -1.0]:
		var c := Vector3(0.076 * lado, 1.258, 0.0)
		var sdf := func(p: Vector3) -> float:
			var d := _sd_elipsoide(p, c, Vector3(0.06, 0.125, 0.074))
			d = maxf(d, -_sd_esfera(p, Vector3(0.076 * lado, 0.99, 0.0), 0.165))         # base sobre el diafragma
			d = maxf(d, -_sd_elipsoide(p, Vector3(0, 1.24, 0.02), Vector3(0.035, 0.12, 0.06)))  # mediastino
			if lado > 0:
				d = maxf(d, -_sd_esfera(p, Vector3(0.025, 1.205, 0.045), 0.05))          # muesca cardiaca
			# Cisuras entre lóbulos (oblicua; el derecho además tiene la horizontal)
			var oblicua := absf((p.y - 1.22) + (p.z + 0.02) * 0.9) - 0.0016
			d = maxf(d, -maxf(oblicua, -(absf(p.x - c.x * 1.25) - 0.03)))
			if lado < 0:
				var horizontal := absf(p.y - 1.28) - 0.0016
				d = maxf(d, -maxf(horizontal, maxf(-(p.z + 0.0), -(absf(p.x - c.x * 1.25) - 0.03))))
			return d
		_organo(s, "Pulmon" + ("Izq" if lado > 0 else "Der"),
				_malla_sdf(sdf, c - Vector3(0.075, 0.14, 0.085), c + Vector3(0.075, 0.14, 0.085), 0.0044), pulmon)


# --- Digestivo -------------------------------------------------------------------------------

func _construir_digestivo() -> void:
	var s := _sistema("Digestivo")
	var esofago := [Vector3(0, 1.53, -0.008), Vector3(0, 1.45, -0.014), Vector3(0, 1.36, -0.02),
			Vector3(0.003, 1.25, -0.022), Vector3(0.012, 1.155, -0.018), Vector3(0.034, 1.108, -0.006)]
	_curvas["esofago"] = esofago
	_organo(s, "Esofago", _malla_tubo(esofago, _perfil_constante(0.0085), 12, 0.004), _material("esofago"))

	var estomago := [Vector3(0.034, 1.108, -0.006), Vector3(0.062, 1.127, 0.0), Vector3(0.085, 1.095, 0.014),
			Vector3(0.08, 1.052, 0.03), Vector3(0.052, 1.025, 0.04), Vector3(0.018, 1.028, 0.042),
			Vector3(-0.014, 1.036, 0.035)]
	_curvas["estomago"] = estomago
	var perfil_estomago := func(t: float) -> float:
		return (0.011 + 0.024 * sin(clampf(t / 0.85, 0.0, 1.0) * PI) + 0.006 * exp(-pow((t - 0.2) / 0.1, 2.0))) \
				* _redondeo(t, 0.03)
	_organo(s, "Estomago", _malla_tubo(estomago, perfil_estomago, 20, 0.003), _material("estomago"))

	var higado := func(p: Vector3) -> float:
		var d := _sd_elipsoide(p, Vector3(-0.042, 1.1, 0.018), Vector3(0.09, 0.056, 0.068))   # lóbulo derecho
		d = _smin(d, _sd_elipsoide(p, Vector3(0.035, 1.118, 0.03), Vector3(0.058, 0.026, 0.05)), 0.025)   # lóbulo izquierdo
		d = maxf(d, (1.045 + (p.x + 0.1) * 0.22) - p.y)   # cara inferior oblicua
		return d
	_organo(s, "Higado", _malla_sdf(higado, Vector3(-0.14, 1.03, -0.06), Vector3(0.1, 1.17, 0.1), 0.0038),
			_material("higado"))

	var delgado := _recorrido_intestino_delgado()
	_curvas["delgado"] = delgado
	_organo(s, "IntestinoDelgado", _malla_tubo(delgado, _perfil_extremos_redondos(0.0125), 12, 0.004),
			_material("intestino_delgado"))

	var grueso := [Vector3(-0.088, 0.882, 0.04), Vector3(-0.096, 0.95, 0.04), Vector3(-0.093, 1.0, 0.042),
			Vector3(-0.078, 1.025, 0.05), Vector3(-0.03, 1.006, 0.066), Vector3(0.03, 1.006, 0.066),
			Vector3(0.082, 1.03, 0.04), Vector3(0.1, 0.99, 0.03), Vector3(0.096, 0.925, 0.03),
			Vector3(0.068, 0.885, 0.04), Vector3(0.028, 0.872, 0.022), Vector3(0.002, 0.86, -0.022),
			Vector3(0.0, 0.81, -0.035)]
	_curvas["grueso"] = grueso
	var haustras := func(t: float) -> float:   # Abultamientos (haustras) del colon
		return 0.0185 * (1.0 + 0.13 * sin(t * TAU * 22.0)) * _redondeo(t, 0.015)
	_organo(s, "IntestinoGrueso", _malla_tubo(grueso, haustras, 14, 0.003), _material("intestino_grueso"))


## Recorrido del intestino delgado: duodeno en "C" y luego asas serpenteantes en varias filas.
func _recorrido_intestino_delgado() -> Array:
	var puntos := [Vector3(-0.014, 1.036, 0.035), Vector3(-0.042, 1.025, 0.02), Vector3(-0.046, 1.0, 0.016),
			Vector3(-0.02, 0.99, 0.024)]
	var filas := [0.985, 0.962, 0.94, 0.918, 0.898]
	for f in filas.size():
		var hacia_derecha := f % 2 == 0
		var z_base := 0.05 if f % 2 == 0 else 0.036
		for k in 8:
			var u := k / 7.0
			var x := lerpf(-0.064, 0.064, u if hacia_derecha else 1.0 - u)
			var y: float = filas[f] + 0.006 * sin(u * TAU * 2.0 + f)
			var z := z_base + 0.009 * cos(u * TAU * 1.5 + f * 0.7)
			puntos.append(Vector3(x, y, z))
	puntos.append(Vector3(-0.075, 0.892, 0.042))
	puntos.append(Vector3(-0.086, 0.895, 0.042))
	return puntos


# --- Nervioso --------------------------------------------------------------------------------

func _construir_nervioso() -> void:
	var s := _sistema("Nervioso")
	var cerebro := func(p: Vector3) -> float:
		var c := Vector3(0, 1.66, 0.0)
		var d := _sd_elipsoide(p, c, Vector3(0.062, 0.056, 0.079))
		d = maxf(d, -_sd_elipsoide(p, c + Vector3(0, -0.07, -0.01), Vector3(0.05, 0.035, 0.05)))   # base
		# Surcos: las líneas donde el ruido vale ~0 forman caminos sinuosos parecidos a circunvoluciones
		var n := _ruido.get_noise_3dv(p)
		d += 0.0032 * (1.0 - smoothstep(0.0, 0.16, absf(n)))
		# Cisura longitudinal entre los dos hemisferios
		if p.y > c.y - 0.035:
			d = maxf(d, -(absf(p.x) - 0.0022))
		return d
	_organo(s, "Cerebro", _malla_sdf(cerebro, Vector3(-0.075, 1.59, -0.09), Vector3(0.075, 1.73, 0.09), 0.003),
			_material("cerebro"))

	var cerebelo := func(p: Vector3) -> float:
		var c := Vector3(0, 1.604, -0.046)
		var d := _sd_elipsoide(p, c, Vector3(0.047, 0.027, 0.031))
		d += 0.0012 * (1.0 - smoothstep(0.0, 0.3, absf(sin((p.y - c.y + (p.z - c.z) * 0.4) * 520.0))))   # folias
		if p.z < c.z:
			d = maxf(d, -(absf(p.x) - 0.002))   # vermis (surco central posterior)
		return d
	_organo(s, "Cerebelo", _malla_sdf(cerebelo, Vector3(-0.055, 1.57, -0.085), Vector3(0.055, 1.64, -0.01), 0.0024),
			_material("cerebelo"))

	var medula := [Vector3(0, 1.635, -0.012), Vector3(0, 1.595, -0.024)] + ESPINA.slice(1)
	_organo(s, "MedulaEspinal", _malla_tubo(medula, _perfil_lineal(0.0085, 0.004), 10, 0.004), _material("medula"))


## Columna: 24 vértebras (cuerpo + apófisis espinosa y transversas) a lo largo de la curva ESPINA.
func _malla_columna() -> ArrayMesh:
	var curva := _curva_suave(ESPINA, false)
	var largo := curva.get_baked_length()
	var partes := []
	for i in 24:
		var t := (i + 0.5) / 24.0
		var centro := curva.sample_baked(t * largo, true)
		var adelante := curva.sample_baked(minf(largo, t * largo + 0.01), true)
		var tangente := (adelante - centro).normalized()
		var radio := lerpf(0.009, 0.019, t)
		var frente := Vector3.BACK.slide(tangente).normalized()   # +Z (anterior) perpendicular a la curva
		var cuerpo := centro + frente * (radio + 0.006)
		partes.append(_malla_tubo([cuerpo - tangente * 0.0055 * (1.0 + t), cuerpo + tangente * 0.0055 * (1.0 + t)],
				_perfil_extremos_redondos(radio), 12, 0.002))
		partes.append(_malla_tubo([centro - frente * 0.005, centro - frente * (0.026 + 0.01 * t) - tangente * 0.01],
				_perfil_lineal(0.004, 0.0028), 6, 0.004))   # apófisis espinosa
		for lado in [1.0, -1.0]:
			partes.append(_malla_tubo([centro + Vector3(0.006 * lado, 0, 0), centro + Vector3((0.02 + 0.012 * t) * lado, 0, -0.006)],
					_perfil_lineal(0.0035, 0.0025), 6, 0.004))   # apófisis transversas
	return _malla_combinada(partes)


# =============================================================================================
# MATERIALES
# =============================================================================================

## Materiales: color, rugosidad, brillo húmedo (clearcoat), borde (rim) y relieve fino con ruido.
const DEF_MATERIALES := {
	"piel": {"color": Color(0.8, 0.58, 0.47), "rugosidad": 0.55, "rim": 0.25, "relieve": [0.12, 18.0]},
	"musculo": {"color": Color(0.58, 0.13, 0.13), "rugosidad": 0.45, "brillo": 0.35, "rim": 0.2, "relieve": [0.35, 30.0]},
	"hueso": {"color": Color(0.9, 0.86, 0.76), "rugosidad": 0.72, "rim": 0.1, "relieve": [0.25, 25.0]},
	"corazon": {"color": Color(0.55, 0.09, 0.1), "rugosidad": 0.35, "brillo": 0.6, "rim": 0.2, "relieve": [0.3, 25.0]},
	"arteria": {"color": Color(0.74, 0.1, 0.12), "rugosidad": 0.35, "brillo": 0.5, "rim": 0.2},
	"vena": {"color": Color(0.22, 0.27, 0.6), "rugosidad": 0.35, "brillo": 0.5, "rim": 0.2},
	"traquea": {"color": Color(0.86, 0.74, 0.72), "rugosidad": 0.5, "brillo": 0.3, "rim": 0.15},
	"pulmon": {"color": Color(0.9, 0.58, 0.6), "rugosidad": 0.7, "brillo": 0.2, "rim": 0.3, "relieve": [0.45, 40.0]},
	"esofago": {"color": Color(0.8, 0.48, 0.43), "rugosidad": 0.45, "brillo": 0.4, "rim": 0.15},
	"estomago": {"color": Color(0.88, 0.58, 0.52), "rugosidad": 0.4, "brillo": 0.5, "rim": 0.2, "relieve": [0.25, 30.0]},
	"higado": {"color": Color(0.45, 0.13, 0.1), "rugosidad": 0.3, "brillo": 0.6, "rim": 0.2, "relieve": [0.15, 20.0]},
	"intestino_delgado": {"color": Color(0.92, 0.66, 0.6), "rugosidad": 0.4, "brillo": 0.5, "rim": 0.2},
	"intestino_grueso": {"color": Color(0.8, 0.56, 0.48), "rugosidad": 0.45, "brillo": 0.4, "rim": 0.2},
	"cerebro": {"color": Color(0.93, 0.74, 0.72), "rugosidad": 0.45, "brillo": 0.35, "rim": 0.2},
	"cerebelo": {"color": Color(0.86, 0.65, 0.64), "rugosidad": 0.45, "brillo": 0.35, "rim": 0.2},
	"medula": {"color": Color(0.95, 0.88, 0.72), "rugosidad": 0.5, "brillo": 0.3, "rim": 0.15},
	"ligamento": {"color": Color(0.85, 0.87, 0.8), "rugosidad": 0.4, "brillo": 0.4, "rim": 0.15},
	"rinon": {"color": Color(0.55, 0.18, 0.16), "rugosidad": 0.35, "brillo": 0.5, "rim": 0.2},
	"vejiga": {"color": Color(0.86, 0.62, 0.55), "rugosidad": 0.4, "brillo": 0.45, "rim": 0.2},
	"reproductor": {"color": Color(0.82, 0.55, 0.52), "rugosidad": 0.4, "brillo": 0.4, "rim": 0.2},
	"glandula": {"color": Color(0.78, 0.48, 0.32), "rugosidad": 0.45, "brillo": 0.4, "rim": 0.2},
	"linfatico": {"color": Color(0.55, 0.72, 0.36), "rugosidad": 0.45, "brillo": 0.4, "rim": 0.2},
	"bazo": {"color": Color(0.42, 0.14, 0.25), "rugosidad": 0.35, "brillo": 0.5, "rim": 0.2},
	"cabello": {"color": Color(0.17, 0.1, 0.06), "rugosidad": 0.68, "brillo": 0.08, "rim": 0.3, "relieve": [0.8, 140.0]},
	"grasa": {"color": Color(0.98, 0.86, 0.52, 0.32), "rugosidad": 0.45, "brillo": 0.3, "rim": 0.35, "transparente": true},
}


func _material(nombre: String) -> StandardMaterial3D:
	if _materiales.has(nombre):
		return _materiales[nombre]
	var d: Dictionary = DEF_MATERIALES[nombre]
	var m := StandardMaterial3D.new()
	m.resource_name = nombre
	m.albedo_color = d["color"]
	m.roughness = d.get("rugosidad", 0.5)
	if d.has("brillo"):
		m.clearcoat_enabled = true
		m.clearcoat = d["brillo"]
		m.clearcoat_roughness = 0.35
	if d.get("transparente", false):
		# Semitransparente (p. ej. la grasa de las mamas): deja ver lo que hay dentro
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_BACK
	if d.has("rim"):
		m.rim_enabled = true
		m.rim = d["rim"]
		m.rim_tint = 0.6
	if d.has("relieve"):
		# Relieve fino (poros, fibras) con ruido proyectado en 3 ejes: no necesita coordenadas UV
		var ruido := FastNoiseLite.new()
		ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		ruido.frequency = 0.05
		var textura := NoiseTexture2D.new()
		textura.noise = ruido
		textura.width = 256
		textura.height = 256
		textura.seamless = true
		textura.as_normal_map = true
		textura.bump_strength = 6.0
		m.normal_enabled = true
		m.normal_texture = textura
		m.normal_scale = d["relieve"][0]
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * d["relieve"][1]
	var ruta := "%s/materiales/%s.tres" % [CARPETA, nombre]
	ResourceSaver.save(m, ruta, ResourceSaver.FLAG_CHANGE_PATH)
	_materiales[nombre] = m
	return m


# =============================================================================================
# CONSTRUCCIÓN DE NODOS
# =============================================================================================

func _sistema(nombre: String) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	_raiz.add_child(n)
	n.owner = _raiz
	return n


## Órgano bilateral (p. ej. "Deltoides") con una parte por lado: <Nombre>Izq y <Nombre>Der.
func _bilateral(padre: Node3D, nombre: String, material: Material, crear: Callable) -> void:
	var grupo := _compuesto(padre, nombre)
	for lado in [1.0, -1.0]:
		_parte(grupo, nombre + ("Izq" if lado > 0 else "Der"), crear.call(lado), material)


func _compuesto(padre: Node3D, nombre: String) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	padre.add_child(n)
	n.owner = _raiz
	return n


## Órgano de una sola malla. La malla se recentra para que el origen quede en su centro
## (necesario para el latido, la respiración y la animación de capas).
func _organo(padre: Node3D, nombre: String, malla: ArrayMesh, material: Material) -> MeshInstance3D:
	return _parte(padre, nombre, malla, material)


func _parte(padre: Node3D, nombre: String, malla: ArrayMesh, material: Material) -> MeshInstance3D:
	var centro := malla.get_aabb().get_center()
	var global_padre := Vector3.ZERO
	var n: Node = padre
	while n is Node3D:
		global_padre += (n as Node3D).position
		n = n.get_parent()
	var recentrada := _con_lods(_trasladar(malla, -centro), material, nombre)
	var ruta := "%s/%s.res" % [CARPETA, _ruta_nodo(padre) + nombre]
	ResourceSaver.save(recentrada, ruta, ResourceSaver.FLAG_COMPRESS)
	recentrada = ResourceLoader.load(ruta, "", ResourceLoader.CACHE_MODE_REPLACE)   # referenciar, no incrustar
	var mi := MeshInstance3D.new()
	mi.name = nombre
	mi.mesh = recentrada
	# Solo las capas grandes proyectan sombra; los órganos internos no (ahorra GPU)
	var sistema := _ruta_nodo(padre).get_slice("_", 0)
	if not sistema in ["Piel", "Muscular", "Oseo"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = centro - global_padre
	padre.add_child(mi)
	mi.owner = _raiz
	var tris := recentrada.surface_get_array_index_len(0) / 3
	_triangulos_total += tris
	print("  %-28s %7d triángulos" % [_ruta_nodo(padre) + nombre, tris])
	return mi


func _ruta_nodo(nodo: Node) -> String:
	var partes := []
	while nodo != null and nodo != _raiz:
		partes.push_front(String(nodo.name))
		nodo = nodo.get_parent()
	return "_".join(partes) + "_" if not partes.is_empty() else ""


# =============================================================================================
# GEOMETRÍA: SDF + SURFACE NETS
# =============================================================================================

## Malla de la superficie sdf(p) = 0 dentro de la caja [minimo, maximo], con celdas de "celda" m.
## Surface nets: un vértice por celda que cruza la superficie (promedio de los cruces en sus
## aristas) y un cuadrilátero por cada arista de la rejilla que cruza la superficie.
func _malla_sdf(sdf: Callable, minimo: Vector3, maximo: Vector3, celda: float) -> ArrayMesh:
	var nx := int(ceil((maximo.x - minimo.x) / celda)) + 1
	var ny := int(ceil((maximo.y - minimo.y) / celda)) + 1
	var nz := int(ceil((maximo.z - minimo.z) / celda)) + 1
	var valores := PackedFloat32Array()
	valores.resize(nx * ny * nz)
	for k in nz:
		for j in ny:
			for i in nx:
				valores[i + nx * (j + ny * k)] = sdf.call(minimo + Vector3(i, j, k) * celda)

	var cx := nx - 1
	var cy := ny - 1
	var indice_celda := PackedInt32Array()
	indice_celda.resize(cx * cy * (nz - 1))
	indice_celda.fill(-1)
	var vertices := PackedVector3Array()
	var esquinas := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
			Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var aristas := []
	for a in 8:
		for b in [1, 2, 4]:
			if not (a & b):
				aristas.append([a, a | b])
	var v := PackedFloat32Array()
	v.resize(8)
	for k in nz - 1:
		for j in cy:
			for i in cx:
				var signo := 0
				for c in 8:
					var e: Vector3i = esquinas[c]
					v[c] = valores[(i + e.x) + nx * ((j + e.y) + ny * (k + e.z))]
					if v[c] < 0.0:
						signo |= 1 << c
				if signo == 0 or signo == 255:
					continue
				var suma := Vector3.ZERO
				var cuenta := 0
				for ar in aristas:
					var va: float = v[ar[0]]
					var vb: float = v[ar[1]]
					if (va < 0.0) != (vb < 0.0):
						var t := va / (va - vb)
						var ea: Vector3i = esquinas[ar[0]]
						var eb: Vector3i = esquinas[ar[1]]
						suma += Vector3(ea).lerp(Vector3(eb), t)
						cuenta += 1
				indice_celda[i + cx * (j + cy * k)] = vertices.size()
				vertices.append(minimo + (Vector3(i, j, k) + suma / cuenta) * celda)

	# Normales suaves a partir del gradiente del campo
	var normales := PackedVector3Array()
	normales.resize(vertices.size())
	var h := celda * 0.5
	for n in vertices.size():
		var p := vertices[n]
		normales[n] = Vector3(
				sdf.call(p + Vector3(h, 0, 0)) - sdf.call(p - Vector3(h, 0, 0)),
				sdf.call(p + Vector3(0, h, 0)) - sdf.call(p - Vector3(0, h, 0)),
				sdf.call(p + Vector3(0, 0, h)) - sdf.call(p - Vector3(0, 0, h))).normalized()

	var indices := PackedInt32Array()
	var celda_en := func(i: int, j: int, k: int) -> int:
		return indice_celda[i + cx * (j + cy * k)]
	for k in nz:
		for j in ny:
			for i in nx:
				var s0 := valores[i + nx * (j + ny * k)] < 0.0
				# Arista en X: celdas (i, j-1..j, k-1..k)
				if i < nx - 1 and j > 0 and k > 0 and j < ny - 1 and k < nz - 1:
					if s0 != (valores[(i + 1) + nx * (j + ny * k)] < 0.0):
						_quad(indices, vertices, normales, celda_en.call(i, j - 1, k - 1), celda_en.call(i, j, k - 1),
								celda_en.call(i, j, k), celda_en.call(i, j - 1, k))
				if j < ny - 1 and i > 0 and k > 0 and i < nx - 1 and k < nz - 1:
					if s0 != (valores[i + nx * ((j + 1) + ny * k)] < 0.0):
						_quad(indices, vertices, normales, celda_en.call(i - 1, j, k - 1), celda_en.call(i, j, k - 1),
								celda_en.call(i, j, k), celda_en.call(i - 1, j, k))
				if k < nz - 1 and i > 0 and j > 0 and i < nx - 1 and j < ny - 1:
					if s0 != (valores[i + nx * (j + ny * (k + 1))] < 0.0):
						_quad(indices, vertices, normales, celda_en.call(i - 1, j - 1, k), celda_en.call(i, j - 1, k),
								celda_en.call(i, j, k), celda_en.call(i - 1, j, k))
	return _malla_desde_arrays(vertices, normales, indices)


## Agrega un cuadrilátero (dos triángulos) con el orden de vértices correcto para que su cara
## frontal mire hacia afuera. Godot considera frontales los triángulos en sentido horario.
func _quad(indices: PackedInt32Array, vertices: PackedVector3Array, normales: PackedVector3Array,
		a: int, b: int, c: int, d: int) -> void:
	if a < 0 or b < 0 or c < 0 or d < 0:
		return
	var normal_cara := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	var afuera := normales[a] + normales[b] + normales[c] + normales[d]
	if normal_cara.dot(afuera) > 0.0:
		indices.append_array([a, c, b, a, d, c])
	else:
		indices.append_array([a, b, c, a, c, d])


func _malla_desde_arrays(vertices: PackedVector3Array, normales: PackedVector3Array,
		indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_INDEX] = indices
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return malla


# --- Funciones de distancia ------------------------------------------------------------------

func _sd_esfera(p: Vector3, c: Vector3, r: float) -> float:
	return (p - c).length() - r


## Elipsoide (aproximación de Inigo Quilez, buena cerca de la superficie)
func _sd_elipsoide(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := p - c
	var k0 := (q / r).length()
	var k1 := (q / (r * r)).length()
	return k0 * (k0 - 1.0) / k1 if k1 > 0.0 else -minf(r.x, minf(r.y, r.z))


## Cápsula con radios distintos en cada extremo (cono redondeado aproximado)
func _sd_capsula(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length() - lerpf(ra, rb, t)


func _sd_caja_redondeada(p: Vector3, medio: Vector3, r: float) -> float:
	var q := p.abs() - medio
	return Vector3(maxf(q.x, 0), maxf(q.y, 0), maxf(q.z, 0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r


## Unión suave: funde dos formas con un "filete" de tamaño k
func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


# =============================================================================================
# GEOMETRÍA: TUBOS A LO LARGO DE CURVAS
# =============================================================================================

## Tubo que sigue una curva suave por los puntos dados. perfil(t) da el radio en t ∈ [0, 1].
## seccion escala la sección transversal (p. ej. para un esternón plano).
func _malla_tubo(puntos: Array, perfil: Callable, lados: int, paso: float, seccion := Vector2.ONE) -> ArrayMesh:
	var curva := _curva_suave(puntos, false)
	var largo := curva.get_baked_length()
	if _registrar_relieve:
		# Aproximación por cápsulas cortas a lo largo de la curva, con el radio del perfil
		var muestras := 8
		var escala := maxf(seccion.x, seccion.y)
		for m in muestras:
			var t0 := float(m) / muestras
			var t1 := float(m + 1) / muestras
			_relieve.append(["c", curva.sample_baked(t0 * largo, true), curva.sample_baked(t1 * largo, true),
					maxf(perfil.call(maxf(t0, 0.05)), 0.002) * escala + INFLADO_RELIEVE,
					maxf(perfil.call(minf(t1, 0.95)), 0.002) * escala + INFLADO_RELIEVE])
	var anillos := maxi(3, int(ceil(largo / paso)) + 1)
	var vertices := PackedVector3Array()
	var normales := PackedVector3Array()
	var indices := PackedInt32Array()
	var tangente_ini := (curva.sample_baked(minf(largo, 0.002), true) - curva.sample_baked(0.0, true)).normalized()
	var n := Vector3.RIGHT.slide(tangente_ini)
	if n.length() < 0.1:
		n = Vector3.BACK.slide(tangente_ini)
	n = n.normalized()
	var centros := []
	for a in anillos:
		var t := float(a) / (anillos - 1)
		var d := t * largo
		var centro := curva.sample_baked(d, true)
		var tangente := (curva.sample_baked(minf(largo, d + 0.002), true) - curva.sample_baked(maxf(0.0, d - 0.002), true)).normalized()
		n = n.slide(tangente).normalized()   # Transporte paralelo: el marco no gira bruscamente
		var b := tangente.cross(n)
		var r: float = perfil.call(t)
		centros.append(centro)
		for l in lados:
			var ang := TAU * l / lados
			var dir_r := n * cos(ang) * seccion.x + b * sin(ang) * seccion.y
			vertices.append(centro + dir_r * r)
			normales.append((n * cos(ang) / seccion.x + b * sin(ang) / seccion.y).normalized())
	for a in anillos - 1:
		for l in lados:
			var l2 := (l + 1) % lados
			_quad(indices, vertices, normales, a * lados + l, (a + 1) * lados + l, (a + 1) * lados + l2, a * lados + l2)
	# Tapas (si el perfil no termina en cero)
	for extremo in [0, anillos - 1]:
		var centro_idx := vertices.size()
		var c: Vector3 = centros[extremo]
		var hacia_fuera: Vector3 = (c - centros[1 if extremo == 0 else anillos - 2]).normalized()
		vertices.append(c)
		normales.append(hacia_fuera)
		for l in lados:
			var i0: int = extremo * lados + l
			var i1: int = extremo * lados + (l + 1) % lados
			var normal_cara := (vertices[i0] - c).cross(vertices[i1] - c)
			if normal_cara.dot(hacia_fuera) > 0.0:
				indices.append_array([centro_idx, i1, i0])
			else:
				indices.append_array([centro_idx, i0, i1])
	return _malla_desde_arrays(vertices, normales, indices)


func _malla_esfera(centro: Vector3, radio: float) -> ArrayMesh:
	var e := SphereMesh.new()
	e.radius = radio
	e.height = radio * 2.0
	e.radial_segments = 16
	e.rings = 8
	var arrays := e.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += centro
	return _malla_desde_arrays(v, arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_INDEX])


## Une varias mallas en una sola superficie (una sola llamada de dibujo).
func _malla_combinada(mallas: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	for m in mallas:
		st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


## Genera niveles de detalle automáticos: de lejos Godot dibuja versiones con menos triángulos.
func _con_lods(malla: ArrayMesh, material: Material, nombre: String) -> ArrayMesh:
	var importador := ImporterMesh.new()
	importador.add_surface(Mesh.PRIMITIVE_TRIANGLES, malla.surface_get_arrays(0), [], {}, material, nombre)
	importador.generate_lods(25.0, 60.0, [])
	return importador.get_mesh()


func _trasladar(malla: ArrayMesh, desplazamiento: Vector3) -> ArrayMesh:
	var arrays := malla.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += desplazamiento
	arrays[Mesh.ARRAY_VERTEX] = v
	var nueva := ArrayMesh.new()
	nueva.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return nueva


## Curva suave tipo Catmull-Rom (tangentes a 1/4 de la distancia entre vecinos).
func _curva_suave(puntos: Array, cerrada: bool) -> Curve3D:
	var curva := Curve3D.new()
	curva.bake_interval = 0.002
	var p: Array[Vector3] = []
	for punto in puntos:
		p.append(punto)
	if cerrada:
		p.append(p[0])
	for i in p.size():
		var anterior := p[i - 1] if i > 0 else p[i]
		var siguiente := p[i + 1] if i < p.size() - 1 else p[i]
		var tangente := (siguiente - anterior) * 0.25
		curva.add_point(p[i], -tangente, tangente)
	return curva


# --- Perfiles de radio -------------------------------------------------------------------------

## Factor que redondea los extremos del tubo (0 en las puntas, 1 en el resto)
func _redondeo(t: float, borde: float) -> float:
	var x := minf(t, 1.0 - t) / borde
	return sqrt(maxf(0.0, 1.0 - pow(1.0 - minf(x, 1.0), 2.0))) if x < 1.0 else 1.0


func _perfil_constante(r: float) -> Callable:
	return func(t: float) -> float: return r * _redondeo(t, 0.02)


func _perfil_lineal(r0: float, r1: float) -> Callable:
	return func(t: float) -> float: return lerpf(r0, r1, t) * _redondeo(t, 0.02)


func _perfil_extremos_redondos(r: float) -> Callable:
	return func(t: float) -> float: return r * _redondeo(t, 0.15)


## Músculo: delgado en los tendones y grueso en el vientre muscular
func _perfil_fusiforme(r_max: float, r_tendon: float) -> Callable:
	return func(t: float) -> float:
		return lerpf(r_tendon, r_max, pow(sin(t * PI), 0.8)) * _redondeo(t, 0.03)


## Hueso largo: diáfisis delgada y epífisis anchas y redondeadas en los extremos
func _perfil_hueso(r_diafisis: float, r_epifisis: float) -> Callable:
	return func(t: float) -> float:
		var bulto := exp(-pow(t / 0.07, 2.0)) + exp(-pow((1.0 - t) / 0.07, 2.0))
		return lerpf(r_diafisis, r_epifisis, clampf(bulto, 0.0, 1.0)) * _redondeo(t, 0.025)


# =============================================================================================
# MANIQUÍ DE LA MINI VISTA
# =============================================================================================

## Partes suaves del maniquí (scripts/personajes/maniqui.gd). Cada malla está en el espacio local
## de su articulación: el origen es la articulación y el segmento cuelga hacia -Y.
func _generar_maniqui() -> void:
	var carpeta := CARPETA + "/maniqui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(carpeta))
	var piel := _material("piel")
	var partes := {
		"torso": [func(p: Vector3) -> float:
			var d := _sd_elipsoide(p, Vector3(0, 0.3, 0), Vector3(0.158, 0.17, 0.108))
			d = _smin(d, _sd_elipsoide(p, Vector3(0, 0.07, 0.004), Vector3(0.132, 0.14, 0.095)), 0.04)
			d = _smin(d, _sd_capsula(p, Vector3(-0.17, 0.42, -0.008), Vector3(0.17, 0.42, -0.008), 0.058, 0.058), 0.04)
			d = _smin(d, _sd_capsula(p, Vector3(0, 0.46, -0.01), Vector3(0, 0.57, -0.004), 0.05, 0.047), 0.03)
			d = _smin(d, _sd_elipsoide(p, Vector3(0, 0.67, -0.006), Vector3(0.079, 0.1, 0.098)), 0.03)
			d = _smin(d, _sd_elipsoide(p, Vector3(0, 0.595, 0.034), Vector3(0.06, 0.07, 0.065)), 0.03)
			return d, Vector3(-0.25, -0.1, -0.15), Vector3(0.25, 0.8, 0.16), 0.012],
		"pelvis": [func(p: Vector3) -> float:
			var d := _sd_elipsoide(p, Vector3(0, 0.0, -0.008), Vector3(0.16, 0.1, 0.1))
			return _smin(d, _sd_elipsoide(p, Vector3(0, -0.03, -0.055), Vector3(0.13, 0.07, 0.07)), 0.03),
			Vector3(-0.2, -0.13, -0.15), Vector3(0.2, 0.12, 0.12), 0.012],
		"brazo": [func(p: Vector3) -> float:
			return _sd_capsula(p, Vector3.ZERO, Vector3(0, -0.29, 0), 0.046, 0.036),
			Vector3(-0.06, -0.34, -0.06), Vector3(0.06, 0.06, 0.06), 0.008],
		"antebrazo": [func(p: Vector3) -> float:
			var d := _sd_capsula(p, Vector3.ZERO, Vector3(0, -0.26, 0), 0.036, 0.025)
			return _smin(d, _sd_elipsoide(p, Vector3(0, -0.33, 0.006), Vector3(0.02, 0.062, 0.04)), 0.02),
			Vector3(-0.05, -0.41, -0.06), Vector3(0.05, 0.05, 0.06), 0.007],
		"muslo": [func(p: Vector3) -> float:
			return _sd_capsula(p, Vector3.ZERO, Vector3(0, -0.44, 0.006), 0.078, 0.05),
			Vector3(-0.09, -0.5, -0.09), Vector3(0.09, 0.09, 0.09), 0.01],
		"pierna": [func(p: Vector3) -> float:
			var d := _sd_capsula(p, Vector3.ZERO, Vector3(0, -0.42, -0.012), 0.05, 0.031)
			d = _smin(d, _sd_elipsoide(p, Vector3(0, -0.15, -0.028), Vector3(0.045, 0.09, 0.045)), 0.03)
			return _smin(d, _sd_capsula(p, Vector3(0, -0.455, -0.03), Vector3(0.008, -0.46, 0.12), 0.034, 0.028), 0.03),
			Vector3(-0.07, -0.51, -0.09), Vector3(0.07, 0.07, 0.17), 0.008],
	}
	for nombre in partes:
		var def: Array = partes[nombre]
		var malla := _malla_sdf(def[0], def[1], def[2], def[3])
		var final := _con_lods(malla, piel, nombre)
		ResourceSaver.save(final, "%s/%s.res" % [carpeta, nombre], ResourceSaver.FLAG_COMPRESS)
	print("Maniquí generado en ", carpeta)


# =============================================================================================
# TRAYECTORIAS PARA data/visuales.json
# =============================================================================================

func _imprimir_trayectorias() -> void:
	var boca := [Vector3(0, 1.556, 0.09), Vector3(0, 1.54, 0.03)]
	var bolo := boca + _muestrear(_curvas["esofago"], 6) + _muestrear(_curvas["estomago"], 7) \
			+ _muestrear(_curvas["delgado"], 24) + _muestrear(_curvas["grueso"], 13)
	print("\nTRAYECTORIAS (copiar en data/visuales.json → trayectorias):")
	print('"bolo": ', _a_json(_sin_repetidos(bolo)))
	var circulacion: Array = [Vector3(0.02, 1.22, 0.035)] + _curvas["aorta"] + [Vector3(0.072, 0.84, 0.01),
			Vector3(0.1, 0.6, 0.02), Vector3(0.1, 0.25, 0.0), Vector3(0.1, 0.1, -0.005), Vector3(-0.1, 0.1, -0.005),
			Vector3(-0.1, 0.25, 0.0), Vector3(-0.1, 0.6, 0.02), Vector3(-0.074, 0.838, 0.002), Vector3(-0.01, 0.94, -0.026),
			Vector3(-0.024, 1.02, -0.03), Vector3(-0.026, 1.1, -0.018), Vector3(-0.02, 1.19, 0.012), Vector3(0.0, 1.235, 0.04),
			Vector3(0.012, 1.34, 0.0), Vector3(0.018, 1.43, 0.006), Vector3(0.022, 1.52, 0.012), Vector3(0.0, 1.6, 0.0),
			Vector3(-0.03, 1.52, 0.004), Vector3(-0.026, 1.4, 0.0), Vector3(-0.024, 1.32, 0.008), Vector3(-0.012, 1.25, 0.03)]
	print('"circulacion": ', _a_json(circulacion))
	for lado in ["Izq", "Der"]:
		var humo := [Vector3(0, 1.556, 0.11), Vector3(0, 1.54, 0.05)] + _muestrear(_curvas["traquea"], 3) \
				+ _muestrear(_curvas["bronquio" + lado], 3)
		var final_bronquio: Vector3 = _curvas["bronquio" + lado][-1]
		humo.append(final_bronquio + Vector3(signf(final_bronquio.x) * 0.012, -0.05, 0.005))
		print('"humo_%s": ' % lado.to_lower(), _a_json(humo))


func _sin_repetidos(puntos: Array) -> Array:
	var resultado := []
	for p in puntos:
		if resultado.is_empty() or (p - resultado[-1]).length() > 0.004:
			resultado.append(p)
	return resultado


func _muestrear(puntos: Array, cantidad: int) -> Array:
	var curva := _curva_suave(puntos, false)
	var largo := curva.get_baked_length()
	var resultado := []
	for i in cantidad:
		resultado.append(curva.sample_baked(largo * i / maxf(1, cantidad - 1), true))
	return resultado


func _a_json(puntos: Array) -> String:
	var textos := []
	for p in puntos:
		textos.append("[%.3f, %.3f, %.3f]" % [p.x, p.y, p.z])
	return "[" + ", ".join(textos) + "]"
