// Деревья, трава, кусты, камни. Цвет — из вершин, у каждого экземпляра свой оттенок.
// Ветер гнёт всё гибкое (UV.x — гибкость от корня к макушке), листва просвечивает на солнце,
// зимой на верхние поверхности ложится снег. То, что закрывает фокус камеры, растворяется.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float winter = 0.0;
uniform float autumn = 0.0;
uniform float night = 0.0;
uniform float rigid = 0.0;
uniform float wind = 1.0;
// точка, которую нельзя закрывать (игрок), и радиус «окна» вокруг луча камеры
uniform vec3 focus_world = vec3(0.0, -10000.0, 0.0);
uniform float reveal_radius = 3.2;

varying vec3 wpos;
varying float variation;
varying float flex;
varying float leaf;

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	variation = hash1(floor(inst * 3.0));
	flex = UV.x;
	leaf = UV.y;
	vec3 wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (rigid < 0.5) {
		float f = flex * flex;
		float t = TIME * (1.1 + variation * 0.4);
		float gust = texture(noise_a, inst.xz * 0.004 + TIME * 0.015).r;
		vec2 sway = vec2(sin(t + inst.x * 0.13), cos(t * 0.83 + inst.z * 0.11)) * (0.12 + gust * 0.22);
		float flutter = sin(TIME * 6.0 + wv.x * 3.0 + wv.y * 2.0) * 0.03 * leaf;
		vec3 off = vec3(sway.x, 0.0, sway.y) * f * wind + vec3(flutter, flutter * 0.5, flutter) * f;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	// оттенок экземпляра: светлее/темнее, чуть теплее/холоднее
	col *= 0.86 + variation * 0.28;
	col = mix(col, col * vec3(1.08, 1.0, 0.85), (variation - 0.5) * 0.6 * leaf);
	// осень: листва желтеет и краснеет
	col = mix(col, col.g * vec3(1.6, 1.0, 0.3) + vec3(0.12, 0.02, 0.0), autumn * leaf * (0.5 + variation * 0.5));
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		n_world = -n_world;
	}
	// снег на верхних поверхностях
	float snow = winter * smoothstep(0.35, 0.8, n_world.y) * smoothstep(0.25, 0.6, texture(noise_a, wpos.xz * 0.2).g + winter * 0.4);
	col = mix(col, vec3(0.9, 0.92, 0.96), snow);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, leaf);
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.32, 0.4, 0.18) * leaf * (1.0 - snow);
	// светящиеся пятна (альфа цвета вершины < 0.95)
	if (COLOR.a < 0.95) {
		float spots = smoothstep(0.62, 0.7, texture(noise_a, wpos.xz * 0.6 + wpos.y * 0.3).r);
		EMISSION = vec3(0.25, 0.85, 1.0) * spots * (0.3 + night * 2.2);
	}
	// не закрываем фокус: всё, что на луче камера→фокус, растворяется сеткой
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 seg = focus_world - cam;
	float t = clamp(dot(wpos - cam, seg) / max(dot(seg, seg), 0.001), 0.0, 1.0);
	float d = length(wpos - (cam + seg * t));
	if (t > 0.08 && t < 0.97 && d < reveal_radius && rigid < 0.5) {
		ivec2 px = ivec2(FRAGCOORD.xy) % ivec2(4);
		float bayer = float((px.x * 3 + px.y * 2) % 4) / 4.0;
		if (smoothstep(reveal_radius, reveal_radius * 0.55, d) > bayer + 0.12) {
			discard;
		}
	}
}
