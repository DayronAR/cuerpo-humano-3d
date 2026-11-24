shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color_resaltado : source_color = vec4(0.2, 0.75, 1.0, 1.0);
uniform float intensidad = 1.3;
uniform float velocidad_pulso = 4.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float pulso = 0.75 + 0.25 * sin(TIME * velocidad_pulso);
	ALBEDO = color_resaltado.rgb * (0.25 + fresnel) * intensidad * pulso;
}
