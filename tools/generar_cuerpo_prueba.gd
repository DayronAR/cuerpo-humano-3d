extends SceneTree
## Genera res://scenes/cuerpo_prueba.tscn: un cuerpo humano de prueba hecho con primitivas.
##
## Uso (desde la raíz del proyecto):
##     godot --headless --path . --script res://tools/generar_cuerpo_prueba.gd
##
## Convención OBLIGATORIA (la misma que deben cumplir los .glb de Blender):
##     Cuerpo (Node3D)
##     └── <Sistema> (Node3D)        Piel, Muscular, Oseo, Circulatorio, Respiratorio, Digestivo, Nervioso
##         └── <Organo>              MeshInstance3D, o Node3D con varias MeshInstance3D hijas (partes)
##
## Unidades en metros. Pies en y = 0, altura ~1.75 m. El cuerpo mira hacia +Z.
## El lado IZQUIERDO del paciente está en +X.
## Esta geometría es solo un andamio temporal: no son datos de la aplicación, por eso vive aquí
## y no en res://data/.

const SALIDA := "res://scenes/cuerpo_prueba.tscn"

var _raiz: Node3D
var _materiales := {}


func _init() -> void:
	_raiz = Node3D.new()
	_raiz.name = "Cuerpo"
	_construir_piel()
	_construir_muscular()
	_construir_oseo()
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
	print("Cuerpo de prueba generado en ", SALIDA)
	_raiz.free()
	quit()


# --- Sistemas ---------------------------------------------------------------

func _construir_piel() -> void:
	var s := _sistema("Piel")
	var piel := Color(0.86, 0.64, 0.52)
	var epidermis := _organo_compuesto(s, "Epidermis")
	_malla(epidermis, "Cabeza", _esfera(0.11), Vector3(0, 1.63, 0), piel, Vector3(0.9, 1.05, 1.0))
	_malla(epidermis, "Cuello", _capsula(0.055, 0.16), Vector3(0, 1.49, 0), piel)
	_malla(epidermis, "Torso", _capsula(0.17, 0.64), Vector3(0, 1.17, 0), piel, Vector3(1.1, 1.0, 0.72))
	_malla(epidermis, "BrazoIzq", _capsula(0.05, 0.64), Vector3(0.25, 1.13, 0), piel)
	_malla(epidermis, "BrazoDer", _capsula(0.05, 0.64), Vector3(-0.25, 1.13, 0), piel)
	_malla(epidermis, "PiernaIzq", _capsula(0.075, 0.9), Vector3(0.1, 0.45, 0), piel)
	_malla(epidermis, "PiernaDer", _capsula(0.075, 0.9), Vector3(-0.1, 0.45, 0), piel)


func _construir_muscular() -> void:
	var s := _sistema("Muscular")
	var musculo := Color(0.72, 0.2, 0.2)
	_malla(s, "Pectorales", _caja(Vector3(0.24, 0.12, 0.03)), Vector3(0, 1.29, 0.075), musculo)
	_malla(s, "Abdominales", _caja(Vector3(0.16, 0.22, 0.03)), Vector3(0, 1.08, 0.075), musculo)
	_malla(s, "BicepsIzq", _capsula(0.035, 0.24), Vector3(0.25, 1.28, 0.012), musculo)
	_malla(s, "BicepsDer", _capsula(0.035, 0.24), Vector3(-0.25, 1.28, 0.012), musculo)
	_malla(s, "CuadricepsIzq", _capsula(0.06, 0.4), Vector3(0.1, 0.66, 0.012), musculo)
	_malla(s, "CuadricepsDer", _capsula(0.06, 0.4), Vector3(-0.1, 0.66, 0.012), musculo)
	_malla(s, "GemeloIzq", _capsula(0.05, 0.28), Vector3(0.1, 0.26, -0.02), musculo)
	_malla(s, "GemeloDer", _capsula(0.05, 0.28), Vector3(-0.1, 0.26, -0.02), musculo)


func _construir_oseo() -> void:
	var s := _sistema("Oseo")
	var hueso := Color(0.92, 0.9, 0.82)
	_malla(s, "Craneo", _esfera(0.095), Vector3(0, 1.635, 0), hueso, Vector3(0.9, 1.05, 1.0))
	_malla(s, "ColumnaVertebral", _capsula(0.018, 0.56), Vector3(0, 1.17, -0.05), hueso)

	var caja := _organo_compuesto(s, "CajaToracica", Vector3(0, 1.24, 0))
	for i in 5:
		var y := -0.1 + i * 0.05
		_malla(caja, "Costilla%d" % (i + 1), _toro(0.14, 0.155), Vector3(0, y, 0), hueso, Vector3(1.0, 1.0, 0.55))
	_malla(caja, "Esternon", _caja(Vector3(0.03, 0.18, 0.015)), Vector3(0, 0, 0.08), hueso)

	_malla(s, "Pelvis", _toro(0.07, 0.11), Vector3(0, 0.92, 0), hueso, Vector3(1.2, 1.6, 0.75))
	_malla(s, "HumeroIzq", _capsula(0.018, 0.3), Vector3(0.25, 1.28, -0.01), hueso)
	_malla(s, "HumeroDer", _capsula(0.018, 0.3), Vector3(-0.25, 1.28, -0.01), hueso)
	_malla(s, "FemurIzq", _capsula(0.022, 0.44), Vector3(0.1, 0.66, 0), hueso)
	_malla(s, "FemurDer", _capsula(0.022, 0.44), Vector3(-0.1, 0.66, 0), hueso)
	_malla(s, "TibiaIzq", _capsula(0.018, 0.4), Vector3(0.1, 0.23, 0.01), hueso)
	_malla(s, "TibiaDer", _capsula(0.018, 0.4), Vector3(-0.1, 0.23, 0.01), hueso)


func _construir_circulatorio() -> void:
	var s := _sistema("Circulatorio")
	var corazon := _malla(s, "Corazon", _esfera(0.05), Vector3(0.025, 1.2, 0.03), Color(0.78, 0.1, 0.15),
			Vector3(1.0, 1.2, 0.9))
	corazon.rotation_degrees = Vector3(0, 0, 25)  # La punta del corazón apunta a la izquierda (+X)
	_malla(s, "Aorta", _cilindro(0.01, 0.34), Vector3(0.0, 1.06, -0.025), Color(0.85, 0.12, 0.15))
	_malla(s, "VenaCava", _cilindro(0.011, 0.36), Vector3(-0.03, 1.08, -0.015), Color(0.22, 0.32, 0.75))


func _construir_respiratorio() -> void:
	var s := _sistema("Respiratorio")
	var rosa := Color(0.93, 0.56, 0.6)
	_malla(s, "Traquea", _cilindro(0.011, 0.16), Vector3(0, 1.42, 0), Color(0.88, 0.7, 0.7))
	_malla(s, "PulmonIzq", _capsula(0.06, 0.22), Vector3(0.07, 1.25, 0), rosa)
	_malla(s, "PulmonDer", _capsula(0.062, 0.23), Vector3(-0.07, 1.25, 0), rosa)


func _construir_digestivo() -> void:
	var s := _sistema("Digestivo")
	_malla(s, "Esofago", _cilindro(0.009, 0.3), Vector3(0, 1.27, -0.03), Color(0.85, 0.55, 0.45))
	_malla(s, "Estomago", _esfera(0.055), Vector3(0.055, 1.06, 0.02), Color(0.88, 0.6, 0.5), Vector3(1.2, 0.9, 0.8))
	_malla(s, "Higado", _esfera(0.07), Vector3(-0.05, 1.09, 0.02), Color(0.55, 0.2, 0.18), Vector3(1.4, 0.6, 0.9))
	_malla(s, "IntestinoDelgado", _esfera(0.08), Vector3(0, 0.96, 0.03), Color(0.93, 0.68, 0.6),
			Vector3(1.1, 0.75, 0.55))
	var grueso := _malla(s, "IntestinoGrueso", _toro(0.07, 0.088), Vector3(0, 0.96, 0.03), Color(0.8, 0.52, 0.42),
			Vector3(1.15, 1.0, 1.0))
	grueso.rotation_degrees = Vector3(90, 0, 0)  # El anillo queda de frente, enmarcando al intestino delgado


func _construir_nervioso() -> void:
	var s := _sistema("Nervioso")
	_malla(s, "Cerebro", _esfera(0.08), Vector3(0, 1.655, 0.005), Color(0.93, 0.72, 0.72), Vector3(0.9, 0.8, 1.05))
	_malla(s, "Cerebelo", _esfera(0.03), Vector3(0, 1.6, -0.045), Color(0.85, 0.62, 0.62), Vector3(1.2, 0.8, 1.0))
	_malla(s, "MedulaEspinal", _cilindro(0.008, 0.62), Vector3(0, 1.27, -0.05), Color(0.95, 0.85, 0.55))


# --- Ayudantes de construcción --------------------------------------------

func _sistema(nombre: String) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	_raiz.add_child(n)
	n.owner = _raiz
	return n


func _organo_compuesto(padre: Node3D, nombre: String, posicion := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	n.position = posicion
	padre.add_child(n)
	n.owner = _raiz
	return n


func _malla(padre: Node3D, nombre: String, malla: PrimitiveMesh, posicion: Vector3, color: Color,
		escala := Vector3.ONE) -> MeshInstance3D:
	malla.material = _material(color)
	var mi := MeshInstance3D.new()
	mi.name = nombre
	mi.mesh = malla
	mi.position = posicion
	mi.scale = escala
	padre.add_child(mi)
	mi.owner = _raiz
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var clave := color.to_html()
	if not _materiales.has(clave):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.6
		_materiales[clave] = m
	return _materiales[clave]


func _esfera(radio: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radio
	m.height = radio * 2.0
	m.radial_segments = 32
	m.rings = 16
	return m


func _capsula(radio: float, altura: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radio
	m.height = altura
	m.radial_segments = 24
	m.rings = 6
	return m


func _cilindro(radio: float, altura: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radio
	m.bottom_radius = radio
	m.height = altura
	m.radial_segments = 16
	m.rings = 1
	return m


func _caja(tamano: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = tamano
	return m


func _toro(radio_interno: float, radio_externo: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = radio_interno
	m.outer_radius = radio_externo
	m.rings = 32
	m.ring_segments = 12
	return m
