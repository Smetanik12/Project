class_name PlanetView
extends Node3D
## 3D-отображение планеты: подгружает чанки вокруг точки фокуса в рабочих потоках,
## в главном потоке только собирает узлы (не дольше BUDGET_MS за кадр). Дальние выгружает.
## Логики мира здесь нет — только чтение Planet.

const RADIUS := 7
const UNLOAD := 9
const MAX_TASKS := 4
const BUDGET_MS := 5.0
const CHUNK_M := Chunk.N * Planet.TILE_M

var planet: Planet
var atlas := GroundAtlas.new()
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var flora: FloraLib
## Vector2i -> Node3D
var loaded: Dictionary = {}
## Vector2i -> id задачи
var pending: Dictionary = {}
var _ready_list: Array = []
var _mutex := Mutex.new()
var _offsets: Array = []
## Тайл, вокруг которого грузим.
var focus_tile := Vector2.ZERO
var winter := 0.0


func setup(p: Planet) -> void:
	planet = p
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("ground_atlas", atlas.texture)
	terrain_mat.set_shader_parameter("noise_a", NoiseLib.noise_a())
	terrain_mat.set_shader_parameter("noise_b", NoiseLib.noise_b())
	terrain_mat.set_shader_parameter("noise_c", NoiseLib.noise_c())
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("noise_a", NoiseLib.noise_a())
	water_mat.set_shader_parameter("noise_c", NoiseLib.noise_c())
	flora = FloraLib.new()
	for dy in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			if dx * dx + dy * dy <= RADIUS * RADIUS + 1:
				_offsets.append(Vector2i(dx, dy))
	_offsets.sort_custom(func(a: Vector2i, b: Vector2i): return a.length_squared() < b.length_squared())


func set_winter(w: float) -> void:
	winter = w
	terrain_mat.set_shader_parameter("winter", w)
	flora.set_winter(w)


## Всё в радиусе загружено и в очереди пусто (для скриншотов и тестов).
func settled() -> bool:
	if not pending.is_empty():
		return false
	var fc := _focus_chunk()
	for off: Vector2i in _offsets:
		var key: Vector2i = fc + off
		if _in_planet(key) and not loaded.has(key):
			return false
	return true


func _focus_chunk() -> Vector2i:
	return Vector2i(floori(focus_tile.x / Chunk.N), floori(focus_tile.y / Chunk.N))


func _in_planet(key: Vector2i) -> bool:
	return key.x >= 0 and key.y >= 0 and key.x < planet.w / Chunk.N and key.y < planet.h / Chunk.N


func _process(_delta: float) -> void:
	if planet == null:
		return
	var fc := _focus_chunk()
	# выгрузка дальних
	for key: Vector2i in loaded.keys():
		if (key - fc).length_squared() > UNLOAD * UNLOAD:
			loaded[key].queue_free()
			loaded.erase(key)
	# новые задачи — ближние первыми
	for off: Vector2i in _offsets:
		if pending.size() >= MAX_TASKS:
			break
		var key: Vector2i = fc + off
		if not _in_planet(key) or loaded.has(key) or pending.has(key):
			continue
		pending[key] = WorkerThreadPool.add_task(_build.bind(key))
	_integrate()
	atlas.flush()


## Рабочий поток: данные чанка и массивы мешей.
func _build(key: Vector2i) -> void:
	var c := planet.chunk(key.x, key.y)
	var res := {
		"key": key, "chunk": c,
		"terrain": ChunkMesher.terrain_arrays(c),
		"water": ChunkMesher.water_arrays(c) if c.has_water or c.water.size() > 0 else [],
		"atlas": GroundAtlas.chunk_bytes(c),
		"flora": flora.instances(c),
	}
	_mutex.lock()
	_ready_list.append(res)
	_mutex.unlock()


## Главный поток: собираем узлы готовых чанков, пока не вышли из бюджета кадра.
func _integrate() -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < BUDGET_MS * 1000.0:
		_mutex.lock()
		var res: Dictionary = _ready_list.pop_front() if not _ready_list.is_empty() else {}
		_mutex.unlock()
		if res.is_empty():
			break
		var key: Vector2i = res["key"]
		if pending.has(key):
			WorkerThreadPool.wait_for_task_completion(pending[key])
			pending.erase(key)
		if (key - _focus_chunk()).length_squared() > UNLOAD * UNLOAD or loaded.has(key):
			continue
		var c: Chunk = res["chunk"]
		var node := Node3D.new()
		node.name = "Chunk_%d_%d" % [key.x, key.y]
		node.position = Vector3(c.ox * Planet.TILE_M, 0.0, c.oy * Planet.TILE_M)
		var tm := ArrayMesh.new()
		tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["terrain"])
		tm.custom_aabb = AABB(Vector3(0, c.min_h - 8.0, 0), Vector3(CHUNK_M, c.max_h - c.min_h + 10.0, CHUNK_M))
		var ti := MeshInstance3D.new()
		ti.mesh = tm
		ti.material_override = terrain_mat
		node.add_child(ti)
		var wa: Array = res["water"]
		if not wa.is_empty():
			var wm := ArrayMesh.new()
			wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
			var wi := MeshInstance3D.new()
			wi.mesh = wm
			wi.material_override = water_mat
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(wi)
		flora.attach(node, res["flora"], key - _focus_chunk())
		atlas.put(c, res["atlas"])
		add_child(node)
		loaded[key] = node


func _exit_tree() -> void:
	for key in pending:
		WorkerThreadPool.wait_for_task_completion(pending[key])
	pending.clear()
