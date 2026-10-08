class_name ChunkGen
extends RefCounted
## Генерация чанка 32×32 тайла: высоты вершин (рельеф, выравнивание поселений, полотно дорог,
## русла и берега рек, окопы, воронки), поверхность, вода, дороги и мосты, постройки
## (стены по граням тайлов, двери, мебель), деревья и мелкая растительность.
## Всё детерминировано из сида планеты — повторная генерация даёт тот же чанк.
##
## Можно звать из рабочего потока: читает только неизменные данные планеты,
## общие кэши планировок защищены мьютексами поселений.

const N := Planet.CHUNK
const G := Planet.G

## Виды деревьев и крупных камней (блокируют тайл).
enum TREE { PINE, SPRUCE, OAK, BIRCH, MAPLE, WILLOW, PALM, JUNGLE, ACACIA, BAOBAB, DEAD, CACTUS, GLOWCAP, BOULDER, CHARRED }
## Мелочь без коллизий.
enum DECOR { GRASS, TALLGRASS, FLOWERS, FERN, BUSH, REED, PEBBLES, ROCK, LILY, DRYBUSH, MUSHROOMS, BONES, STUMP, SNOWDRIFT, CRATER_DEBRIS }


## Всё, что нужно генерации одного чанка и считается один раз: поля климата на сетке
## (N+2)×(N+2) (с каймой в тайл), список воронок, кандидаты деревьев.
class Ctx:
	var p: Planet
	var ox := 0
	var oy := 0
	var sites: Array = []
	var trenches: Array = []
	## [центр Vector2, радиус] воронок рядом с чанком
	var craters: Array = []
	var moist := PackedFloat32Array()
	var temp := PackedFloat32Array()
	var ash := PackedFloat32Array()
	var sea := PackedFloat32Array()
	var cand := PackedFloat32Array()
	var forest := PackedFloat32Array()

	func _init(planet: Planet, x0: int, y0: int) -> void:
		p = planet
		ox = x0
		oy = y0
		var m := N + 2
		moist.resize(m * m)
		temp.resize(m * m)
		ash.resize(m * m)
		sea.resize(m * m)
		# поле крупной сетки внутри чанка билинейно (чанк лежит в одной ячейке интерполяции),
		# поэтому достаточно значений в углах
		var corners := [Vector2(ox - 0.5, oy - 0.5), Vector2(ox + N + 1.5, oy - 0.5),
			Vector2(ox - 0.5, oy + N + 1.5), Vector2(ox + N + 1.5, oy + N + 1.5)]
		var cm := PackedFloat32Array()
		var ct := PackedFloat32Array()
		var ca := PackedFloat32Array()
		var cs := PackedFloat32Array()
		for q: Vector2 in corners:
			cm.append(p.sample_macro(p.m_moist, q.x, q.y))
			ct.append(p.sample_macro(p.m_temp, q.x, q.y))
			ca.append(p.sample_macro(p.m_ash, q.x, q.y))
			cs.append(p.sample_macro_bytes(p.m_sea, q.x, q.y))
		var span := float(N + 2)
		for ly in m:
			for lx in m:
				var ax := (lx + 0.5) / span
				var ay := (ly + 0.5) / span
				var i := ly * m + lx
				moist[i] = lerpf(lerpf(cm[0], cm[1], ax), lerpf(cm[2], cm[3], ax), ay)
				temp[i] = lerpf(lerpf(ct[0], ct[1], ax), lerpf(ct[2], ct[3], ax), ay)
				ash[i] = lerpf(lerpf(ca[0], ca[1], ax), lerpf(ca[2], ca[3], ax), ay)
				sea[i] = lerpf(lerpf(cs[0], cs[1], ax), lerpf(cs[2], cs[3], ax), ay)
		if maxf(maxf(ca[0], ca[1]), maxf(ca[2], ca[3])) > 0.15:
			_find_craters()
		cand.resize(m * m)
		forest.resize(m * m)
		for ly in m:
			for lx in m:
				var i := ly * m + lx
				var x := ox + lx - 1
				var y := oy + ly - 1
				var fo := p.n_forest.get_noise_2d(x + 0.5, y + 0.5)
				forest[i] = fo
				cand[i] = _candidate(x, y, fo, moist[i], temp[i], ash[i])

	## Индекс в сетке с каймой для мировых координат тайла.
	func gi(x: int, y: int) -> int:
		return (y - oy + 1) * (N + 2) + (x - ox + 1)

	func _candidate(x: int, y: int, fo: float, mo: float, te: float, a: float) -> float:
		var dens := 0.0
		if te < 0.12:
			dens = 0.03
		elif te > 0.74 and mo < 0.42:
			dens = 0.04
		elif mo < 0.3:
			dens = 0.03
		else:
			dens = 0.06 + mo * 0.25
		dens *= 0.35 + smoothstep(-0.2, 0.45, fo) * 2.2
		if a > 0.3:
			dens *= 0.6
		var v := float(U.hash3(p.seed_value, x, y) % 100000) / 100000.0
		return 0.0 if v > dens else 1.0 + v

	func _find_craters() -> void:
		for qy in range(floori((oy - 10.0) / 12.0), floori((oy + N + 10.0) / 12.0) + 1):
			for qx in range(floori((ox - 10.0) / 12.0), floori((ox + N + 10.0) / 12.0) + 1):
				var hs := U.hash3(p.seed_value, qx, qy)
				var cpos := Vector2((qx + float((hs / 1000) % 100) / 100.0) * 12.0, (qy + float((hs / 100000) % 100) / 100.0) * 12.0)
				var a := p.sample_macro(p.m_ash, cpos.x, cpos.y)
				if a < 0.15 or float(hs % 1000) / 1000.0 > a * 0.55:
					continue
				var rd := p.road_at(cpos.x, cpos.y)
				if rd.w > 0.0 and rd.x < rd.y + 4.0:
					continue
				if p.site_at(cpos.x, cpos.y) != null:
					continue
				craters.append([cpos, 1.6 + float((hs / 7) % 40) / 10.0])


static func generate(p: Planet, cx: int, cy: int) -> Chunk:
	var c := Chunk.new()
	c.cx = cx
	c.cy = cy
	c.ox = cx * N
	c.oy = cy * N
	var vn := N + 1
	c.hgt.resize(vn * vn)
	c.ground.resize(N * N)
	c.water.resize(N * N)
	c.water.fill(Chunk.NO_WATER)
	c.cost.resize(N * N)
	c.flags.resize(N * N)
	c.walls.resize(N * N)
	var rect := Rect2i(c.ox, c.oy, N, N)
	var sites: Array = p.sites_near_chunk(cx, cy)
	# постройки, задевающие чанк (нужны уже для высот: окопы)
	for st: Site in sites:
		for s: Dictionary in LayoutGen.structures_in(p, st, rect.grow(2)):
			c.structures.append([st, s])
			var sr: Rect2i = s["r"]
			if rect.has_point(sr.position):
				c.own.append([st, s])
	var ctx := Ctx.new(p, c.ox, c.oy)
	ctx.sites = sites
	for e: Array in c.structures:
		if e[1]["t"] == "trench":
			ctx.trenches.append(e[1]["pts"])
	# 1) высоты вершин
	for vy in vn:
		for vx in vn:
			c.hgt[vy * vn + vx] = corner_height(ctx, float(c.ox + vx), float(c.oy + vy))
	c.min_h = INF
	c.max_h = -INF
	for hh in c.hgt:
		c.min_h = minf(c.min_h, hh)
		c.max_h = maxf(c.max_h, hh)
	# 2) поверхность, вода, дороги
	for ty in N:
		for tx in N:
			_tile(ctx, c, tx, ty)
	# 3) постройки; клетки у дверей — тропа (там не вырастет дерево)
	for e: Array in c.structures:
		_apply_structure(p, c, e[0], e[1])
	for e: Array in c.structures:
		var door: Vector2i = e[1].get("door", Vector2i(-1, -1))
		if door.x >= c.ox and door.y >= c.oy and door.x < c.ox + N and door.y < c.oy + N:
			var di := c.li(door.x, door.y)
			if c.flags[di] & (Chunk.F_SOLID | Chunk.F_INDOOR) == 0:
				c.flags[di] |= Chunk.F_PATH
	# 4) стоимость шага
	for i in N * N:
		c.cost[i] = _cost(c, i)
	# 5) деревья и мелочь
	_vegetation(ctx, c)
	return c


# ---------------- высоты ----------------

## Высота вершины (м): рельеф → площадки поселений → полотно дорог → русла рек → окопы и воронки.
static func corner_height(ctx: Ctx, x: float, y: float) -> float:
	var p := ctx.p
	var h := p.height_base(x, y)
	var orig := h
	var in_site := 0.0
	for st: Site in ctx.sites:
		var d := Vector2(x - st.center.x, y - st.center.y).length()
		var fr := LayoutGen.flat_radius(st)
		if d < fr + 12.0 and orig > -0.4:
			var wgt := 1.0 - smoothstep(fr, fr + 12.0, d)
			h = lerpf(h, st.base_h, wgt)
			in_site = maxf(in_site, wgt)
	var rd := p.road_at(x, y)
	if rd.w > 0.0 and rd.x < rd.y + Planet.ROAD_FLAT and orig > -0.4:
		var target := lerpf(p.road_height(x, y), h, in_site)
		var wgt := 1.0 - smoothstep(rd.y, rd.y + Planet.ROAD_FLAT, rd.x)
		h = lerpf(h, target, wgt)
	var rv := p.river_at(x, y)
	if rv.w > 0.0:
		var hw := rv.y
		var lv := rv.z
		var d := rv.x
		if d < hw:
			var k := d / hw
			var depth := 0.45 + (0.8 + hw * 0.22) * (1.0 - k * k)
			h = minf(h, lv - depth)
		elif d < hw + Planet.BANK and orig > -0.4:
			var t := (d - hw) / Planet.BANK
			var bank := lv + 0.25 + t * 1.4
			if h > bank:
				h = lerpf(bank, h, smoothstep(0.0, 1.0, t))
			h = maxf(h, lv + 0.18)
	for pts: PackedVector2Array in ctx.trenches:
		var dt := _dist_poly(pts, Vector2(x, y))
		if dt < 1.6:
			h -= 1.6 * (1.0 - smoothstep(0.9, 1.6, dt))
	for cr: Array in ctx.craters:
		var cpos: Vector2 = cr[0]
		var rad: float = cr[1]
		var d := Vector2(x, y).distance_to(cpos)
		if d > rad * 1.5:
			continue
		var k := d / rad
		if k < 1.0:
			h -= (1.0 - k * k) * rad * 0.35
		else:
			h += (1.0 - smoothstep(1.0, 1.5, k)) * rad * 0.12
	return h


static func _dist_poly(pts: PackedVector2Array, q: Vector2) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a := pts[k]
		var ab := pts[k + 1] - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


# ---------------- тайлы ----------------

static func _tile(ctx: Ctx, c: Chunk, tx: int, ty: int) -> void:
	var p := ctx.p
	var sites := ctx.sites
	var vn := N + 1
	var i := ty * N + tx
	var h0 := c.hgt[ty * vn + tx]
	var h1 := c.hgt[ty * vn + tx + 1]
	var h2 := c.hgt[(ty + 1) * vn + tx]
	var h3 := c.hgt[(ty + 1) * vn + tx + 1]
	var th := (h0 + h1 + h2 + h3) * 0.25
	var slope := (maxf(maxf(h0, h1), maxf(h2, h3)) - minf(minf(h0, h1), minf(h2, h3))) / Planet.TILE_M
	var x := c.ox + tx
	var y := c.oy + ty
	var fx := x + 0.5
	var fy := y + 0.5
	# вода: река (свой уровень) или море (уровень 0); уровень хранится и у прибрежных тайлов,
	# чтобы плоскость воды заходила под берег без щелей
	var level := Chunk.NO_WATER
	var rv := p.river_at(fx, fy)
	if rv.w > 0.0 and rv.x < rv.y + 2.0:
		level = rv.z
	if th < 1.2 and p.continent(fx, fy) < 0.12:
		level = maxf(level, 0.0)
	c.water[i] = level
	var flags := 0
	if level > Chunk.NO_WATER and th < level - 0.05:
		c.has_water = true
		c.ground[i] = G.DEEP if level - th > 1.4 else G.SHALLOW
	else:
		c.has_land = true
		c.ground[i] = _land_ground(ctx, x, y, th, slope)
		if level > Chunk.NO_WATER:
			flags |= Chunk.F_SHORE
	# дороги и мосты
	var rd := p.road_at(fx, fy)
	var on_road := rd.w > 0.0 and rd.x < rd.y
	var site: Site = null
	for st: Site in sites:
		if Vector2(fx - st.center.x, fy - st.center.y).length() <= st.radius:
			site = st
			break
	if site != null:
		flags |= Chunk.F_SETTLE
		if site.is_city():
			var street := LayoutGen.city_street_at(site, x, y)
			if street > 0:
				on_road = true
			elif c.ground[i] != G.DEEP and c.ground[i] != G.SHALLOW and site.tech >= 2:
				# тротуары и дворы мощёные
				c.ground[i] = G.PAVED
				flags |= Chunk.F_PAVED
	if on_road:
		flags |= Chunk.F_ROAD
		if c.ground[i] == G.DEEP or c.ground[i] == G.SHALLOW:
			flags |= Chunk.F_BRIDGE
		else:
			var paved := site != null and site.tech >= 2 or int(rd.z) == 2 and rd.w > 0.0
			c.ground[i] = G.PAVED if paved else G.GRAVEL
			if paved:
				flags |= Chunk.F_PAVED
	c.flags[i] = flags


## Поверхность суши по климату, крутизне, высоте и близости моря и фронта.
static func _land_ground(ctx: Ctx, x: int, y: int, th: float, slope: float) -> int:
	if slope > 0.9:
		return G.CLIFF
	var p := ctx.p
	var fx := x + 0.5
	var fy := y + 0.5
	var gi := ctx.gi(x, y)
	var temp := p.temperature(fx, fy, th)
	var patch := p.n_patch.get_noise_2d(fx, fy)
	if th > p.snow_line(temp) + patch * 25.0:
		return G.SNOW
	if slope > 0.45:
		return G.ROCK if temp > 0.2 or patch > 0.0 else G.SNOW
	var ash := ctx.ash[gi]
	if ash > 0.5 + patch * 0.15:
		return G.ASH if patch < 0.25 else G.DIRT
	var moist := ctx.moist[gi] + patch * 0.1
	var sea_d := ctx.sea[gi]
	if th < 2.4 and sea_d < 1.3:
		return G.SAND
	if temp < 0.15:
		return G.SNOW if patch > -0.3 else G.DRYGRASS
	if temp > 0.74:
		if moist > 0.62:
			return G.JUNGLE if patch > -0.45 else G.MUD
		if moist > 0.42:
			return G.DRYGRASS if patch > -0.2 else G.DIRT
		if slope > 0.2 or patch > 0.4:
			return G.REDROCK
		return G.SAND
	if moist < 0.3:
		return G.DRYGRASS if patch > -0.35 else G.DIRT
	if moist > 0.78 and th < 9.0:
		return G.MUD if patch > 0.15 else G.GRASS
	if temp < 0.3 and patch > 0.45:
		return G.SNOW
	return G.DIRT if patch > 0.55 else G.GRASS


# ---------------- постройки ----------------

static func _apply_structure(p: Planet, c: Chunk, st: Site, s: Dictionary) -> void:
	var t: String = s["t"]
	var r: Rect2i = s["r"]
	var rect := Rect2i(c.ox, c.oy, N, N)
	match t:
		"path":
			_raster_line(c, s["pts"], 0.7, func(i: int) -> void:
				if c.flags[i] & (Chunk.F_ROAD | Chunk.F_SOLID) == 0 and c.ground[i] != G.DEEP and c.ground[i] != G.SHALLOW:
					c.ground[i] = G.DIRT
					c.flags[i] |= Chunk.F_PATH)
			return
		"trench":
			_raster_line(c, s["pts"], 1.4, func(i: int) -> void:
				c.flags[i] |= Chunk.F_TRENCH
				if c.ground[i] != G.DEEP and c.ground[i] != G.SHALLOW:
					c.ground[i] = G.DIRT)
			return
		"parapet":
			_raster_line(c, s["pts"], 0.9, func(i: int) -> void:
				c.flags[i] |= Chunk.F_SOLID)
			return
		"wire":
			_raster_line(c, s["pts"], 0.6, func(i: int) -> void:
				c.flags[i] |= Chunk.F_WIRE)
			return
	var area := r.intersection(rect)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	match t:
		"field":
			_fill(c, area, func(i: int) -> void:
				c.ground[i] = G.FARMLAND
				c.flags[i] |= Chunk.F_FIELD)
		"pasture", "pen":
			var gate: Vector2i = s.get("gate", Vector2i(-99999, 0))
			_fill(c, area, func(i: int) -> void:
				c.flags[i] |= Chunk.F_FIELD)
			for yy in range(area.position.y, area.end.y):
				for xx in range(area.position.x, area.end.x):
					var on_edge := xx == r.position.x or yy == r.position.y or xx == r.end.x - 1 or yy == r.end.y - 1
					if on_edge and Vector2i(xx, yy) != gate:
						c.flags[c.li(xx, yy)] |= Chunk.F_SOLID
		"pier":
			_fill(c, area, func(i: int) -> void:
				c.flags[i] |= Chunk.F_BRIDGE | Chunk.F_PIER)
		"park":
			_fill(c, area, func(i: int) -> void:
				if c.flags[i] & Chunk.F_ROAD == 0:
					c.ground[i] = G.GRASS
					c.flags[i] &= ~Chunk.F_PAVED)
		"plaza", "market", "landing_pad":
			_fill(c, area, func(i: int) -> void:
				c.ground[i] = G.PAVED
				c.flags[i] |= Chunk.F_PAVED)
		"gate":
			_fill(c, area, func(i: int) -> void:
				c.flags[i] |= Chunk.F_GATE)
		"ruin":
			for wt: Vector2i in s.get("walls", []):
				if rect.has_point(wt):
					c.flags[c.li(wt.x, wt.y)] |= Chunk.F_SOLID
		_:
			if InteriorGen.enterable(s):
				_building(c, st, s, area)
			elif s["solid"]:
				_fill(c, area, func(i: int) -> void:
					c.flags[i] |= Chunk.F_SOLID)


## Здание с интерьером: пол внутри, стены по граням, мебель блокирует свои тайлы.
static func _building(c: Chunk, st: Site, s: Dictionary, area: Rect2i) -> void:
	var bp := InteriorGen.ground_floor(s, st.mutex)
	var walls: Dictionary = bp["walls"]
	for yy in range(area.position.y, area.end.y):
		for xx in range(area.position.x, area.end.x):
			var i := c.li(xx, yy)
			c.flags[i] |= Chunk.F_INDOOR
			c.flags[i] &= ~Chunk.F_PAVED
			c.walls[i] = int(walls.get(Vector2i(xx, yy), 0))
			c.ground[i] = G.PAVED
	for f: Dictionary in bp["furniture"]:
		var q: Vector2i = f["p"]
		if f["block"] and area.has_point(q):
			c.flags[c.li(q.x, q.y)] |= Chunk.F_FURNITURE


static func _fill(c: Chunk, area: Rect2i, fn: Callable) -> void:
	for yy in range(area.position.y, area.end.y):
		for xx in range(area.position.x, area.end.x):
			fn.call(c.li(xx, yy))


## Тайлы чанка в пределах half_w от ломаной.
static func _raster_line(c: Chunk, pts: PackedVector2Array, half_w: float, fn: Callable) -> void:
	var rect := Rect2(c.ox - half_w, c.oy - half_w, N + half_w * 2.0, N + half_w * 2.0)
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		if not rect.intersects(Rect2(a.min(b), (a - b).abs()).grow(half_w + 1.0)):
			continue
		var x0 := maxi(c.ox, floori(minf(a.x, b.x) - half_w))
		var x1 := mini(c.ox + N - 1, floori(maxf(a.x, b.x) + half_w))
		var y0 := maxi(c.oy, floori(minf(a.y, b.y) - half_w))
		var y1 := mini(c.oy + N - 1, floori(maxf(a.y, b.y) + half_w))
		var ab := b - a
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var q := Vector2(xx + 0.5, yy + 0.5)
				var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				if q.distance_to(a + ab * t) <= half_w:
					fn.call(c.li(xx, yy))


# ---------------- проходимость ----------------

static func _cost(c: Chunk, i: int) -> int:
	var f := c.flags[i]
	if f & (Chunk.F_SOLID | Chunk.F_TREE | Chunk.F_FURNITURE):
		return 0
	var g := c.ground[i]
	if f & Chunk.F_BRIDGE:
		return 8
	if g == G.DEEP or g == G.CLIFF:
		return 0
	if f & Chunk.F_WIRE:
		return 60
	if f & Chunk.F_ROAD:
		return 7
	if f & (Chunk.F_PATH | Chunk.F_INDOOR | Chunk.F_PAVED):
		return 9
	return clampi(int(Planet.G_COST[g] * 10.0), 1, 250)


# ---------------- растительность ----------------

## Деревья ставятся там, где «кандидат» тайла — максимум среди соседей 3×3: так деревья
## не стоят вплотную даже на границе чанков (соседей можно посчитать без их чанка).
static func _vegetation(ctx: Ctx, c: Chunk) -> void:
	var p := ctx.p
	var trees := PackedFloat32Array()
	var decor := PackedFloat32Array()
	for ty in N:
		for tx in N:
			var i := ty * N + tx
			var x := c.ox + tx
			var y := c.oy + ty
			var f := c.flags[i]
			var g := c.ground[i]
			var free := f & (Chunk.F_ROAD | Chunk.F_SOLID | Chunk.F_INDOOR | Chunk.F_FIELD | Chunk.F_PATH | Chunk.F_TRENCH | Chunk.F_PAVED | Chunk.F_BRIDGE | Chunk.F_FURNITURE | Chunk.F_WIRE | Chunk.F_GATE) == 0
			var fx := x + 0.5
			var fy := y + 0.5
			if free and g != G.DEEP and g != G.SHALLOW and g != G.CLIFF and f & Chunk.F_SETTLE == 0:
				var gi := ctx.gi(x, y)
				var cand := ctx.cand[gi]
				if cand > 0.0:
					var best := true
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							if (ox != 0 or oy != 0) and ctx.cand[gi + oy * (N + 2) + ox] > cand:
								best = false
					if best:
						var kind := _tree_kind(ctx, x, y, c.tile_height(x, y), g)
						var hs := U.hash3(p.seed_value + 5, x, y)
						var jx := float(hs % 100) / 100.0 * 0.5 + 0.25
						var jy := float((hs / 100) % 100) / 100.0 * 0.5 + 0.25
						var sc := 0.75 + float((hs / 10000) % 100) / 100.0 * 0.6
						trees.append_array(PackedFloat32Array([x + jx, y + jy, sc, kind, float(hs % 628) / 100.0]))
						c.flags[i] |= Chunk.F_TREE
						continue
			_decor_tile(p, c, i, x, y, g, f, decor)
	c.trees = trees
	c.decor = decor


static func _tree_kind(ctx: Ctx, x: int, y: int, th: float, g: int) -> int:
	var p := ctx.p
	var gi := ctx.gi(x, y)
	var temp := p.temperature(x + 0.5, y + 0.5, th)
	var moist := ctx.moist[gi]
	var ash := ctx.ash[gi]
	var hs := U.hash3(p.seed_value + 9, x, y) % 100
	if g == G.ROCK or g == G.REDROCK or g == G.SNOW and hs < 30:
		return TREE.BOULDER
	if ash > 0.45:
		return TREE.CHARRED if hs < 70 else TREE.DEAD
	if temp < 0.3:
		return TREE.SPRUCE if hs < 55 else (TREE.PINE if hs < 90 else TREE.DEAD)
	if temp > 0.74:
		if moist > 0.62:
			if hs < 8:
				return TREE.GLOWCAP
			return TREE.JUNGLE if hs < 60 else TREE.PALM
		if moist > 0.42:
			return TREE.ACACIA if hs < 75 else TREE.BAOBAB
		return TREE.CACTUS if hs < 70 else TREE.DEAD
	if g == G.MUD or moist > 0.8:
		return TREE.WILLOW if hs < 60 else (TREE.GLOWCAP if hs < 70 else TREE.BIRCH)
	if g == G.SAND:
		return TREE.PALM if temp > 0.55 else TREE.PINE
	if hs < 30:
		return TREE.OAK
	if hs < 50:
		return TREE.BIRCH
	if hs < 70:
		return TREE.MAPLE
	return TREE.PINE


static func _decor_tile(p: Planet, c: Chunk, i: int, x: int, y: int, g: int, f: int, decor: PackedFloat32Array) -> void:
	if f & (Chunk.F_ROAD | Chunk.F_SOLID | Chunk.F_INDOOR | Chunk.F_PAVED | Chunk.F_BRIDGE | Chunk.F_FURNITURE | Chunk.F_GATE):
		return
	var hs := U.hash3(p.seed_value + 3, x, y)
	var count := 0
	var kinds: Array = []
	match g:
		G.GRASS:
			count = 3 + hs % 3
			kinds = [DECOR.GRASS, DECOR.GRASS, DECOR.TALLGRASS, DECOR.FLOWERS, DECOR.GRASS, DECOR.BUSH]
		G.DRYGRASS:
			count = 2 + hs % 3
			kinds = [DECOR.GRASS, DECOR.TALLGRASS, DECOR.DRYBUSH, DECOR.PEBBLES]
		G.JUNGLE:
			count = 4 + hs % 3
			kinds = [DECOR.FERN, DECOR.FERN, DECOR.TALLGRASS, DECOR.BUSH, DECOR.FLOWERS]
		G.MUD:
			count = 2
			kinds = [DECOR.REED, DECOR.TALLGRASS, DECOR.MUSHROOMS]
		G.SAND, G.REDROCK:
			count = hs % 2
			kinds = [DECOR.PEBBLES, DECOR.DRYBUSH, DECOR.BONES, DECOR.ROCK]
		G.ROCK, G.DIRT, G.GRAVEL:
			count = hs % 3
			kinds = [DECOR.PEBBLES, DECOR.ROCK, DECOR.DRYBUSH]
		G.SNOW:
			count = hs % 2
			kinds = [DECOR.SNOWDRIFT, DECOR.ROCK]
		G.ASH:
			count = hs % 3
			kinds = [DECOR.CRATER_DEBRIS, DECOR.BONES, DECOR.PEBBLES, DECOR.STUMP]
		G.SHALLOW:
			if f & Chunk.F_PIER == 0 and hs % 5 == 0:
				count = 1
				kinds = [DECOR.LILY]
		G.FARMLAND:
			return
	if f & Chunk.F_SHORE and g != G.SHALLOW and g != G.DEEP:
		count += 2
		kinds = [DECOR.REED, DECOR.REED, DECOR.TALLGRASS]
	if f & (Chunk.F_PATH | Chunk.F_TRENCH | Chunk.F_SETTLE) and count > 1:
		count = 1
	for k in count:
		var h2 := U.ihash(hs + k * 7919)
		var kind: int = kinds[h2 % kinds.size()]
		decor.append_array(PackedFloat32Array([x + float(h2 % 97) / 97.0, y + float((h2 / 97) % 89) / 89.0,
			0.7 + float((h2 / 9000) % 60) / 100.0, kind, float(h2 % 628) / 100.0]))
