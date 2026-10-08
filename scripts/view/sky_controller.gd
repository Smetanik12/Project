class_name SkyController
extends Node3D
## Солнце, луна, небо, туман и окружение. set_time() двигает солнце по небу и меняет цвета:
## рассвет, день, закат, ночь со звёздами и лунным светом. Зима — ниже солнце, холоднее свет.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var world_env: WorldEnvironment
var hour := 10.0
## 0..1 — доля зимы (для цвета света и высоты солнца).
var winter := 0.0


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("noise_a", NoiseLib.noise_a())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 140.0
	env.fog_depth_end = 330.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.shadow_blur = 1.2
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.shadow_enabled = false
	moon.light_color = Color(0.55, 0.62, 0.85)
	add_child(moon)
	set_time(hour)


## Время суток (0..24). Восход ~5:30, закат ~19:30 (зимой день короче).
func set_time(h: float) -> void:
	hour = fposmod(h, 24.0)
	var day_len := lerpf(14.5, 9.0, winter)
	var rise := 12.0 - day_len * 0.5
	var t := (hour - rise) / day_len  # 0 — восход, 1 — закат
	var elev := sin(clampf(t, -0.25, 1.25) * PI) * lerpf(62.0, 32.0, winter)
	var azim := lerpf(-100.0, 100.0, t)
	sun.rotation_degrees = Vector3(-elev, azim + 180.0, 0.0)
	var day := clampf(elev / 18.0, 0.0, 1.0)
	var low := clampf(1.0 - absf(elev - 4.0) / 16.0, 0.0, 1.0)
	var night := clampf(-elev / 10.0, 0.0, 1.0)
	# свет солнца: белый днём, оранжевый на рассвете и закате
	var sun_col := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.58, 0.32), low * 0.85)
	sun_col = sun_col.lerp(Color(0.9, 0.95, 1.0), winter * 0.3)
	sun.light_color = sun_col
	sun.light_energy = smoothstep(-2.0, 10.0, elev) * lerpf(1.5, 1.15, winter)
	sun.visible = elev > -3.0
	# луна — напротив солнца
	moon.rotation_degrees = Vector3(-maxf(12.0, 45.0 * night), azim, 0.0)
	moon.light_energy = 0.18 * night
	moon.visible = night > 0.01
	# небо
	var top := Color(0.2, 0.42, 0.82).lerp(Color(0.32, 0.36, 0.6), low * 0.5).lerp(Color(0.02, 0.03, 0.08), night)
	var hor := Color(0.68, 0.8, 0.92).lerp(Color(0.98, 0.6, 0.38), low * 0.8).lerp(Color(0.06, 0.08, 0.16), night)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.45))
	sky_mat.set_shader_parameter("sun_color", sun_col)
	sky_mat.set_shader_parameter("stars", night)
	sky_mat.set_shader_parameter("cloud_color", Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.55), low * 0.7).lerp(Color(0.12, 0.13, 0.18), night))
	sky_mat.set_shader_parameter("cloud_shade", Color(0.62, 0.66, 0.74).lerp(Color(0.6, 0.38, 0.38), low * 0.6).lerp(Color(0.05, 0.05, 0.08), night))
	env.ambient_light_energy = lerpf(0.25, 1.0, day) + low * 0.15
	env.fog_light_color = hor.lerp(Color(0.5, 0.55, 0.62), 0.3)
	env.fog_light_energy = lerpf(0.25, 1.0, day)
	env.tonemap_exposure = lerpf(1.35, 1.0, day)


func set_winter(w: float) -> void:
	winter = clampf(w, 0.0, 1.0)
	set_time(hour)
