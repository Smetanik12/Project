class_name FactionAI
extends RefCounted
## Решения фракций: войны, набеги, подкрепления, награды за головы
## и реакция на новости, которые их люди принесли в свои поселения.

const PLAYER := 0
const TPH := World.TICKS_PER_HOUR


static func hourly(w: World) -> void:
	_learn(w)
	_check_captures(w)
	_resolve_raids(w)


static func daily(w: World) -> void:
	for f: Faction in w.factions.values():
		if f.defeated:
			continue
		for s: Settlement in w.settlements.values():
			if s.faction == f.id:
				f.wealth += 15
	_recruit(w)
	_reinforce(w)
	_wars(w)
	_syndicate_raids(w)


# ---------------- фракция узнаёт новости ----------------

## Фракция «знает» факт, когда её человек, который в него верит, находится в её поселении.
static func _learn(w: World) -> void:
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed or n.faction == "" or n.knowledge.is_empty():
			continue
		var s := w.settlement_at(n.pos)
		if s == null or s.faction != n.faction:
			continue
		var f: Faction = w.factions[n.faction]
		for fid in n.knowledge.keys():
			if f.known_facts.has(fid) or float(n.knowledge[fid]["acc"]) < 0.45:
				continue
			var fact: Fact = w.facts.get(fid)
			if fact == null:
				continue
			f.known_facts[fid] = true
			_react(w, f, fact)


static func _react(w: World, f: Faction, fact: Fact) -> void:
	var d := fact.data
	match fact.type:
		"raid", "raid_village":
			var att := str(d.get("attacker", ""))
			if att != "" and att != f.id and w.factions.has(att):
				w.change_relation(f.id, att, -20 if str(d.get("victim_faction", "")) == f.id else -3)
		"kill":
			var killer := int(d.get("killer_id", -1))
			var vf := str(d.get("victim_faction", ""))
			var victim := int(d.get("victim_id", -1))
			if killer == PLAYER:
				if vf == f.id:
					f.player_rep -= 35
					if f.player_rep <= Faction.HOSTILE and not f.bounties.has("player"):
						bounty_player(w, f, 60)
				elif vf != "" and w.faction_hostile(f.id, vf):
					f.player_rep = mini(100, f.player_rep + 8)
				if f.bounties.has(victim):
					var amount := int(f.bounties[victim])
					f.bounties.erase(victim)
					w.player.money += amount
					w.notify("%s выплатили тебе награду: %d₵." % [U.cap(f.members()), amount])
			elif killer > 0 and vf == f.id and w.npcs.has(killer):
				var kf: String = w.npcs[killer].faction
				if kf != "" and kf != f.id:
					w.change_relation(f.id, kf, -6)
		"escape", "desertion":
			if str(d.get("faction", "")) == f.id:
				f.player_rep = mini(f.player_rep, -80)
				bounty_player(w, f, 80)
		"secret_arms":
			match f.id:
				"front":
					f.player_rep = mini(100, f.player_rep + 50)
					w.notify("Фронт узнал о сделке генерала. Фронтовики теперь считают тебя своим.")
				"guild":
					w.change_relation("guild", "empire", -35)
				"free":
					w.change_relation("free", "empire", -25)
		"raid_planned":
			var target := str(d.get("place", ""))
			if w.settlements.has(target) and w.settlements[target].faction == f.id:
				_send_patrol(w, f, target)
		"spy":
			var pid := int(d.get("victim_id", -1))
			if w.npcs.has(pid):
				var p: NPC = w.npcs[pid]
				if p.alive and not p.jailed:
					if p.faction == f.id:
						_arrest(w, f, p)
					elif not f.bounties.has(pid):
						f.bounties[pid] = 40
		"threat":
			if str(d.get("victim_faction", "")) == f.id:
				f.player_rep -= 5
		"crash":
			if f.id == "scav":
				_send_looters(w, f, str(d.get("wreck", "")))


static func bounty_player(w: World, f: Faction, amount: int) -> void:
	f.bounties["player"] = amount
	var at: Settlement = w.settlements.get(f.capital)
	var p := at.center if at != null else w.player.tile()
	w.add_fact("bounty", p, {"issuer": f.id, "target": w.player.name, "target_f": w.player.female,
		"amount": amount}, 2, 8.0)
	w.notify("⚠ %s назначили награду за твою голову: %d₵." % [U.cap(f.members()), amount])


static func _send_patrol(w: World, f: Faction, target: String) -> void:
	var t: Settlement = w.settlements[target]
	var sent := 0
	for n: NPC in _idle_fighters(w, f.id, ""):
		if sent >= 3:
			break
		if Vector2(n.pos - t.center).length() > 70.0:
			continue
		n.action = "patrol"
		n.action_until = w.tick + 24 * TPH
		NpcAI.go_to_settlement(w, n, target)
		sent += 1
	if sent > 0:
		w.add_fact("reinforce", t.center, {"faction": f.id}, 1, 6.0)


static func _arrest(w: World, f: Faction, p: NPC) -> void:
	if p.role == "leader":
		w.log_event("%s отмахнулся от обвинений в шпионаже." % p.full_name())
		return
	w.add_fact("arrest", p.pos, {"victim": p.full_name(), "victim_f": p.female, "victim_id": p.id,
		"faction": f.id}, 2, 8.0)
	p.jailed = true
	p.engage_id = -1
	p.follow_id = -1
	p.path.clear()
	p.action = "jailed"


static func _send_looters(w: World, f: Faction, wreck: String) -> void:
	if not w.settlements.has(wreck):
		return
	var sent := 0
	for n: NPC in _idle_fighters(w, f.id, ""):
		if sent >= 3:
			break
		n.action = "loot"
		NpcAI.go_to_settlement(w, n, wreck)
		sent += 1
	if sent > 0:
		w.log_event("%s отправились растаскивать обломки корабля." % U.cap(f.members()))


static func loot_place(w: World, n: NPC) -> void:
	var s: Settlement = w.settlements.get(n.target_settlement)
	if s == null or not s.lootable:
		return
	var left := 0.0
	for g in s.stock.keys():
		var q := mini(int(float(s.stock[g])), 8)
		if q > 0:
			s.stock[g] = float(s.stock[g]) - q
			n.cargo[g] = int(n.cargo.get(g, 0)) + q
		left += float(s.stock[g])
	if left < 1.0:
		s.lootable = false
		w.log_event("Обломки корабля растащили подчистую.")


# ---------------- захват поселений ----------------

static func _check_captures(w: World) -> void:
	for s: Settlement in w.settlements.values():
		if s.faction == "" or s.kind == "wreck":
			continue
		var attackers := []
		var defenders := 0
		for id in w.actors_near(Vector2(s.center) + Vector2(0.5, 0.5), float(s.radius)):
			if id == PLAYER:
				continue
			var n: NPC = w.npcs[id]
			if not n.is_fighter():
				continue
			if n.faction == s.faction:
				defenders += 1
			elif (n.action == "hold" or n.action == "assault") and w.faction_hostile(n.faction, s.faction):
				attackers.append(n)
		if defenders == 0 and not attackers.is_empty():
			capture(w, s, attackers[0].faction, attackers)


static func capture(w: World, s: Settlement, new_f: String, garrison: Array) -> void:
	var old := s.faction
	s.faction = new_f
	w.add_fact("capture", s.center, {"attacker": new_f, "prev": old}, 3, 20.0)
	for n: NPC in garrison:
		n.home = s.id
		n.action = "idle"
		n.action_until = 0
		n.path.clear()
	var old_f: Faction = w.factions[old]
	var refuge := _refuge(w, old, s.center)
	for n: NPC in w.npcs.values():
		if n.alive and n.home == s.id and n.faction == old and refuge != "":
			n.home = refuge
	if old_f.capital == s.id:
		old_f.capital = refuge
		if refuge == "":
			old_f.defeated = true
			w.add_fact("fall", s.center, {"faction": old}, 3, 30.0)
			var wars := []
			for pair in w.flags.get("wars", []):
				if not (old in pair):
					wars.append(pair)
			w.flags["wars"] = wars


static func _refuge(w: World, fid: String, from: Vector2i) -> String:
	var best := ""
	var best_d := INF
	for s: Settlement in w.settlements.values():
		if s.faction != fid:
			continue
		var d := Vector2(s.center - from).length()
		if d < best_d:
			best_d = d
			best = s.id
	return best


# ---------------- войны ----------------

static func _wars(w: World) -> void:
	for pair in w.flags.get("wars", []):
		var a: String = pair[0]
		var b: String = pair[1]
		if w.factions[a].defeated or w.factions[b].defeated:
			continue
		var att := ""
		var forced := str(w.flags.get("force_assault", ""))
		if forced == a or forced == b:
			att = forced
			w.flags.erase("force_assault")
		elif w.rng.randf() < 0.5:
			att = a if w.rng.randf() < 0.5 else b
		else:
			continue
		_launch_assault(w, att, b if att == a else a)


static func _launch_assault(w: World, att: String, def: String) -> void:
	var base := _front_settlement(w, att, def)
	if base == null:
		return
	var target := _nearest_of(w, def, base.center)
	if target == null:
		return
	var squad := _idle_fighters(w, att, base.id)
	if squad.size() < 3:
		return
	squad.pop_back()  # один остаётся сторожить
	for n: NPC in squad:
		n.action = "assault"
		n.action_until = w.tick + 10 * TPH
		NpcAI.go_to_settlement(w, n, target.id)
	w.log_event("%s выступили %s в атаку. Цель — %s." % [U.cap(w.factions[att].members()), base.from, target.name])


static func on_assault_arrival(w: World, n: NPC) -> void:
	var t: Settlement = w.settlements.get(n.target_settlement)
	if t == null:
		return
	var key := "assault_%s_%d" % [t.id, w.day()]
	if w.flags.has(key):
		return
	w.flags[key] = true
	w.add_fact("assault", t.center, {"attacker": n.faction, "defender": t.faction}, 2, 14.0)


static func _reinforce(w: World) -> void:
	for pair in w.flags.get("wars", []):
		for i in 2:
			var side: String = pair[i]
			var enemy: String = pair[1 - i]
			var f: Faction = w.factions[side]
			var front := _front_settlement(w, side, enemy)
			if f.defeated or front == null or front.id == f.capital:
				continue
			var have := _idle_fighters(w, side, front.id).size()
			var pool := _idle_fighters(w, side, f.capital)
			var send := mini(5 - have, pool.size() - 2)
			for k in range(maxi(0, send)):
				var n: NPC = pool[k]
				n.home = front.id
				n.action = "goto_post"
				NpcAI.go_to_settlement(w, n, front.id)


static func _recruit(w: World) -> void:
	for f: Faction in w.factions.values():
		if f.defeated or not w.settlements.has(f.capital) or w.settlements[f.capital].faction != f.id:
			continue
		var rec: Dictionary = f.info().get("recruit", {})
		var role := str(rec.get("role", "soldier"))
		var target := int(rec.get("target", 0))
		var count := 0
		for n: NPC in w.npcs.values():
			if n.alive and not n.jailed and n.faction == f.id and n.role == role:
				count += 1
		var made := 0
		while count + made < target and f.wealth >= 40 and made < 2:
			WorldGen.make_npc(w, role, f.id, f.capital)
			f.wealth -= 40
			made += 1
		if made > 0:
			w.log_event("%s получили пополнение: %d чел." % [U.cap(f.members()), made])


static func _syndicate_raids(w: World) -> void:
	var f: Faction = w.factions.get("syndicate")
	if f == null or f.defeated or w.day() < 2 or w.rng.randf() > 0.45:
		return
	var base: Settlement = w.settlements.get(f.capital)
	if base == null or base.faction != "syndicate":
		return
	var squad := _idle_fighters(w, "syndicate", base.id)
	if squad.size() < 4:
		return
	squad = squad.slice(0, 3)
	var prey: NPC = null
	for n: NPC in w.npcs.values():
		if n.alive and n.action == "travel_trade" and n.faction != "syndicate" \
				and Vector2(n.pos - base.center).length() < 70.0:
			prey = n
			break
	if prey != null and w.rng.randf() < 0.6:
		for p: NPC in squad:
			p.action = "hunt"
			p.target_id = prey.id
			p.action_until = w.tick + 16 * TPH
			p.path.clear()
		w.log_event("%s вышли на охоту за караваном торговца %s." % [U.cap(f.members()), prey.full_name()])
		return
	var targets := []
	for s: Settlement in w.settlements.values():
		if s.kind in ["village", "mine", "post"] and s.faction != "syndicate" and w.faction_hostile("syndicate", s.faction):
			targets.append(s)
	if targets.is_empty():
		return
	var t: Settlement = targets[w.rng.randi() % targets.size()]
	for p: NPC in squad:
		p.action = "raid"
		p.action_until = w.tick + 14 * TPH
		NpcAI.go_to_settlement(w, p, t.id)
	w.log_event("%s отправились в набег. Цель — %s." % [U.cap(f.members()), t.name])


## Набег удался, если в поселении не осталось защитников: грабёж и угон в рабство.
static func _resolve_raids(w: World) -> void:
	var groups := {}
	for n: NPC in w.npcs.values():
		if n.alive and not n.jailed and n.action == "pillage" and n.engage_id < 0:
			var s := w.settlement_at(n.pos)
			if s == null:
				continue
			if not groups.has(s.id):
				groups[s.id] = []
			groups[s.id].append(n)
	for sid in groups:
		var s: Settlement = w.settlements[sid]
		var raiders: Array = groups[sid]
		var leader: NPC = raiders[0]
		var defenders := 0
		var civilians := []
		for id in w.actors_near(Vector2(s.center) + Vector2(0.5, 0.5), float(s.radius) + 1.0):
			if id == PLAYER:
				continue
			var m: NPC = w.npcs[id]
			if m.faction != s.faction or m.follow_id >= 0:
				continue
			if m.is_fighter():
				defenders += 1
			elif m.role != "leader":
				civilians.append(m)
		if defenders > 0:
			continue
		for g in ["food", "medicine", "weapons", "fuel"]:
			var q := mini(int(float(s.stock.get(g, 0.0))), 10 if g == "food" else 4)
			if q > 0:
				s.stock[g] = float(s.stock[g]) - q
				leader.cargo[g] = int(leader.cargo.get(g, 0)) + q
		var data := {"attacker": leader.faction, "victim_faction": s.faction, "victim": ""}
		var mine := _slave_mine(w)
		if not civilians.is_empty() and leader.faction == "syndicate" and mine != "":
			var c: NPC = civilians[w.rng.randi() % civilians.size()]
			c.pending = {"orig_faction": c.faction, "orig_home": c.home, "orig_role": c.role}
			c.faction = leader.faction
			c.role = "slave"
			c.home = mine
			c.follow_id = leader.id
			c.action = "captive"
			c.engage_id = -1
			c.path.clear()
			data["victim"] = c.full_name()
			data["victim_f"] = c.female
		w.add_fact("raid_village", s.center, data, 2, float(s.radius) + 8.0)
		for r: NPC in raiders:
			r.action = "return"
			NpcAI.go_home(w, r)


# ---------------- помощники ----------------

static func _slave_mine(w: World) -> String:
	for s: Settlement in w.settlements.values():
		if s.kind == "mine" and s.faction == "syndicate":
			return s.id
	return ""


## Свободные бойцы фракции (home == "" — из любого поселения).
static func _idle_fighters(w: World, fid: String, home: String) -> Array:
	var out := []
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed or n.faction != fid or n.follow_id >= 0 or n.engage_id >= 0:
			continue
		if home != "" and n.home != home:
			continue
		if not n.is_fighter() or n.role == "leader":
			continue
		if n.action in ["idle", "work", "sleep", "guard"]:
			out.append(n)
	return out


static func _front_settlement(w: World, side: String, enemy: String) -> Settlement:
	var best: Settlement = null
	var best_d := INF
	for s: Settlement in w.settlements.values():
		if s.faction != side:
			continue
		var e := _nearest_of(w, enemy, s.center)
		if e == null:
			continue
		var d := Vector2(e.center - s.center).length()
		if d < best_d:
			best_d = d
			best = s
	return best


static func _nearest_of(w: World, fid: String, from: Vector2i) -> Settlement:
	var best: Settlement = null
	var best_d := INF
	for s: Settlement in w.settlements.values():
		if s.faction != fid:
			continue
		var d := Vector2(s.center - from).length()
		if d < best_d:
			best_d = d
			best = s
	return best
