// Небо: градиент по времени суток, солнце с ореолом, луна, звёзды ночью, облака.
// Цвета задаёт SkyController (scripts/view/sky_controller.gd).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.25, 0.45, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.3, 0.3, 0.32);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float stars = 0.0;
uniform float clouds = 0.45;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.65, 0.72);
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.18, h));
	if (LIGHT0_ENABLED) {
		float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += sun_color * pow(sd, 8.0) * 0.35 + sun_color * pow(sd, 64.0) * 0.6;
		col += sun_color * smoothstep(0.9994, 0.9997, sd) * 6.0;
	}
	if (LIGHT1_ENABLED) {
		float md = max(dot(dir, LIGHT1_DIRECTION), 0.0);
		col += vec3(0.85, 0.88, 1.0) * smoothstep(0.9990, 0.9993, md) * 1.6;
		col += vec3(0.3, 0.35, 0.5) * pow(md, 40.0) * 0.25;
	}
	if (stars > 0.001 && h > 0.0) {
		vec3 g = floor(dir * 260.0);
		float s = hash(g);
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + s * 40.0);
		col += vec3(0.9, 0.92, 1.0) * step(0.9965, s) * stars * tw * smoothstep(0.0, 0.25, h);
	}
	if (h > 0.0 && clouds > 0.001) {
		vec2 uv = dir.xz / (h + 0.12) * 0.25 + TIME * vec2(0.002, 0.001);
		float c = texture(noise_a, uv).r * 0.65 + texture(noise_a, uv * 2.7).g * 0.35;
		float cov = smoothstep(1.0 - clouds, 1.25 - clouds * 0.7, c);
		float shade = texture(noise_a, uv * 1.3 + 0.07).b;
		vec3 cc = mix(cloud_shade, cloud_color, smoothstep(0.3, 0.7, shade));
		col = mix(col, cc, cov * smoothstep(0.0, 0.12, h) * 0.9);
	}
	COLOR = col;
}
