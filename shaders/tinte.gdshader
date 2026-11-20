// Tinte de un órgano según la simulación (pulmón oscurecido, músculo con ácido láctico).
// Se aplica como material_overlay: una capa semitransparente encima del material original,
// así no hace falta modificar ni duplicar los materiales del modelo.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform vec4 color_tinte : source_color = vec4(0.2, 0.15, 0.13, 1.0);
uniform float cantidad : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = color_tinte.rgb;
	ROUGHNESS = 0.7;
	ALPHA = cantidad;
}
