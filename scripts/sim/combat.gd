class_name Combat
extends RefCounted
## Ближний бой: попадания, раны, смерть и последствия (союзники мстят, свидетели разносят слух).

const PLAYER := 0
const REACH := 1.6


static func tick(w: World) -> void:
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed or n.engage_id < 0 or n.attack_cd > 0:
			continue
		if not w.actor_alive(n.engage_id):
			n.engage_id = -1
			continue
		if w.actor_pos(n.engage_id).distance_to(w.actor_pos(n.id)) <= REACH:
			attack(w, n.id, n.engage_id)


static func player_can_attack(w: World) -> bool:
	return w.tick - w.player.attack_tick >= 2


static func attack(w: World, a: int, t: int) -> void:
	if not w.actor_alive(a) or not w.actor_alive(t):
		return
	if a == PLAYER:
		w.player.attack_tick = w.tick
	else:
		w.npcs[a].attack_cd = 2
	var ap := w.actor_power(a)
	var chance := clampf(0.55 + (ap - w.actor_power(t)) * 0.03, 0.15, 0.9)
	var hit := w.rng.randf() < chance
	w.hits.append({"a": w.actor_pos(a), "b": w.actor_pos(t), "tick": w.tick, "hit": hit})
	_on_attacked(w, t, a)
	if not hit:
		return
	var dmg := w.rng.randf_range(7.0, 13.0) * (1.0 + ap * 0.04)
	if t == PLAYER:
		w.player.hp -= dmg
		if w.player.hp <= 0.0:
			kill(w, PLAYER, a)
	else:
		var v: NPC = w.npcs[t]
		v.hp -= dmg
		if v.hp <= 0.0:
			kill(w, t, a)


static func _on_attacked(w: World, victim: int, attacker: int) -> void:
	if victim == PLAYER:
		for f: NPC in w.followers():
			if f.engage_id < 0 and f.is_fighter():
				f.engage_id = attacker
		return
	var v: NPC = w.npcs[victim]
	if not w.is_hostile(victim, attacker):
		v.grudges[attacker] = true
		if attacker == PLAYER:
			v.trust -= 40
			v.remember(w.day(), "mem.attack")
	# свои вступаются
	for id in w.actors_near(w.actor_pos(victim), 8.0):
		if id == PLAYER or id == attacker or id == victim:
			continue
		var al: NPC = w.npcs[id]
		var ally: bool = (al.faction != "" and al.faction == v.faction) or al.follow_id == victim or v.follow_id == id
		if not ally or al.follow_id == attacker:
			continue
		if not w.is_hostile(id, attacker):
			al.grudges[attacker] = true
		if al.engage_id < 0 and al.is_fighter():
			al.engage_id = attacker
	if attacker == PLAYER:
		for f: NPC in w.followers():
			if f.engage_id < 0 and f.is_fighter() and f.id != victim:
				f.engage_id = victim
	if v.engage_id < 0:
		if v.is_fighter() or v.axis("courage") > 20:
			v.engage_id = attacker
		else:
			NpcAI.flee(w, v, w.actor_pos(attacker))


static func kill(w: World, victim: int, killer: int) -> void:
	var where_tile := w.actor_tile(victim)
	var data := {"victim": w.actor_name(victim), "victim_f": w.actor_female(victim),
		"victim_id": victim, "victim_faction": w.actor_faction(victim)}
	var type := "starved"
	if killer >= 0:
		type = "kill"
		data["killer"] = w.actor_name(killer)
		data["killer_f"] = w.actor_female(killer)
		data["killer_id"] = killer
		data["killer_faction"] = w.actor_faction(killer)
	var importance := 1
	if victim == PLAYER:
		w.player.alive = false
		w.player.hp = 0.0
		w.game_over = true
		importance = 2
	else:
		var v: NPC = w.npcs[victim]
		v.alive = false
		v.hp = 0.0
		v.engage_id = -1
		v.follow_id = -1
		v.path.clear()
		w.corpses.append({"pos": v.pos, "tick": w.tick, "faction": v.faction})
		if v.role == "officer":
			importance = 2
		elif v.role == "leader":
			importance = 3
		if killer == PLAYER:
			importance = maxi(importance, 2)
			w.player.kills += 1
			var loot := []
			if v.money > 0:
				w.player.money += v.money
				loot.append("%d₵" % v.money)
			for g in v.cargo:
				var q := int(v.cargo[g])
				if q > 0:
					w.player.add_item(g, q)
					loot.append("%s ×%d" % [DataDB.good_name(g), q])
			if not loot.is_empty():
				w.notify("Добыча: " + ", ".join(PackedStringArray(loot)))
		elif killer > 0 and w.npcs.has(killer):
			var k: NPC = w.npcs[killer]
			k.money += v.money
			for g in v.cargo:
				k.cargo[g] = int(k.cargo.get(g, 0)) + int(v.cargo[g])
			if k.action == "hunt" and v.role == "merchant":
				type = "raid"
				data["attacker"] = k.faction
				for h: NPC in w.npcs.values():
					if h.alive and h.action == "hunt" and h.target_id == victim:
						h.engage_id = -1
						h.action = "return"
						NpcAI.go_home(w, h)
		v.money = 0
		v.cargo.clear()
	w.add_fact(type, where_tile, data, importance, 10.0)
