class_name WorldGen
extends RefCounted
## Генерация мира: рельеф по шуму, поселения из data/settlements.json, дороги, жители.

const W := 160
const H := 110
const T := MapData.T


static func generate(world_seed: int) -> World:
	DataDB.ensure_loaded()
	var w := World.new()
	w.world_seed = world_seed
	w.rng.seed = world_seed
	w.map = MapData.new(W, H)
	_terrain(w)
	_factions(w)
	_settlements(w)
	_roads(w)
	w.map.build_astar()
	w.build_settle_grid()
	for s: Settlement in w.settlements.values():
		_populate(w, s)
	w._update_residents()
	return w


static func _terrain(w: World) -> void:
	var elev := FastNoiseLite.new()
	elev.seed = w.world_seed
	elev.frequency = 0.03
	elev.fractal_octaves = 4
	var moist := FastNoiseLite.new()
	moist.seed = w.world_seed + 7
	moist.frequency = 0.05
	for y in H:
		for x in W:
			var e := elev.get_noise_2d(x, y)
			var m := moist.get_noise_2d(x, y)
			var fx := float(x) / W
			var fy := float(y) / H
			# южное море у пиратского порта
			e -= maxf(0.0, fy - 0.9) * 4.0
			var t := T.GRASS
			if e < -0.33:
				t = T.WATER
			elif e > 0.4:
				t = T.MOUNTAIN
			elif e > 0.28:
				t = T.ROCK
			elif fy > 0.62 + m * 0.12:
				t = T.SAND
			elif absf(fx - 0.5) < 0.09 + m * 0.04 and fy < 0.42:
				t = T.ASH
			elif m > 0.18:
				t = T.DIRT
			w.map.set_t(Vector2i(x, y), t)


static func _factions(w: World) -> void:
	for id in DataDB.faction_ids():
		var f := Faction.new()
		f.id = id
		w.factions[id] = f
	for r in DataDB.factions.get("_relations", []):
		var a: String = r[0]
		var b: String = r[1]
		w.factions[a].relations[b] = int(r[2])
		w.factions[b].relations[a] = int(r[2])
	w.flags["wars"] = DataDB.factions.get("_wars", []).duplicate(true)


static func _settlements(w: World) -> void:
	for d in DataDB.settlements["list"]:
		var s := Settlement.new()
		s.id = d["id"]
		s.name = d["name"]
		s.where = d["where"]
		s.from = d["from"]
		s.near = d["near"]
		s.kind = d["kind"]
		s.faction = d["faction"]
		s.radius = int(d["r"])
		var p: Array = d["pos"]
		s.center = Vector2i(int(p[0] * W), int(p[1] * H)) + Vector2i(w.rng.randi_range(-3, 3), w.rng.randi_range(-2, 2))
		s.center = s.center.clamp(Vector2i(s.radius + 2, s.radius + 2), Vector2i(W - s.radius - 3, H - s.radius - 3))
		for g in d.get("passive", {}):
			s.passive[g] = float(d["passive"][g])
		for g in DataDB.good_ids():
			s.stock[g] = float(d.get("stock", {}).get(g, 0))
		_clear_area(w, s.center, s.radius + 1)
		s.buildings = _buildings(w, s)
		w.settlements[s.id] = s
		if s.kind == "capital" or s.kind == "base" or (s.kind == "port" and s.faction == "syndicate") \
				or (s.kind == "hub" and s.faction == "guild") or (s.kind == "scav") \
				or (s.id == "rodnik"):
			var f: Faction = w.factions[s.faction]
			if f.capital == "":
				f.capital = s.id


static func _clear_area(w: World, c: Vector2i, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := c + Vector2i(dx, dy)
			if w.map.in_bounds(p) and dx * dx + dy * dy <= r * r:
				w.map.set_t(p, T.DIRT)


static func _buildings(w: World, s: Settlement) -> Array:
	var out := []
	var c := s.center
	var r := s.radius
	match s.kind:
		"capital":
			out.append({"t": "wall", "r": Rect2i(c - Vector2i(r - 1, r - 1), Vector2i(r * 2 - 1, r * 2 - 1))})
			_place(w, out, s, "house", 6, Vector2i(2, 2), Vector2i(4, 3))
		"trench":
			out.append({"t": "trench", "r": Rect2i(c.x - 3, c.y - 1, 7, 1)})
			out.append({"t": "trench", "r": Rect2i(c.x - 2, c.y + 1, 5, 1)})
			_place(w, out, s, "tent", 2, Vector2i(2, 1), Vector2i(2, 2))
		"base":
			_place(w, out, s, "tent", 4, Vector2i(2, 2), Vector2i(3, 2))
			_place(w, out, s, "house", 2, Vector2i(3, 2), Vector2i(4, 3))
		"mine":
			out.append({"t": "mine", "r": Rect2i(c.x - 1, c.y - 2, 3, 2)})
			_place(w, out, s, "house", 1, Vector2i(3, 2), Vector2i(3, 2))
			_place(w, out, s, "tent", 3, Vector2i(2, 1), Vector2i(2, 2))
		"port":
			_place(w, out, s, "house", 4, Vector2i(2, 2), Vector2i(4, 3))
			_place(w, out, s, "junk", 2, Vector2i(1, 1), Vector2i(2, 2))
		"hub":
			_place(w, out, s, "house", 6, Vector2i(3, 2), Vector2i(4, 3))
			_place(w, out, s, "stall", 4, Vector2i(1, 1), Vector2i(2, 1))
		"post":
			_place(w, out, s, "house", 2, Vector2i(2, 2), Vector2i(3, 2))
			_place(w, out, s, "stall", 2, Vector2i(1, 1), Vector2i(2, 1))
		"village":
			_place(w, out, s, "field", 3, Vector2i(3, 2), Vector2i(4, 3))
			_place(w, out, s, "house", 3, Vector2i(2, 2), Vector2i(3, 2))
		"scav":
			_place(w, out, s, "junk", 5, Vector2i(1, 1), Vector2i(3, 2))
			_place(w, out, s, "tent", 3, Vector2i(2, 1), Vector2i(2, 2))
		"wreck":
			out.append({"t": "hull", "r": Rect2i(c.x - 3, c.y - 1, 6, 3)})
	return out


static func _place(w: World, out: Array, s: Settlement, t: String, count: int, smin: Vector2i, smax: Vector2i) -> void:
	for i in count:
		for attempt in 25:
			var size := Vector2i(w.rng.randi_range(smin.x, smax.x), w.rng.randi_range(smin.y, smax.y))
			var lim := s.radius - 1
			var pos := s.center + Vector2i(w.rng.randi_range(-lim, lim - size.x + 1), w.rng.randi_range(-lim, lim - size.y + 1))
			var rect := Rect2i(pos, size)
			if not s.contains(rect.position) or not s.contains(rect.end - Vector2i.ONE):
				continue
			var ok := true
			for b in out:
				if b["t"] != "wall" and (b["r"] as Rect2i).grow(1).intersects(rect):
					ok = false
					break
			if ok:
				out.append({"t": t, "r": rect})
				break


static func _roads(w: World) -> void:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, W, H)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			var t := w.map.get_t(p)
			var cost := 1.0
			match t:
				T.WATER: cost = 14.0
				T.MOUNTAIN: cost = 9.0
				T.ROCK: cost = 2.5
				T.SAND: cost = 1.5
			grid.set_point_weight_scale(p, cost)
	for pair in DataDB.settlements.get("roads", []):
		var a: Settlement = w.settlements[pair[0]]
		var b: Settlement = w.settlements[pair[1]]
		for p in grid.get_id_path(a.center, b.center):
			var i := w.map.idx(p)
			w.map.road[i] = 1
			# уже проложенная дорога дешевле — дороги сливаются в сеть
			grid.set_point_weight_scale(p, 0.5)
			if not MapData.PASSABLE[w.map.tiles[i]]:
				w.map.tiles[i] = T.DIRT


static func _populate(w: World, s: Settlement) -> void:
	for d in DataDB.settlements["list"]:
		if d["id"] != s.id:
			continue
		var pop: Dictionary = d.get("pop", {})
		for role in pop:
			for i in int(pop[role]):
				make_npc(w, role, s.faction, s.id)


static func make_npc(w: World, role: String, faction: String, home: String) -> NPC:
	var n := NPC.new()
	n.id = w.new_id()
	n.role = role
	n.faction = faction
	n.home = home
	var fighter := bool(DataDB.role_data(role).get("fighter", false))
	n.female = w.rng.randf() < (0.35 if fighter else 0.5)
	var firsts: Array = DataDB.names["female" if n.female else "male"]
	var lasts: Array = DataDB.names["last"]
	n.first = firsts[w.rng.randi() % firsts.size()]
	n.last = lasts[w.rng.randi() % lasts.size()]
	if n.female:
		n.last = U.female_surname(n.last)
	n.traits = _random_traits(w, role)
	n.money = int(DataDB.role_data(role).get("money", 10)) + w.rng.randi_range(0, 20)
	if fighter:
		n.cargo["weapons"] = 1
	n.cargo["food"] = w.rng.randi_range(0, 2)
	n.hunger = w.rng.randf_range(0.0, 50.0)
	var s: Settlement = w.settlements[home]
	n.pos = w.random_point_in(s)
	n.prev_pos = n.pos
	n.target_pos = n.pos
	w.npcs[n.id] = n
	return n


static func _random_traits(w: World, role: String) -> Array:
	var pool: Array = DataDB.traits.keys()
	var out := []
	# склонности по роли
	var bias := {"pirate": ["cruel", "greedy", "hothead"], "soldier": ["brave", "zealot"],
		"officer": ["zealot", "paranoid"], "merchant": ["greedy", "gossip"], "barkeep": ["gossip"],
		"slave": ["coward", "kind"], "leader": ["vain", "zealot"], "scavenger": ["greedy"]}
	var count := w.rng.randi_range(1, 3)
	if bias.has(role) and w.rng.randf() < 0.6:
		var b: Array = bias[role]
		out.append(b[w.rng.randi() % b.size()])
	var guard := 0
	while out.size() < count and guard < 30:
		guard += 1
		var t: String = pool[w.rng.randi() % pool.size()]
		if t in out:
			continue
		var bad := false
		for o in out:
			if t in DataDB.traits[o].get("conflicts", []):
				bad = true
		if not bad:
			out.append(t)
	return out
