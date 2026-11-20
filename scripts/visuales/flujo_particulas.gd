class_name FlujoParticulas
extends MultiMeshInstance3D
## Partículas que recorren una trayectoria (Curve3D): humo hacia los pulmones, glóbulos rojos.
## Usa un MultiMesh (una sola llamada de dibujo para todas las partículas): barato en GPU integradas.
## Se dibujan sin prueba de profundidad para verse aunque estén dentro de un órgano.

var curva := Curve3D.new()
var cerrada := false            ## true: circuito cerrado (circulación); false: de inicio a fin (humo)
var velocidad := 0.2            ## Metros por segundo
var factor_tiempo := 1.0        ## Velocidad de la simulación (0 = pausa)
var emitiendo := false          ## Las partículas aparecen o se desvanecen suavemente
var crecer := false             ## true: la partícula crece a lo largo del recorrido (humo que se expande)

var _tamano := 0.01
var _color := Color.WHITE
var _intensidad := 0.0
var _largo := 1.0
var _distancias := PackedFloat32Array()
var _desvios := PackedVector3Array()


func configurar(puntos: Array, es_cerrada: bool, cantidad: int, tamano: float, color: Color, dispersion: float) -> void:
	cerrada = es_cerrada
	_tamano = tamano
	_color = color
	_construir_curva(puntos)
	_largo = maxf(curva.get_baked_length(), 0.001)

	var esfera := SphereMesh.new()
	esfera.radius = 0.5
	esfera.height = 1.0
	esfera.radial_segments = 8
	esfera.rings = 4
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.roughness = 0.8
	esfera.material = material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = esfera
	multimesh.instance_count = cantidad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var azar := RandomNumberGenerator.new()
	azar.seed = 1234
	_distancias.resize(cantidad)
	_desvios.resize(cantidad)
	for i in cantidad:
		_distancias[i] = _largo * float(i) / cantidad
		_desvios[i] = Vector3(azar.randf_range(-1, 1), azar.randf_range(-1, 1), azar.randf_range(-1, 1)) * dispersion
	visible = false


func _process(delta: float) -> void:
	_intensidad = move_toward(_intensidad, 1.0 if emitiendo else 0.0, delta * 1.5)
	visible = _intensidad > 0.0
	if not visible:
		return
	var avance := velocidad * delta * factor_tiempo
	for i in _distancias.size():
		var d := fposmod(_distancias[i] + avance, _largo)
		_distancias[i] = d
		var fraccion := d / _largo
		var desvanecer := 1.0
		var escala := _tamano
		if not cerrada:
			desvanecer = smoothstep(0.0, 0.08, fraccion) * (1.0 - smoothstep(0.75, 1.0, fraccion))
		if crecer:
			escala *= 0.6 + 1.2 * fraccion
		var posicion := curva.sample_baked(d, true) + _desvios[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * escala), posicion))
		var c := _color
		c.a *= _intensidad * desvanecer
		multimesh.set_instance_color(i, c)


## Curva suave (tipo Catmull-Rom) a partir de una lista de puntos [x, y, z].
func _construir_curva(puntos: Array) -> void:
	curva.clear_points()
	curva.bake_interval = 0.01
	var p: Array[Vector3] = []
	for punto in puntos:
		p.append(Vector3(punto[0], punto[1], punto[2]))
	if cerrada and p.size() > 1:
		p.append(p[0])
	for i in p.size():
		var anterior := p[i - 1] if i > 0 else (p[p.size() - 2] if cerrada else p[i])
		var siguiente := p[i + 1] if i < p.size() - 1 else (p[1] if cerrada else p[i])
		var tangente := (siguiente - anterior) * 0.25
		curva.add_point(p[i], -tangente, tangente)
