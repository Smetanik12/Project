class_name LayoutGen
extends RefCounted
## Планировка поселений: дома, мастерские, поля, причалы, стены, башни, окопы.
## Малые поселения (деревни, хутора, рудники, форты, лагеря, руины) строятся целиком
## на локальной сетке занятости — постройки никогда не налезают друг на друга, на воду,
## дороги и кручи. Города строятся лениво по «суперкварталам» вокруг игрока: улицы — сетка,
## кварталы делятся на участки, на каждом участке один дом, поэтому пересечений нет по построению.
##
## Постройка — словарь:
##   t      вид ("house", "tower", "field", "pier", "wall", ...)
##   r      Rect2i — занятые тайлы
##   fl     этажей (0 — плоское: поле, площадь)
##   roof   "gable", "hip", "flat", "dome", "thatch", "shed", "none"
##   face   куда смотрит фасад: 0 юг (+y), 1 восток (+x), 2 север (-y), 3 запад (-x)
##   door   тайл перед дверью (снаружи) или (-1, -1)
##   solid  перекрывает ли тайлы для ходьбы
##   style  культура (архитектура): empire, front, guild, syndicate, scav, free
##   v      вариант (для разнообразия отрисовки)
##   posts  Array[Vector3]: места, где можно стоять наверху (x, y в тайлах, высота в м)
##   cap    сколько человек живёт
##   work   кто здесь работает (профессия) или ""
##   pts    PackedVector2Array для линейных построек (окоп, проволока)
##   lvl    высота основания (м), если не равна высоте площадки (причалы над водой)

const FLOOR_M := 3.2
const NO_DOOR := Vector2i(-1, -1)

## Участки: тайл свободен / дорога / вода / круча / занят / поле / тропа / вне поселения.
const FREE := 0
const ROAD := 1
const WATER := 2
const STEEP := 3
const BUILT := 4
const FIELD := 5
const PATH := 6
const OUT := 7

const FACE_DIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

## Общественные здания городов: вид, доля участков, минимальная техника, районы, этажи.
## Узлы связи, ПВО, склады, гарнизоны и штабы — цели орбитальных ударов.
const CIVIC := [
	["school", 0.03, 1, ["mid", "high", "low"], [2, 3]],
	["police", 0.012, 2, ["mid", "high", "low", "slums"], [2, 4]],
	["hospital", 0.008, 2, ["mid", "high"], [3, 8]],
	["bank", 0.006, 2, ["towers", "mid", "high"], [3, 6]],
	["temple", 0.008, 0, ["mid", "low", "high"], [2, 3]],
	["hotel", 0.02, 2, ["towers", "mid", "high"], [4, 14]],
	["bar", 0.03, 0, ["mid", "low", "slums", "industrial"], [1, 2]],
	["fire_station", 0.006, 2, ["mid", "low"], [2, 2]],
	["prison", 0.002, 2, ["industrial", "low"], [2, 3]],
	["power_plant", 0.006, 2, ["industrial"], [2, 3]],
	["water_works", 0.004, 2, ["industrial", "low"], [1, 2]],
	["comm_center", 0.005, 2, ["mid", "high", "industrial"], [3, 5]],
	["aa_battery", 0.004, 3, ["mid", "industrial", "low"], [1, 1]],
	["depot", 0.012, 1, ["industrial"], [1, 2]],
	["garrison", 0.006, 2, ["mid", "low", "industrial"], [2, 3]],
	["theater", 0.004, 2, ["towers", "mid", "high"], [3, 4]],
	["guild_hall", 0.004, 2, ["towers", "mid"], [4, 8]],
	["clinic", 0.012, 1, ["low", "mid", "slums"], [1, 2]],
	["market_hall", 0.006, 1, ["mid", "low"], [1, 2]],
]
## Кто работает в общественном здании.
const CIVIC_WORK := {"school": "official", "police": "guard", "hospital": "medic", "bank": "merchant", "temple": "official",
	"hotel": "barkeep", "bar": "barkeep", "fire_station": "laborer", "prison": "guard", "power_plant": "worker",
	"water_works": "worker", "comm_center": "official", "aa_battery": "soldier", "depot": "laborer", "garrison": "soldier",
	"theater": "barkeep", "guild_hall": "merchant", "clinic": "medic", "market_hall": "merchant", "city_hall": "official"}


## Постройки поселения, задевающие прямоугольник тайлов.
static func structures_in(p: Planet, st: Site, rect: Rect2i) -> Array:
	var out: Array = []
	if st.is_city():
		_city_collect(p, st, rect, out)
		return out
	ensure_small(p, st)
	for s: Dictionary in st.layout:
		if (s["r"] as Rect2i).intersects(rect):
			out.append(s)
	return out


## Все постройки малого поселения (генерирует при первом обращении).
static func ensure_small(p: Planet, st: Site) -> void:
	st.mutex.lock()
	if not st.layout_ready:
		st.layout = _small(p, st)
		st.layout_ready = true
	st.mutex.unlock()


# ======================================================================
#  Сетка занятости для малых поселений
# ======================================================================

class Grid:
	var ox := 0
	var oy := 0
	var n := 0
	var c := PackedByteArray()
	## Расстояние до дороги/тропы в тайлах (до 30), для выбора мест вдоль улиц.
	var road_d := PackedByteArray()

	func _init(center: Vector2i, r: int) -> void:
		ox = center.x - r
		oy = center.y - r
		n = r * 2 + 1
		c.resize(n * n)
		road_d.resize(n * n)

	func at(x: int, y: int) -> int:
		var lx := x - ox
		var ly := y - oy
		if lx < 0 or ly < 0 or lx >= n or ly >= n:
			return OUT
		return c[ly * n + lx]

	func put(x: int, y: int, v: int) -> void:
		var lx := x - ox
		var ly := y - oy
		if lx >= 0 and ly >= 0 and lx < n and ly < n:
			c[ly * n + lx] = v

	func rd(x: int, y: int) -> int:
		var lx := x - ox
		var ly := y - oy
		if lx < 0 or ly < 0 or lx >= n or ly >= n:
			return 30
		return road_d[ly * n + lx]

	## Прямоугольник свободен, а вокруг него на margin тайлов нет построек, полей, воды и края.
	func free_rect(r: Rect2i, margin: int) -> bool:
		for y in range(r.position.y - margin, r.end.y + margin):
			for x in range(r.position.x - margin, r.end.x + margin):
				var v := at(x, y)
				if x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y:
					if v != FREE:
						return false
				elif v == BUILT or v == FIELD or v == WATER or v == OUT:
					return false
		return true

	func fill(r: Rect2i, v: int) -> void:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				put(x, y, v)

	func walkable(x: int, y: int) -> bool:
		var v := at(x, y)
		return v == FREE or v == ROAD or v == PATH

	## Расстояния до дорог и троп волной (по 4 соседям).
	func compute_road_distance() -> void:
		road_d.fill(30)
		var q := PackedInt32Array()
		for i in n * n:
			if c[i] == ROAD or c[i] == PATH:
				road_d[i] = 0
				q.append(i)
		var head := 0
		while head < q.size():
			var i := q[head]
			head += 1
			var d := road_d[i]
			if d >= 29:
				continue
			var x := i % n
			var y := i / n
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= n or ny >= n:
					continue
				var j := ny * n + nx
				if road_d[j] > d + 1:
					road_d[j] = d + 1
					q.append(j)


## Размечает сетку: вода, дороги, кручи и всё за пределами круга.
## Высоты считаются один раз на вершину (n+1)², как у меша рельефа.
static func _scan(p: Planet, st: Site, g: Grid, r_out: int, flat_r: float) -> void:
	var vn := g.n + 1
	var vh := PackedFloat32Array()
	vh.resize(vn * vn)
	var lim := (r_out + 2) * (r_out + 2)
	for vy in vn:
		for vx in vn:
			var x := g.ox + vx
			var y := g.oy + vy
			var dx := x - st.center.x
			var dy := y - st.center.y
			if dx * dx + dy * dy > lim:
				continue
			vh[vy * vn + vx] = surface(p, st, flat_r, float(x), float(y))
	for ly in g.n:
		for lx in g.n:
			var x := g.ox + lx
			var y := g.oy + ly
			var dx := x - st.center.x
			var dy := y - st.center.y
			var i := ly * g.n + lx
			if dx * dx + dy * dy > r_out * r_out:
				g.c[i] = OUT
				continue
			var fx := x + 0.5
			var fy := y + 0.5
			var rv := p.river_at(fx, fy)
			if rv.w > 0.0 and rv.x < rv.y + 1.6:
				g.c[i] = WATER
				continue
			var h0 := vh[ly * vn + lx]
			var h1 := vh[ly * vn + lx + 1]
			var h2 := vh[(ly + 1) * vn + lx]
			var h3 := vh[(ly + 1) * vn + lx + 1]
			if (h0 + h1 + h2 + h3) * 0.25 < 0.25:
				g.c[i] = WATER
				continue
			var rd := p.road_at(fx, fy)
			if rd.w > 0.0 and rd.x < rd.y + 0.6:
				g.c[i] = ROAD
				continue
			# крутизна по итоговому рельефу (с площадкой и берегами рек), как у ChunkGen
			if maxf(maxf(h0, h1), maxf(h2, h3)) - minf(minf(h0, h1), minf(h2, h3)) > 1.2:
				g.c[i] = STEEP


## Высота вершины так же, как её получит ChunkGen (площадка поселения + русла и берега рек),
## без окопов и воронок. Нужна, чтобы не строить на обрывах у реки.
static func surface(p: Planet, st: Site, flat_r: float, x: float, y: float) -> float:
	var h := p.height_base(x, y)
	var orig := h
	var d := Vector2(x - st.center.x, y - st.center.y).length()
	if d < flat_r + 12.0 and orig > -0.4:
		h = lerpf(h, st.base_h, 1.0 - smoothstep(flat_r, flat_r + 12.0, d))
	var rv := p.river_at(x, y)
	if rv.w > 0.0:
		if rv.x < rv.y:
			var k := rv.x / rv.y
			h = minf(h, rv.z - (0.45 + (0.8 + rv.y * 0.22) * (1.0 - k * k)))
		elif rv.x < rv.y + Planet.BANK and orig > -0.4:
			var t := (rv.x - rv.y) / Planet.BANK
			var bank := rv.z + 0.25 + t * 1.4
			if h > bank:
				h = lerpf(bank, h, smoothstep(0.0, 1.0, t))
			h = maxf(h, rv.z + 0.18)
	return h


## Убирает постройки, к дверям которых нельзя дойти от центра (по проходимым клеткам сетки).
static func _prune_unreachable(g: Grid, st: Site, out: Array) -> void:
	var start := Vector2i(-1, -1)
	for rr in 40:
		if start.x >= 0:
			break
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var t := st.center + Vector2i(dx, dy)
				if start.x < 0 and _walk(g, t):
					start = t
	if start.x < 0:
		return
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for o: Vector2i in FACE_DIRS:
			var nb := c + o
			if not seen.has(nb) and _walk(g, nb):
				seen[nb] = true
				q.append(nb)
	var keep: Array = []
	for s: Dictionary in out:
		var door: Vector2i = s.get("door", NO_DOOR)
		if door.x >= 0 and not seen.has(door):
			continue
		keep.append(s)
	out.assign(keep)


static func _walk(g: Grid, t: Vector2i) -> bool:
	var v := g.at(t.x, t.y)
	return v == FREE or v == ROAD or v == PATH or v == FIELD


# ======================================================================
#  Малые поселения
# ======================================================================

static func _small(p: Planet, st: Site) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = st.site_seed
	var out: Array = []
	var margin := 46 if st.kind in ["village", "hamlet"] else 8
	var g := Grid.new(st.center, st.radius + margin)
	_scan(p, st, g, st.radius + margin, flat_radius(st))
	g.compute_road_distance()
	match st.kind:
		"village", "hamlet":
			_village(p, st, g, rng, out)
		"mine":
			_mine(p, st, g, rng, out)
		"fort":
			_fort(p, st, g, rng, out)
		"trench":
			_trench(p, st, g, rng, out)
		"camp":
			_camp(p, st, g, rng, out)
		"hideout":
			_hideout(p, st, g, rng, out)
		"ruins":
			_ruins(p, st, g, rng, out)
		"cave":
			_cave(p, st, g, rng, out)
		"wreck":
			_wreck(p, st, g, rng, out)
	_prune_unreachable(g, st, out)
	for k in out.size():
		out[k]["id"] = k
	return out


## Радиус, внутри которого рельеф выравнивается до площадки поселения.
static func flat_radius(st: Site) -> float:
	match st.kind:
		"village", "hamlet":
			return st.core * 1.15
		"trench", "hideout", "ruins", "cave":
			return st.radius * 0.6
		"capital", "city", "town":
			return float(st.radius)
	return st.radius * 0.85


static func _new(t: String, r: Rect2i, st: Site, rng: RandomNumberGenerator) -> Dictionary:
	return {"t": t, "r": r, "fl": 1, "roof": "gable", "face": 0, "door": NO_DOOR, "solid": true,
		"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "", "lvl": NAN}


## Ставит здание размером из диапазона около точки. Возвращает словарь постройки или {}.
## near_road — сколько тайлов от дороги/тропы считать идеальным (-1 — не важно).
static func _place(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, t: String,
		smin: Vector2i, smax: Vector2i, around: Vector2, spread: float, near_road: int, tries := 40) -> Dictionary:
	var best_rect := Rect2i()
	var best_score := -INF
	var found := false
	for k in tries:
		var size := Vector2i(rng.randi_range(smin.x, smax.x), rng.randi_range(smin.y, smax.y))
		if rng.randf() < 0.5:
			size = Vector2i(size.y, size.x)
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var c := around + Vector2(cos(a), sin(a)) * d
		var rect := Rect2i(Vector2i(c) - size / 2, size)
		if not g.free_rect(rect, 1):
			continue
		var score := -d * 0.05
		if near_road >= 0:
			var rdist := _rect_road_distance(g, rect)
			score -= absf(rdist - near_road) * 1.5
		if score > best_score:
			best_score = score
			best_rect = rect
			found = true
	if not found:
		return {}
	var face := _face_toward_road(g, best_rect, around)
	var door := _door_tile(best_rect, face)
	if not g.walkable(door.x, door.y):
		# дверь упёрлась в препятствие — пробуем другие стороны
		var ok := false
		for f in 4:
			var d2 := _door_tile(best_rect, f)
			if g.walkable(d2.x, d2.y):
				face = f
				door = d2
				ok = true
				break
		if not ok:
			return {}
	g.fill(best_rect, BUILT)
	var s := _new(t, best_rect, st, rng)
	s["face"] = face
	s["door"] = door
	out.append(s)
	return s


## Разворачивает здание фасадом в сторону face, если дверь там проходима.
static func _set_face(g: Grid, s: Dictionary, face: int) -> void:
	var d := _door_tile(s["r"], face)
	if g.walkable(d.x, d.y):
		s["face"] = face
		s["door"] = d


static func _rect_road_distance(g: Grid, r: Rect2i) -> int:
	var best := 30
	for x in range(r.position.x - 1, r.end.x + 1):
		best = mini(best, mini(g.rd(x, r.position.y - 1), g.rd(x, r.end.y)))
	for y in range(r.position.y, r.end.y):
		best = mini(best, mini(g.rd(r.position.x - 1, y), g.rd(r.end.x, y)))
	return best


## Сторона, у которой ближе всего дорога (а без дорог — к центру поселения).
static func _face_toward_road(g: Grid, r: Rect2i, center: Vector2) -> int:
	var best := 0
	var best_d := 1000.0
	for f in 4:
		var t := _door_tile(r, f)
		var d := float(g.rd(t.x, t.y))
		if d >= 30:
			d = 40.0 + Vector2(t).distance_to(center) * 0.1
		if d < best_d:
			best_d = d
			best = f
	return best


static func _door_tile(r: Rect2i, face: int) -> Vector2i:
	match face:
		0:
			return Vector2i(r.position.x + r.size.x / 2, r.end.y)
		1:
			return Vector2i(r.end.x, r.position.y + r.size.y / 2)
		2:
			return Vector2i(r.position.x + r.size.x / 2, r.position.y - 1)
	return Vector2i(r.position.x - 1, r.position.y + r.size.y / 2)


## Тропинка от двери до ближайшей дороги или тропы (по убыванию расстояния до дороги).
static func _path_from(g: Grid, start: Vector2i, out: Array, st: Site) -> void:
	var cur := start
	var pts := PackedVector2Array([Vector2(cur) + Vector2(0.5, 0.5)])
	for step in 60:
		var d := g.rd(cur.x, cur.y)
		if d == 0 or d >= 30:
			break
		var next := cur
		for o: Vector2i in FACE_DIRS:
			var q := cur + o
			if g.rd(q.x, q.y) < d and g.walkable(q.x, q.y):
				next = q
				break
		if next == cur:
			break
		if g.at(next.x, next.y) == FREE:
			g.put(next.x, next.y, PATH)
		cur = next
		pts.append(Vector2(cur) + Vector2(0.5, 0.5))
	if pts.size() >= 2:
		out.append({"t": "path", "r": _bounds(pts, 1), "fl": 0, "roof": "none", "face": 0, "door": NO_DOOR,
			"solid": false, "style": st.culture, "v": 0, "posts": [], "cap": 0, "work": "", "pts": pts, "lvl": NAN})


static func _bounds(pts: PackedVector2Array, grow: int) -> Rect2i:
	var mn := pts[0]
	var mx := pts[0]
	for q in pts:
		mn = mn.min(q)
		mx = mx.max(q)
	return Rect2i(Vector2i(mn.floor()) - Vector2i(grow, grow), Vector2i((mx - mn).ceil()) + Vector2i(grow * 2 + 1, grow * 2 + 1))


static func _count(st: Site, role: String) -> int:
	return int(st.pops.get(role, 0))


# ---------------- деревня и хутор ----------------

static func _village(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var core := float(st.core)
	var pop := st.population()
	var hamlet := st.kind == "hamlet"
	# площадь с колодцем и амбаром — сюда сносят добытое
	var granary := _place(g, rng, st, out, "granary", Vector2i(6, 5), Vector2i(8, 6), c, 6.0, 2)
	if not granary.is_empty():
		granary["work"] = "store"
		_path_from(g, granary["door"], out, st)
	var well := _place(g, rng, st, out, "well", Vector2i(2, 2), Vector2i(2, 2), c, 8.0, 1)
	if not well.is_empty():
		well["fl"] = 0
		well["roof"] = "none"
	if not hamlet:
		if pop > 100:
			var tav := _place(g, rng, st, out, "tavern", Vector2i(8, 6), Vector2i(10, 7), c, core * 0.4, 2)
			if not tav.is_empty():
				tav["work"] = "barkeep"
				tav["cap"] = 2
				_path_from(g, tav["door"], out, st)
		if _count(st, "smith") > 0:
			var sm := _place(g, rng, st, out, "smithy", Vector2i(6, 5), Vector2i(7, 6), c, core * 0.6, 2)
			if not sm.is_empty():
				sm["work"] = "smith"
				_path_from(g, sm["door"], out, st)
		if _count(st, "leader") > 0:
			var el := _place(g, rng, st, out, "hall", Vector2i(8, 6), Vector2i(10, 8), c, core * 0.4, 2)
			if not el.is_empty():
				el["work"] = "leader"
				el["fl"] = 2
				_path_from(g, el["door"], out, st)
		if _count(st, "medic") > 0:
			var md := _place(g, rng, st, out, "clinic", Vector2i(6, 5), Vector2i(7, 6), c, core * 0.6, 2)
			if not md.is_empty():
				md["work"] = "medic"
				_path_from(g, md["door"], out, st)
		if _count(st, "tailor") > 0:
			var tl := _place(g, rng, st, out, "workshop", Vector2i(6, 5), Vector2i(7, 6), c, core * 0.7, 2)
			if not tl.is_empty():
				tl["work"] = "tailor"
				_path_from(g, tl["door"], out, st)
		if pop > 450 and rng.randf() < 0.6:
			var ch := _place(g, rng, st, out, "chapel", Vector2i(7, 10), Vector2i(8, 12), c, core * 0.5, 2)
			if not ch.is_empty():
				ch["fl"] = 2
				_path_from(g, ch["door"], out, st)
		if _count(st, "guard") > 0:
			for k in clampi(_count(st, "guard") / 6, 1, 3):
				var tw := _place(g, rng, st, out, "watchtower", Vector2i(3, 3), Vector2i(3, 3), c, core * 0.95, -1)
				if not tw.is_empty():
					tw["fl"] = 3
					tw["roof"] = "hip"
					tw["work"] = "guard"
					var rr: Rect2i = tw["r"]
					tw["posts"] = [Vector3(rr.position.x + 1.5, rr.position.y + 1.5, 7.6)]
	# дома: семья ~5 человек
	var houses := clampi(int(ceil(pop / 5.0)), 2, 420)
	var made := 0
	for k in houses:
		var spread := core * (0.55 + 0.45 * float(k) / houses)
		var h := _place(g, rng, st, out, "house", Vector2i(5, 4), Vector2i(7, 6), c, spread, 3, 24)
		if h.is_empty():
			continue
		made += 1
		h["cap"] = 5
		h["roof"] = "thatch" if st.tech <= 1 and rng.randf() < 0.55 else "gable"
		if rng.randf() < 0.2:
			h["fl"] = 2
		_path_from(g, h["door"], out, st)
	# сараи и амбары у полей
	var farmers := _count(st, "farmer")
	for k in clampi(farmers / 8, 0, 14):
		var b := _place(g, rng, st, out, "barn", Vector2i(6, 5), Vector2i(8, 7), c, core * 1.05, 3, 20)
		if not b.is_empty():
			b["work"] = "farmer"
			_path_from(g, b["door"], out, st)
	# коптильни и сушилки у рыбаков
	var fishers := _count(st, "fisher")
	if fishers > 0:
		_piers(p, st, g, rng, out, fishers)
	if _count(st, "woodcutter") > 0:
		var wy := _place(g, rng, st, out, "woodyard", Vector2i(6, 4), Vector2i(8, 5), c, core * 1.1, 3, 20)
		if not wy.is_empty():
			wy["work"] = "woodcutter"
			wy["fl"] = 0
			wy["roof"] = "shed"
	# поля: ~22 тайла на фермера
	var want := farmers * 22
	var have := 0
	for k in 220:
		if have >= want:
			break
		var f := _field(g, rng, st, out, c, core * 0.95, float(st.radius) + 30.0)
		if f.is_empty():
			continue
		have += (f["r"] as Rect2i).get_area()
	# выпасы
	var herders := _count(st, "herder")
	for k in clampi(herders / 3, 0, 6):
		_pasture(g, rng, st, out, c, core, float(st.radius) + 26.0)
	# мелочь: стога, поленницы, телеги, бочки
	for k in clampi(made / 3, 1, 50):
		var t: String = ["haystack", "woodpile", "cart", "barrels", "crates", "bench"][rng.randi() % 6]
		var pr := _place(g, rng, st, out, t, Vector2i(1, 1), Vector2i(2, 2), c, core, 2, 12)
		if not pr.is_empty():
			pr["fl"] = 0
			pr["roof"] = "none"
			pr["door"] = NO_DOOR


## Поле: прямоугольник в кольце за домами, не на дороге, воде и круче.
static func _field(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, c: Vector2, r0: float, r1: float) -> Dictionary:
	for k in 16:
		var size := Vector2i(rng.randi_range(8, 20), rng.randi_range(6, 14))
		var a := rng.randf() * TAU
		var d := lerpf(r0, r1, sqrt(rng.randf()))
		var cc := c + Vector2(cos(a), sin(a)) * d
		var rect := Rect2i(Vector2i(cc) - size / 2, size)
		if not g.free_rect(rect, 1):
			continue
		g.fill(rect, FIELD)
		var crops := _crops_for(st)
		var f := {"t": "field", "r": rect, "fl": 0, "roof": "none", "face": rng.randi() % 2, "door": NO_DOOR,
			"solid": false, "style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "farmer",
			"crop": crops[rng.randi() % crops.size()], "lvl": NAN}
		out.append(f)
		return f
	return {}


static func _crops_for(st: Site) -> Array:
	return ["wheat", "barley", "potato", "cabbage", "corn", "flax", "sunflower"]


## Выпас с изгородью и калиткой.
static func _pasture(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, c: Vector2, r0: float, r1: float) -> void:
	for k in 14:
		var size := Vector2i(rng.randi_range(12, 20), rng.randi_range(10, 16))
		var a := rng.randf() * TAU
		var d := lerpf(r0, r1, sqrt(rng.randf()))
		var cc := c + Vector2(cos(a), sin(a)) * d
		var rect := Rect2i(Vector2i(cc) - size / 2, size)
		if not g.free_rect(rect, 1):
			continue
		g.fill(rect, FIELD)
		var face := _face_toward_road(g, rect, c)
		var gate: Vector2i = _door_tile(rect, face) - FACE_DIRS[face]
		out.append({"t": "pasture", "r": rect, "fl": 0, "roof": "none", "face": face, "door": _door_tile(rect, face),
			"gate": gate, "solid": false, "fence": true, "style": st.culture, "v": rng.randi() % 1000, "posts": [],
			"cap": 0, "work": "herder", "animals": ["sheep", "cow", "goat"][rng.randi() % 3], "lvl": NAN})
		return


## Причалы: ищем берег по лучам от центра, причал уходит в воду по оси, к нему лодки.
static func _piers(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array, fishers: int) -> void:
	var c := Vector2(st.center)
	var want := clampi(int(ceil(fishers / 12.0)), 1, 4)
	var made := 0
	var base_a := st.dir.angle()
	for k in 24:
		if made >= want:
			break
		var a := base_a + (float(k) * 0.9 if k % 2 == 0 else -float(k) * 0.9) * 0.25
		var dirv := Vector2.from_angle(a)
		# ось причала — ближайшее из 4 направлений
		var face := 0
		if absf(dirv.x) > absf(dirv.y):
			face = 1 if dirv.x > 0.0 else 3
		else:
			face = 0 if dirv.y > 0.0 else 2
		var step: Vector2i = FACE_DIRS[face]
		var shore := Vector2i(-99999, 0)
		var q := Vector2i(c)
		for s in st.radius + 44:
			q += step
			var v := g.at(q.x, q.y)
			if v == OUT:
				break
			if v == WATER:
				shore = q - step
				break
		if shore.x == -99999 or not g.walkable(shore.x, shore.y):
			continue
		# длина: пока под причалом вода, но не дальше середины реки
		var length := 0
		var w := q
		for s in 9:
			if g.at(w.x, w.y) != WATER:
				break
			length += 1
			w += step
		length = clampi(length - 1, 0, 8)
		if length < 3:
			continue
		var start := shore + step
		var rect := _axis_rect(start, step, length, 2)
		var clash := false
		for y in range(rect.position.y - 1, rect.end.y + 1):
			for x in range(rect.position.x - 1, rect.end.x + 1):
				if g.at(x, y) == BUILT:
					clash = true
		if clash:
			continue
		g.fill(rect, BUILT)
		var lvl := _water_level_near(p, Vector2(start) + Vector2(step) * (length * 0.5))
		var tip := Vector2(start) + Vector2(step) * (length - 0.5) + Vector2(0.5, 0.5)
		out.append({"t": "pier", "r": rect, "fl": 0, "roof": "none", "face": face, "door": shore, "solid": false,
			"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "fisher",
			"spot": tip, "lvl": lvl + 0.6})
		made += 1
		g.put(shore.x, shore.y, PATH)
		_path_from(g, shore, out, st)
		# сушилка для рыбы у берега
		var rack := _place(g, rng, st, out, "fishrack", Vector2i(2, 1), Vector2i(3, 2), Vector2(shore) - Vector2(step) * 3.0, 3.0, -1, 10)
		if not rack.is_empty():
			rack["fl"] = 0
			rack["roof"] = "none"
			rack["door"] = NO_DOOR
			rack["work"] = "fisher"


static func _axis_rect(start: Vector2i, step: Vector2i, length: int, width: int) -> Rect2i:
	var end := start + step * (length - 1)
	var mn := Vector2i(mini(start.x, end.x), mini(start.y, end.y))
	var mx := Vector2i(maxi(start.x, end.x), maxi(start.y, end.y))
	var r := Rect2i(mn, mx - mn + Vector2i.ONE)
	if step.x != 0:
		r.size.y = width
		r.position.y -= width / 2
	else:
		r.size.x = width
		r.position.x -= width / 2
	return r


static func _water_level_near(p: Planet, q: Vector2) -> float:
	var rv := p.river_at(q.x + 0.5, q.y + 0.5)
	if rv.w > 0.0 and rv.x < rv.y + 2.0:
		return rv.z
	return 0.0


# ---------------- рудник ----------------

static func _mine(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var r := float(st.radius)
	# где гора: самая высокая точка на кольце
	var best_a := 0.0
	var best_h := -INF
	for k in 24:
		var a := TAU * k / 24.0
		var q := c + Vector2.from_angle(a) * r * 1.15
		var hh := p.height_base(q.x, q.y)
		if hh > best_h:
			best_h = hh
			best_a = a
	var to_mtn := Vector2.from_angle(best_a)
	st.dir = to_mtn
	var face := _face_of(-to_mtn)
	var ent := _place(g, rng, st, out, "mine_entrance", Vector2i(6, 4), Vector2i(6, 4), c + to_mtn * r * 0.7, 4.0, -1, 30)
	if not ent.is_empty():
		_set_face(g, ent, face)
		ent["work"] = "miner"
		ent["fl"] = 2
		ent["roof"] = "flat"
		var head := _place(g, rng, st, out, "headframe", Vector2i(4, 4), Vector2i(4, 4), c + to_mtn * r * 0.5, 6.0, -1, 20)
		if not head.is_empty():
			head["fl"] = 5
			head["roof"] = "none"
		for k in 3:
			var pile := _place(g, rng, st, out, "orepile", Vector2i(3, 3), Vector2i(4, 3), c + to_mtn * r * 0.45, 9.0, -1, 14)
			if not pile.is_empty():
				pile["fl"] = 0
				pile["roof"] = "none"
				pile["door"] = NO_DOOR
	var store := _place(g, rng, st, out, "warehouse", Vector2i(8, 6), Vector2i(10, 7), c, 6.0, 2)
	if not store.is_empty():
		store["work"] = "store"
		_path_from(g, store["door"], out, st)
	_place_staff(g, rng, st, out, c, r * 0.55)
	var guards := _count(st, "guard")
	_perimeter(g, rng, st, out, c, int(r * 0.78), clampi(guards / 4, 2, 4))
	if _count(st, "slave") > 0:
		var pen := _place(g, rng, st, out, "pen", Vector2i(12, 9), Vector2i(14, 10), c - to_mtn * r * 0.2, 10.0, 3)
		if not pen.is_empty():
			pen["fl"] = 0
			pen["roof"] = "none"
			pen["solid"] = false
			pen["fence"] = true
			pen["gate"] = pen["door"] - FACE_DIRS[pen["face"]]


## Бараки, столовая, дом начальника — для рудников и фортов.
static func _place_staff(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, c: Vector2, spread: float) -> void:
	var people := st.population()
	for k in clampi(people / 60, 1, 10):
		var b := _place(g, rng, st, out, "barracks", Vector2i(10, 5), Vector2i(12, 6), c, spread, 3)
		if not b.is_empty():
			b["cap"] = 60
			_path_from(g, b["door"], out, st)
	var mess := _place(g, rng, st, out, "messhall", Vector2i(9, 7), Vector2i(11, 8), c, spread * 0.6, 2)
	if not mess.is_empty():
		mess["work"] = "cook"
		_path_from(g, mess["door"], out, st)
	var hq := _place(g, rng, st, out, "hq", Vector2i(8, 7), Vector2i(10, 8), c, spread * 0.5, 2)
	if not hq.is_empty():
		hq["work"] = "officer"
		hq["fl"] = 2
		hq["roof"] = "flat"
		var rr: Rect2i = hq["r"]
		hq["posts"] = [Vector3(rr.position.x + 1.0, rr.position.y + 1.0, 6.6), Vector3(rr.end.x - 1.0, rr.end.y - 1.0, 6.6)]
		_path_from(g, hq["door"], out, st)


## Ограда квадратом с воротами к дороге и вышками по углам.
static func _perimeter(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, c: Vector2, half: int, towers: int) -> void:
	var ci := Vector2i(c)
	var gate_face := _face_of(_road_dir(g, ci, half))
	# сначала вышки по углам, потом ограда — она обходит занятые клетки
	var corners := [Vector2i(-half, -half), Vector2i(half, -half), Vector2i(half, half), Vector2i(-half, half)]
	for k in mini(towers, 4):
		var q: Vector2i = ci + corners[k] - Vector2i(1, 1)
		var rect := Rect2i(q, Vector2i(3, 3))
		if not g.free_rect(rect, 0):
			continue
		var tw := _new("watchtower", rect, st, rng)
		tw["fl"] = 3
		tw["roof"] = "hip"
		tw["work"] = "guard"
		tw["posts"] = [Vector3(q.x + 1.5, q.y + 1.5, 7.6)]
		g.fill(rect, BUILT)
		out.append(tw)
	var sides := [[Vector2i(-half, half), Vector2i(half, half), 0], [Vector2i(half, -half), Vector2i(half, half), 1],
		[Vector2i(-half, -half), Vector2i(half, -half), 2], [Vector2i(-half, -half), Vector2i(-half, half), 3]]
	for sd: Array in sides:
		var a: Vector2i = ci + sd[0]
		var b: Vector2i = ci + sd[1]
		var face: int = sd[2]
		var seg := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(b.x - a.x) + 1, absi(b.y - a.y) + 1))
		_fence_line(g, rng, st, out, seg, face == gate_face, face)


## Отрезок ограды по тайлам; на воротах — проём 4 тайла. Тайлы под оградой сплошные.
static func _fence_line(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, seg: Rect2i, gate: bool, face: int) -> void:
	_line_runs(g, rng, st, out, seg, gate, face, "fence", 4, 0)


## Делит линию (ограду или стену) на куски ≤16 тайлов по свободным клеткам: занятые клетки
## (башни, дома) и вода разрывают линию, поэтому куски никогда не налезают на другие постройки.
static func _line_runs(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, seg: Rect2i, gate: bool,
		face: int, t: String, gate_w: int, floors: int) -> void:
	var horizontal := seg.size.x >= seg.size.y
	var length := seg.size.x if horizontal else seg.size.y
	var thick := seg.size.y if horizontal else seg.size.x
	var mid := length / 2
	var g0 := mid - gate_w / 2
	var g1 := g0 + gate_w
	var run_start := -1
	var k := 0
	while k <= length:
		var ok := k < length and not (gate and k >= g0 and k < g1)
		if ok:
			for w in thick:
				var q := seg.position + (Vector2i(k, w) if horizontal else Vector2i(w, k))
				var v := g.at(q.x, q.y)
				if v == BUILT or v == WATER or v == OUT or v == ROAD or v == STEEP:
					ok = false
					break
		if ok and run_start < 0:
			run_start = k
		if run_start >= 0 and (not ok or k - run_start >= 16):
			var r := Rect2i(seg.position + (Vector2i(run_start, 0) if horizontal else Vector2i(0, run_start)),
				Vector2i(k - run_start, thick) if horizontal else Vector2i(thick, k - run_start))
			g.fill(r, BUILT)
			var f := _new(t, r, st, rng)
			f["fl"] = floors
			f["roof"] = "none"
			f["face"] = face
			if t == "wall":
				var cc := Vector2(r.get_center())
				f["posts"] = [Vector3(cc.x, cc.y, floors * FLOOR_M)]
			out.append(f)
			run_start = k if ok else -1
		k += 1
	if gate:
		var gr := Rect2i(seg.position + (Vector2i(g0, 0) if horizontal else Vector2i(0, g0)),
			Vector2i(gate_w, thick) if horizontal else Vector2i(thick, gate_w))
		var gt := _new("gate", gr, st, rng)
		gt["solid"] = false
		gt["fl"] = floors
		gt["roof"] = "none"
		gt["face"] = face
		out.append(gt)


static func _face_of(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 1 if v.x > 0.0 else 3
	return 0 if v.y > 0.0 else 2


## Куда от центра уходит дорога (для ворот).
static func _road_dir(g: Grid, c: Vector2i, half: int) -> Vector2:
	var best := Vector2.DOWN
	var best_n := -1
	for f in 4:
		var o: Vector2i = FACE_DIRS[f]
		var n := 0
		for s in range(half - 3, half + 4):
			var q := c + o * s
			for w in range(-3, 4):
				var qq := q + Vector2i(o.y, o.x) * w
				if g.at(qq.x, qq.y) == ROAD:
					n += 1
		if n > best_n:
			best_n = n
			best = Vector2(o)
	return best


# ---------------- форт ----------------

static func _fort(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var half := clampi(int(st.radius * 0.62), 14, 40)
	var ci := Vector2i(c)
	var gate_face := _face_of(_road_dir(g, ci, half))
	# сначала угловые башни, потом стены между ними — стены обходят занятые клетки
	for q: Vector2i in [Vector2i(-half, -half), Vector2i(half - 3, -half), Vector2i(half - 3, half - 3), Vector2i(-half, half - 3)]:
		var rect := Rect2i(ci + q - Vector2i(1, 1), Vector2i(5, 5))
		if not g.free_rect(rect, 0):
			continue
		g.fill(rect, BUILT)
		var tw := _new("tower", rect, st, rng)
		tw["fl"] = 4
		tw["roof"] = "flat"
		tw["work"] = "soldier"
		tw["posts"] = [Vector3(rect.position.x + 1.2, rect.position.y + 1.2, 12.8), Vector3(rect.end.x - 1.2, rect.end.y - 1.2, 12.8)]
		out.append(tw)
	var sides := [[Vector2i(-half, half - 1), Vector2i(half, half), 0], [Vector2i(half - 1, -half), Vector2i(half, half), 1],
		[Vector2i(-half, -half), Vector2i(half, -half + 1), 2], [Vector2i(-half, -half), Vector2i(-half + 1, half), 3]]
	for sd: Array in sides:
		var a: Vector2i = ci + sd[0]
		var b: Vector2i = ci + sd[1]
		var face: int = sd[2]
		_wall_line(g, rng, st, out, Rect2i(a, b - a + Vector2i.ONE), face == gate_face, face)
	_place_staff(g, rng, st, out, c, half * 0.6)
	var arm := _place(g, rng, st, out, "armory", Vector2i(7, 6), Vector2i(8, 7), c, half * 0.6, 2)
	if not arm.is_empty():
		arm["work"] = "smith"
		_path_from(g, arm["door"], out, st)
	var flag := _place(g, rng, st, out, "flagpole", Vector2i(1, 1), Vector2i(1, 1), c, 3.0, -1)
	if not flag.is_empty():
		flag["fl"] = 0
		flag["roof"] = "none"
		flag["door"] = NO_DOOR
	for k in 6:
		var sb := _place(g, rng, st, out, "sandbags", Vector2i(3, 1), Vector2i(4, 1), c, half * 0.8, -1, 10)
		if not sb.is_empty():
			sb["fl"] = 0
			sb["roof"] = "none"
			sb["door"] = NO_DOOR


## Каменная стена толщиной 2 тайла с проходом наверху и воротами.
static func _wall_line(g: Grid, rng: RandomNumberGenerator, st: Site, out: Array, seg: Rect2i, gate: bool, face: int) -> void:
	_line_runs(g, rng, st, out, seg, gate, face, "wall", 6, 2)


# ---------------- окоп ----------------

static func _trench(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var fwd := st.dir.normalized()
	if fwd == Vector2.ZERO:
		fwd = Vector2.RIGHT
	var side := Vector2(-fwd.y, fwd.x)
	var half := float(st.radius) * 0.8
	# зигзаг линии окопа
	var pts := PackedVector2Array()
	var n := int(half * 2.0 / 7.0)
	for k in n + 1:
		var t := -half + k * 7.0
		var zig := 2.2 if k % 2 == 0 else -2.2
		pts.append(c + side * t + fwd * zig)
	var tr := {"t": "trench", "r": _bounds(pts, 3), "fl": 0, "roof": "none", "face": _face_of(fwd), "door": NO_DOOR,
		"solid": false, "style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "soldier",
		"pts": pts, "fwd": fwd, "lvl": NAN}
	out.append(tr)
	_mark_line(g, pts, 1.4, PATH)
	# мешки с песком на бруствере (со стороны врага) — сплошные, кроме проходов
	var bag := PackedVector2Array()
	for q in pts:
		bag.append(q + fwd * 2.4)
	var bags := {"t": "parapet", "r": _bounds(bag, 2), "fl": 0, "roof": "none", "face": _face_of(fwd), "door": NO_DOOR,
		"solid": true, "style": st.culture, "v": 0, "posts": [], "cap": 0, "work": "", "pts": bag, "lvl": NAN}
	out.append(bags)
	_mark_line(g, bag, 0.9, BUILT)
	# колючая проволока впереди, с разрывами для вылазок
	for row in 2:
		var wire := PackedVector2Array()
		for q in pts:
			wire.append(q + fwd * (12.0 + row * 6.0))
		var w := {"t": "wire", "r": _bounds(wire, 2), "fl": 0, "roof": "none", "face": 0, "door": NO_DOOR,
			"solid": false, "style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "",
			"pts": wire, "lvl": NAN}
		out.append(w)
	# блиндажи и палатки в тылу
	for k in clampi(st.population() / 70, 2, 6):
		var b := _place(g, rng, st, out, "bunker", Vector2i(5, 4), Vector2i(6, 5), c - fwd * 9.0 + side * rng.randf_range(-half, half) * 0.8, 4.0, -1, 20)
		if not b.is_empty():
			b["fl"] = 1
			b["roof"] = "flat"
			_set_face(g, b, _face_of(-fwd))
	for k in clampi(st.population() / 40, 3, 10):
		var tn := _place(g, rng, st, out, "tent", Vector2i(4, 3), Vector2i(5, 4), c - fwd * 20.0 + side * rng.randf_range(-half, half) * 0.8, 6.0, -1, 20)
		if not tn.is_empty():
			tn["roof"] = "tent"
			tn["cap"] = 8
	var hq := _place(g, rng, st, out, "hq", Vector2i(7, 6), Vector2i(8, 6), c - fwd * 26.0, 6.0, -1, 30)
	if not hq.is_empty():
		hq["work"] = "officer"
		hq["roof"] = "flat"
	var tw := _place(g, rng, st, out, "watchtower", Vector2i(3, 3), Vector2i(3, 3), c - fwd * 14.0 + side * half * 0.5, 4.0, -1, 20)
	if not tw.is_empty():
		tw["fl"] = 3
		tw["roof"] = "hip"
		tw["work"] = "soldier"
		var rr: Rect2i = tw["r"]
		tw["posts"] = [Vector3(rr.position.x + 1.5, rr.position.y + 1.5, 7.6)]
	for k in 8:
		var cr := _place(g, rng, st, out, "crates", Vector2i(2, 1), Vector2i(3, 2), c - fwd * 16.0, half * 0.6, -1, 10)
		if not cr.is_empty():
			cr["fl"] = 0
			cr["roof"] = "none"
			cr["door"] = NO_DOOR


static func _mark_line(g: Grid, pts: PackedVector2Array, half_w: float, v: int) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var steps := int(a.distance_to(b) * 2.0) + 1
		for s in steps + 1:
			var q := a.lerp(b, float(s) / steps)
			for oy in range(-int(ceil(half_w)), int(ceil(half_w)) + 1):
				for ox in range(-int(ceil(half_w)), int(ceil(half_w)) + 1):
					var t := Vector2i(int(floor(q.x)) + ox, int(floor(q.y)) + oy)
					if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(q) <= half_w:
						var cur := g.at(t.x, t.y)
						if cur != OUT and cur != WATER:
							g.put(t.x, t.y, v)


# ---------------- лагерь мусорщиков, логово, руины, пещера ----------------

static func _camp(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var r := float(st.radius)
	var store := _place(g, rng, st, out, "scrapyard", Vector2i(8, 6), Vector2i(10, 8), c, 6.0, 2)
	if not store.is_empty():
		store["work"] = "store"
		store["roof"] = "shed"
	for k in clampi(st.population() / 6, 4, 60):
		var t: String = ["shack", "shack", "tent", "junkpile", "wreck_car"][rng.randi() % 5]
		var b := _place(g, rng, st, out, t, Vector2i(4, 3), Vector2i(6, 5), c, r * 0.8, 3, 16)
		if b.is_empty():
			continue
		match t:
			"shack":
				b["roof"] = "shed"
				b["cap"] = 5
			"tent":
				b["roof"] = "tent"
				b["cap"] = 4
			_:
				b["fl"] = 0
				b["roof"] = "none"
				b["door"] = NO_DOOR
	for k in clampi(st.population() / 30, 2, 12):
		var fb := _place(g, rng, st, out, "firebarrel", Vector2i(1, 1), Vector2i(1, 1), c, r * 0.7, 2, 10)
		if not fb.is_empty():
			fb["fl"] = 0
			fb["roof"] = "none"
			fb["door"] = NO_DOOR
	var tw := _place(g, rng, st, out, "watchtower", Vector2i(3, 3), Vector2i(3, 3), c, r * 0.9, -1, 20)
	if not tw.is_empty():
		tw["fl"] = 3
		tw["roof"] = "shed"
		tw["work"] = "scavenger"
		var rr: Rect2i = tw["r"]
		tw["posts"] = [Vector3(rr.position.x + 1.5, rr.position.y + 1.5, 7.6)]


static func _hideout(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var fire := _place(g, rng, st, out, "campfire", Vector2i(2, 2), Vector2i(2, 2), c, 2.0, -1)
	if not fire.is_empty():
		fire["fl"] = 0
		fire["roof"] = "none"
		fire["door"] = NO_DOOR
	for k in clampi(st.population() / 4, 2, 12):
		var tn := _place(g, rng, st, out, "tent", Vector2i(4, 3), Vector2i(4, 4), c, 9.0, -1, 16)
		if not tn.is_empty():
			tn["roof"] = "tent"
			tn["cap"] = 4
	var lk := _place(g, rng, st, out, "lookout", Vector2i(3, 3), Vector2i(3, 3), c, 10.0, -1, 20)
	if not lk.is_empty():
		lk["fl"] = 2
		lk["roof"] = "none"
		lk["work"] = "pirate"
		var rr: Rect2i = lk["r"]
		lk["posts"] = [Vector3(rr.position.x + 1.5, rr.position.y + 1.5, 5.4)]
	for k in 5:
		var cr := _place(g, rng, st, out, "crates", Vector2i(1, 1), Vector2i(2, 2), c, 7.0, -1, 10)
		if not cr.is_empty():
			cr["fl"] = 0
			cr["roof"] = "none"
			cr["door"] = NO_DOOR


static func _ruins(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var r := float(st.radius)
	for k in rng.randi_range(5, 12):
		var shell := _place(g, rng, st, out, "ruin", Vector2i(6, 5), Vector2i(12, 9), c, r * 0.8, -1, 20)
		if shell.is_empty():
			continue
		# у руин сплошные только стены, внутри можно ходить
		shell["solid"] = false
		shell["fl"] = rng.randi_range(1, 3)
		shell["roof"] = "none"
		shell["door"] = NO_DOOR
		var rr: Rect2i = shell["r"]
		var walls: Array = []
		for x in range(rr.position.x, rr.end.x):
			for y in [rr.position.y, rr.end.y - 1]:
				if rng.randf() < 0.72:
					walls.append(Vector2i(x, y))
		for y in range(rr.position.y + 1, rr.end.y - 1):
			for x in [rr.position.x, rr.end.x - 1]:
				if rng.randf() < 0.72:
					walls.append(Vector2i(x, y))
		shell["walls"] = walls
	for k in rng.randi_range(4, 10):
		var rb := _place(g, rng, st, out, "rubble", Vector2i(2, 2), Vector2i(3, 3), c, r * 0.85, -1, 10)
		if not rb.is_empty():
			rb["fl"] = 0
			rb["roof"] = "none"
			rb["door"] = NO_DOOR


static func _cave(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var best_a := 0.0
	var best_h := -INF
	for k in 24:
		var a := TAU * k / 24.0
		var q := c + Vector2.from_angle(a) * 14.0
		var hh := p.height_base(q.x, q.y)
		if hh > best_h:
			best_h = hh
			best_a = a
	var to_rock := Vector2.from_angle(best_a)
	st.dir = to_rock
	var mouth := _place(g, rng, st, out, "cave_mouth", Vector2i(5, 3), Vector2i(5, 3), c + to_rock * 5.0, 2.0, -1, 30)
	if not mouth.is_empty():
		_set_face(g, mouth, _face_of(-to_rock))
		mouth["fl"] = 2
		mouth["roof"] = "none"


static func _wreck(p: Planet, st: Site, g: Grid, rng: RandomNumberGenerator, out: Array) -> void:
	var c := Vector2(st.center)
	var hull := _place(g, rng, st, out, "hull", Vector2i(12, 6), Vector2i(12, 6), c, 2.0, -1, 40)
	if not hull.is_empty():
		hull["fl"] = 2
		hull["roof"] = "none"
		hull["face"] = 0
	for k in 7:
		var d := _place(g, rng, st, out, "debris", Vector2i(2, 1), Vector2i(3, 2), c, 12.0, -1, 10)
		if not d.is_empty():
			d["fl"] = 0
			d["roof"] = "none"
			d["door"] = NO_DOOR


# ======================================================================
#  Города: сетка улиц, суперкварталы, участки
# ======================================================================

## Параметры сетки: шаг проспектов, ширина проспекта и улицы, этажность.
static func city_params(st: Site) -> Dictionary:
	match st.kind:
		"capital":
			return {"A": 128, "aw": 10, "sw": 4, "tower": [18, 64], "high": [8, 18], "mid": [4, 8], "low": [1, 3]}
		"city":
			return {"A": 112, "aw": 8, "sw": 4, "tower": [12, 30], "high": [6, 14], "mid": [3, 7], "low": [1, 3]}
	return {"A": 96, "aw": 6, "sw": 3, "tower": [6, 10], "high": [4, 7], "mid": [2, 5], "low": [1, 2]}


## Улица в тайле города: 0 — нет, 1 — улица, 2 — проспект.
static func city_street_at(st: Site, x: int, y: int) -> int:
	var lx := x - st.center.x
	var ly := y - st.center.y
	if lx * lx + ly * ly > st.radius * st.radius:
		return 0
	var cp := city_params(st)
	var A: int = cp["A"]
	var aw: int = cp["aw"]
	var ux := posmod(lx + aw / 2, A)
	var uy := posmod(ly + aw / 2, A)
	if ux < aw or uy < aw:
		return 2
	var i := floori(float(lx + aw / 2) / A)
	var j := floori(float(ly + aw / 2) / A)
	var cuts_x := _cuts(st, i, j, 0)
	var cuts_y := _cuts(st, i, j, 1)
	var sw: int = cp["sw"]
	for cx in cuts_x:
		if ux >= cx and ux < cx + sw:
			return 1
	for cy in cuts_y:
		if uy >= cy and uy < cy + sw:
			return 1
	return 0


## Позиции улиц внутри суперквартала (локальные, от начала суперквартала с проспектом).
static func _cuts(st: Site, i: int, j: int, axis: int) -> PackedInt32Array:
	var cp := city_params(st)
	var A: int = cp["A"]
	var aw: int = cp["aw"]
	var sw: int = cp["sw"]
	var hs := U.hash3(st.site_seed, i * 7 + axis, j * 13 + axis)
	var spacing: int = [24, 30, 36, 42][hs % 4]
	var d := _district_at(st, i, j)
	if d == "palace" or d == "park":
		spacing = A
	elif d == "industrial":
		spacing = maxi(spacing, 40)
	var out := PackedInt32Array()
	var u := aw + spacing
	while u + sw + spacing / 2 <= A:
		out.append(u)
		u += spacing + sw
	return out


## Район суперквартала по удалённости от центра (и случайности).
static func _district_at(st: Site, i: int, j: int) -> String:
	var cp := city_params(st)
	var A: int = cp["A"]
	var aw: int = cp["aw"]
	var cxy := Vector2((i + 0.5) * A - aw / 2.0, (j + 0.5) * A - aw / 2.0)
	var d := cxy.length() / maxf(1.0, st.radius)
	var r := U.rnd3(st.site_seed, i, j)
	if st.kind == "capital" and (i == 0 or i == -1) and (j == 0 or j == -1):
		return "palace"
	if r < 0.05 and d < 0.85:
		return "park"
	if d < 0.32:
		return "towers" if st.kind != "town" else "mid"
	if d < 0.58:
		return "high" if st.kind != "town" else "mid"
	if d < 0.8:
		return "industrial" if r > 0.78 else "mid"
	return "slums" if r > 0.7 and st.faction != "guild" else "low"


static func _city_collect(p: Planet, st: Site, rect: Rect2i, out: Array) -> void:
	var cp := city_params(st)
	var A: int = cp["A"]
	var aw: int = cp["aw"]
	var i0 := floori(float(rect.position.x - st.center.x + aw / 2) / A)
	var i1 := floori(float(rect.end.x - st.center.x + aw / 2) / A)
	var j0 := floori(float(rect.position.y - st.center.y + aw / 2) / A)
	var j1 := floori(float(rect.end.y - st.center.y + aw / 2) / A)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var key := Vector2i(i, j)
			st.mutex.lock()
			var list: Array = st.blocks.get(key, [])
			var have := st.blocks.has(key)
			st.mutex.unlock()
			if not have:
				list = _superblock(p, st, i, j)
				st.mutex.lock()
				st.blocks[key] = list
				st.mutex.unlock()
			for s: Dictionary in list:
				if (s["r"] as Rect2i).intersects(rect):
					out.append(s)


## Суперквартал между проспектами: улицы режут его на кварталы, кварталы — на участки.
static func _superblock(p: Planet, st: Site, i: int, j: int) -> Array:
	var cp := city_params(st)
	var A: int = cp["A"]
	var aw: int = cp["aw"]
	var sw: int = cp["sw"]
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash3(st.site_seed, i, j)
	var ox := st.center.x + i * A - aw / 2
	var oy := st.center.y + j * A - aw / 2
	var district := _district_at(st, i, j)
	var cuts_x := _cuts(st, i, j, 0)
	var cuts_y := _cuts(st, i, j, 1)
	var xs: Array = [aw]
	for c in cuts_x:
		xs.append(c)
		xs.append(c + sw)
	xs.append(A)
	var ys: Array = [aw]
	for c in cuts_y:
		ys.append(c)
		ys.append(c + sw)
	ys.append(A)
	var inner := 0
	if district == "palace":
		inner = 6  # место под стену цитадели
	for by in range(0, ys.size(), 2):
		for bx in range(0, xs.size(), 2):
			var block := Rect2i(ox + int(xs[bx]), oy + int(ys[by]), int(xs[bx + 1]) - int(xs[bx]), int(ys[by + 1]) - int(ys[by]))
			if district == "palace":
				block = _citadel_trim(st, block, A, aw, inner)
			if block.size.x < 6 or block.size.y < 6:
				continue
			# квартал целиком внутри города
			var far := Vector2(block.get_center() - st.center).length()
			if far + block.size.length() * 0.5 > st.radius:
				continue
			_block(p, st, rng, block, district, out)
	if district == "palace":
		_citadel_walls(p, st, rng, i, j, A, aw, out)
	elif i == 0 and j == 0:
		_city_hall(st, rng, out)
	for k in out.size():
		out[k]["id"] = U.hash3(st.site_seed, i * 1000 + j, k)
	return out


## Мэрия — самое крупное здание центрального квартала (у столицы её роль играет дворец).
static func _city_hall(st: Site, rng: RandomNumberGenerator, out: Array) -> void:
	var best := -1
	var best_v := -INF
	for k in out.size():
		var b: Dictionary = out[k]
		if not (b["r"] is Rect2i) or not b.get("solid", false):
			continue
		var r: Rect2i = b["r"]
		var v := float(r.get_area()) - Vector2(r.get_center() - st.center).length() * 2.0
		if v > best_v:
			best_v = v
			best = k
	if best < 0:
		return
	var h: Dictionary = out[best]
	h["t"] = "city_hall"
	h["fl"] = clampi(int(h["fl"]), 3, 8)
	h["roof"] = "dome" if st.culture == "empire" else "hip"
	h["work"] = "official"
	h["cap"] = 0


## Внутри цитадели отступаем от внешних проспектов под стену.
static func _citadel_trim(st: Site, block: Rect2i, A: int, aw: int, inner: int) -> Rect2i:
	var lo := st.center - Vector2i(A - aw / 2, A - aw / 2)
	var hi := st.center + Vector2i(A - aw / 2, A - aw / 2)
	var r := block
	if r.position.x < lo.x + inner:
		var cut := lo.x + inner - r.position.x
		r.position.x += cut
		r.size.x -= cut
	if r.position.y < lo.y + inner:
		var cut := lo.y + inner - r.position.y
		r.position.y += cut
		r.size.y -= cut
	if r.end.x > hi.x - inner:
		r.size.x -= r.end.x - (hi.x - inner)
	if r.end.y > hi.y - inner:
		r.size.y -= r.end.y - (hi.y - inner)
	return r


## Стены цитадели по внешнему краю четырёх центральных суперкварталов, ворота на проспектах.
## Каждый суперквартал строит свою часть стены; куски не длиннее 16 тайлов.
static func _citadel_walls(p: Planet, st: Site, rng: RandomNumberGenerator, i: int, j: int, A: int, aw: int, out: Array) -> void:
	var lo := st.center - Vector2i(A - aw / 2, A - aw / 2)
	var hi := st.center + Vector2i(A - aw / 2, A - aw / 2)
	var t := 4
	var x0 := st.center.x + i * A - aw / 2
	var y0 := st.center.y + j * A - aw / 2
	var mine := Rect2i(x0, y0, A, A)
	var towers: Array = []
	for q: Vector2i in [lo, Vector2i(hi.x - 8, lo.y), Vector2i(lo.x, hi.y - 8), hi - Vector2i(8, 8)]:
		towers.append(Rect2i(q, Vector2i(8, 8)))
	# стороны: горизонтальные и вертикальные; ворота — проём шириной проспекта + 4
	var sides: Array = [[Rect2i(lo.x, lo.y, hi.x - lo.x, t), true], [Rect2i(lo.x, hi.y - t, hi.x - lo.x, t), true],
		[Rect2i(lo.x, lo.y, t, hi.y - lo.y), false], [Rect2i(hi.x - t, lo.y, t, hi.y - lo.y), false]]
	for sd: Array in sides:
		var side: Rect2i = sd[0]
		var horizontal: bool = sd[1]
		var a0 := side.position.x if horizontal else side.position.y
		var a1 := side.end.x if horizontal else side.end.y
		var gmid := st.center.x if horizontal else st.center.y
		var g0 := gmid - aw / 2 - 2
		var g1 := gmid + aw / 2 + 2
		# участки: стена до ворот, ворота, стена после
		for run: Array in [[a0, g0, false], [g0, g1, true], [g1, a1, false]]:
			var k: int = run[0]
			var e1: int = run[1]
			var gate_run: bool = run[2]
			while k < e1:
				var is_gate := gate_run
				var e := mini(k + 16, e1)
				var r := Rect2i(Vector2i(k, side.position.y), Vector2i(e - k, t)) if horizontal \
					else Rect2i(Vector2i(side.position.x, k), Vector2i(t, e - k))
				k = e
				var part := r.intersection(mine)
				if part.size.x <= 0 or part.size.y <= 0:
					continue
				var hits_tower := false
				for tw: Rect2i in towers:
					if tw.intersects(part):
						hits_tower = true
				if hits_tower or _rect_wet(p, part, 0):
					continue
				# через стену идёт дорога — здесь ворота
				if not is_gate and _rect_road(p, part, 0):
					is_gate = true
				var wl := {"t": "gate" if is_gate else "citadel_wall", "r": part, "fl": 4, "roof": "none",
					"face": 0 if horizontal else 1, "door": NO_DOOR, "solid": not is_gate, "style": st.culture,
					"v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "soldier", "lvl": NAN}
				if not is_gate:
					var cc := Vector2(part.get_center())
					wl["posts"] = [Vector3(cc.x, cc.y, 13.0)]
				out.append(wl)
	for tr: Rect2i in towers:
		if mine.encloses(tr) and not _rect_wet(p, tr, 0) and not _rect_road(p, tr, 0):
			out.append({"t": "citadel_tower", "r": tr, "fl": 7, "roof": "dome", "face": 0, "door": NO_DOOR,
				"solid": true, "style": st.culture, "v": rng.randi() % 1000,
				"posts": [Vector3(tr.position.x + 2.0, tr.position.y + 2.0, 23.0), Vector3(tr.end.x - 2.0, tr.end.y - 2.0, 23.0)],
				"cap": 0, "work": "soldier", "lvl": NAN})


## Квартал: делим на участки и ставим на каждый одно здание (или делаем парк/площадь).
static func _block(p: Planet, st: Site, rng: RandomNumberGenerator, block: Rect2i, district: String, out: Array) -> void:
	var cp := city_params(st)
	if district == "park":
		if _rect_wet(p, block, 0) or _rect_road(p, block, 0):
			return
		out.append({"t": "park", "r": block, "fl": 0, "roof": "none", "face": 0, "door": NO_DOOR, "solid": false,
			"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "", "lvl": NAN})
		return
	if district != "palace" and rng.randf() < 0.035 and not _rect_wet(p, block, 0) and not _rect_road(p, block, 0):
		var kind := "plaza" if rng.randf() < 0.6 else "market"
		out.append({"t": kind, "r": block, "fl": 0, "roof": "none", "face": 0, "door": NO_DOOR, "solid": false,
			"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "merchant" if kind == "market" else "", "lvl": NAN})
		return
	if st.tech >= 3 and district in ["high", "mid", "industrial"] and rng.randf() < 0.025 \
			and not _rect_wet(p, block, 0) and not _rect_road(p, block, 0):
		out.append({"t": "landing_pad", "r": block, "fl": 0, "roof": "none", "face": 0, "door": NO_DOOR, "solid": false,
			"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "", "lvl": NAN})
		return
	var lot_range := {"palace": Vector2i(30, 60), "towers": Vector2i(14, 26), "high": Vector2i(12, 20),
		"mid": Vector2i(9, 15), "industrial": Vector2i(14, 26), "low": Vector2i(7, 11), "slums": Vector2i(4, 7)}
	var lr: Vector2i = lot_range.get(district, Vector2i(8, 12))
	var lots: Array = []
	_split(block, lr, rng, lots, 0)
	for lot: Rect2i in lots:
		if _rect_road(p, lot) or _rect_wet(p, lot):
			continue
		_lot_building(st, rng, lot, block, district, cp, out)
		var b: Dictionary = out[out.size() - 1] if not out.is_empty() else {}
		if not b.is_empty() and b["r"] is Rect2i and lot.encloses(b["r"]) and b["t"] in ["house", "apartment", "shopfront", "workshop", "warehouse", "factory", "shack"]:
			_maybe_civic(st, rng, b, district)


## Иногда обычный дом на участке заменяется общественным зданием своего района.
static func _maybe_civic(st: Site, rng: RandomNumberGenerator, b: Dictionary, district: String) -> void:
	var roll := rng.randf()
	var acc := 0.0
	for c: Array in CIVIC:
		if st.tech < int(c[2]) or not (district in c[3]):
			continue
		acc += float(c[1])
		if roll < acc:
			var t: String = c[0]
			var fr: Array = c[4]
			b["t"] = t
			b["fl"] = randi_range_det(rng, int(fr[0]), int(fr[1]))
			b["roof"] = "flat" if t in ["power_plant", "aa_battery", "comm_center", "garrison", "prison", "hospital", "bank", "hotel"] else b["roof"]
			b["work"] = CIVIC_WORK.get(t, "")
			b["cap"] = 0
			if b["roof"] == "flat":
				var r: Rect2i = b["r"]
				var top: float = b["fl"] * FLOOR_M + 0.3
				b["posts"] = [Vector3(r.position.x + 1.0, r.position.y + 1.0, top), Vector3(r.end.x - 1.0, r.end.y - 1.0, top)]
			return


static func randi_range_det(rng: RandomNumberGenerator, a: int, b: int) -> int:
	return rng.randi_range(a, b)


static func _split(r: Rect2i, lr: Vector2i, rng: RandomNumberGenerator, out: Array, depth: int) -> void:
	var long_x := r.size.x >= r.size.y
	var long := r.size.x if long_x else r.size.y
	if long <= lr.y or depth > 8:
		out.append(r)
		return
	var cut := int(long * rng.randf_range(0.35, 0.65))
	cut = clampi(cut, lr.x, long - lr.x)
	if cut < lr.x or long - cut < lr.x:
		out.append(r)
		return
	if long_x:
		_split(Rect2i(r.position, Vector2i(cut, r.size.y)), lr, rng, out, depth + 1)
		_split(Rect2i(r.position + Vector2i(cut, 0), Vector2i(r.size.x - cut, r.size.y)), lr, rng, out, depth + 1)
	else:
		_split(Rect2i(r.position, Vector2i(r.size.x, cut)), lr, rng, out, depth + 1)
		_split(Rect2i(r.position + Vector2i(0, cut), Vector2i(r.size.x, r.size.y - cut)), lr, rng, out, depth + 1)


static func _lot_building(st: Site, rng: RandomNumberGenerator, lot: Rect2i, block: Rect2i, district: String, cp: Dictionary, out: Array) -> void:
	# фасад — к ближайшей улице (краю квартала)
	var dists := [block.end.y - lot.end.y, block.end.x - lot.end.x, lot.position.y - block.position.y, lot.position.x - block.position.x]
	var face := 0
	for f in 4:
		if dists[f] < dists[face]:
			face = f
	var setback := 2 if district in ["towers", "palace"] else 1
	var r := lot.grow(-setback)
	if district == "slums":
		r = lot.grow(-1)
	if r.size.x < 3 or r.size.y < 3:
		return
	var t := "house"
	var fl := 1
	var roof := "gable"
	match district:
		"palace":
			t = "palace"
			fl = rng.randi_range(6, 12)
			roof = "dome"
		"towers":
			t = "skyscraper"
			var a: Array = cp["tower"]
			fl = rng.randi_range(int(a[0]), int(a[1]))
			roof = "flat"
		"high":
			t = "apartment"
			var a: Array = cp["high"]
			fl = rng.randi_range(int(a[0]), int(a[1]))
			roof = "flat"
		"mid":
			t = "apartment" if rng.randf() < 0.6 else "shopfront"
			var a: Array = cp["mid"]
			fl = rng.randi_range(int(a[0]), int(a[1]))
			roof = "flat" if rng.randf() < 0.6 else "hip"
		"industrial":
			t = "factory" if rng.randf() < 0.55 else "warehouse"
			fl = rng.randi_range(2, 4)
			roof = "shed" if t == "factory" else "flat"
		"slums":
			t = "shack"
			fl = 1
			roof = "shed"
		_:
			t = "house" if rng.randf() < 0.8 else "workshop"
			var a: Array = cp["low"]
			fl = rng.randi_range(int(a[0]), int(a[1]))
			roof = "gable" if rng.randf() < 0.7 else "hip"
	if st.culture == "free" and roof == "gable" and st.tech <= 2 and rng.randf() < 0.3:
		roof = "thatch"
	var s := {"t": t, "r": r, "fl": fl, "roof": roof, "face": face, "door": _door_tile(r, face), "solid": true,
		"style": st.culture, "v": rng.randi() % 1000, "posts": [], "cap": 0, "work": "", "lvl": NAN}
	var area := r.get_area()
	match t:
		"skyscraper", "apartment":
			s["cap"] = int(area * fl * 0.12)
		"house", "shack":
			s["cap"] = clampi(area / 5, 3, 12) * fl
		"factory", "warehouse":
			s["work"] = "worker"
		"shopfront":
			s["work"] = "merchant"
			s["cap"] = int(area * (fl - 1) * 0.1)
		"workshop":
			s["work"] = ["smith", "tailor", "cook"][rng.randi() % 3]
			s["cap"] = 4
		"palace":
			s["work"] = "official"
	if roof == "flat" and fl >= 2:
		var top := fl * FLOOR_M + 0.3
		s["posts"] = [Vector3(r.position.x + 1.0, r.position.y + 1.0, top), Vector3(r.end.x - 1.0, r.end.y - 1.0, top)]
	out.append(s)


## Есть ли в прямоугольнике (с запасом margin) вода: река или море. Пробы через 2 тайла по всей площади.
static func _rect_wet(p: Planet, r: Rect2i, margin := 2) -> bool:
	var g := r.grow(margin)
	var y := g.position.y
	while y <= g.end.y:
		var x := g.position.x
		while x <= g.end.x:
			var rv := p.river_at(x, y)
			if rv.w > 0.0 and rv.x < rv.y + 1.6:
				return true
			if p.height_base(x, y) < 0.3:
				return true
			x += 2
		y += 2
	return false


## Проходит ли через прямоугольник (с запасом) внешняя дорога. Пробы через 2 тайла.
static func _rect_road(p: Planet, r: Rect2i, margin := 1) -> bool:
	var g := r.grow(margin)
	var y := g.position.y
	while y <= g.end.y:
		var x := g.position.x
		while x <= g.end.x:
			var rd := p.road_at(x, y)
			if rd.w > 0.0 and rd.x < rd.y + 1.6:
				return true
			x += 2
		y += 2
	return false
