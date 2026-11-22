// Tinte de un órgano según la simulación (pulmón oscurecido, músculo con ácido láctico, daño del
// tabaco). Se aplica como material_overlay: una capa semitransparente encima del material
// original, así no hace falta modificar ni duplicar los materiales del modelo.
// "manchas" (0 a 1) hace el tinte irregular, en parches (alquitrán, placas, nicotina).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform vec4 color_tinte : source_color = vec4(0.2, 0.15, 0.13, 1.0);
uniform float cantidad : hint_range(0.0, 1.0) = 0.0;
uniform float manchas : hint_range(0.0, 1.0) = 0.0;
uniform float escala_manchas = 45.0;

varying vec3 posicion;

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
	posicion = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = color_tinte.rgb;
	ROUGHNESS = 0.7;
	float a = cantidad;
	if (manchas > 0.0) {
		vec3 q = posicion * escala_manchas;
		float n = ruido(q) * 0.55 + ruido(q * 2.7) * 0.3 + ruido(q * 7.1) * 0.15;
		// Con más daño las manchas se juntan y cubren más superficie
		float parche = smoothstep(0.62 - cantidad * 0.45, 0.72 - cantidad * 0.4, n);
		a = cantidad * mix(1.0, parche * 1.25, manchas);
	}
	ALPHA = clamp(a, 0.0, 1.0);
}
