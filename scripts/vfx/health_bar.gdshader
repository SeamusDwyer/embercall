shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// 0 = empty, 1 = full. Driven by HealthBar3D.set_health().
uniform float health : hint_range(0.0, 1.0) = 1.0;
uniform vec3 fill_color : source_color = vec3(0.22, 0.85, 0.25);
uniform vec3 low_color : source_color = vec3(0.9, 0.15, 0.1);
uniform vec3 background_color : source_color = vec3(0.06, 0.06, 0.06);
uniform vec3 border_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float border : hint_range(0.0, 0.45) = 0.09;

// Camera-facing billboard that preserves the quad's authored scale.
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	vec3 col;
	if (uv.x < border || uv.x > 1.0 - border || uv.y < border || uv.y > 1.0 - border) {
		col = border_color;
	} else {
		float t = (uv.x - border) / (1.0 - 2.0 * border);
		col = t <= health ? mix(low_color, fill_color, health) : background_color;
	}
	ALBEDO = col;
}
