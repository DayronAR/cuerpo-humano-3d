shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 color : source_color = vec4(0.8, 0.6, 0.5, 1.0);
uniform float rugosidad : hint_range(0.0, 1.0) = 0.5;
uniform float especular : hint_range(0.0, 1.0) = 0.5;
uniform float borde : hint_range(0.0, 1.0) = 0.0;
uniform float tinte_borde : hint_range(0.0, 1.0) = 0.5;
uniform float brillo : hint_range(0.0, 1.0) = 0.0;
uniform vec4 plano = vec4(0.0, 0.0, 1.0, 1000.0);
uniform float alfa : hint_range(0.0, 1.0) = 1.0;
global uniform float peristaltismo_onda;
global uniform float peristaltismo_fase;
uniform float longitud = 0.045;
uniform vec3 direccion = vec3(0.0, -1.0, 0.2);
uniform float variacion = 0.15;
uniform float escala_variacion = 25.0;

varying vec3 posicion_mundo;
varying vec3 posicion_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float ruido(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 p = VERTEX;
	posicion_local = VERTEX;
	float a = sin(dot(p, normalize(direccion)) * 6.2832 / longitud - peristaltismo_fase);
	float b = sin(dot(p, normalize(vec3(direccion.z, 0.4, -direccion.x))) * 6.2832 / (longitud * 1.7) - peristaltismo_fase * 0.7);
	float contraccion = max(0.0, a) * 0.7 + max(0.0, b) * 0.3;
	VERTEX -= NORMAL * peristaltismo_onda * contraccion;
	posicion_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(posicion_mundo, plano.xyz) > plano.w) {
		discard;
	}
	vec3 q = posicion_local * escala_variacion;
	float n = ruido(q) * 0.6 + ruido(q * 2.3) * 0.4;
	ALBEDO = color.rgb * mix(vec3(1.0 - variacion, 1.0 - variacion * 0.85, 1.0 - variacion * 0.85), vec3(1.0), n);
	ROUGHNESS = rugosidad;
	SPECULAR = especular;
	RIM = borde;
	RIM_TINT = tinte_borde;
	CLEARCOAT = brillo;
	CLEARCOAT_ROUGHNESS = 0.6;
	ALPHA = color.a * alfa;
}
