class_name Planet
extends RefCounted
## Статичная география планеты. Генерируется из сида (PlanetGen) и во время игры не меняется:
## изменчивое состояние (население, склады, хозяева) живёт в World.
##
## Масштаб: 1 тайл = 2 м. Планета 32768×16384 тайлов (65×33 км). Подробные тайлы не хранятся
## целиком: рельеф — непрерывная функция от координат, а чанки 32×32 считаются лениво (ChunkGen)
## и кэшируются. Крупная сетка (macro, 64 тайла на клетку) — для карты, биомов, рек, дорог и поселений.

const TILE_M := 2.0
const CHUNK := 32
const MACRO := 64
## Как далеко от русла река влияет на рельеф (берега), в тайлах.
const BANK := 7.0
const ROAD_FLAT := 4.0
const CHUNK_CACHE := 900

## Тип поверхности тайла (материал земли и проходимость).
enum G { DEEP, SHALLOW, SAND, GRASS, DRYGRASS, DIRT, MUD, ROCK, CLIFF, SNOW, ASH, JUNGLE, FARMLAND, PAVED, GRAVEL, REDROCK }
## Биом крупной клетки (для карты и выбора растительности).
enum B { OCEAN, BEACH, MEADOW, FOREST, TAIGA, TUNDRA, STEPPE, DESERT, BADLANDS, SAVANNA, JUNGLE, SWAMP, MOUNTAIN, ALPINE, ASHLANDS }

const B_NAMES := ["Океан", "Побережье", "Луга", "Лес", "Тайга", "Тундра", "Степь", "Пустыня", "Бесплодные земли",
	"Саванна", "Джунгли", "Болота", "Горы", "Высокогорье", "Пепельные пустоши"]
## Стоимость шага по типу поверхности (0 — непроходимо).
const G_COST := [0.0, 3.0, 1.3, 1.0, 1.0, 1.0, 1.8, 1.4, 0.0, 1.6, 1.1, 1.4, 1.2, 0.85, 0.75, 1.3]

var seed_value := 0
var w := 32768
var h := 16384
var mw := 512
var mh := 256

var n_cont: FastNoiseLite
var n_hill: FastNoiseLite
var n_ridge: FastNoiseLite
var n_mask: FastNoiseLite
var n_detail: FastNoiseLite
var n_moist: FastNoiseLite
var n_temp: FastNoiseLite
var n_patch: FastNoiseLite
var n_forest: FastNoiseLite
var n_sea: FastNoiseLite

# --- крупная сетка (mw × mh) ---
var m_height := PackedFloat32Array()
var m_temp := PackedFloat32Array()
var m_moist := PackedFloat32Array()
var m_biome := PackedByteArray()
## Индекс фракции-хозяина территории в factions_order, 255 — ничья земля.
var m_owner := PackedByteArray()
## Близость к линии фронта (0..1): выжженная земля, воронки.
var m_ash := PackedFloat32Array()
## Расстояние до моря и до реки в клетках (0..15).
var m_sea := PackedByteArray()
var m_riv := PackedByteArray()
var factions_order: Array = []
## Номер связного куска суши в крупной сетке (0 — главный материк, 255 — море/острова).
var m_land := PackedByteArray()
## Перешейки, пришитые генератором: [a: Vector2, b: Vector2, полуширина в тайлах].
var bridges: Array = []

# --- линии ---
## Реки: {"pts": PackedVector2Array (тайлы), "hw": PackedFloat32Array (полуширина), "lvl": PackedFloat32Array (уровень воды, м)}
var rivers: Array = []
## Дороги: {"pts": PackedVector2Array, "hw": float, "kind": int (0 тропа, 1 дорога, 2 тракт), "a": id, "b": id, "len": float}
var roads: Array = []
var river_index: Dictionary = {}
var road_index: Dictionary = {}

# --- поселения ---
var sites: Dictionary = {}
var site_order: Array = []
var site_index: Dictionary = {}

# --- кэш чанков ---
var chunks: Dictionary = {}
var _chunk_order: Array = []
var mutex := Mutex.new()


func setup(world_seed: int, width: int, height: int) -> void:
	seed_value = world_seed
	w = width
	h = height
	mw = w / MACRO
	mh = h / MACRO
	n_cont = _noise(world_seed, 1.0 / 9000.0, 5)
	n_hill = _noise(world_seed + 11, 1.0 / 900.0, 3)
	n_ridge = _noise(world_seed + 23, 1.0 / 2600.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	n_mask = _noise(world_seed + 37, 1.0 / 7000.0, 2)
	n_detail = _noise(world_seed + 41, 1.0 / 90.0, 2)
	n_moist = _noise(world_seed + 53, 1.0 / 5500.0, 3)
	n_temp = _noise(world_seed + 67, 1.0 / 4000.0, 2)
	n_patch = _noise(world_seed + 79, 1.0 / 40.0, 2)
	n_forest = _noise(world_seed + 83, 1.0 / 260.0, 3)
	n_sea = _noise(world_seed + 97, 1.0 / 5200.0, 3)
	var cells := mw * mh
	m_height.resize(cells)
	m_temp.resize(cells)
	m_moist.resize(cells)
	m_biome.resize(cells)
	m_owner.resize(cells)
	m_owner.fill(255)
	m_ash.resize(cells)
	m_sea.resize(cells)
	m_riv.resize(cells)
	m_land.resize(cells)
	m_land.fill(255)


static func _noise(s: int, freq: float, octaves := 1, ftype := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = ftype if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	return n


# ---------------- непрерывный рельеф и климат ----------------

## «Материковость»: > 0 — суша, < 0 — море. Один большой материк (суперэллипс),
## шум рисует заливы, полуострова и острова, отдельный шум — внутренние моря.
## По краям карты всегда океан.
func continent(x: float, y: float) -> float:
	var nx := absf(x / w - 0.5) * 2.0
	var ny := absf(y / h - 0.5) * 2.0
	var shape := 1.0 - pow(pow(nx, 2.6) + pow(ny, 2.6), 1.0 / 2.6)
	var c := (shape - 0.2) * 0.95 + n_cont.get_noise_2d(x, y) * 0.8
	c -= smoothstep(0.36, 0.62, n_sea.get_noise_2d(x, y)) * 1.1
	var ex := minf(x, w - x) / (w * 0.06)
	var ey := minf(y, h - y) / (h * 0.09)
	var e := clampf(minf(ex, ey), 0.0, 1.0)
	c -= (1.0 - e) * (1.0 - e) * 1.2
	for b: Array in bridges:
		var a: Vector2 = b[0]
		var ab: Vector2 = b[1] - a
		var q := Vector2(x, y)
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		var hw: float = b[2]
		if d < hw * 2.0:
			# перешеек: поднимаем сушу до уровня берега с плавными краями
			c = maxf(c, 0.11 * (1.0 - smoothstep(hw * 0.6, hw * 2.0, d)))
	return c


## Высота поверхности в метрах без рек, дорог и поселений. 0 — уровень моря.
func height_base(x: float, y: float) -> float:
	var c := continent(x, y)
	if c <= 0.0:
		return c * 90.0 - 0.6
	var coast := smoothstep(0.0, 0.07, c)
	var land := smoothstep(0.0, 0.65, c)
	var hgt := 0.5 + land * land * 52.0
	hgt += n_hill.get_noise_2d(x, y) * (2.0 + land * 24.0) * coast
	var m := n_mask.get_noise_2d(x, y)
	if m > 0.06:
		var r := n_ridge.get_noise_2d(x, y)
		if r > 0.0:
			hgt += pow(r, 1.7) * smoothstep(0.06, 0.32, m) * 520.0 * smoothstep(0.08, 0.35, c)
	hgt += n_detail.get_noise_2d(x, y) * 0.9 * coast
	return hgt


## 0 — вечная мерзлота, 1 — тропики. Экватор чуть южнее центра карты.
func temperature(x: float, y: float, hgt: float) -> float:
	var lat := absf(y / h - 0.55) / 0.55
	return clampf(1.02 - lat * 1.02 + n_temp.get_noise_2d(x, y) * 0.22 - maxf(0.0, hgt) / 650.0, 0.0, 1.0)


func moisture(x: float, y: float) -> float:
	return clampf(0.5 + n_moist.get_noise_2d(x, y) * 0.85, 0.0, 1.0)


func snow_line(temp: float) -> float:
	return 110.0 + temp * 380.0


# ---------------- крупная сетка ----------------

func mi(mx: int, my: int) -> int:
	return clampi(my, 0, mh - 1) * mw + clampi(mx, 0, mw - 1)


func macro_of(tx: float, ty: float) -> Vector2i:
	return Vector2i(clampi(int(tx / MACRO), 0, mw - 1), clampi(int(ty / MACRO), 0, mh - 1))


## Билинейное значение поля крупной сетки в точке (тайлы).
func sample_macro(arr: PackedFloat32Array, x: float, y: float) -> float:
	var fx := x / MACRO - 0.5
	var fy := y / MACRO - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var ax := fx - x0
	var ay := fy - y0
	var a := arr[mi(x0, y0)]
	var b := arr[mi(x0 + 1, y0)]
	var c := arr[mi(x0, y0 + 1)]
	var d := arr[mi(x0 + 1, y0 + 1)]
	return lerpf(lerpf(a, b, ax), lerpf(c, d, ax), ay)


## То же для байтовых полей (расстояния до воды).
func sample_macro_bytes(arr: PackedByteArray, x: float, y: float) -> float:
	var fx := x / MACRO - 0.5
	var fy := y / MACRO - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var ax := fx - x0
	var ay := fy - y0
	var a := float(arr[mi(x0, y0)])
	var b := float(arr[mi(x0 + 1, y0)])
	var c := float(arr[mi(x0, y0 + 1)])
	var d := float(arr[mi(x0 + 1, y0 + 1)])
	return lerpf(lerpf(a, b, ax), lerpf(c, d, ax), ay)


func biome_at(tx: float, ty: float) -> int:
	return m_biome[mi(int(tx / MACRO), int(ty / MACRO))]


func owner_at(tx: float, ty: float) -> String:
	var o := m_owner[mi(int(tx / MACRO), int(ty / MACRO))]
	return "" if o == 255 else str(factions_order[o])


# ---------------- реки и дороги ----------------

## Ближайшая река: x — расстояние до оси, y — полуширина, z — уровень воды, w — 1, если река рядом.
func river_at(x: float, y: float) -> Vector4:
	var key := Vector2i(floori(x / CHUNK), floori(y / CHUNK))
	var list: PackedInt32Array = river_index.get(key, PackedInt32Array())
	var best := Vector4(INF, 0.0, 0.0, 0.0)
	var p := Vector2(x, y)
	for k in range(0, list.size(), 2):
		var r: Dictionary = rivers[list[k]]
		var pts: PackedVector2Array = r["pts"]
		var s := list[k + 1]
		var a := pts[s]
		var ab := pts[s + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			var hw: PackedFloat32Array = r["hw"]
			var lv: PackedFloat32Array = r["lvl"]
			best = Vector4(d, lerpf(hw[s], hw[s + 1], t), lerpf(lv[s], lv[s + 1], t), 1.0)
	return best


## Ближайшая дорога: x — расстояние, y — полуширина, z — вид дороги, w — 1, если дорога рядом.
func road_at(x: float, y: float) -> Vector4:
	var key := Vector2i(floori(x / CHUNK), floori(y / CHUNK))
	var list: PackedInt32Array = road_index.get(key, PackedInt32Array())
	var best := Vector4(INF, 0.0, 0.0, 0.0)
	var p := Vector2(x, y)
	for k in range(0, list.size(), 2):
		var r: Dictionary = roads[list[k]]
		var pts: PackedVector2Array = r["pts"]
		var s := list[k + 1]
		var a := pts[s]
		var ab := pts[s + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			best = Vector4(d, float(r["hw"]), float(r["kind"]), 1.0)
	return best


## Высота полотна дороги в точке: сглаженный рельеф без мелких кочек.
func road_height(x: float, y: float) -> float:
	var c := continent(x, y)
	if c <= 0.0:
		return 0.6
	var land := smoothstep(0.0, 0.65, c)
	var hgt := 0.5 + land * land * 52.0 + n_hill.get_noise_2d(x, y) * (2.0 + land * 24.0) * smoothstep(0.0, 0.07, c)
	return maxf(hgt, 0.6)


func build_indices() -> void:
	river_index.clear()
	road_index.clear()
	for i in rivers.size():
		var r: Dictionary = rivers[i]
		var pts: PackedVector2Array = r["pts"]
		var hw: PackedFloat32Array = r["hw"]
		for s in pts.size() - 1:
			var m := maxf(hw[s], hw[s + 1]) + BANK + 1.0
			_index_segment(river_index, pts[s], pts[s + 1], m, i, s)
	for i in roads.size():
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r["pts"]
		var m := float(r["hw"]) + ROAD_FLAT + 1.0
		for s in pts.size() - 1:
			_index_segment(road_index, pts[s], pts[s + 1], m, i, s)
	site_index.clear()
	for id in site_order:
		var st: Site = sites[id]
		# у деревень поля и причалы выходят за радиус
		var r := st.radius + (48 if not st.is_city() else 16)
		for cy in range(floori(float(st.center.y - r) / CHUNK), floori(float(st.center.y + r) / CHUNK) + 1):
			for cx in range(floori(float(st.center.x - r) / CHUNK), floori(float(st.center.x + r) / CHUNK) + 1):
				var key := Vector2i(cx, cy)
				if not site_index.has(key):
					site_index[key] = []
				site_index[key].append(st)


func _index_segment(index: Dictionary, a: Vector2, b: Vector2, margin: float, line: int, seg: int) -> void:
	var c0 := Vector2i(floori((minf(a.x, b.x) - margin) / CHUNK), floori((minf(a.y, b.y) - margin) / CHUNK))
	var c1 := Vector2i(floori((maxf(a.x, b.x) + margin) / CHUNK), floori((maxf(a.y, b.y) + margin) / CHUNK))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cy)
			if not index.has(key):
				index[key] = PackedInt32Array()
			var arr: PackedInt32Array = index[key]
			arr.append(line)
			arr.append(seg)
			index[key] = arr


# ---------------- поселения ----------------

## Поселение, в чьих границах точка (тайлы), или null.
func site_at(tx: float, ty: float) -> Site:
	var list: Array = site_index.get(Vector2i(floori(tx / CHUNK), floori(ty / CHUNK)), [])
	var best: Site = null
	var best_d := INF
	for st: Site in list:
		var d := Vector2(tx - st.center.x, ty - st.center.y).length()
		if d <= st.radius and d < best_d:
			best_d = d
			best = st
	return best


func sites_near_chunk(cx: int, cy: int) -> Array:
	return site_index.get(Vector2i(cx, cy), [])


# ---------------- чанки и тайлы ----------------

func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < w and ty < h


## Чанк по координатам чанка. Генерируется при первом обращении и кэшируется.
func chunk(cx: int, cy: int) -> Chunk:
	var key := Vector2i(cx, cy)
	mutex.lock()
	var c: Chunk = chunks.get(key)
	mutex.unlock()
	if c != null:
		return c
	c = ChunkGen.generate(self, cx, cy)
	mutex.lock()
	if chunks.has(key):
		c = chunks[key]
	else:
		chunks[key] = c
		_chunk_order.append(key)
		if _chunk_order.size() > CHUNK_CACHE:
			var old: Vector2i = _chunk_order.pop_front()
			chunks.erase(old)
	mutex.unlock()
	return c


func has_chunk(cx: int, cy: int) -> bool:
	mutex.lock()
	var ok := chunks.has(Vector2i(cx, cy))
	mutex.unlock()
	return ok


func chunk_of_tile(tx: int, ty: int) -> Chunk:
	return chunk(floori(float(tx) / CHUNK), floori(float(ty) / CHUNK))


func ground(tx: int, ty: int) -> int:
	if not in_bounds(tx, ty):
		return G.DEEP
	var c := chunk_of_tile(tx, ty)
	return c.ground[c.li(tx, ty)]


func is_passable(tx: int, ty: int) -> bool:
	if not in_bounds(tx, ty):
		return false
	var c := chunk_of_tile(tx, ty)
	return c.cost[c.li(tx, ty)] > 0


## Стоимость шага (0 — нельзя пройти).
func move_cost(tx: int, ty: int) -> float:
	if not in_bounds(tx, ty):
		return 0.0
	var c := chunk_of_tile(tx, ty)
	return c.cost[c.li(tx, ty)] / 10.0


## Высота поверхности земли (м) в произвольной точке — по вершинам чанка, как у меша.
func height_at(x: float, y: float) -> float:
	var tx := floori(x)
	var ty := floori(y)
	if not in_bounds(tx, ty):
		return -20.0
	var c := chunk_of_tile(tx, ty)
	return c.height_at(x, y)


## Уровень воды в тайле или -INF.
func water_at(tx: int, ty: int) -> float:
	if not in_bounds(tx, ty):
		return 0.0
	var c := chunk_of_tile(tx, ty)
	return c.water[c.li(tx, ty)]
