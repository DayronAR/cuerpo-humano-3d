class_name MaterialVivo
extends RefCounted
## Crea los materiales de shaders/organo_vivo.gdshader a partir de un material estándar.
## Hay dos variantes del shader: opaca (sin ALPHA, se dibuja como sólido) y transparente (para
## cuando las capas la desvanecen). El material se marca con la meta "organo_vivo".

const SHADER := preload("res://shaders/organo_vivo.gdshader")
static var _opaco: Shader


static func shader_opaco() -> Shader:
	if _opaco == null:
		_opaco = Shader.new()
		_opaco.code = SHADER.code.replace("\tALPHA = color.a * alfa;\n", "")
	return _opaco


static func shader_transparente() -> Shader:
	return SHADER


static func desde(base: BaseMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_opaco()
	m.set_shader_parameter("color", base.albedo_color)
	m.set_shader_parameter("rugosidad", base.roughness)
	m.set_shader_parameter("especular", base.metallic_specular)
	m.set_shader_parameter("borde", base.rim if base.rim_enabled else 0.0)
	m.set_shader_parameter("tinte_borde", base.rim_tint)
	m.set_shader_parameter("brillo", base.clearcoat if base.clearcoat_enabled else 0.0)
	m.set_meta("organo_vivo", true)
	return m


static func es_vivo(m: Material) -> bool:
	return m is ShaderMaterial and m.has_meta("organo_vivo")


## Copia transparente (para desvanecer la capa).
static func transparente(m: ShaderMaterial) -> ShaderMaterial:
	var copia: ShaderMaterial = m.duplicate()
	copia.shader = shader_transparente()
	copia.set_meta("organo_vivo", true)
	copia.set_meta("original", m)
	return copia
