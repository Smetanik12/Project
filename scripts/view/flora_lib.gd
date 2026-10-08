class_name FloraLib
extends RefCounted
## Растительность и камни: процедурные модели (строятся один раз) и расстановка по чанкам
## через MultiMesh. У деревьев две детализации: вблизи подробная, дальше упрощённая
## (переключение — visibility_range, без кода). Трава и мелочь — только вблизи.
##
## В вершинах: COLOR — цвет; UV.x — гибкость на ветру (0 у корня, 1 на макушке),
## UV.y — 1 для листвы (светится насквозь), 0 для коры и камня; CUSTOM0 не используется.

const TREE_NEAR := 95.0
const TREE_FAR := 420.0
const DECOR_FAR := 75.0
const DECOR_RING := 3

var tree_hi: Dictionary = {}
var tree_lo: Dictionary = {}
var decor: Dictionary = {}
var mat: ShaderMaterial
var mat_rock: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("noise_a", NoiseLib.noise_a())
	mat_rock = ShaderMaterial.new()
	mat_rock.shader = load("res://shaders/foliage.gdshader")
	mat_rock.set_shader_parameter("noise_a", NoiseLib.noise_a())
	mat_rock.set_shader_parameter("rigid", 1.0)
	var T := ChunkGen.TREE
	for kind in T.values():
		_rng.seed = 1000 + kind
		tree_hi[kind] = _tree(kind, true)
		_rng.seed = 1000 + kind
		tree_lo[kind] = _tree(kind, false)
	var D := ChunkGen.DECOR
	for kind in D.values():
		_rng.seed = 2000 + kind
		decor[kind] = _decor(kind)


func set_winter(w: float) -> void:
	mat.set_shader_parameter("winter", w)
	mat_rock.set_shader_parameter("winter", w)


func material_for(kind: int, is_tree: bool) -> ShaderMaterial:
	if is_tree and kind == ChunkGen.TREE.BOULDER:
		return mat_rock
	if not is_tree and kind in [ChunkGen.DECOR.PEBBLES, ChunkGen.DECOR.ROCK, ChunkGen.DECOR.CRATER_DEBRIS]:
		return mat_rock
	return mat


# ======================================================================
#  Расстановка (рабочий поток): преобразования экземпляров по видам
# ======================================================================

## {"trees": {вид: PackedFloat32Array (12 чисел на экземпляр)}, "decor": {вид: ...}} в координатах чанка.
func instances(c: Chunk) -> Dictionary:
	var out_t := {}
	var out_d := {}
	for k in range(0, c.trees.size(), 5):
		var kind := int(c.trees[k + 3])
		_put(out_t, kind, c, c.trees[k], c.trees[k + 1], c.trees[k + 2], c.trees[k + 4], false)
	for k in range(0, c.decor.size(), 5):
		var kind := int(c.decor[k + 3])
		_put(out_d, kind, c, c.decor[k], c.decor[k + 1], c.decor[k + 2], c.decor[k + 4], kind == ChunkGen.DECOR.LILY)
	return {"trees": out_t, "decor": out_d}


func _put(out: Dictionary, kind: int, c: Chunk, x: float, y: float, sc: float, rot: float, on_water: bool) -> void:
	var h := c.height_at(x, y)
	if on_water:
		var w := c.water[c.li(clampi(int(x), c.ox, c.ox + Chunk.N - 1), clampi(int(y), c.oy, c.oy + Chunk.N - 1))]
		if w <= Chunk.NO_WATER:
			return
		h = w + 0.03
	var b := Basis(Vector3.UP, rot).scaled(Vector3(sc, sc, sc))
	var o := Vector3((x - c.ox) * Planet.TILE_M, h - 0.05, (y - c.oy) * Planet.TILE_M)
	if not out.has(kind):
		out[kind] = PackedFloat32Array()
	var arr: PackedFloat32Array = out[kind]
	# формат буфера MultiMesh: 3 строки базиса + сдвиг
	arr.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]))
	out[kind] = arr


## Главный поток: MultiMesh по видам. rel — смещение чанка от фокуса (мелочь только рядом).
func attach(node: Node3D, data: Dictionary, rel: Vector2i) -> void:
	var trees: Dictionary = data["trees"]
	for kind in trees:
		var buf: PackedFloat32Array = trees[kind]
		var n := buf.size() / 12
		if n == 0:
			continue
		var hi := _mm(tree_hi[kind], buf, n, material_for(kind, true))
		hi.visibility_range_end = TREE_NEAR
		hi.visibility_range_end_margin = 12.0
		hi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(hi)
		var lo := _mm(tree_lo[kind], buf, n, material_for(kind, true))
		lo.visibility_range_begin = TREE_NEAR
		lo.visibility_range_begin_margin = 12.0
		lo.visibility_range_end = TREE_FAR
		lo.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(lo)
	if absi(rel.x) > DECOR_RING or absi(rel.y) > DECOR_RING:
		return
	var dec: Dictionary = data["decor"]
	for kind in dec:
		var buf: PackedFloat32Array = dec[kind]
		var n := buf.size() / 12
		if n == 0:
			continue
		var mi := _mm(decor[kind], buf, n, material_for(kind, false))
		mi.visibility_range_end = DECOR_FAR
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)


func _mm(mesh: Mesh, buf: PackedFloat32Array, n: int, m: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	return mi


# ======================================================================
#  Модели деревьев
# ======================================================================

func _tree(kind: int, hi: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var T := ChunkGen.TREE
	var sides := 7 if hi else 4
	var det := 1 if hi else 0
	match kind:
		T.PINE:
			_conifer(st, 15.0, 3.2, 7 if hi else 4, Color(0.09, 0.2, 0.11), Color(0.2, 0.33, 0.16), sides, 0.36)
		T.SPRUCE:
			_conifer(st, 17.0, 3.0, 9 if hi else 5, Color(0.07, 0.17, 0.12), Color(0.15, 0.28, 0.19), sides, 0.4)
		T.OAK:
			_broadleaf(st, 7.5, 0.55, 3.4, 7, Color(0.17, 0.32, 0.1), Color(0.3, 0.45, 0.16), sides, det, Color(0.3, 0.22, 0.15))
		T.BIRCH:
			_broadleaf(st, 10.0, 0.26, 2.3, 5, Color(0.26, 0.42, 0.14), Color(0.42, 0.56, 0.22), sides, det, Color(0.86, 0.85, 0.8))
		T.MAPLE:
			_broadleaf(st, 8.0, 0.42, 3.0, 6, Color(0.2, 0.36, 0.1), Color(0.36, 0.48, 0.15), sides, det, Color(0.33, 0.24, 0.16))
		T.WILLOW:
			_willow(st, sides, det)
		T.PALM:
			_palm(st, sides, hi)
		T.JUNGLE:
			_jungle(st, sides, det)
		T.ACACIA:
			_acacia(st, sides, det)
		T.BAOBAB:
			_baobab(st, sides, det)
		T.DEAD:
			_dead(st, 9.0, Color(0.36, 0.31, 0.26), sides)
		T.CHARRED:
			_dead(st, 6.5, Color(0.1, 0.09, 0.08), sides)
		T.CACTUS:
			_cactus(st, sides)
		T.GLOWCAP:
			_glowcap(st, sides, det)
		T.BOULDER:
			_rock(st, Vector3(0, 0.6, 0), 1.6, Vector3(1.0, 0.75, 1.0), 2 if hi else 1, Color(0.42, 0.4, 0.37))
	return st.commit()


func _conifer(st: SurfaceTool, height: float, radius: float, layers: int, dark: Color, light: Color, sides: int, trunk_r: float) -> void:
	_cyl(st, Vector3.ZERO, Vector3(0, height * 0.92, 0), trunk_r, 0.06, sides, Color(0.25, 0.18, 0.12), Color(0.3, 0.22, 0.15), 0.0, 0.6)
	for i in layers:
		var t := float(i) / layers
		var y0 := lerpf(height * 0.2, height * 0.82, t)
		var r := lerpf(radius, radius * 0.22, t) * _rng.randf_range(0.9, 1.1)
		var hgt := lerpf(height * 0.32, height * 0.2, t)
		var off := Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
		_cone(st, Vector3(0, y0, 0) + off, r, hgt, sides + 3, dark.lerp(light, t * 0.5), light.lerp(dark, 0.2), y0 / height, 0.55)
	_cone(st, Vector3(0, height * 0.86, 0), radius * 0.16, height * 0.16, sides + 2, light, light, 0.95, 0.5)


func _broadleaf(st: SurfaceTool, height: float, trunk_r: float, crown: float, blobs: int, dark: Color, light: Color,
		sides: int, det: int, bark: Color) -> void:
	var top := Vector3(_rng.randf_range(-0.3, 0.3), height * 0.75, _rng.randf_range(-0.3, 0.3))
	_cyl(st, Vector3.ZERO, top, trunk_r, trunk_r * 0.6, sides, bark.darkened(0.25), bark, 0.0, 0.5)
	# ветви
	for b in 3:
		var a := TAU * b / 3.0 + _rng.randf()
		var tip := top + Vector3(cos(a) * crown * 0.7, crown * 0.5, sin(a) * crown * 0.7)
		_cyl(st, top - Vector3(0, height * 0.12, 0), tip, trunk_r * 0.45, trunk_r * 0.15, maxi(3, sides - 2), bark, bark, 0.5, 0.8)
	# крона из «облаков»
	var center := top + Vector3(0, crown * 0.75, 0)
	for b in blobs:
		var dirv := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.35, 0.8), _rng.randf_range(-1, 1)).normalized()
		var p := center + dirv * crown * _rng.randf_range(0.3, 0.75)
		var r := crown * _rng.randf_range(0.55, 0.8)
		_blob(st, p, r, Vector3(1, 0.82, 1), det, dark, light, 0.7, 1.0)
	_blob(st, center + Vector3(0, crown * 0.2, 0), crown * 0.75, Vector3(1, 0.9, 1), det, dark, light, 0.8, 1.0)


func _willow(st: SurfaceTool, sides: int, det: int) -> void:
	var top := Vector3(0, 5.5, 0)
	_cyl(st, Vector3.ZERO, top, 0.6, 0.38, sides, Color(0.25, 0.2, 0.14), Color(0.33, 0.27, 0.18), 0.0, 0.4)
	var c := top + Vector3(0, 2.2, 0)
	_blob(st, c, 3.6, Vector3(1.1, 0.6, 1.1), det, Color(0.2, 0.32, 0.12), Color(0.38, 0.5, 0.2), 0.7, 1.0)
	# свисающие пряди
	var n := 16 if det > 0 else 8
	for k in n:
		var a := TAU * k / n + _rng.randf() * 0.3
		var r := 3.2 + _rng.randf() * 0.6
		var p0 := c + Vector3(cos(a) * r, -0.5, sin(a) * r)
		_strip(st, p0, Vector3(cos(a) * 0.15, -1, sin(a) * 0.15), 4.2 + _rng.randf() * 1.0, 0.9, 0.1,
			Color(0.24, 0.38, 0.14), Color(0.36, 0.5, 0.2), 1.0)


func _palm(st: SurfaceTool, sides: int, hi: bool) -> void:
	var segs := 6 if hi else 3
	var height := 11.0
	var lean := Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	var prev := Vector3.ZERO
	for i in segs:
		var t := float(i + 1) / segs
		var p := Vector3(lean.x * t * t, height * t, lean.z * t * t)
		_cyl(st, prev, p, lerpf(0.34, 0.2, t - 1.0 / segs), lerpf(0.34, 0.2, t), sides, Color(0.42, 0.33, 0.22), Color(0.5, 0.4, 0.27), t - 1.0 / segs, 0.4)
		prev = p
	var n := 9 if hi else 6
	for k in n:
		var a := TAU * k / n + _rng.randf() * 0.2
		_strip(st, prev, Vector3(cos(a), 0.35, sin(a)), 5.5, 1.1, -0.9, Color(0.16, 0.34, 0.1), Color(0.34, 0.52, 0.18), 1.0)


func _jungle(st: SurfaceTool, sides: int, det: int) -> void:
	var height := 22.0
	_cyl(st, Vector3.ZERO, Vector3(0, height, 0), 0.9, 0.45, sides, Color(0.3, 0.26, 0.2), Color(0.38, 0.33, 0.25), 0.0, 0.25)
	# корни-контрфорсы
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		_cyl(st, Vector3(cos(a) * 2.2, 0, sin(a) * 2.2), Vector3(cos(a) * 0.5, 3.2, sin(a) * 0.5), 0.35, 0.15, 4, Color(0.3, 0.26, 0.2), Color(0.33, 0.28, 0.21), 0.0, 0.0)
	for layer in 2:
		var y := height - layer * 4.0
		for k in 4:
			var a := TAU * k / 4.0 + layer * 0.8
			_blob(st, Vector3(cos(a) * 3.0, y, sin(a) * 3.0), 3.4, Vector3(1.2, 0.5, 1.2), det, Color(0.06, 0.2, 0.07), Color(0.16, 0.36, 0.12), 0.8, 1.0)


func _acacia(st: SurfaceTool, sides: int, det: int) -> void:
	var fork := Vector3(0, 3.2, 0)
	_cyl(st, Vector3.ZERO, fork, 0.4, 0.3, sides, Color(0.35, 0.27, 0.18), Color(0.4, 0.3, 0.2), 0.0, 0.3)
	for k in 3:
		var a := TAU * k / 3.0 + _rng.randf()
		_cyl(st, fork, Vector3(cos(a) * 2.6, 6.2, sin(a) * 2.6), 0.24, 0.12, maxi(3, sides - 2), Color(0.35, 0.27, 0.18), Color(0.4, 0.3, 0.2), 0.4, 0.6)
	_blob(st, Vector3(0, 6.8, 0), 5.2, Vector3(1.0, 0.24, 1.0), det, Color(0.3, 0.36, 0.13), Color(0.48, 0.52, 0.22), 0.9, 1.0)


func _baobab(st: SurfaceTool, sides: int, det: int) -> void:
	_cyl(st, Vector3.ZERO, Vector3(0, 8.0, 0), 1.7, 1.15, sides + 2, Color(0.46, 0.38, 0.3), Color(0.52, 0.43, 0.34), 0.0, 0.1)
	for k in 5:
		var a := TAU * k / 5.0
		var tip := Vector3(cos(a) * 2.8, 10.5 + _rng.randf(), sin(a) * 2.8)
		_cyl(st, Vector3(0, 7.8, 0), tip, 0.4, 0.12, 4, Color(0.46, 0.38, 0.3), Color(0.5, 0.42, 0.33), 0.5, 0.6)
		_blob(st, tip, 1.3, Vector3(1, 0.7, 1), det, Color(0.24, 0.34, 0.12), Color(0.36, 0.46, 0.18), 0.9, 1.0)


func _dead(st: SurfaceTool, height: float, bark: Color, sides: int) -> void:
	var top := Vector3(_rng.randf_range(-0.4, 0.4), height, _rng.randf_range(-0.4, 0.4))
	_cyl(st, Vector3.ZERO, top, 0.35, 0.08, sides, bark.darkened(0.2), bark, 0.0, 0.3)
	for b in 6:
		var y := height * _rng.randf_range(0.35, 0.85)
		var a := _rng.randf() * TAU
		var base := Vector3(0, y, 0) + top * (y / height) * Vector3(1, 0, 1)
		var tip := base + Vector3(cos(a) * 2.2, _rng.randf_range(0.6, 1.8), sin(a) * 2.2)
		_cyl(st, base, tip, 0.12, 0.03, 3, bark, bark, y / height, 0.5)
		var tip2 := tip + Vector3(cos(a + 0.8) * 0.9, 0.7, sin(a + 0.8) * 0.9)
		_cyl(st, tip, tip2, 0.05, 0.02, 3, bark, bark, 0.8, 0.8)


func _cactus(st: SurfaceTool, sides: int) -> void:
	var g := Color(0.22, 0.38, 0.2)
	var g2 := Color(0.3, 0.46, 0.24)
	_cyl(st, Vector3.ZERO, Vector3(0, 4.2, 0), 0.38, 0.32, sides + 1, g, g2, 0.0, 0.05)
	_sphere_cap(st, Vector3(0, 4.2, 0), 0.32, sides + 1, g2)
	for side in [-1.0, 1.0]:
		var y := _rng.randf_range(1.4, 2.4)
		var p0 := Vector3(0.3 * side, y, 0)
		var p1 := Vector3(1.0 * side, y + 0.2, 0)
		var p2 := Vector3(1.0 * side, y + 1.7, 0)
		_cyl(st, p0, p1, 0.2, 0.2, sides, g, g, 0.2, 0.05)
		_cyl(st, p1, p2, 0.2, 0.18, sides, g, g2, 0.2, 0.05)
		_sphere_cap(st, p2, 0.18, sides, g2)


func _glowcap(st: SurfaceTool, sides: int, det: int) -> void:
	_cyl(st, Vector3.ZERO, Vector3(0.3, 6.5, 0.1), 0.45, 0.32, sides, Color(0.72, 0.68, 0.6), Color(0.8, 0.76, 0.68), 0.0, 0.2)
	# шляпка: светящиеся пятна (альфа цвета вершины > 0.5 — свечение в шейдере)
	_blob(st, Vector3(0.3, 7.2, 0.1), 3.6, Vector3(1.0, 0.38, 1.0), det, Color(0.18, 0.3, 0.42, 0.9), Color(0.3, 0.55, 0.62, 0.9), 0.6, 1.0)


# ======================================================================
#  Мелочь
# ======================================================================

func _decor(kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var D := ChunkGen.DECOR
	match kind:
		D.GRASS:
			_tuft(st, 8, 0.45, 0.35, Color(0.2, 0.33, 0.1), Color(0.42, 0.55, 0.2))
		D.TALLGRASS:
			_tuft(st, 10, 0.95, 0.45, Color(0.23, 0.34, 0.12), Color(0.5, 0.56, 0.24))
		D.FLOWERS:
			_tuft(st, 6, 0.45, 0.3, Color(0.2, 0.33, 0.1), Color(0.36, 0.5, 0.18))
			for k in 4:
				var a := _rng.randf() * TAU
				var p := Vector3(cos(a) * 0.18, 0.45 + _rng.randf() * 0.12, sin(a) * 0.18)
				var col: Color = [Color(0.95, 0.85, 0.25), Color(0.9, 0.35, 0.5), Color(0.6, 0.5, 0.95), Color(1, 1, 1)][_rng.randi() % 4]
				_blob(st, p, 0.07, Vector3(1, 0.5, 1), 0, col, col.lightened(0.2), 1.0, 1.0)
		D.FERN:
			for k in 7:
				var a := TAU * k / 7.0 + _rng.randf() * 0.3
				_strip(st, Vector3(0, 0.05, 0), Vector3(cos(a), 0.9, sin(a)), 0.85, 0.22, -0.55, Color(0.1, 0.26, 0.08), Color(0.24, 0.44, 0.14), 1.0)
		D.BUSH:
			_blob(st, Vector3(0, 0.45, 0), 0.75, Vector3(1.1, 0.75, 1.1), 1, Color(0.14, 0.27, 0.09), Color(0.3, 0.44, 0.16), 0.6, 1.0)
		D.REED:
			_tuft(st, 9, 1.6, 0.2, Color(0.28, 0.36, 0.14), Color(0.52, 0.56, 0.26))
			for k in 3:
				var p := Vector3(_rng.randf_range(-0.12, 0.12), 1.35 + _rng.randf() * 0.2, _rng.randf_range(-0.12, 0.12))
				_cyl(st, p, p + Vector3(0, 0.25, 0), 0.035, 0.035, 4, Color(0.35, 0.22, 0.12), Color(0.4, 0.26, 0.14), 1.0, 0.0)
		D.PEBBLES:
			for k in 4:
				_rock(st, Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4)), _rng.randf_range(0.06, 0.14), Vector3(1, 0.6, 1), 0, Color(0.48, 0.46, 0.42))
		D.ROCK:
			_rock(st, Vector3(0, 0.05, 0), 0.45, Vector3(1.1, 0.65, 0.9), 1, Color(0.45, 0.43, 0.4))
		D.LILY:
			_disc(st, 0.35, 10, Color(0.18, 0.38, 0.14))
			_blob(st, Vector3(0.1, 0.04, 0.05), 0.08, Vector3(1, 0.6, 1), 0, Color(0.95, 0.9, 0.95), Color(1, 0.8, 0.9), 1.0, 0.0)
		D.DRYBUSH:
			for k in 7:
				var a := _rng.randf() * TAU
				_cyl(st, Vector3.ZERO, Vector3(cos(a) * 0.45, 0.55 + _rng.randf() * 0.3, sin(a) * 0.45), 0.025, 0.01, 3, Color(0.4, 0.33, 0.22), Color(0.5, 0.42, 0.28), 0.0, 1.0)
		D.MUSHROOMS:
			for k in 3:
				var p := Vector3(_rng.randf_range(-0.25, 0.25), 0, _rng.randf_range(-0.25, 0.25))
				_cyl(st, p, p + Vector3(0, 0.14, 0), 0.025, 0.02, 4, Color(0.85, 0.82, 0.75), Color(0.9, 0.88, 0.8), 0.0, 0.0)
				_blob(st, p + Vector3(0, 0.15, 0), 0.08, Vector3(1, 0.5, 1), 0, Color(0.6, 0.25, 0.15), Color(0.75, 0.35, 0.2), 1.0, 0.0)
		D.BONES:
			_cyl(st, Vector3(-0.3, 0.04, 0), Vector3(0.3, 0.04, 0.1), 0.035, 0.035, 4, Color(0.85, 0.82, 0.74), Color(0.9, 0.88, 0.8), 0.0, 0.0)
			_blob(st, Vector3(0.35, 0.08, 0.1), 0.11, Vector3(1, 0.85, 1.2), 0, Color(0.86, 0.83, 0.75), Color(0.92, 0.9, 0.84), 1.0, 0.0)
		D.STUMP:
			_cyl(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.32, 0.28, 7, Color(0.3, 0.22, 0.15), Color(0.36, 0.27, 0.18), 0.0, 0.0)
			_disc(st, 0.28, 7, Color(0.62, 0.5, 0.34), 0.45)
		D.SNOWDRIFT:
			_blob(st, Vector3(0, 0.0, 0), 0.8, Vector3(1.4, 0.3, 1.0), 1, Color(0.84, 0.87, 0.93), Color(0.94, 0.96, 1.0), 1.0, 0.0)
		D.CRATER_DEBRIS:
			for k in 5:
				_rock(st, Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6)), _rng.randf_range(0.07, 0.18), Vector3(1.2, 0.5, 0.8), 0, Color(0.16, 0.14, 0.13))
	return st.commit()


# ======================================================================
#  Геометрия
# ======================================================================

func _v(st: SurfaceTool, p: Vector3, col: Color, flex: float, leaf: float, n := Vector3.UP) -> void:
	st.set_color(col)
	st.set_uv(Vector2(flex, leaf))
	st.set_normal(n)
	st.add_vertex(p)


## Усечённый конус между точками a и b.
func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, ca: Color, cb: Color, flex_a: float, flex_b: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var p00 := a + d0 * ra
		var p01 := a + d1 * ra
		var p10 := b + d0 * rb
		var p11 := b + d1 * rb
		_v(st, p00, ca, flex_a, 0.0, d0)
		_v(st, p10, cb, flex_b, 0.0, d0)
		_v(st, p11, cb, flex_b, 0.0, d1)
		_v(st, p00, ca, flex_a, 0.0, d0)
		_v(st, p11, cb, flex_b, 0.0, d1)
		_v(st, p01, ca, flex_a, 0.0, d1)


## Конус хвои: тёмный низ (тень), светлые кончики, края чуть опущены.
func _cone(st: SurfaceTool, base: Vector3, r: float, h: float, sides: int, cbase: Color, ctip: Color, flex: float, droop: float) -> void:
	var tip := base + Vector3(0, h, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var j0 := 1.0 + sin(a0 * 3.0 + r) * 0.08
		var j1 := 1.0 + sin(a1 * 3.0 + r) * 0.08
		var p0 := base + Vector3(cos(a0) * r * j0, -droop, sin(a0) * r * j0)
		var p1 := base + Vector3(cos(a1) * r * j1, -droop, sin(a1) * r * j1)
		var n0 := (Vector3(cos(a0), 0.0, sin(a0)) * h + Vector3(0, r, 0)).normalized()
		var n1 := (Vector3(cos(a1), 0.0, sin(a1)) * h + Vector3(0, r, 0)).normalized()
		_v(st, p0, cbase, flex, 1.0, n0)
		_v(st, tip, ctip, minf(1.0, flex + 0.2), 1.0, Vector3.UP)
		_v(st, p1, cbase, flex, 1.0, n1)
		# нижняя сторона — тёмная
		_v(st, p0, cbase.darkened(0.45), flex, 1.0, Vector3.DOWN)
		_v(st, p1, cbase.darkened(0.45), flex, 1.0, Vector3.DOWN)
		_v(st, base + Vector3(0, -droop * 0.3, 0), cbase.darkened(0.6), flex, 1.0, Vector3.DOWN)


## Ком листвы/камня: сфера, искажённая шумом; низ темнее (как затенение).
func _blob(st: SurfaceTool, c: Vector3, r: float, squash: Vector3, det: int, dark: Color, light: Color, flex: float, leaf: float) -> void:
	var rings := 5 + det * 3
	var segs := 7 + det * 5
	var pts: Array = []
	for i in rings + 1:
		var lat := PI * float(i) / rings - PI / 2.0
		var row: Array = []
		for j in segs:
			var lon := TAU * float(j) / segs
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var bump := 1.0 + _rng.randf_range(-0.12, 0.12) * (1.0 if i > 0 and i < rings else 0.0)
			row.append(c + d * r * bump * squash)
		pts.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % segs]
			var cc: Vector3 = pts[i + 1][j]
			var dd: Vector3 = pts[i + 1][(j + 1) % segs]
			var ta := float(i) / rings
			var tb := float(i + 1) / rings
			var col_a := dark.lerp(light, ta)
			var col_b := dark.lerp(light, tb)
			var na := ((a - c) / squash).normalized()
			var nb := ((b - c) / squash).normalized()
			var nc := ((cc - c) / squash).normalized()
			var nd := ((dd - c) / squash).normalized()
			_v(st, a, col_a, flex, leaf, na)
			_v(st, cc, col_b, flex, leaf, nc)
			_v(st, dd, col_b, flex, leaf, nd)
			_v(st, a, col_a, flex, leaf, na)
			_v(st, dd, col_b, flex, leaf, nd)
			_v(st, b, col_a, flex, leaf, nb)


func _sphere_cap(st: SurfaceTool, c: Vector3, r: float, sides: int, col: Color) -> void:
	_blob(st, c, r, Vector3(1, 0.7, 1), 0, col, col.lightened(0.1), 0.1, 0.0)


func _rock(st: SurfaceTool, c: Vector3, r: float, squash: Vector3, det: int, col: Color) -> void:
	_blob(st, c, r, squash, det, col.darkened(0.25), col.lightened(0.1), 0.0, 0.0)


## Лента (травинка, лист пальмы, прядь ивы): сужается к концу и изгибается.
func _strip(st: SurfaceTool, start: Vector3, dirv: Vector3, length: float, width: float, bend: float, c0: Color, c1: Color, leaf: float) -> void:
	var d := dirv.normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var segs := 4
	var prev_l := start
	var prev_r := start
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var p0 := start + d * length * t0 + Vector3(0, bend * t0 * t0 * length * 0.5, 0)
		var p1 := start + d * length * t1 + Vector3(0, bend * t1 * t1 * length * 0.5, 0)
		var w0 := width * (1.0 - t0 * 0.85) * 0.5
		var w1 := width * (1.0 - t1 * 0.85) * 0.5
		var l0 := p0 - side * w0
		var r0 := p0 + side * w0
		var l1 := p1 - side * w1
		var r1 := p1 + side * w1
		var ca := c0.lerp(c1, t0)
		var cb := c0.lerp(c1, t1)
		var nrm := side.cross(p1 - p0).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		nrm = (nrm + Vector3.UP * 0.6).normalized()
		_v(st, l0, ca, t0, leaf, nrm)
		_v(st, l1, cb, t1, leaf, nrm)
		_v(st, r1, cb, t1, leaf, nrm)
		_v(st, l0, ca, t0, leaf, nrm)
		_v(st, r1, cb, t1, leaf, nrm)
		_v(st, r0, ca, t0, leaf, nrm)


## Пучок травинок из центра.
func _tuft(st: SurfaceTool, blades: int, height: float, spread: float, c0: Color, c1: Color) -> void:
	for k in blades:
		var a := _rng.randf() * TAU
		var lean := _rng.randf_range(0.15, 0.5)
		var d := Vector3(cos(a) * lean, 1.0, sin(a) * lean)
		var base := Vector3(cos(a) * spread * 0.3 * _rng.randf(), 0, sin(a) * spread * 0.3 * _rng.randf())
		_strip(st, base, d, height * _rng.randf_range(0.7, 1.15), 0.07, -0.25, c0, c1, 1.0)


func _disc(st: SurfaceTool, r: float, sides: int, col: Color, y := 0.0) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		_v(st, Vector3(0, y, 0), col, 0.0, 1.0)
		_v(st, Vector3(cos(a1) * r, y, sin(a1) * r), col, 0.0, 1.0)
		_v(st, Vector3(cos(a0) * r, y, sin(a0) * r), col, 0.0, 1.0)
