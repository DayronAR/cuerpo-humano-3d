extends Node3D
## Maniquí de prueba para la mini vista, animado por código (sin AnimationPlayer).
##
## CONTRATO de cualquier personaje de la mini vista (lo cumple también personaje_mixamo.gd):
##     func fijar_actividad(actividad: String) -> void    # "reposo", "caminar", "trotar", "correr", "cansado"
##     func fijar_factor_tiempo(factor: float) -> void     # velocidad de la simulación (0 = pausa)
## Así la mini vista no sabe si anima primitivas o un modelo de Mixamo.

## Parámetros de la marcha por actividad: frecuencia (pasos/s), ángulos en grados, rebote (m)
const POSES := {
	"reposo":  {"frecuencia": 0.0, "cadera": 0.0,  "rodilla": 0.0,  "brazo": 0.0,  "codo": 10.0, "rebote": 0.0,   "inclinacion": 0.0,  "respiracion": 0.01, "ritmo_resp": 0.25},
	"caminar": {"frecuencia": 0.9, "cadera": 24.0, "rodilla": 35.0, "brazo": 22.0, "codo": 20.0, "rebote": 0.015, "inclinacion": 2.0,  "respiracion": 0.015, "ritmo_resp": 0.35},
	"trotar":  {"frecuencia": 1.3, "cadera": 34.0, "rodilla": 70.0, "brazo": 38.0, "codo": 75.0, "rebote": 0.035, "inclinacion": 6.0,  "respiracion": 0.02, "ritmo_resp": 0.5},
	"correr":  {"frecuencia": 1.6, "cadera": 45.0, "rodilla": 95.0, "brazo": 55.0, "codo": 90.0, "rebote": 0.055, "inclinacion": 11.0, "respiracion": 0.025, "ritmo_resp": 0.7},
	"cansado": {"frecuencia": 0.7, "cadera": 18.0, "rodilla": 30.0, "brazo": 10.0, "codo": 25.0, "rebote": 0.01,  "inclinacion": 22.0, "respiracion": 0.06, "ritmo_resp": 0.9},
}
const SUAVIZADO := 4.0

var _actual: Dictionary = POSES["reposo"].duplicate()
var _objetivo: Dictionary = POSES["reposo"]
var _factor_tiempo := 1.0
var _fase := 0.0
var _fase_resp := 0.0

var _pelvis: Node3D
var _torso: Node3D
var _caderas: Array[Node3D] = []
var _rodillas: Array[Node3D] = []
var _hombros: Array[Node3D] = []
var _codos: Array[Node3D] = []


func _ready() -> void:
	_construir()


func fijar_actividad(actividad: String) -> void:
	_objetivo = POSES.get(actividad, POSES["reposo"])


func fijar_factor_tiempo(factor: float) -> void:
	_factor_tiempo = factor


func _process(delta: float) -> void:
	var dt := delta * _factor_tiempo
	if dt <= 0.0:
		return
	var t := 1.0 - exp(-SUAVIZADO * dt)
	for clave in _actual:
		_actual[clave] = lerpf(_actual[clave], _objetivo[clave], t)
	_fase = fposmod(_fase + _actual["frecuencia"] * dt, 1.0)
	_fase_resp = fposmod(_fase_resp + _actual["ritmo_resp"] * dt, 1.0)

	var s := sin(TAU * _fase)
	for lado in 2:
		var signo := 1.0 if lado == 0 else -1.0
		var paso := s * signo
		_caderas[lado].rotation_degrees.x = -_actual["cadera"] * paso
		# La rodilla se dobla sobre todo cuando la pierna va hacia atrás
		_rodillas[lado].rotation_degrees.x = _actual["rodilla"] * clampf(0.5 + 0.5 * sin(TAU * _fase + signo * 1.2), 0.0, 1.0)
		_hombros[lado].rotation_degrees.x = _actual["brazo"] * paso
		_codos[lado].rotation_degrees.x = -_actual["codo"]
	_pelvis.position.y = 0.95 + _actual["rebote"] * absf(cos(TAU * _fase))
	_torso.rotation_degrees.x = -_actual["inclinacion"]
	var aire: float = 1.0 + _actual["respiracion"] * sin(TAU * _fase_resp)
	_torso.scale = Vector3(aire, 1.0, aire)


# --- Construcción con primitivas -----------------------------------------------------

## Mallas suaves generadas por tools/generar_cuerpo_prueba.gd (si no existen, se usan cápsulas)
const CARPETA_MALLAS := "res://models/prueba/maniqui/"


func _construir() -> void:
	var piel := _material(Color(0.8, 0.58, 0.47))
	var ropa := _material(Color(0.2, 0.32, 0.42))
	_pelvis = _pivote(self, Vector3(0, 0.95, 0))
	_parte(_pelvis, _malla("pelvis", _capsula(0.13, 0.26)), Vector3.ZERO, ropa)
	_torso = _pivote(_pelvis, Vector3(0, 0.05, 0))
	_parte(_torso, _malla("torso", _capsula(0.16, 0.5)), Vector3.ZERO, piel)
	for lado in 2:
		var x := 0.1 if lado == 0 else -0.1
		var cadera := _pivote(_pelvis, Vector3(x * 0.92, -0.02, 0))
		_parte(cadera, _malla("muslo", _capsula(0.06, 0.45)), Vector3.ZERO, ropa)
		var rodilla := _pivote(cadera, Vector3(0, -0.44, 0.006))
		_parte(rodilla, _malla("pierna", _capsula(0.05, 0.45)), Vector3.ZERO, piel)
		_caderas.append(cadera)
		_rodillas.append(rodilla)
		var hombro := _pivote(_torso, Vector3(x * 2.0, 0.415, -0.008))
		_parte(hombro, _malla("brazo", _capsula(0.045, 0.32)), Vector3.ZERO, piel)
		var codo := _pivote(hombro, Vector3(0, -0.29, 0))
		_parte(codo, _malla("antebrazo", _capsula(0.04, 0.3)), Vector3.ZERO, piel)
		_hombros.append(hombro)
		_codos.append(codo)


func _malla(nombre: String, alternativa: Mesh) -> Mesh:
	var ruta := CARPETA_MALLAS + nombre + ".res"
	return load(ruta) if ResourceLoader.exists(ruta) else alternativa


func _pivote(padre: Node3D, posicion: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = posicion
	padre.add_child(n)
	return n


func _parte(padre: Node3D, malla: Mesh, posicion: Vector3, material: Material, escala := Vector3.ONE,
		rotacion := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = malla
	mi.material_override = material
	mi.position = posicion
	mi.scale = escala
	mi.rotation_degrees = rotacion
	padre.add_child(mi)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _capsula(radio: float, alto: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radio
	m.height = alto
	m.radial_segments = 12
	m.rings = 4
	return m


func _esfera(radio: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radio
	m.height = radio * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


func _caja(tamano: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = tamano
	return m
