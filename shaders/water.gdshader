// Вода: цвет по глубине (видно дно у берега), пена на мелководье, рябь и блики солнца.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_c : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.14, 0.42, 0.42);
uniform vec3 deep_col : source_color = vec3(0.02, 0.1, 0.17);
uniform float murk = 0.0;
uniform float frozen = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.35 + TIME * 1.1) * cos(wpos.z * 0.29 + TIME * 0.9);
	VERTEX.y += w * 0.04 * (1.0 - frozen);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, d), 1.0);
	view.xyz /= view.w;
	float behind = max(0.0, -view.z - (-VERTEX.z));
	// приблизительная вертикальная глубина
	vec3 vdir = normalize(VERTEX);
	float depth = behind * abs(dot(vdir, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
	float fd = clamp(depth / 3.5, 0.0, 1.0);
	vec2 uv1 = wpos.xz * 0.045 + TIME * vec2(0.012, 0.007);
	vec2 uv2 = wpos.xz * 0.11 - TIME * vec2(0.009, 0.015);
	vec2 n1 = texture(noise_a, uv1).rg - 0.5;
	vec2 n2 = texture(noise_a, uv2).ba - 0.5;
	vec2 nn = (n1 + n2 * 0.6) * (1.0 - frozen * 0.85);
	vec3 n_world = normalize(vec3(nn.x * 0.9, 1.0, nn.y * 0.9));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, fd + murk * 0.5));
	// пена у берега: тонкая полоса с рябью
	float fn = texture(noise_c, wpos.xz * 0.35 + TIME * 0.05).r;
	float foam = smoothstep(0.55, 0.0, depth) * smoothstep(0.35, 0.75, fn + sin(depth * 9.0 - TIME * 2.0) * 0.15);
	col = mix(col, vec3(0.92, 0.95, 0.97), foam * 0.85);
	col = mix(col, vec3(0.78, 0.84, 0.9), frozen);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.35, frozen);
	SPECULAR = 0.65;
	ALPHA = clamp(0.28 + smoothstep(0.0, 1.6, depth) * 0.62 + foam * 0.5 + murk * 0.3 + frozen, 0.0, 1.0);
}
