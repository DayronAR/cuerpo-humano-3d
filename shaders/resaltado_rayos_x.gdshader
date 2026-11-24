shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, blend_mix, cull_back, shadows_disabled;

uniform vec4 color_resaltado : source_color = vec4(0.12, 0.85, 1.0, 1.0);
uniform float velocidad_pulso = 4.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float pulso = 0.8 + 0.2 * sin(TIME * velocidad_pulso);
	ALBEDO = color_resaltado.rgb * (0.7 + 0.6 * fresnel);
	ALPHA = clamp(0.35 + 0.65 * fresnel, 0.0, 1.0) * pulso;
}
