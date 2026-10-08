// Рельеф: смешивание материалов поверхности по тайлам.
// Тип тайла берётся из атласа ground_atlas (512×512 тайлов вокруг камеры, адресация по модулю),
// поэтому соседние чанки смешиваются без швов. Границы «рваные» за счёт сдвига шумом,
// а материалы с «высотой» (трава, камни) прорастают поверх низких (песок, грязь).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;


uniform sampler2D ground_atlas : filter_nearest, repeat_enable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_c : filter_linear_mipmap, repeat_enable;
// 0 — лето, 1 — глубокая зима (снег на ровных местах в умеренных широтах)
uniform float winter = 0.0;
// сухость/желтизна травы (осень, засуха)
uniform float autumn = 0.0;
uniform float rain_wet = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

const float TILE = 2.0;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

int ground_at(ivec2 t) {
	return int(round(texelFetch(ground_atlas, t & ivec2(511), 0).r * 255.0));
}

int flags_at(ivec2 t) {
	return int(round(texelFetch(ground_atlas, t & ivec2(511), 0).g * 255.0));
}

// Материал: цвет, «высота» для смешивания, шероховатость.
void material(int g, vec2 t, vec3 wp, out vec3 col, out float h, out float rough) {
	float n1 = texture(noise_a, t * 0.031).r;
	float n2 = texture(noise_a, t * 0.13).g;
	float n3 = texture(noise_c, t * 0.9).r;
	float n4 = texture(noise_c, t * 3.1).g;
	vec2 cell = texture(noise_b, t * 0.55).rg;
	rough = 0.92;
	h = 0.4;
	if (g == 3) { // трава
		vec3 a = vec3(0.21, 0.33, 0.11);
		vec3 b = vec3(0.35, 0.44, 0.16);
		col = mix(a, b, n1);
		col = mix(col, vec3(0.42, 0.40, 0.18), smoothstep(0.55, 0.8, n2) * 0.45 + autumn * 0.5);
		col *= 0.82 + n4 * 0.32;
		col = mix(col, col * 0.7, smoothstep(0.45, 0.75, n3) * 0.5);
		// цветы
		float fl = step(0.985, texture(noise_c, t * 7.3).b);
		col = mix(col, mix(vec3(0.95, 0.85, 0.3), vec3(0.85, 0.35, 0.55), n2), fl * (1.0 - autumn));
		h = 0.62 + n3 * 0.3;
	} else if (g == 4) { // сухая трава, степь
		col = mix(vec3(0.52, 0.47, 0.25), vec3(0.62, 0.55, 0.3), n1);
		col *= 0.85 + n4 * 0.28;
		col = mix(col, vec3(0.4, 0.36, 0.22), smoothstep(0.5, 0.8, n3) * 0.4);
		h = 0.55 + n3 * 0.25;
	} else if (g == 5) { // земля
		col = mix(vec3(0.33, 0.25, 0.17), vec3(0.42, 0.32, 0.21), n1);
		float stone = smoothstep(0.12, 0.05, cell.r);
		col = mix(col, vec3(0.52, 0.48, 0.42) * (0.8 + n4 * 0.3), stone);
		col *= 0.85 + n4 * 0.22;
		h = 0.3 + stone * 0.3;
	} else if (g == 6) { // грязь, болото
		col = mix(vec3(0.2, 0.17, 0.12), vec3(0.27, 0.23, 0.15), n1) * (0.85 + n4 * 0.2);
		float puddle = smoothstep(0.62, 0.7, n2);
		col = mix(col, vec3(0.12, 0.14, 0.12), puddle);
		rough = mix(0.75, 0.12, puddle);
		h = 0.2;
	} else if (g == 2) { // песок
		float rip = sin(dot(wp.xz, vec2(1.7, 0.6)) * 1.3 + n2 * 6.0) * 0.5 + 0.5;
		col = mix(vec3(0.74, 0.65, 0.45), vec3(0.84, 0.75, 0.55), n1);
		col *= 0.9 + rip * 0.08 + n4 * 0.08;
		h = 0.15 + rip * 0.05;
	} else if (g == 7 || g == 8) { // камень, скала
		col = mix(vec3(0.36, 0.35, 0.33), vec3(0.5, 0.48, 0.45), n1);
		float crack = smoothstep(0.03, 0.0, abs(cell.g - cell.r));
		col *= (0.82 + n4 * 0.3) * (1.0 - crack * 0.5);
		col = mix(col, vec3(0.38, 0.42, 0.26), smoothstep(0.7, 0.85, n2) * 0.4);
		h = 0.75 + n3 * 0.25;
		rough = 0.85;
		if (g == 8) {
			col *= 0.78;
			h = 1.0;
		}
	} else if (g == 9) { // снег
		col = vec3(0.86, 0.89, 0.94) * (0.94 + n4 * 0.06);
		col = mix(col, vec3(0.75, 0.8, 0.9), smoothstep(0.5, 0.8, n2) * 0.3);
		rough = 0.55;
		h = 0.5 + n3 * 0.2;
	} else if (g == 10) { // пепел
		col = mix(vec3(0.2, 0.19, 0.18), vec3(0.32, 0.29, 0.26), n1);
		col *= 0.8 + n4 * 0.3;
		col = mix(col, vec3(0.09, 0.08, 0.08), smoothstep(0.6, 0.75, n3) * 0.6);
		h = 0.3;
	} else if (g == 11) { // джунгли
		col = mix(vec3(0.1, 0.24, 0.08), vec3(0.18, 0.33, 0.1), n1);
		col *= 0.8 + n4 * 0.35;
		col = mix(col, vec3(0.28, 0.2, 0.1), smoothstep(0.6, 0.85, n3) * 0.35);
		h = 0.7 + n3 * 0.2;
	} else if (g == 12) { // пашня: борозды
		float rows = sin(wp.x * 3.1 + n2 * 0.6) * 0.5 + 0.5;
		col = mix(vec3(0.26, 0.19, 0.12), vec3(0.36, 0.27, 0.17), rows);
		col *= 0.88 + n4 * 0.2;
		h = 0.35;
	} else if (g == 13) { // мостовая, бетон: плитка 1×1 м
		vec2 q = wp.xz * 1.0;
		vec2 fq = abs(fract(q) - 0.5);
		float seam = smoothstep(0.47, 0.5, max(fq.x, fq.y));
		float tile_v = texture(noise_c, floor(q) * 0.137).r;
		col = mix(vec3(0.45, 0.43, 0.4), vec3(0.58, 0.55, 0.5), tile_v);
		col *= 0.92 + n4 * 0.1;
		col = mix(col, vec3(0.22, 0.2, 0.18), seam * 0.7);
		col = mix(col, vec3(0.3, 0.27, 0.2), smoothstep(0.65, 0.85, n2) * 0.35);
		rough = 0.8;
		h = 0.45;
	} else if (g == 14) { // гравий, дорога
		col = mix(vec3(0.43, 0.39, 0.32), vec3(0.55, 0.5, 0.42), n1);
		float pebble = smoothstep(0.16, 0.08, texture(noise_b, t * 2.3).r);
		col = mix(col, vec3(0.62, 0.58, 0.52), pebble * 0.6);
		col *= 0.88 + n4 * 0.18;
		h = 0.25;
	} else if (g == 15) { // красный камень: слоистый
		float layers = sin(wp.y * 2.2 + n2 * 3.0) * 0.5 + 0.5;
		col = mix(vec3(0.55, 0.3, 0.18), vec3(0.72, 0.45, 0.28), layers);
		col *= 0.85 + n4 * 0.25;
		h = 0.7;
	} else { // дно
		col = mix(vec3(0.3, 0.29, 0.22), vec3(0.45, 0.41, 0.3), n1);
		h = 0.1;
	}
}

void fragment() {
	vec2 t = wpos.xz / TILE;
	vec2 warp = (texture(noise_a, t * 0.045).rg - 0.5) * 0.9 + (texture(noise_a, t * 0.19).ba - 0.5) * 0.35;
	vec2 sp = t + warp - 0.5;
	ivec2 i0 = ivec2(floor(sp));
	vec2 f = fract(sp);
	ivec2 cs[4] = ivec2[](i0, i0 + ivec2(1, 0), i0 + ivec2(0, 1), i0 + ivec2(1, 1));
	float ws[4] = float[]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	int types[4];
	float wsum[4];
	int n = 0;
	for (int k = 0; k < 4; k++) {
		int g = ground_at(cs[k]);
		int found = -1;
		for (int j = 0; j < n; j++) {
			if (types[j] == g) { found = j; }
		}
		if (found >= 0) {
			wsum[found] += ws[k];
		} else {
			types[n] = g;
			wsum[n] = ws[k];
			n++;
		}
	}
	vec3 cols[4];
	float hs[4];
	float rs[4];
	float best = -10.0;
	for (int j = 0; j < n; j++) {
		material(types[j], t, wpos, cols[j], hs[j], rs[j]);
		hs[j] = hs[j] * 0.6 + wsum[j] * 1.6;
		best = max(best, hs[j]);
	}
	vec3 col = vec3(0.0);
	float rough = 0.0;
	float wt = 0.0;
	for (int j = 0; j < n; j++) {
		float w = max(hs[j] - best + 0.22, 0.0);
		col += cols[j] * w;
		rough += rs[j] * w;
		wt += w;
	}
	col /= max(wt, 0.0001);
	rough /= max(wt, 0.0001);
	// крутые склоны — голый камень (трипланарно, чтобы текстура не тянулась)
	float steep = smoothstep(0.82, 0.62, wnorm.y);
	if (steep > 0.001) {
		vec3 bw = pow(abs(wnorm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		float nx = texture(noise_a, wpos.zy * 0.06).r;
		float nz = texture(noise_a, wpos.xy * 0.06).r;
		float ny = texture(noise_a, wpos.xz * 0.06).r;
		float nn = nx * bw.x + ny * bw.y + nz * bw.z;
		float strata = sin(wpos.y * 1.6 + nn * 5.0) * 0.5 + 0.5;
		vec3 rock = mix(vec3(0.33, 0.31, 0.29), vec3(0.5, 0.47, 0.43), nn) * (0.8 + strata * 0.25);
		col = mix(col, rock, steep);
		rough = mix(rough, 0.88, steep);
	}
	// снег зимой и на высоте ложится на ровные места
	float snow = winter * smoothstep(0.55, 0.85, wnorm.y) * smoothstep(0.3, 0.6, texture(noise_a, t * 0.07).b + winter * 0.5);
	col = mix(col, vec3(0.88, 0.9, 0.95), clamp(snow, 0.0, 1.0));
	// мокрый берег и дождь
	int fl = flags_at(ivec2(floor(t)));
	float wet = rain_wet * 0.6 + (((fl & 64) != 0) ? 0.5 : 0.0);
	col *= 1.0 - wet * 0.35;
	rough = mix(rough, 0.25, wet);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
