class_name NpcAI
extends RefCounted
## Поведение NPC. Каждый тик — движение и реакция на угрозы,
## каждый час — потребности и выбор занятия по полезности (Utility AI).

const PLAYER := 0
const SCAN_RANGE := 7.0
const LOSE_RANGE := 14.0
## Действия «дойти до точки».
const TRAVEL := ["travel_trade", "assault", "raid", "patrol", "goto_post", "loot", "treasure",
	"return", "wander_trip", "flee"]
## Действия с таймером action_until.
const TIMED := ["hold", "pillage", "guard", "hunt", "flee"]
const LOCAL := ["idle", "work", "guard", "hold", "pillage"]


static func tick(w: World) -> void:
	for n: NPC in w.npcs.values():
		n.prev_pos = n.pos
		if not n.alive or n.jailed:
			continue
		if n.attack_cd > 0:
			n.attack_cd -= 1
		if (w.tick + n.id) % 3 == 0:
			_scan(w, n)
		if n.engage_id >= 0:
			_move_engaged(w, n)
		elif n.follow_id >= 0:
			_move_follow(w, n)
		elif n.action == "hunt":
			_move_hunt(w, n)
		elif not n.path.is_empty():
			n.pos = n.path.pop_front()
			if n.path.is_empty():
				_arrived(w, n)
		elif n.action in LOCAL and w.rng.randf() < 0.03:
			_wander_local(w, n)


# ---------------- угрозы и бой ----------------

static func _scan(w: World, n: NPC) -> void:
	var me := w.actor_pos(n.id)
	if n.engage_id >= 0:
		var keep := w.actor_alive(n.engage_id) and w.actor_pos(n.engage_id).distance_to(me) <= LOSE_RANGE
		var hunting := n.action == "hunt" and n.engage_id == n.target_id
		if keep and not hunting and not w.is_hostile(n.id, n.engage_id):
			keep = false
		if not keep:
			n.engage_id = -1
			_resume(w, n)
		return
	if n.action == "flee" or n.action == "captive":
		return
	var fighter := n.is_fighter()
	var best := -1
	var best_d := INF
	for id in w.actors_near(me, SCAN_RANGE if fighter else 5.0):
		if id == n.id or not w.is_hostile(n.id, id):
			continue
		var other_fights: bool = id == PLAYER or w.npcs[id].is_fighter()
		# мирных жителей бойцы не трогают, а мирные их не боятся
		if not other_fights and not n.grudges.has(id) and n.axis("aggression") < 40:
			continue
		var d := w.actor_pos(id).distance_to(me)
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		return
	if fighter and n.hp > 25.0:
		n.engage_id = best
	else:
		flee(w, n, w.actor_pos(best))


static func _move_engaged(w: World, n: NPC) -> void:
	if not w.actor_alive(n.engage_id):
		n.engage_id = -1
		_resume(w, n)
		return
	var target := w.actor_tile(n.engage_id)
	if w.actor_pos(n.engage_id).distance_to(w.actor_pos(n.id)) <= Combat.REACH:
		return
	if n.path.is_empty() or (w.tick + n.id) % 3 == 0:
		n.path = w.map.find_path(n.pos, target)
	if not n.path.is_empty():
		n.pos = n.path.pop_front()


static func flee(w: World, n: NPC, from: Vector2) -> void:
	var me := w.actor_pos(n.id)
	var dir := (me - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(w.rng.randf() * TAU)
	var dest := Vector2i((me + dir * 10.0).floor())
	dest = dest.clamp(Vector2i.ZERO, Vector2i(w.map.w - 1, w.map.h - 1))
	n.engage_id = -1
	n.action = "flee"
	n.action_until = w.tick + 18
	go_to(w, n, w.map.nearest_passable(dest))


# ---------------- ходьба ----------------

static func _move_follow(w: World, n: NPC) -> void:
	if not w.actor_alive(n.follow_id):
		_lost_leader(w, n)
		return
	var lt := w.actor_tile(n.follow_id)
	if Vector2(lt - n.pos).length() <= 1.5:
		n.path.clear()
		return
	if n.path.is_empty() or (w.tick + n.id) % 4 == 0:
		var p := w.map.find_path(n.pos, lt)
		if p.size() > 1:
			p.pop_back()
		n.path = p
	if not n.path.is_empty():
		n.pos = n.path.pop_front()


static func _lost_leader(w: World, n: NPC) -> void:
	n.follow_id = -1
	if n.action == "captive" and n.pending.has("orig_faction"):
		n.faction = str(n.pending["orig_faction"])
		n.home = str(n.pending["orig_home"])
		n.role = str(n.pending["orig_role"])
		n.pending.clear()
		w.log_event("%s снова на свободе и идёт домой." % n.full_name())
	n.action = "return"
	go_home(w, n)


static func _move_hunt(w: World, n: NPC) -> void:
	if not w.actor_alive(n.target_id) or w.tick > n.action_until:
		n.action = "return"
		go_home(w, n)
		return
	var tt := w.actor_tile(n.target_id)
	if Vector2(tt - n.pos).length() <= 6.0:
		n.engage_id = n.target_id
		return
	if n.path.is_empty() or (w.tick + n.id) % 6 == 0:
		n.path = w.map.find_path(n.pos, tt)
	if not n.path.is_empty():
		n.pos = n.path.pop_front()


static func _wander_local(w: World, n: NPC) -> void:
	var s := w.settlement_at(n.pos)
	var dest: Vector2i
	if s != null:
		dest = w.random_point_in(s)
	else:
		dest = w.map.nearest_passable(n.pos + Vector2i(w.rng.randi_range(-2, 2), w.rng.randi_range(-2, 2)))
	var p := w.map.find_path(n.pos, dest)
	if p.size() <= 10:
		n.path = p


static func go_to(w: World, n: NPC, dest: Vector2i) -> bool:
	n.target_pos = dest
	n.path = w.map.find_path(n.pos, dest)
	return not n.path.is_empty()


static func go_to_settlement(w: World, n: NPC, sid: String) -> bool:
	var s: Settlement = w.settlements.get(sid)
	if s == null:
		return false
	n.target_settlement = sid
	return go_to(w, n, w.random_point_in(s))


static func go_home(w: World, n: NPC) -> bool:
	return go_to_settlement(w, n, n.home)


static func _resume(w: World, n: NPC) -> void:
	n.path.clear()
	if n.action in TRAVEL and n.target_pos != n.pos:
		go_to(w, n, n.target_pos)


static func _arrived(w: World, n: NPC) -> void:
	match n.action:
		"travel_trade":
			Economy.sell_cargo(w, n)
			_release_followers(w, n, "escort")
			n.action = "idle"
		"assault":
			n.action = "hold"
			FactionAI.on_assault_arrival(w, n)
		"raid":
			n.action = "pillage"
		"patrol":
			n.action = "guard"
		"loot":
			FactionAI.loot_place(w, n)
			n.action = "return"
			go_home(w, n)
		"treasure":
			w.log_event("%s перекопал%s всё вокруг — клада нет." % [n.full_name(), n.a()])
			n.action = "return"
			go_home(w, n)
		"return":
			n.action = "idle"
			_release_followers(w, n, "captive")
		"goto_post", "wander_trip":
			n.action = "idle"


static func _release_followers(w: World, leader: NPC, kind: String) -> void:
	for f: NPC in w.npcs.values():
		if f.follow_id == leader.id and f.action == kind:
			f.follow_id = -1
			f.pending.clear()
			f.action = "return"
			go_home(w, f)


# ---------------- ежечасные решения ----------------

static func hourly(w: World) -> void:
	var night := w.is_night()
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed:
			continue
		_needs(w, n)
		if not n.alive or n.engage_id >= 0 or n.follow_id >= 0:
			continue
		if n.action in TIMED and w.tick < n.action_until:
			continue
		if n.action in TRAVEL and not n.path.is_empty():
			continue
		_decide(w, n, night)


static func _needs(w: World, n: NPC) -> void:
	n.hunger += 2.5
	if n.hunger >= 60.0:
		if int(n.cargo.get("food", 0)) > 0:
			n.cargo["food"] = int(n.cargo["food"]) - 1
			n.hunger = 0.0
		else:
			var s := w.settlement_at(n.pos)
			if s != null and not w.faction_hostile(n.faction, s.faction) and float(s.stock.get("food", 0.0)) >= 1.0:
				s.stock["food"] = float(s.stock["food"]) - 1.0
				s.stock["water"] = maxf(0.0, float(s.stock.get("water", 0.0)) - 1.0)
				n.hunger = 0.0
	if n.hunger >= 100.0:
		n.hunger = 100.0
		n.hp -= 3.0
		if n.hp <= 0.0:
			Combat.kill(w, n.id, -1)
	elif n.hp < 100.0 and n.engage_id < 0:
		var heal := 1.0
		var s2 := w.settlement_at(n.pos)
		if s2 != null:
			heal = 3.0
			if n.hp < 60.0 and float(s2.stock.get("medicine", 0.0)) >= 0.2:
				s2.stock["medicine"] = float(s2.stock["medicine"]) - 0.2
				heal = 8.0
		n.hp = minf(100.0, n.hp + heal)


static func _decide(w: World, n: NPC, night: bool) -> void:
	var here := w.settlement_at(n.pos)
	var at_home := here != null and here.id == n.home
	if not at_home:
		if n.role == "merchant" and here != null and not night and _try_trade(w, n):
			return
		n.action = "return"
		if not go_home(w, n):
			n.action = "idle"
		return
	if night:
		n.action = "sleep"
		n.path.clear()
		return
	n.action = "work" if str(n.role_info().get("work", "")) != "" else "idle"
	match n.role:
		"merchant":
			if w.rng.randf() < 0.5 and _try_trade(w, n):
				return
			var src := Economy.plan_restock(w, n)
			if src != "":
				n.action = "wander_trip"
				go_to_settlement(w, n, src)
				return
		"drifter":
			if w.rng.randf() < 0.12 and _wander_trip(w, n):
				return
	if n.axis("greed") > 0:
		_check_treasure(w, n)


static func _try_trade(w: World, n: NPC) -> bool:
	var plan := Economy.plan_trade(w, n)
	if plan.is_empty():
		return false
	var here := w.settlement_at(n.pos)
	Economy.buy_for_trip(w, n, plan)
	n.action = "travel_trade"
	go_to_settlement(w, n, plan["dst"])
	# нанять охрану каравана
	var hired := 0
	for g: NPC in w.npcs.values():
		if hired >= 2:
			break
		if g == n or not g.alive or g.jailed or g.faction != n.faction or g.follow_id >= 0:
			continue
		if not g.is_fighter() or g.role == "leader" or g.role == "officer":
			continue
		if not (g.action in ["idle", "work", "guard"]) or w.settlement_at(g.pos) != here:
			continue
		g.follow_id = n.id
		g.action = "escort"
		hired += 1
	return true


static func _wander_trip(w: World, n: NPC) -> bool:
	var ids := w.settlements.keys()
	var s: Settlement = w.settlements[ids[w.rng.randi() % ids.size()]]
	if s.kind == "wreck" or s.id == n.home or w.faction_hostile(n.faction, s.faction):
		return false
	n.action = "wander_trip"
	return go_to_settlement(w, n, s.id)


static func _check_treasure(w: World, n: NPC) -> void:
	for fid in n.knowledge:
		if n.done.has(fid):
			continue
		var f: Fact = w.facts.get(fid)
		if f == null or f.type != "treasure" or float(n.knowledge[fid]["acc"]) < 0.5:
			continue
		n.done[fid] = true
		var s: Settlement = w.settlements.get(str(f.data.get("place", "")))
		if s == null or w.rng.randf() > 0.6:
			continue
		n.action = "treasure"
		go_to(w, n, w.map.nearest_passable(s.center + Vector2i(s.radius + 2, 1)))
		w.log_event("%s бросает всё и идёт искать клад: %s." % [n.full_name(), s.near])
		return


## Личная реакция на новость (реакции фракций — в FactionAI).
static func on_learn(w: World, n: NPC, f: Fact) -> void:
	if float(n.knowledge.get(f.id, {}).get("acc", 0.0)) < 0.6:
		return
	match f.type:
		"kill":
			if int(f.data.get("killer_id", -1)) == PLAYER and n.faction != "" \
					and str(f.data.get("victim_faction", "")) == n.faction:
				n.trust -= 30
				if n.is_fighter() and n.axis("courage") >= 0:
					n.grudges[PLAYER] = true
		"threat":
			if n.faction != "" and str(f.data.get("victim_faction", "")) == n.faction:
				n.trust -= 8
		"secret_arms":
			if n.faction == "front" or n.faction == "free":
				n.trust += 5
