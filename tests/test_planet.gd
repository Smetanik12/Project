extends SceneTree
## Проверки генерации планеты и чанков. Запуск:
##   godot --headless --path . --script res://tests/test_planet.gd
## Проверяет: детерминизм, поселения не пересекаются, постройки не налезают друг на друга,
## на воду и дороги, двери доступны с улицы, внутри домов нет отрезанных мест,
## деревья не стоят на постройках и дорогах, скорость генерации.

const SEED := 7
## Постройки-линии и площадки, которые проверяются отдельно (не прямоугольником).
const LINEAR := ["path", "trench", "parapet", "wire"]
## Плоские постройки, по которым можно ходить и которые могут лежать рядом с другими.
const FLAT := ["park", "plaza", "market", "landing_pad", "gate"]

var failures := 0
var checks := 0


func _initialize() -> void:
	DataDB.ensure_loaded()
	var t0 := Time.get_ticks_msec()
	var p := PlanetGen.generate(SEED)
	var gen_ms := Time.get_ticks_msec() - t0
	print("планета: %d мс, поселений %d, рек %d, дорог %d" % [gen_ms, p.sites.size(), p.rivers.size(), p.roads.size()])
	check(gen_ms < 30000, "генерация планеты дольше 30 с: %d мс" % gen_ms)
	_determinism(p)
	_population(p)
	_sites_apart(p)
	_landmarks(p)
	var total_chunks := 0
	var t1 := Time.get_ticks_msec()
	for id in _sample_sites(p):
		total_chunks += _check_site(p, p.sites[id])
	var per := float(Time.get_ticks_msec() - t1) / maxf(1.0, total_chunks)
	print("чанков проверено: %d, в среднем %.1f мс на чанк (с проверками)" % [total_chunks, per])
	_wild_chunks(p)
	print("")
	if failures == 0:
		print("ВСЕ ПРОВЕРКИ ПЛАНЕТЫ ПРОЙДЕНЫ (%d)" % checks)
	else:
		print("ОШИБОК: %d из %d проверок" % [failures, checks])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		if failures <= 60:
			print("  ✗ " + msg)


func _determinism(p: Planet) -> void:
	var q := PlanetGen.generate(SEED)
	check(q.sites.size() == p.sites.size(), "другое число поселений при том же сиде")
	var same := true
	for id in p.site_order:
		if not q.sites.has(id) or q.sites[id].center != p.sites[id].center or q.sites[id].name != p.sites[id].name:
			same = false
			break
	check(same, "поселения отличаются при том же сиде")
	var a := p.chunk(300, 150)
	var b := q.chunk(300, 150)
	check(a.hgt == b.hgt and a.ground == b.ground and a.flags == b.flags and a.trees == b.trees, "чанк отличается при том же сиде")
	print("детерминизм: ок")


func _population(p: Planet) -> void:
	var total := 0
	for id in p.site_order:
		var st: Site = p.sites[id]
		total += st.population()
		check(st.population() == st.pop0, "%s: население по профессиям (%d) не равно общему (%d)" % [id, st.population(), st.pop0])
		check(st.name != "" and st.where != "" and st.from != "" and st.near != "", "%s: нет названия или форм" % id)
		check(p.in_bounds(st.center.x, st.center.y), "%s вне карты" % id)
	print("население планеты: %d" % total)
	check(total > 1000000, "меньше миллиона жителей: %d" % total)


func _sites_apart(p: Planet) -> void:
	var list: Array = p.sites.values()
	var bad := 0
	for a in list.size():
		for b in range(a + 1, list.size()):
			var sa: Site = list[a]
			var sb: Site = list[b]
			if Vector2(sa.center).distance_to(Vector2(sb.center)) < sa.radius + sb.radius:
				bad += 1
				if bad <= 5:
					check(false, "поселения пересекаются: %s и %s" % [sa.id, sb.id])
	check(bad == 0, "пересекающихся пар поселений: %d" % bad)


func _landmarks(p: Planet) -> void:
	for d: Dictionary in DataDB.landmarks["list"]:
		check(p.sites.has(d["id"]), "нет особого поселения %s" % d["id"])
	var imp: Site = p.sites.get("pepel_imp")
	var fr: Site = p.sites.get("pepel_front")
	if imp != null and fr != null:
		var d := Vector2(imp.center).distance_to(Vector2(fr.center))
		check(d > 150.0 and d < 900.0, "окопы фронта стоят странно: расстояние %.0f" % d)
		check(p.owner_at(imp.center.x, imp.center.y) == "empire", "имперский окоп не на земле Империи")
		check(p.owner_at(fr.center.x, fr.center.y) == "front", "окоп Фронта не на земле Фронта")


## Особые поселения + по несколько каждого вида.
func _sample_sites(p: Planet) -> Array:
	var out: Array = []
	var per_kind := {}
	for id in p.site_order:
		var st: Site = p.sites[id]
		var n := int(per_kind.get(st.kind, 0))
		if st.landmark or n < 3:
			out.append(id)
			per_kind[st.kind] = n + 1
	return out


## Чанки вокруг поселения: постройки не пересекаются, не на воде и дорогах, двери доступны.
func _check_site(p: Planet, st: Site) -> int:
	var r := mini(st.radius + 40, 110)
	var c0 := Vector2i(floori(float(st.center.x - r) / Planet.CHUNK), floori(float(st.center.y - r) / Planet.CHUNK))
	var c1 := Vector2i(floori(float(st.center.x + r) / Planet.CHUNK), floori(float(st.center.y + r) / Planet.CHUNK))
	var chunks := {}
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			chunks[Vector2i(cx, cy)] = p.chunk(cx, cy)
	var area := Rect2i(c0 * Planet.CHUNK, (c1 - c0 + Vector2i.ONE) * Planet.CHUNK)
	var structs := LayoutGen.structures_in(p, st, area)
	var label := "%s (%s)" % [st.name, st.kind]
	# 1) прямоугольные постройки не пересекаются
	var rects: Array = []
	for s: Dictionary in structs:
		if s["t"] in LINEAR:
			continue
		rects.append(s)
	var overlaps := 0
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			var ra: Rect2i = rects[a]["r"]
			var rb: Rect2i = rects[b]["r"]
			if ra.intersects(rb):
				overlaps += 1
				if overlaps <= 3:
					check(false, "%s: %s %s налезает на %s %s" % [label, rects[a]["t"], ra, rects[b]["t"], rb])
	check(overlaps == 0, "%s: пересечений построек %d" % [label, overlaps])
	# 2) здания не на воде и не на дорогах; 3) двери доступны
	var wet := 0
	var on_road := 0
	var bad_door := 0
	for s: Dictionary in rects:
		var t: String = s["t"]
		if t in FLAT or t == "pier" or t == "field" or t == "pasture" or t == "pen":
			continue
		var sr: Rect2i = s["r"]
		var w0 := wet
		var r0 := on_road
		for y in range(sr.position.y, sr.end.y):
			for x in range(sr.position.x, sr.end.x):
				var ch: Chunk = chunks.get(Vector2i(floori(float(x) / Planet.CHUNK), floori(float(y) / Planet.CHUNK)))
				if ch == null:
					continue
				var i := ch.li(x, y)
				var g := ch.ground[i]
				if g == Planet.G.DEEP or g == Planet.G.SHALLOW:
					wet += 1
				if ch.flags[i] & Chunk.F_ROAD:
					on_road += 1
		if (wet > w0 or on_road > r0) and wet + on_road - w0 - r0 > 0 and failures < 40:
			var q := sr.get_center()
			print("    %s %s: на воде %d, на дороге %d; высота %.2f, река %s, дорога %s" % [t, sr, wet - w0, on_road - r0,
				p.height_at(q.x + 0.5, q.y + 0.5), p.river_at(q.x + 0.5, q.y + 0.5), p.road_at(q.x + 0.5, q.y + 0.5)])
		var door: Vector2i = s["door"]
		if door.x >= 0 and area.has_point(door):
			var ch2: Chunk = chunks[Vector2i(floori(float(door.x) / Planet.CHUNK), floori(float(door.y) / Planet.CHUNK))]
			if ch2.cost[ch2.li(door.x, door.y)] == 0:
				bad_door += 1
				if bad_door <= 3:
					check(false, "%s: дверь %s у %s %s заблокирована" % [label, door, t, sr])
	check(wet == 0, "%s: тайлов зданий на воде: %d" % [label, wet])
	check(on_road == 0, "%s: тайлов зданий на дороге: %d" % [label, on_road])
	check(bad_door == 0, "%s: заблокированных дверей %d" % [label, bad_door])
	# 4) деревья не на постройках, дорогах и воде
	var bad_tree := 0
	for key in chunks:
		var ch: Chunk = chunks[key]
		for k in range(0, ch.trees.size(), 5):
			var tx := floori(ch.trees[k])
			var ty := floori(ch.trees[k + 1])
			var i := ch.li(tx, ty)
			var f := ch.flags[i]
			if f & (Chunk.F_ROAD | Chunk.F_SOLID | Chunk.F_INDOOR | Chunk.F_FIELD | Chunk.F_PATH | Chunk.F_PAVED | Chunk.F_BRIDGE):
				bad_tree += 1
			var g := ch.ground[i]
			if g == Planet.G.DEEP or g == Planet.G.SHALLOW:
				bad_tree += 1
	check(bad_tree == 0, "%s: деревьев на постройках/дорогах/воде: %d" % [label, bad_tree])
	# 5) внутри зданий всё достижимо от входа
	var cut := 0
	for s: Dictionary in rects:
		if not InteriorGen.enterable(s):
			continue
		var bp := InteriorGen.ground_floor(s, st.mutex)
		if bp["entry"].x < 0:
			continue
		var unreach := _unreachable_inside(s, bp)
		if unreach > 0:
			cut += 1
			if cut <= 3:
				check(false, "%s: в %s %s недостижимо клеток: %d" % [label, s["t"], s["r"], unreach])
	check(cut == 0, "%s: зданий с отрезанными комнатами: %d" % [label, cut])
	# 6) от двери любого здания можно дойти до центра поселения
	_doors_connected(p, st, chunks, rects, label)
	return chunks.size()


func _unreachable_inside(s: Dictionary, bp: Dictionary) -> int:
	var r: Rect2i = s["r"]
	var walls: Dictionary = bp["walls"]
	var blocked := {}
	for f: Dictionary in bp["furniture"]:
		if f["block"]:
			blocked[f["p"]] = true
	var start: Vector2i = bp["entry"]
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for bit in [1, 2, 4, 8]:
			if InteriorGen.blocked(walls, c, bit):
				continue
			var nb: Vector2i = c + InteriorGen.DIRS[bit]
			if r.has_point(nb) and not seen.has(nb) and not blocked.has(nb):
				seen[nb] = true
				q.append(nb)
	var missing := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not seen.has(t) and not blocked.has(t):
				missing += 1
	return missing


## Волна от центра поселения по проходимым тайлам (с учётом стен по граням);
## двери всех зданий в проверяемой области должны быть достигнуты.
func _doors_connected(p: Planet, st: Site, chunks: Dictionary, rects: Array, label: String) -> void:
	var start := Vector2i(-1, -1)
	for rr in 30:
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if start.x >= 0:
					break
				var t := st.center + Vector2i(dx, dy)
				var ch: Chunk = chunks.get(Vector2i(floori(float(t.x) / Planet.CHUNK), floori(float(t.y) / Planet.CHUNK)))
				if ch != null and ch.cost[ch.li(t.x, t.y)] > 0 and ch.flags[ch.li(t.x, t.y)] & Chunk.F_INDOOR == 0:
					start = t
	if start.x < 0:
		check(false, "%s: нет проходимой клетки у центра" % label)
		return
	var seen := {start: true}
	var q: Array = [start]
	var dirs := [[Vector2i(0, -1), 1, 4], [Vector2i(1, 0), 2, 8], [Vector2i(0, 1), 4, 1], [Vector2i(-1, 0), 8, 2]]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		var ch: Chunk = chunks[Vector2i(floori(float(c.x) / Planet.CHUNK), floori(float(c.y) / Planet.CHUNK))]
		var wc := ch.walls[ch.li(c.x, c.y)]
		for d: Array in dirs:
			var nb: Vector2i = c + d[0]
			var chn: Chunk = chunks.get(Vector2i(floori(float(nb.x) / Planet.CHUNK), floori(float(nb.y) / Planet.CHUNK)))
			if chn == null or seen.has(nb):
				continue
			var ni := chn.li(nb.x, nb.y)
			if chn.cost[ni] == 0 or (wc & int(d[1])) != 0 or (chn.walls[ni] & int(d[2])) != 0:
				continue
			seen[nb] = true
			q.append(nb)
	var unreached := 0
	for s: Dictionary in rects:
		var door: Vector2i = s["door"]
		if door.x < 0 or not chunks.has(Vector2i(floori(float(door.x) / Planet.CHUNK), floori(float(door.y) / Planet.CHUNK))):
			continue
		if not seen.has(door):
			unreached += 1
			if unreached <= 3:
				check(false, "%s: к двери %s у %s %s не дойти от центра" % [label, door, s["t"], s["r"]])
	check(unreached == 0, "%s: недостижимых дверей %d" % [label, unreached])


## Дикие места: чанки в случайных точках суши генерируются и не содержат мусора.
func _wild_chunks(p: Planet) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var t0 := Time.get_ticks_msec()
	var n := 0
	for k in 40:
		var cx := rng.randi_range(0, p.w / Planet.CHUNK - 1)
		var cy := rng.randi_range(0, p.h / Planet.CHUNK - 1)
		var ch := p.chunk(cx, cy)
		n += 1
		check(ch.hgt.size() == (Planet.CHUNK + 1) * (Planet.CHUNK + 1), "чанк без высот")
		for hh in ch.hgt:
			if is_nan(hh) or absf(hh) > 2000.0:
				check(false, "странная высота %.1f в чанке %d,%d" % [hh, cx, cy])
				break
	print("случайных чанков: %d, %.1f мс на чанк" % [n, float(Time.get_ticks_msec() - t0) / n])
