class_name MaterialVivo
extends RefCounted

const SHADER := preload("res://shaders/organo_vivo.gdshader")
static var _opaco: Shader


static func jlrl_shader_opaco() -> Shader:
	if _opaco == null:
		_opaco = Shader.new()
		_opaco.code = SHADER.code.replace("\tALPHA = color.a * alfa;\n", "")
	return _opaco


static func jlrl_shader_transparente() -> Shader:
	return SHADER


static func jlrl_desde(base: BaseMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = jlrl_shader_opaco()
	m.set_shader_parameter("color", base.albedo_color)
	m.set_shader_parameter("rugosidad", base.roughness)
	m.set_shader_parameter("especular", base.metallic_specular)
	m.set_shader_parameter("borde", base.rim if base.rim_enabled else 0.0)
	m.set_shader_parameter("tinte_borde", base.rim_tint)
	m.set_shader_parameter("brillo", base.clearcoat if base.clearcoat_enabled else 0.0)
	if base.albedo_texture is NoiseTexture2D and base.albedo_texture.color_ramp:
		var oscuro: Color = base.albedo_texture.color_ramp.get_color(0)
		m.set_shader_parameter("variacion", 1.0 - oscuro.r)
		m.set_shader_parameter("escala_variacion", base.uv1_scale.x)
	else:
		m.set_shader_parameter("variacion", 0.0)
	m.set_meta("organo_vivo", true)
	return m


static func jlrl_es_vivo(m: Material) -> bool:
	return m is ShaderMaterial and m.has_meta("organo_vivo")


static func jlrl_transparente(m: ShaderMaterial) -> ShaderMaterial:
	var copia: ShaderMaterial = m.duplicate()
	copia.shader = jlrl_shader_transparente()
	copia.set_meta("organo_vivo", true)
	copia.set_meta("original", m)
	return copia
