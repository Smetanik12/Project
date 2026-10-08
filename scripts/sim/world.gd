class_name World
extends RefCounted
## Всё состояние игрового мира и главный цикл симуляции.
## Мир живёт тиками (1 тик = 5 игровых минут) независимо от игрока и графики.

const PLAYER := 0
const TICK_MINUTES := 5
const TICKS_PER_HOUR := 12
const TICKS_PER_DAY := 288
const BUCKET := 8
const FACTS_CAP := 900
## Где защитники сражаются из укрытий.
const FORTIFIED := ["capital", "trench", "base", "mine", "port"]

var world_seed := 0
var rng := RandomNumberGenerator.new()
var tick := 0
var map: MapData
var factions: Dictionary = {}
var settlements: Dictionary = {}
var npcs: Dictionary = {}
var facts: Dictionary = {}
var player := PlayerState.new()
var scenario := ""
var flags: Dictionary = {}
var next_id := 1
## Все события мира (режим «всевидящее око»): [{"tick": int, "text": String}]
var chronicle: Array = []
var corpses: Array = []

# --- не сохраняется, пересчитывается ---
var hits: Array = []
var settle_grid := PackedInt32Array()
var settle_ids: Array = []
var residents_cache: Dictionary = {}
var buckets: Dictionary = {}
var game_over := false
## Всплывающие сообщения для интерфейса.
var notices: Array = []


func new_id() -> int:
	next_id += 1
	return next_id - 1


# ---------------- время ----------------

func minutes() -> int:
	return tick * TICK_MINUTES


func day() -> int:
	return minutes() / 1440 + 1


func hour() -> int:
	return (minutes() % 1440) / 60


func is_night() -> bool:
	var h := hour()
	return h >= 22 or h < 6


func time_str() -> String:
	var m := minutes() % 1440
	return "День %d, %02d:%02d" % [day(), m / 60, m % 60]


# ---------------- главный цикл ----------------

func step() -> void:
	tick += 1
	_build_buckets()
	NpcAI.tick(self)
	Combat.tick(self)
	if tick % TICKS_PER_HOUR == 0:
		_hourly()
	if tick % TICKS_PER_DAY == 6 * TICKS_PER_HOUR:
		FactionAI.daily(self)
	if not hits.is_empty() and tick - int(hits[0]["tick"]) > 3:
		var keep := []
		for h in hits:
			if tick - int(h["tick"]) <= 3:
				keep.append(h)
		hits = keep


func _hourly() -> void:
	_update_residents()
	Economy.hourly(self)
	NpcAI.hourly(self)
	Rumors.hourly(self)
	FactionAI.hourly(self)
	Scenarios.hourly(self)
	_player_hourly()
	if hour() == 0:
		Economy.daily(self)
		_cleanup()


func _player_hourly() -> void:
	if not player.alive:
		return
	player.hunger += 3.0
	if player.hunger >= 60.0 and int(player.inv.get("food", 0)) > 0:
		player.add_item("food", -1)
		player.hunger = 0.0
		notify("Ты поел%s." % player.a())
	if player.hunger >= 100.0:
		player.hunger = 100.0
		player.hp -= 4.0
		notify("Ты голодаешь! Найди еду.")
		if player.hp <= 0.0:
			Combat.kill(self, PLAYER, -1)
	elif player.hp < 100.0:
		player.hp = minf(100.0, player.hp + 1.0)


func _cleanup() -> void:
	var keep := []
	for c in corpses:
		if tick - int(c["tick"]) < TICKS_PER_DAY * 2:
			keep.append(c)
	corpses = keep
	if chronicle.size() > 400:
		chronicle = chronicle.slice(chronicle.size() - 400)
	if player.journal.size() > 300:
		player.journal = player.journal.slice(player.journal.size() - 300)


# ---------------- пространство ----------------

func build_settle_grid() -> void:
	settle_ids = settlements.keys()
	settle_grid.resize(map.w * map.h)
	settle_grid.fill(-1)
	for i in settle_ids.size():
		var s: Settlement = settlements[settle_ids[i]]
		for dy in range(-s.radius, s.radius + 1):
			for dx in range(-s.radius, s.radius + 1):
				var p := s.center + Vector2i(dx, dy)
				if map.in_bounds(p) and s.contains(p):
					settle_grid[map.idx(p)] = i


func settlement_at(p: Vector2i) -> Settlement:
	if not map.in_bounds(p):
		return null
	var i := settle_grid[map.idx(p)]
	if i < 0:
		return null
	return settlements[settle_ids[i]]


func nearest_settlement(p: Vector2i, skip_wreck := true) -> Settlement:
	var best: Settlement = null
	var best_d := INF
	for s: Settlement in settlements.values():
		if skip_wreck and s.kind == "wreck":
			continue
		var d := Vector2(s.center - p).length()
		if d < best_d:
			best_d = d
			best = s
	return best


func place_phrase(p: Vector2i) -> String:
	var s := settlement_at(p)
	if s != null:
		return s.where
	return nearest_settlement(p, false).near


func random_point_in(s: Settlement) -> Vector2i:
	for i in 12:
		var r := maxi(1, s.radius - 1)
		var p := s.center + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r))
		if s.contains(p) and map.is_passable(p):
			return p
	return map.nearest_passable(s.center)


func _build_buckets() -> void:
	buckets.clear()
	for n: NPC in npcs.values():
		if not n.alive or n.jailed:
			continue
		var key := Vector2i(n.pos.x / BUCKET, n.pos.y / BUCKET)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(n.id)
	if player.alive:
		var pk := Vector2i(player.tile().x / BUCKET, player.tile().y / BUCKET)
		if not buckets.has(pk):
			buckets[pk] = []
		buckets[pk].append(PLAYER)


## id всех живых участников (NPC и игрок) в радиусе r тайлов.
func actors_near(p: Vector2, r: float) -> Array:
	var out := []
	var c0 := Vector2i(floori((p.x - r) / BUCKET), floori((p.y - r) / BUCKET))
	var c1 := Vector2i(floori((p.x + r) / BUCKET), floori((p.y + r) / BUCKET))
	for by in range(c0.y, c1.y + 1):
		for bx in range(c0.x, c1.x + 1):
			var key := Vector2i(bx, by)
			if not buckets.has(key):
				continue
			for id in buckets[key]:
				if actor_pos(id).distance_to(p) <= r:
					out.append(id)
	return out


# ---------------- участники (NPC или игрок) ----------------

func actor_pos(id: int) -> Vector2:
	if id == PLAYER:
		return player.pos
	return Vector2(npcs[id].pos) + Vector2(0.5, 0.5)


func actor_tile(id: int) -> Vector2i:
	if id == PLAYER:
		return player.tile()
	return npcs[id].pos


func actor_alive(id: int) -> bool:
	if id == PLAYER:
		return player.alive
	if not npcs.has(id):
		return false
	var n: NPC = npcs[id]
	return n.alive and not n.jailed


func actor_name(id: int) -> String:
	if id == PLAYER:
		return player.name
	if npcs.has(id):
		return npcs[id].full_name()
	return "кто-то"


func actor_female(id: int) -> bool:
	if id == PLAYER:
		return player.female
	return npcs.has(id) and npcs[id].female


func actor_faction(id: int) -> String:
	if id == PLAYER:
		return player.faction
	return npcs[id].faction if npcs.has(id) else ""


func actor_power(id: int) -> float:
	if id == PLAYER:
		return player.power()
	var n: NPC = npcs[id]
	var p := n.combat_power()
	var s := settlement_at(n.pos)
	if s != null and s.faction == n.faction and s.kind in FORTIFIED:
		p += 2.5
	return p


func followers() -> Array:
	var out := []
	for n: NPC in npcs.values():
		if n.alive and n.follow_id == PLAYER:
			out.append(n)
	return out


# ---------------- отношения ----------------

func faction_hostile(a: String, b: String) -> bool:
	if a == "" or b == "" or a == b:
		return false
	return factions[a].rel(b) <= Faction.HOSTILE


func change_relation(a: String, b: String, delta: int) -> void:
	if a == b or not factions.has(a) or not factions.has(b):
		return
	var fa: Faction = factions[a]
	var fb: Faction = factions[b]
	var before := fa.rel(b)
	var after := clampi(before + delta, -100, 100)
	fa.relations[b] = after
	fb.relations[a] = after
	if before > Faction.HOSTILE and after <= Faction.HOSTILE:
		log_event("%s и %s теперь враги." % [U.cap(fa.members()), fb.members()])
	elif before <= Faction.HOSTILE and after > Faction.HOSTILE:
		log_event("%s и %s больше не воюют." % [U.cap(fa.members()), fb.members()])


func npc_hostile_to_player(n: NPC) -> bool:
	if n.follow_id == PLAYER:
		return false
	if n.grudges.has(PLAYER):
		return true
	if n.bribed_day >= day() - 1:
		return false
	if n.faction == "" or not factions.has(n.faction):
		return false
	var f: Faction = factions[n.faction]
	return f.bounties.has("player") or f.player_rep <= Faction.HOSTILE


func is_hostile(a: int, b: int) -> bool:
	if a == b:
		return false
	if a == PLAYER:
		return npc_hostile_to_player(npcs[b])
	if b == PLAYER:
		return npc_hostile_to_player(npcs[a])
	var na: NPC = npcs[a]
	var nb: NPC = npcs[b]
	if na.grudges.has(b) or nb.grudges.has(a):
		return true
	var a_f := na.follow_id == PLAYER
	var b_f := nb.follow_id == PLAYER
	if a_f and b_f:
		return false
	if a_f:
		return npc_hostile_to_player(nb)
	if b_f:
		return npc_hostile_to_player(na)
	if na.faction == nb.faction or na.faction == "" or nb.faction == "":
		return false
	if factions[na.faction].bounties.has(b) or factions[nb.faction].bounties.has(a):
		return true
	return faction_hostile(na.faction, nb.faction)


# ---------------- факты и сообщения ----------------

## Создаёт факт. Все в радиусе witness_radius видят его своими глазами.
func add_fact(type: String, p: Vector2i, data: Dictionary, importance := 1,
		witness_radius := 8.0, truth := true) -> Fact:
	var f := Fact.new()
	f.id = new_id()
	f.type = type
	f.tick = tick
	f.day = day()
	f.pos = p
	f.importance = importance
	f.truth = truth
	if not data.has("where"):
		data["where"] = place_phrase(p)
	if not data.has("place"):
		var s := settlement_at(p)
		data["place"] = s.id if s != null else nearest_settlement(p, false).id
	f.data = data
	facts[f.id] = f
	var text := FactText.describe(self, f, 1.0)
	if truth:
		log_event(text)
	if witness_radius > 0.0:
		for id in actors_near(Vector2(p) + Vector2(0.5, 0.5), witness_radius):
			witness(id, f, text)
	if facts.size() > FACTS_CAP:
		_prune_facts()
	return f


func witness(id: int, f: Fact, text := "") -> void:
	if id == PLAYER:
		if player.learn(f.id, 1.0):
			if text == "":
				text = FactText.describe(self, f, 1.0)
			journal("[Своими глазами] " + text)
	else:
		var n: NPC = npcs[id]
		if n.learn(f.id, 1.0, day()):
			NpcAI.on_learn(self, n, f)


func _prune_facts() -> void:
	var ids := facts.keys()
	ids.sort()
	var removed := 0
	for fid in ids:
		if facts.size() <= FACTS_CAP - 100:
			break
		var f: Fact = facts[fid]
		if f.importance >= 3 or player.knowledge.has(fid):
			continue
		facts.erase(fid)
		removed += 1
	if removed > 0:
		for n: NPC in npcs.values():
			for k in n.knowledge.keys():
				if not facts.has(k):
					n.knowledge.erase(k)


func log_event(text: String) -> void:
	chronicle.append({"tick": tick, "text": text})


## Сообщение игроку: в журнал и всплывающим уведомлением.
func notify(text: String) -> void:
	journal(text)
	notices.append(text)


func journal(text: String) -> void:
	player.journal.append({"tick": tick, "text": text})


func _update_residents() -> void:
	residents_cache.clear()
	for n: NPC in npcs.values():
		if n.alive and not n.jailed:
			residents_cache[n.home] = int(residents_cache.get(n.home, 0)) + 1


func residents(sid: String) -> int:
	return int(residents_cache.get(sid, 0))


# ---------------- сохранение ----------------

func to_dict() -> Dictionary:
	var d := {
		"version": 1, "seed": world_seed, "rng_state": rng.state, "tick": tick, "scenario": scenario,
		"flags": flags, "next_id": next_id, "chronicle": chronicle, "corpses": corpses,
		"map": map.to_dict(), "player": player.to_dict(),
		"factions": {}, "settlements": {}, "npcs": {}, "facts": {},
	}
	for k in factions:
		d["factions"][k] = factions[k].to_dict()
	for k in settlements:
		d["settlements"][k] = settlements[k].to_dict()
	for k in npcs:
		d["npcs"][k] = npcs[k].to_dict()
	for k in facts:
		d["facts"][k] = facts[k].to_dict()
	return d


static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.world_seed = int(d["seed"])
	w.rng.seed = w.world_seed
	w.rng.state = int(d["rng_state"])
	w.tick = int(d["tick"])
	w.scenario = str(d["scenario"])
	w.flags = d["flags"]
	w.next_id = int(d["next_id"])
	w.chronicle = d["chronicle"]
	w.corpses = d["corpses"]
	w.map = MapData.from_dict(d["map"])
	w.player = PlayerState.from_dict(d["player"])
	for k in d["factions"]:
		w.factions[k] = Faction.from_dict(d["factions"][k])
	for k in d["settlements"]:
		w.settlements[k] = Settlement.from_dict(d["settlements"][k])
	for k in d["npcs"]:
		w.npcs[k] = NPC.from_dict(d["npcs"][k])
	for k in d["facts"]:
		w.facts[k] = Fact.from_dict(d["facts"][k])
	w.build_settle_grid()
	w._update_residents()
	return w


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(var_to_str(to_dict()))
	return true


static func load_from(path: String) -> World:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = str_to_var(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return null
	return World.from_dict(d)
