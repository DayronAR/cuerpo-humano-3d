// Corte transversal: reemplaza al material de cada malla mientras se usa la herramienta de corte.
// Copia lo esencial del material original (color, rugosidad, brillo, borde) y descarta lo que
// queda del lado cortado del plano. El interior de cada órgano (sus caras de atrás) se ve un poco
// más oscuro, así se distingue la superficie de corte de la de afuera.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.6, 0.5, 1.0);
uniform float rugosidad : hint_range(0.0, 1.0) = 0.5;
uniform float especular : hint_range(0.0, 1.0) = 0.5;
uniform float borde : hint_range(0.0, 1.0) = 0.0;
uniform float tinte_borde : hint_range(0.0, 1.0) = 0.5;
uniform float brillo : hint_range(0.0, 1.0) = 0.0;
uniform vec4 plano = vec4(0.0, 0.0, 1.0, 1000.0);   // Normal (xyz) y distancia (w): se quita dot(p, n) > w

varying vec3 posicion_mundo;

void vertex() {
	posicion_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(posicion_mundo, plano.xyz) > plano.w) {
		discard;
	}
	ALBEDO = FRONT_FACING ? color.rgb : color.rgb * 0.62;
	ROUGHNESS = FRONT_FACING ? rugosidad : 0.85;
	SPECULAR = especular;
	RIM = FRONT_FACING ? borde : 0.0;
	RIM_TINT = tinte_borde;
	CLEARCOAT = FRONT_FACING ? brillo : 0.0;
	CLEARCOAT_ROUGHNESS = 0.6;
	if (color.a < 0.99) {
		ALPHA = color.a;
	}
}
