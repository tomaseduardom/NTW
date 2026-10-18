shader_type canvas_item;
render_mode blend_mix;

// =============================================================================
// SHADER DE RELIEVE FÍSICO PARA CARTAS (TCG)
// - Troquelado de esquinas redondeadas con antialiasing
// - Bisel 3D físico con luz cenital/superior-izquierda y sombra inferior-derecha
// - Reborde sutil de cartulina cortada (rim)
// - Iluminación ambiental de superficie
// =============================================================================

uniform vec2 card_size = vec2(150.0, 210.0);
uniform float corner_radius : hint_range(0.0, 20.0) = 7.0;
uniform float bevel_width : hint_range(0.5, 4.0) = 1.8;
uniform float bevel_intensity : hint_range(0.0, 0.8) = 0.28;
uniform float rim_width : hint_range(0.5, 3.0) = 1.0;
uniform float rim_darkness : hint_range(0.0, 1.0) = 0.50;
uniform vec4 rim_color : source_color = vec4(0.06, 0.05, 0.04, 1.0);
uniform float ambient_depth : hint_range(0.0, 0.2) = 0.045;

float sd_round_rect(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 p = (UV - 0.5) * card_size;
	float dist = sd_round_rect(p, half_size, corner_radius);

	// Recorte antialiased suave para esquinas
	float alpha = 1.0 - smoothstep(-0.75, 0.75, dist);
	if (alpha <= 0.001) {
		discard;
	}

	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb;

	// 1. Iluminación ambiental cenital sutil (superficie con volumen)
	col *= (1.0 + (0.5 - UV.y) * ambient_depth * 2.0);

	// Distancia al borde exterior (0 = borde, positiva hacia adentro)
	float edge_dist = -dist;

	// 2. Bisel 3D físico (Luz desde arriba-izquierda a 135°)
	if (edge_dist < bevel_width) {
		float factor = 1.0 - (edge_dist / bevel_width);
		factor = factor * factor; // Curvatura natural del bisel
		
		// Normal aproximada en el borde
		vec2 n = length(p) > 0.001 ? normalize(p / half_size) : vec2(0.0, -1.0);
		vec2 light_dir = normalize(vec2(-0.7071, -0.7071));
		float light_factor = dot(n, -light_dir); // Positivo en sup-izq, negativo en inf-der
		
		if (light_factor > 0.0) {
			// Borde iluminado (brillo de corte)
			col += vec3(bevel_intensity * light_factor * factor);
		} else {
			// Borde sombreado (penumbra de espesor)
			col += vec3(bevel_intensity * 1.3 * light_factor * factor);
		}
	}

	// 3. Reborde micro-oscuro de cartón cortado
	if (edge_dist < rim_width) {
		float rim_factor = 1.0 - (edge_dist / rim_width);
		col = mix(col, rim_color.rgb, rim_darkness * rim_factor);
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), tex.a * alpha);
}
