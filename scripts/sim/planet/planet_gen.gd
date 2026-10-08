class_name PlanetGen
extends RefCounted
## Генерация планеты из сида: крупная сетка, реки, территории фракций, линия фронта,
## биомы, поселения (особые из data/landmarks.json + сотни обычных), дороги и население.
## Всё детерминировано: один сид — одна и та же планета.

const W := 32768
const H := 16384
const M := Planet.MACRO
const FACTIONS := ["empire", "front", "syndicate", "guild", "scav", "free"]
## Территорией владеют только государства. Обычно планета целиком принадлежит одной державе;
## Рубеж — спорная: формально имперская, но восток держит Фронт. Гильдия, Синдикат,
## мусорщики и вольные владеют отдельными поселениями, а не землёй.
## Значения: сила (насколько далеко «дотягивается»), опорные поселения, доп. точки в долях карты.
const SOVEREIGN := "empire"
const TERRITORY := {
	"empire": [1.0, ["arkon"], [Vector2(0.3, 0.55), Vector2(0.45, 0.8), Vector2(0.35, 0.25)]],
	"front": [0.85, ["svoboda"], [Vector2(0.8, 0.45)]]}
## Сколько обычных поселений каждого вида и минимальный зазор между краями (в крупных клетках).
const QUOTA := {"town": [46, 24.0], "mine": [30, 8.0], "fort": [24, 8.0], "camp": [16, 6.0], "hideout": [26, 5.0],
	"ruins": [34, 4.0], "cave": [40, 3.0], "village": [270, 4.0], "hamlet": [420, 2.5]}
const PLACE_ORDER := ["town", "mine", "fort", "camp", "hideout", "ruins", "cave", "village", "hamlet"]
## Наибольший зазор между поселениями (тайлы) — радиус обновления поля расстояний.
const MAX_GAP := 26.0 * M
const NB8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


static func generate(world_seed: int, size := Vector2i(W, H)) -> Planet:
	DataDB.ensure_loaded()
	var p := Planet.new()
	p.setup(world_seed, size.x, size.y)
	p.factions_order = FACTIONS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 13
	var names := NameGen.new(world_seed)
	_t("старт")
	_macro_fields(p)
	_connect_land(p)
	_t("крупная сетка и перешейки")
	_rivers(p, rng)
	p.build_indices()
	_t("реки")
	_distances(p)
	_landmarks(p, names, false)
	_t("особые поселения")
	_territories(p)
	_war_zone(p)
	_t("территории и фронт")
	_landmarks(p, names, true)
	_front_line(p, rng, names)
	_biomes(p)
	_t("окопы и биомы")
	_settlements(p, rng, names)
	_t("поселения")
	_roads(p, rng)
	_t("дороги")
	_populations(p, rng)
	p.build_indices()
	_t("население и индексы")
	return p


## Печать времени этапов (для отладки генератора).
static var verbose := false
static var _t0 := 0


static func _t(stage: String) -> void:
	if not verbose:
		return
	var now := Time.get_ticks_msec()
	if stage != "старт":
		print("  %s: %d мс" % [stage, now - _t0])
	_t0 = now


# ---------------- поля крупной сетки ----------------

static func _macro_fields(p: Planet) -> void:
	for my in p.mh:
		for mx in p.mw:
			var x := (mx + 0.5) * M
			var y := (my + 0.5) * M
			var hh := p.height_base(x, y)
			var i := my * p.mw + mx
			p.m_height[i] = hh
			p.m_temp[i] = p.temperature(x, y, hh)
			p.m_moist[i] = p.moisture(x, y)


## Связные куски суши. Крупные материки сшиваются с главным перешейками,
## чтобы по суше можно было дойти куда угодно (мелкие острова остаются островами).
static func _connect_land(p: Planet) -> void:
	for pass_i in 8:
		var comps := _components(p)
		if comps.size() <= 1:
			break
		var main: PackedInt32Array = comps[0]
		var joined := false
		for k in range(1, comps.size()):
			var comp: PackedInt32Array = comps[k]
			if comp.size() < 220:
				continue
			var pair := _closest_pair(p, comp, main)
			if pair.x < 0:
				continue
			var a := _cell_center(p, pair.x)
			var b := _cell_center(p, pair.y)
			# короткий и не слишком широкий перешеек — естественное узкое место
			p.bridges.append([a, b, 150.0])
			_refresh_fields(p, a, b, 400.0)
			joined = true
			break
		if not joined:
			break
	var comps2 := _components(p)
	if not comps2.is_empty():
		for c in comps2[0]:
			p.m_land[c] = 0


## Куски суши по убыванию размера (массивы индексов клеток).
static func _components(p: Planet) -> Array:
	var cells := p.mw * p.mh
	var label := PackedInt32Array()
	label.resize(cells)
	label.fill(-1)
	var comps: Array = []
	for i in cells:
		if label[i] >= 0 or p.m_height[i] < 0.0:
			continue
		var comp := PackedInt32Array([i])
		label[i] = comps.size()
		var head := 0
		while head < comp.size():
			var c := comp[head]
			head += 1
			var cx := c % p.mw
			var cy := c / p.mw
			for d: Vector2i in NB8:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= p.mw or ny >= p.mh:
					continue
				var n := ny * p.mw + nx
				if label[n] < 0 and p.m_height[n] >= 0.0:
					label[n] = comps.size()
					comp.append(n)
		comps.append(comp)
	comps.sort_custom(func(a, b): return a.size() > b.size())
	return comps


## Ближайшая пара клеток двух кусков суши (по береговым клеткам).
static func _closest_pair(p: Planet, a: PackedInt32Array, b: PackedInt32Array) -> Vector2i:
	var ea := _edge_cells(p, a)
	var eb := _edge_cells(p, b)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for i in ea:
		var pi := Vector2(i % p.mw, i / p.mw)
		for j in eb:
			var d := pi.distance_squared_to(Vector2(j % p.mw, j / p.mw))
			if d < best_d:
				best_d = d
				best = Vector2i(i, j)
	return best


static func _edge_cells(p: Planet, comp: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in comp:
		var cx := c % p.mw
		var cy := c / p.mw
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if p.m_height[p.mi(cx + d.x, cy + d.y)] < 0.0:
				out.append(c)
				break
	return out


static func _refresh_fields(p: Planet, a: Vector2, b: Vector2, margin: float) -> void:
	var c0 := Vector2i(int((minf(a.x, b.x) - margin) / M), int((minf(a.y, b.y) - margin) / M))
	var c1 := Vector2i(int((maxf(a.x, b.x) + margin) / M), int((maxf(a.y, b.y) + margin) / M))
	for my in range(maxi(0, c0.y), mini(p.mh, c1.y + 1)):
		for mx in range(maxi(0, c0.x), mini(p.mw, c1.x + 1)):
			var x := (mx + 0.5) * M
			var y := (my + 0.5) * M
			var hh := p.height_base(x, y)
			var i := my * p.mw + mx
			p.m_height[i] = hh
			p.m_temp[i] = p.temperature(x, y, hh)


static func _cell_center(p: Planet, i: int) -> Vector2:
	return Vector2((i % p.mw + 0.5) * M, (i / p.mw + 0.5) * M)


## Детерминированный сдвиг точки клетки — чтобы реки и дороги не шли по сетке.
static func _jitter(p: Planet, i: int, amp: float) -> Vector2:
	var hsh := U.ihash(i * 2654435 + p.seed_value)
	var a := float(hsh % 10007) / 10007.0 * TAU
	var r := float((hsh / 10007) % 1009) / 1009.0
	return Vector2(cos(a), sin(a)) * amp * r


# ---------------- реки ----------------

static func _rivers(p: Planet, rng: RandomNumberGenerator) -> void:
	var cells := p.mw * p.mh
	var cand := PackedInt32Array()
	for i in cells:
		var hh := p.m_height[i]
		if hh > 28.0 and hh < 330.0 and p.m_moist[i] > 0.42 and p.m_temp[i] > 0.1:
			cand.append(i)
	_shuffle(cand, rng)
	var sources := PackedInt32Array()
	for i in cand:
		if sources.size() >= 95:
			break
		var c := Vector2i(i % p.mw, i / p.mw)
		var ok := true
		for s in sources:
			if Vector2i(s % p.mw, s / p.mw).distance_squared_to(c) < 100:
				ok = false
				break
		if ok:
			sources.append(i)
	var river_of := {}
	var down := {}
	var flow := {}
	var paths: Array = []
	var joins: Array = []
	for src in sources:
		if river_of.has(src):
			continue
		var path := PackedInt32Array([src])
		var visited := {src: true}
		var cur := src
		var ok := false
		var join := -1
		for step in 2500:
			if p.m_height[cur] < 0.0:
				ok = true
				break
			if step > 0 and river_of.has(cur):
				join = cur
				ok = true
				break
			var best := -1
			var best_h := INF
			var cx := cur % p.mw
			var cy := cur / p.mw
			for d: Vector2i in NB8:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= p.mw or ny >= p.mh:
					continue
				var n := ny * p.mw + nx
				if visited.has(n):
					continue
				# лёгкий шум против прямых линий
				var hn := p.m_height[n] + float(U.ihash(n + src) % 100) * 0.004
				if hn < best_h:
					best_h = hn
					best = n
			if best < 0:
				break
			visited[best] = true
			path.append(best)
			cur = best
		if not ok:
			continue
		if path.size() < (8 if join >= 0 else 14):
			continue
		var rid := paths.size()
		var steps := path.size() if join < 0 else path.size() - 1
		for k in steps:
			var c := path[k]
			river_of[c] = rid
			flow[c] = float(flow.get(c, 0.0)) + float(k + 1)
			if k + 1 < path.size():
				down[c] = path[k + 1]
		if join >= 0:
			var add := float(steps)
			var c2 := join
			var guard := 0
			while guard < 4000:
				guard += 1
				flow[c2] = float(flow.get(c2, 0.0)) + add
				if not down.has(c2):
					break
				c2 = down[c2]
		paths.append(path)
		joins.append(join)
	for k in paths.size():
		var path: PackedInt32Array = paths[k]
		var join: int = joins[k]
		_build_river(p, path, join, flow, int(river_of.get(join, -1)))
		for c in path:
			if p.m_height[c] >= 0.0:
				p.m_riv[c] = 1  # временная метка, расстояния — в _distances


static func _build_river(p: Planet, path: PackedInt32Array, join: int, flow: Dictionary, into: int) -> void:
	var pts := PackedVector2Array()
	var fl := PackedFloat32Array()
	for c in path:
		pts.append(_cell_center(p, c) + _jitter(p, c, 20.0))
		fl.append(float(flow.get(c, 1.0)))
	if join < 0:
		# устье: продлеваем в море, чтобы река точно впадала в открытую воду
		var last := pts[pts.size() - 1]
		var dirv := (last - pts[pts.size() - 2]).normalized()
		pts.append(last + dirv * M * 1.5)
		fl.append(fl[fl.size() - 1])
	var sp := _chaikin(pts, 3)
	var sf := _resample_values(fl, sp.size())
	if join >= 0 and into >= 0 and into < p.rivers.size():
		var snap := _nearest_on_river(p.rivers[into], sp[sp.size() - 1])
		sp[sp.size() - 1] = Vector2(snap.x, snap.y)
	var hw := PackedFloat32Array()
	var lvl := PackedFloat32Array()
	var run := INF
	for k in sp.size():
		hw.append(minf(0.9 + sqrt(sf[k]) * 0.55, 14.0))
		var th := p.height_base(sp[k].x, sp[k].y) - 0.8
		run = minf(run, th)
		lvl.append(maxf(run, 0.0))
	if join >= 0 and into >= 0 and into < p.rivers.size():
		var lj := _nearest_on_river(p.rivers[into], sp[sp.size() - 1]).z
		for k in lvl.size():
			lvl[k] = maxf(lvl[k], lj)
	p.rivers.append({"pts": sp, "hw": hw, "lvl": lvl})


static func _chaikin(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := pts
	for it in iters:
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array([cur[0]])
		for i in cur.size() - 1:
			var a := cur[i]
			var b := cur[i + 1]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


static func _resample_values(vals: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in n:
		var t := float(k) / maxf(1.0, n - 1) * (vals.size() - 1)
		var i := mini(int(t), vals.size() - 2)
		out.append(lerpf(vals[i], vals[i + 1], t - i))
	return out


## Ближайшая точка на реке: (x, y, уровень воды там).
static func _nearest_on_river(r: Dictionary, q: Vector2) -> Vector3:
	var pts: PackedVector2Array = r["pts"]
	var lvl: PackedFloat32Array = r["lvl"]
	var best := Vector3(q.x, q.y, 0.0)
	var best_d := INF
	for s in pts.size() - 1:
		var a := pts[s]
		var ab := pts[s + 1] - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * t
		var d := q.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = Vector3(c.x, c.y, lerpf(lvl[s], lvl[s + 1], t))
	return best


# ---------------- расстояния до воды ----------------

static func _distances(p: Planet) -> void:
	var cells := p.mw * p.mh
	var sea_src := PackedInt32Array()
	var riv_src := PackedInt32Array()
	for i in cells:
		if p.m_height[i] < 0.0:
			sea_src.append(i)
		elif p.m_riv[i] == 1:
			riv_src.append(i)
	_bfs(p, sea_src, p.m_sea)
	_bfs(p, riv_src, p.m_riv)
	for i in cells:
		var boost := 0.3 * maxf(0.0, 1.0 - p.m_riv[i] / 5.0) + 0.15 * maxf(0.0, 1.0 - p.m_sea[i] / 4.0)
		p.m_moist[i] = clampf(p.m_moist[i] + boost, 0.0, 1.0)


## Расстояние (в клетках, до 15) от источников по 8 соседям.
static func _bfs(p: Planet, src: PackedInt32Array, out: PackedByteArray) -> void:
	out.fill(15)
	var q := PackedInt32Array()
	for s in src:
		out[s] = 0
		q.append(s)
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var dist := out[c]
		if dist >= 14:
			continue
		var cx := c % p.mw
		var cy := c / p.mw
		for d: Vector2i in NB8:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= p.mw or ny >= p.mh:
				continue
			var n := ny * p.mw + nx
			if out[n] > dist + 1:
				out[n] = dist + 1
				q.append(n)


# ---------------- особые поселения ----------------

static func _landmarks(p: Planet, names: NameGen, front_only: bool) -> void:
	for d: Dictionary in DataDB.landmarks.get("list", []):
		var need := str(d.get("need", ""))
		if (need == "front") != front_only:
			continue
		var target := Vector2i(int(float(d["pos"][0]) * p.mw), int(float(d["pos"][1]) * p.mh))
		var cell := -1
		if need == "front":
			cell = _front_cell(p, target, str(d["faction"]))
		else:
			cell = _find_cell(p, target, need, 70)
		if cell < 0:
			push_warning("Не нашлось места для %s" % d["id"])
			cell = p.mi(target.x, target.y)
		var st := _make_site(p, str(d["id"]), str(d["kind"]), str(d["faction"]), cell, int(d["pop"]))
		st.landmark = true
		st.name = str(d["name"])
		st.where = str(d["where"])
		st.from = str(d["from"])
		st.near = str(d["near"])
		names.used[st.name] = true
		_add_site(p, st)


static func _suitable(p: Planet, i: int) -> bool:
	var hh := p.m_height[i]
	if hh < 1.5 or hh > 170.0 or p.m_temp[i] < 0.1 or p.m_riv[i] == 0 or p.m_land[i] != 0:
		return false
	var cx := i % p.mw
	var cy := i / p.mw
	for d: Vector2i in NB8:
		var n := p.mi(cx + d.x, cy + d.y)
		if absf(p.m_height[n] - hh) > 11.0:
			return false
	return true


static func _needs_ok(p: Planet, i: int, need: String) -> bool:
	match need:
		"coast":
			return p.m_sea[i] >= 1 and p.m_sea[i] <= 2
		"river":
			return p.m_riv[i] >= 1 and p.m_riv[i] <= 2
		"mountain":
			if p.m_height[i] > 95.0:
				return false
			var cx := i % p.mw
			var cy := i / p.mw
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if p.m_height[p.mi(cx + dx, cy + dy)] > 150.0:
						return true
			return false
	return true


## Ближайшая к цели клетка, где можно строиться (спираль до max_r клеток).
static func _find_cell(p: Planet, target: Vector2i, need: String, max_r: int) -> int:
	for r in max_r:
		var best := -1
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := target.x + dx
				var y := target.y + dy
				if x < 2 or y < 2 or x >= p.mw - 2 or y >= p.mh - 2:
					continue
				var i := y * p.mw + x
				if not _suitable(p, i) or not _needs_ok(p, i, need) or _occupied(p, i, 6.0):
					continue
				var dd := float(dx * dx + dy * dy)
				if dd < best_d:
					best_d = dd
					best = i
		if best >= 0:
			return best
	return -1


## Поселения разложены по корзинам 1024×1024 тайла, чтобы проверка соседей была быстрой.
const BUCKET := 1024
const MAX_REACH := 1400.0 + 30.0 * M


static func _occupied(p: Planet, i: int, gap_cells: float) -> bool:
	var c := _cell_center(p, i)
	for st: Site in _sites_near(p, c, MAX_REACH):
		if Vector2(st.center).distance_to(c) < st.radius + gap_cells * M:
			return true
	return false


static func _sites_near(p: Planet, c: Vector2, reach: float) -> Array:
	var grid: Dictionary = p.get_meta("site_buckets", {})
	var out: Array = []
	var b0 := Vector2i(floori((c.x - reach) / BUCKET), floori((c.y - reach) / BUCKET))
	var b1 := Vector2i(floori((c.x + reach) / BUCKET), floori((c.y + reach) / BUCKET))
	for by in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var list: Array = grid.get(Vector2i(bx, by), [])
			out.append_array(list)
	return out


static func _make_site(p: Planet, id: String, kind: String, faction: String, cell: int, pop: int) -> Site:
	var kinds: Dictionary = DataDB.settlement_kinds["kinds"]
	var kd: Dictionary = kinds.get(kind, {})
	var st := Site.new()
	st.id = id
	st.kind = kind
	st.noun = str(kd.get("noun", "посёлок"))
	st.faction = faction
	st.culture = faction if faction != "" else "free"
	st.tech = int(kd.get("tech", 1))
	if kind == "town" and (faction == "empire" or faction == "guild"):
		st.tech = 3
	elif kind == "town" and faction == "scav":
		st.tech = 1
	elif kind == "fort" and faction == "empire":
		st.tech = 3
	elif kind == "city" and faction == "front":
		st.tech = 2
	st.pop0 = pop
	var rr: Array = kd.get("r", [20, 1.0])
	st.radius = int(float(rr[0]) + float(rr[1]) * sqrt(float(pop)))
	st.core = int(st.radius * float(kd.get("core", 1.0)))
	st.site_seed = U.ihash(p.seed_value * 977 + id.hash())
	var c := _cell_center(p, cell) + _jitter(p, cell, 10.0)
	st.center = Vector2i(c)
	st.coastal = p.m_sea[cell] <= 2
	st.river = p.m_riv[cell] <= 2
	st.base_h = _base_height(p, st)
	st.dir = _water_dir(p, cell)
	return st


static func _add_site(p: Planet, st: Site) -> void:
	p.sites[st.id] = st
	p.site_order.append(st.id)
	var grid: Dictionary = p.get_meta("site_buckets", {})
	var key := Vector2i(floori(float(st.center.x) / BUCKET), floori(float(st.center.y) / BUCKET))
	if not grid.has(key):
		grid[key] = []
	grid[key].append(st)
	p.set_meta("site_buckets", grid)


## Направление на ближайшую воду (для причалов) или вниз по умолчанию.
static func _water_dir(p: Planet, cell: int) -> Vector2:
	var cx := cell % p.mw
	var cy := cell / p.mw
	var best := Vector2.DOWN
	var best_d := 99
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := p.mi(cx + dx, cy + dy)
			var dd := mini(p.m_sea[n], p.m_riv[n])
			if dd < best_d and (dx != 0 or dy != 0):
				best_d = dd
				best = Vector2(dx, dy).normalized()
	return best


## Высота площадки: рельеф в центре, но не ниже реки поблизости (иначе город затопит).
static func _base_height(p: Planet, st: Site) -> float:
	var base := maxf(p.height_base(st.center.x, st.center.y), 1.8)
	var step := maxi(8, st.radius / 12)
	for y in range(st.center.y - st.radius, st.center.y + st.radius + 1, step):
		for x in range(st.center.x - st.radius, st.center.x + st.radius + 1, step):
			if Vector2(x - st.center.x, y - st.center.y).length() > st.radius:
				continue
			var rv := p.river_at(x, y)
			if rv.w > 0.0 and rv.x < rv.y + Planet.BANK * 2.0:
				base = maxf(base, rv.z + 2.2)
	return base


# ---------------- территории и фронт ----------------

## Территории государств растут по суше от опорных точек (Дейкстра): горы и крутые склоны
## мешают, море не пересекают. Всё, до чего не дотянулся никто (острова), — владение государя планеты.
static func _territories(p: Planet) -> void:
	var cells := p.mw * p.mh
	var best := PackedFloat32Array()
	best.resize(cells)
	best.fill(INF)
	var heap := Heap.new()
	var weights := PackedFloat32Array()
	weights.resize(FACTIONS.size())
	weights.fill(1.0)
	for f in TERRITORY:
		var info: Array = TERRITORY[f]
		var fi := FACTIONS.find(f)
		weights[fi] = float(info[0])
		var seeds: Array = []
		for sid in info[1]:
			if p.sites.has(sid):
				var st: Site = p.sites[sid]
				seeds.append(p.mi(st.center.x / M, st.center.y / M))
		for v: Vector2 in info[2]:
			seeds.append(p.mi(int(v.x * p.mw), int(v.y * p.mh)))
		for c in seeds:
			if p.m_height[c] >= 0.0 and p.m_land[c] == 0:
				heap.push(0.0, c * 8 + fi)
	while not heap.empty():
		var k := heap.top_key()
		var v := heap.pop()
		var c := v >> 3
		var fi := v & 7
		if p.m_owner[c] != 255:
			continue
		p.m_owner[c] = fi
		var cx := c % p.mw
		var cy := c / p.mw
		var hc := p.m_height[c]
		for d: Vector2i in NB8:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= p.mw or ny >= p.mh:
				continue
			var n := ny * p.mw + nx
			if p.m_owner[n] != 255 or p.m_height[n] < 0.0:
				continue
			var step := (1.414 if d.x != 0 and d.y != 0 else 1.0)
			var hn := p.m_height[n]
			# горы и реки — естественные рубежи, шум делает границу извилистой
			step *= 1.0 + absf(hn - hc) / 18.0 + (3.0 if hn > 160.0 else 0.0) + (1.5 if p.m_riv[n] == 0 else 0.0)
			step *= 1.0 + p.n_forest.get_noise_2d(nx * 23.0, ny * 23.0) * 0.6
			var nk := k + step / weights[fi]
			if nk < best[n]:
				best[n] = nk
				heap.push(nk, n * 8 + fi)
	var sov := FACTIONS.find(SOVEREIGN)
	for i in cells:
		if p.m_owner[i] == 255 and p.m_height[i] >= 0.0:
			p.m_owner[i] = sov


static func _war_zone(p: Planet) -> void:
	var e := FACTIONS.find("empire")
	var f := FACTIONS.find("front")
	var border := PackedInt32Array()
	for my in range(1, p.mh - 1):
		for mx in range(1, p.mw - 1):
			var i := my * p.mw + mx
			var o := p.m_owner[i]
			if o != e and o != f:
				continue
			var other := f if o == e else e
			for d: Vector2i in NB8:
				if p.m_owner[p.mi(mx + d.x, my + d.y)] == other:
					border.append(i)
					break
	var dist := PackedByteArray()
	dist.resize(p.mw * p.mh)
	_bfs(p, border, dist)
	for i in p.mw * p.mh:
		var o := p.m_owner[i]
		if (o == e or o == f) and p.m_height[i] >= 0.0:
			p.m_ash[i] = 1.0 - smoothstep(3.0, 13.0, float(dist[i]))
	p.set_meta("front_border", border)


## Клетка на своей стороне линии фронта, ближайшая к цели.
static func _front_cell(p: Planet, target: Vector2i, faction: String) -> int:
	var border: PackedInt32Array = p.get_meta("front_border", PackedInt32Array())
	if border.is_empty():
		return -1
	var best := -1
	var best_d := INF
	for b in border:
		var d := Vector2(b % p.mw, b / p.mw).distance_squared_to(Vector2(target))
		if d < best_d and p.m_height[b] > 1.0:
			best_d = d
			best = b
	if best < 0:
		return -1
	var n := _front_normal(p, best)
	var own := FACTIONS.find(faction)
	var side := -1.0 if own == FACTIONS.find("empire") else 1.0
	var pos := Vector2(best % p.mw + 0.5, best / p.mw + 0.5) + n * side * 2.6
	return p.mi(int(pos.x), int(pos.y))


## Нормаль к линии фронта: от Империи к Фронту.
static func _front_normal(p: Planet, cell: int) -> Vector2:
	var e := FACTIONS.find("empire")
	var f := FACTIONS.find("front")
	var ce := Vector2.ZERO
	var cf := Vector2.ZERO
	var ne := 0
	var nf := 0
	var cx := cell % p.mw
	var cy := cell / p.mw
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var o := p.m_owner[p.mi(cx + dx, cy + dy)]
			if o == e:
				ce += Vector2(dx, dy)
				ne += 1
			elif o == f:
				cf += Vector2(dx, dy)
				nf += 1
	if ne == 0 or nf == 0:
		return Vector2.RIGHT
	var n := (cf / nf - ce / ne).normalized()
	return n if n != Vector2.ZERO else Vector2.RIGHT


## Пары окопов вдоль линии фронта.
static func _front_line(p: Planet, rng: RandomNumberGenerator, names: NameGen) -> void:
	var border: PackedInt32Array = p.get_meta("front_border", PackedInt32Array())
	var picked: Array = []
	for st: Site in p.sites.values():
		if st.kind == "trench":
			st.dir = _front_normal(p, p.mi(st.center.x / M, st.center.y / M))
			if st.faction == "front":
				st.dir = -st.dir
			picked.append(Vector2(st.center) / M)
	var order := border.duplicate()
	_shuffle(order, rng)
	var made := 0
	for b in order:
		if made >= 9:
			break
		var c := Vector2(b % p.mw + 0.5, b / p.mw + 0.5)
		if p.m_height[b] < 2.0 or p.m_height[b] > 120.0:
			continue
		var far := true
		for q: Vector2 in picked:
			if q.distance_to(c) < 22.0:
				far = false
				break
		if not far:
			continue
		var n := _front_normal(p, b)
		var ok := true
		var cells := []
		for side in [-1.0, 1.0]:
			var pos: Vector2 = c + n * side * 2.6
			var ci := p.mi(int(pos.x), int(pos.y))
			if p.m_height[ci] < 2.0 or p.m_height[ci] > 140.0:
				ok = false
			cells.append(ci)
		if not ok:
			continue
		# окопы не должны налезать на другие поселения
		var clash := false
		for ci2 in cells:
			var cc := _cell_center(p, ci2)
			for o: Site in _sites_near(p, cc, MAX_REACH):
				if Vector2(o.center).distance_to(cc) < o.radius + 60.0:
					clash = true
		if clash:
			continue
		picked.append(c)
		made += 1
		for k in 2:
			var fac: String = "empire" if k == 0 else "front"
			var pop := rng.randi_range(220, 460)
			var st := _make_site(p, "trench_%d_%s" % [made, fac], "trench", fac, cells[k], pop)
			st.dir = n if fac == "empire" else -n
			names.name_site(st)
			_add_site(p, st)


# ---------------- биомы ----------------

static func classify(hgt: float, temp: float, moist: float, ash: float, sea_d: int, slope: float) -> int:
	var B := Planet.B
	if hgt < 0.0:
		return B.OCEAN
	if hgt > 110.0 + temp * 380.0:
		return B.ALPINE
	if slope > 40.0 or hgt > 190.0:
		return B.MOUNTAIN
	if ash > 0.45:
		return B.ASHLANDS
	if sea_d <= 1 and hgt < 4.0:
		return B.BEACH
	if temp < 0.16:
		return B.TUNDRA
	if temp < 0.36:
		return B.TAIGA if moist > 0.45 else B.TUNDRA
	if temp > 0.74:
		if moist > 0.62:
			return B.JUNGLE
		if moist > 0.4:
			return B.SAVANNA
		return B.DESERT if slope < 12.0 else B.BADLANDS
	if moist < 0.3:
		return B.STEPPE if temp < 0.62 else B.BADLANDS
	if moist > 0.78 and hgt < 9.0:
		return B.SWAMP
	if moist > 0.56:
		return B.FOREST
	return B.MEADOW


static func _biomes(p: Planet) -> void:
	for my in p.mh:
		for mx in p.mw:
			var i := my * p.mw + mx
			var hh := p.m_height[i]
			var slope := 0.0
			for d: Vector2i in NB8:
				slope = maxf(slope, absf(p.m_height[p.mi(mx + d.x, my + d.y)] - hh))
			p.m_biome[i] = classify(hh, p.m_temp[i], p.m_moist[i], p.m_ash[i], p.m_sea[i], slope)


# ---------------- обычные поселения ----------------

static func _settlements(p: Planet, rng: RandomNumberGenerator, names: NameGen) -> void:
	var cells := p.mw * p.mh
	# расстояние (тайлы) от центра клетки до края ближайшего поселения — проверка соседей за O(1)
	var edge := PackedFloat32Array()
	edge.resize(cells)
	edge.fill(INF)
	for id in p.site_order:
		_mark_edge(p, edge, p.sites[id])
	var land := PackedInt32Array()
	for i in cells:
		if _suitable(p, i):
			land.append(i)
	_shuffle(land, rng)
	for kind in PLACE_ORDER:
		var q: Array = QUOTA[kind]
		var want: int = q[0]
		var gap: float = float(q[1]) * M
		var cand := PackedInt32Array()
		var scores := PackedFloat32Array()
		for i in land:
			var sc := _score(p, i, kind)
			if sc > 0.0:
				cand.append(i)
				scores.append(sc)
		var made := 0
		for attempt in 4:
			if made >= want:
				break
			# первые проходы берут только лучшие места, следующие — любые подходящие
			var bar: float = [1.15, 0.8, 0.45, 0.0][attempt]
			for k in cand.size():
				if made >= want:
					break
				var i := cand[k]
				if edge[i] < 24.0 + 32.0 or scores[k] + rng.randf() * 0.5 < bar:
					continue
				var pop := _roll_pop(kind, rng)
				var r := _radius_for(kind, pop)
				if edge[i] < r + maxf(gap, 24.0) + M * 0.75:
					continue
				var st := _make_site(p, "%s_%d" % [kind, p.site_order.size()], kind, _faction_for(p, i, kind, rng), i, pop)
				if kind == "ruins":
					st.culture = ["empire", "front", "free", "guild"][rng.randi() % 4]
				names.name_site(st)
				_add_site(p, st)
				_mark_edge(p, edge, st)
				made += 1


## Обновляет поле «расстояние до края ближайшего поселения» вокруг нового поселения.
static func _mark_edge(p: Planet, edge: PackedFloat32Array, st: Site) -> void:
	var reach := float(st.radius) + MAX_GAP
	var rc := int(ceil(reach / M)) + 1
	var cx := st.center.x / M
	var cy := st.center.y / M
	var c := Vector2(st.center)
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= p.mw or y >= p.mh:
				continue
			var d := maxf(0.0, Vector2((x + 0.5) * M, (y + 0.5) * M).distance_to(c) - st.radius)
			var i := y * p.mw + x
			if d < edge[i]:
				edge[i] = d


static func _radius_for(kind: String, pop: int) -> int:
	var kd: Dictionary = DataDB.settlement_kinds["kinds"].get(kind, {})
	var rr: Array = kd.get("r", [20, 1.0])
	return int(float(rr[0]) + float(rr[1]) * sqrt(float(pop)))


static func _score(p: Planet, i: int, kind: String) -> float:
	var B := Planet.B
	var b := classify(p.m_height[i], p.m_temp[i], p.m_moist[i], p.m_ash[i], p.m_sea[i], 0.0)
	var fert := {B.MEADOW: 1.0, B.FOREST: 0.7, B.SAVANNA: 0.6, B.STEPPE: 0.55, B.TAIGA: 0.45, B.BEACH: 0.6,
		B.JUNGLE: 0.45, B.SWAMP: 0.25, B.TUNDRA: 0.2, B.DESERT: 0.15, B.BADLANDS: 0.15, B.ASHLANDS: 0.1}
	var f: float = fert.get(b, 0.0)
	var water := 0.0
	if p.m_riv[i] <= 2:
		water += 0.8
	if p.m_sea[i] <= 2:
		water += 0.5
	match kind:
		"town":
			return f + water + (0.0 if p.m_ash[i] > 0.3 else 0.4)
		"village", "hamlet":
			return 0.0 if p.m_ash[i] > 0.4 else f + water * 0.8
		"mine":
			return 1.0 if _needs_ok(p, i, "mountain") else 0.0
		"fort":
			# крепости — в тылу фронта, у моря и на перешейках
			var a := p.m_ash[i]
			if a > 0.02 and a < 0.6:
				return 1.6
			return 0.5 if p.m_sea[i] <= 2 else 0.25
		"camp":
			return 0.6 + p.m_ash[i] if b in [B.ASHLANDS, B.BADLANDS, B.DESERT, B.STEPPE] else 0.0
		"hideout":
			return 0.8 if b in [B.FOREST, B.TAIGA, B.JUNGLE, B.SWAMP, B.BADLANDS] else 0.0
		"ruins":
			return 0.3 + p.m_ash[i]
		"cave":
			return 0.8 if _needs_ok(p, i, "mountain") and p.m_height[i] > 25.0 else 0.0
	return 0.0


## Чьё поселение: государства — по территории; часть городов — торговые города Гильдии,
## часть деревень — вольные (особенно в глуши), лагеря — мусорщиков, логова — Синдиката.
static func _faction_for(p: Planet, i: int, kind: String, rng: RandomNumberGenerator) -> String:
	var owner := "" if p.m_owner[i] == 255 else str(FACTIONS[p.m_owner[i]])
	match kind:
		"camp":
			return "scav"
		"hideout":
			return "syndicate"
		"ruins", "cave":
			return ""
		"town":
			if rng.randf() < 0.22:
				return "guild"
		"mine":
			var r := rng.randf()
			if r < 0.25:
				return "guild"
			if r < 0.38:
				return "syndicate"
		"village", "hamlet":
			if rng.randf() < 0.18 + p.m_ash[i] * 0.3:
				return "free"
	return owner if owner != "" else SOVEREIGN


static func _roll_pop(kind: String, rng: RandomNumberGenerator) -> int:
	var kd: Dictionary = DataDB.settlement_kinds["kinds"].get(kind, {})
	var r: Array = kd.get("pop", [0, 0])
	var t := pow(rng.randf(), 1.8)
	return int(lerpf(float(r[0]), float(r[1]), t))


# ---------------- дороги ----------------

static func _roads(p: Planet, rng: RandomNumberGenerator) -> void:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, p.mw, p.mh)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for my in p.mh:
		for mx in p.mw:
			var i := my * p.mw + mx
			var hh := p.m_height[i]
			if hh < 0.0:
				grid.set_point_solid(Vector2i(mx, my), true)
				continue
			var slope := 0.0
			for d: Vector2i in NB8:
				slope = maxf(slope, absf(p.m_height[p.mi(mx + d.x, my + d.y)] - hh))
			var cost := 1.0 + slope * 0.12
			if p.m_riv[i] == 0:
				cost += 5.0
			if hh > 200.0:
				cost += 14.0
			elif hh > 120.0:
				cost += 4.0
			if slope > 45.0:
				cost += 30.0
			grid.set_point_weight_scale(Vector2i(mx, my), cost)
	var hubs: Array = []
	var others: Array = []
	for id in p.site_order:
		var st: Site = p.sites[id]
		if st.kind in ["capital", "city", "town"]:
			hubs.append(st)
		elif st.kind != "ruins" and st.kind != "hideout":
			others.append(st)
	# магистрали: минимальное остовное дерево между городами + короткие дополнительные связи
	var edges: Array = []
	for a in hubs.size():
		for b in range(a + 1, hubs.size()):
			var d := Vector2(hubs[a].center).distance_to(Vector2(hubs[b].center))
			if d < 95.0 * M:
				edges.append([d, a, b])
	edges.sort_custom(func(x, y): return x[0] < y[0])
	var parent := range(hubs.size())
	var links: Array = []
	for e: Array in edges:
		var ra := _find_root(parent, e[1])
		var rb := _find_root(parent, e[2])
		if ra != rb:
			parent[ra] = rb
			links.append([hubs[e[1]], hubs[e[2]], 2])
		elif float(e[0]) < 34.0 * M and rng.randf() < 0.5:
			links.append([hubs[e[1]], hubs[e[2]], 2])
	# остальные — к ближайшему более крупному или к соседу
	var linked: Array = hubs.duplicate()
	others.sort_custom(func(a: Site, b: Site): return a.pop0 > b.pop0)
	for st: Site in others:
		var best: Site = null
		var best_d := INF
		for o: Site in linked:
			var d := Vector2(o.center).distance_to(Vector2(st.center))
			if d < best_d:
				best_d = d
				best = o
		if best != null and best_d < 60.0 * M:
			var kind := 1 if st.kind in ["village", "mine", "fort", "camp", "trench"] else 0
			links.append([st, best, kind])
		linked.append(st)
	for l: Array in links:
		_make_road(p, grid, l[0], l[1], int(l[2]))


static func _find_root(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _make_road(p: Planet, grid: AStarGrid2D, a: Site, b: Site, kind: int) -> void:
	var ca := Vector2i(a.center.x / M, a.center.y / M)
	var cb := Vector2i(b.center.x / M, b.center.y / M)
	if grid.is_point_solid(ca) or grid.is_point_solid(cb):
		return
	var path := grid.get_id_path(ca, cb)
	if path.size() < 2:
		return
	var pts := PackedVector2Array([Vector2(a.center) + Vector2(0.5, 0.5)])
	for k in range(1, path.size() - 1):
		var c: Vector2i = path[k]
		var i := c.y * p.mw + c.x
		pts.append(_cell_center(p, i) + _jitter(p, i + 777, 14.0))
		grid.set_point_weight_scale(c, minf(grid.get_point_weight_scale(c), 0.45))
	pts.append(Vector2(b.center) + Vector2(0.5, 0.5))
	var sp := _chaikin(pts, 2)
	var length := 0.0
	for k in sp.size() - 1:
		length += sp[k].distance_to(sp[k + 1])
	var hw: float = [1.3, 2.2, 3.2][kind]
	p.roads.append({"pts": sp, "hw": hw, "kind": kind, "a": a.id, "b": b.id, "len": length})


# ---------------- население ----------------

static func _populations(p: Planet, rng: RandomNumberGenerator) -> void:
	var kinds: Dictionary = DataDB.settlement_kinds["kinds"]
	var over: Dictionary = DataDB.settlement_kinds.get("faction_overrides", {})
	for id in p.site_order:
		var st: Site = p.sites[id]
		var kd: Dictionary = kinds.get(st.kind, {})
		var comp: Dictionary = kd.get("comp", {}).duplicate()
		var fo: Dictionary = over.get(st.faction, {}).get(st.kind, {})
		for r in fo:
			comp[r] = fo[r]
		var cell := p.mi(st.center.x / M, st.center.y / M)
		var b := p.m_biome[cell]
		if p.m_riv[cell] > 2 and p.m_sea[cell] > 2:
			comp.erase("fisher")
		if not (b in [Planet.B.FOREST, Planet.B.TAIGA, Planet.B.JUNGLE, Planet.B.MEADOW, Planet.B.SWAMP]):
			comp.erase("woodcutter")
		if b in [Planet.B.DESERT, Planet.B.ASHLANDS, Planet.B.TUNDRA, Planet.B.JUNGLE]:
			comp.erase("herder")
		st.pops = _allocate(comp, st.pop0)
		if comp.has("leader") and st.pop0 >= 30:
			# староста или правитель — один из жителей, а не лишний человек
			var biggest := ""
			for r in st.pops:
				if biggest == "" or int(st.pops[r]) > int(st.pops[biggest]):
					biggest = r
			st.pops[biggest] = int(st.pops[biggest]) - 1
			st.pops["leader"] = 1


## Делит население по долям, сумма ровно total (метод наибольших остатков).
static func _allocate(comp: Dictionary, total: int) -> Dictionary:
	var out := {}
	var sum := 0.0
	for r in comp:
		if r != "leader":
			sum += float(comp[r])
	if sum <= 0.0 or total <= 0:
		return out
	var rema: Array = []
	var given := 0
	for r in comp:
		if r == "leader":
			continue
		var exact := float(comp[r]) / sum * total
		var n := int(exact)
		if n > 0:
			out[r] = n
		given += n
		rema.append([exact - n, r])
	rema.sort_custom(func(a, b): return a[0] > b[0])
	var k := 0
	while given < total and k < rema.size():
		var r: String = rema[k][1]
		out[r] = int(out.get(r, 0)) + 1
		given += 1
		k += 1
	return out


static func _shuffle(arr: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Двоичная куча: ключ float, значение int (для Дейкстры по крупной сетке).
class Heap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()

	func empty() -> bool:
		return keys.is_empty()

	func top_key() -> float:
		return keys[0]

	func push(k: float, v: int) -> void:
		keys.append(k)
		vals.append(v)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := vals[0]
		var last := keys.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := vals[a]
		vals[a] = vals[b]
		vals[b] = tv
