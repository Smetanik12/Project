class_name Rumors
extends RefCounted
## Слухи. Жители одного поселения болтают и пересказывают друг другу факты.
## Путники разносят их между поселениями. При каждом пересказе слух теряет точность.


static func hourly(w: World) -> void:
	var h := w.hour()
	if h < 7 or h >= 23:
		return
	var groups := {}
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed:
			continue
		var s := w.settlement_at(n.pos)
		if s == null:
			continue
		if not groups.has(s.id):
			groups[s.id] = []
		groups[s.id].append(n)
	for sid in groups:
		var list: Array = groups[sid]
		if list.size() < 2:
			continue
		for n: NPC in list:
			if n.knowledge.is_empty():
				continue
			if w.rng.randf() > 0.3 + n.axis("talk") / 150.0:
				continue
			var other: NPC = list[w.rng.randi() % list.size()]
			if other != n and not w.is_hostile(n.id, other.id):
				share(w, n, other)


## Рассказчик выбирает самое интересное из 3 случайных фактов, которых слушатель не знает.
static func share(w: World, teller: NPC, listener: NPC) -> void:
	var keys := teller.knowledge.keys()
	var best_id = null
	var best_score := -INF
	for i in 3:
		var fid = keys[w.rng.randi() % keys.size()]
		var f: Fact = w.facts.get(fid)
		if f == null:
			continue
		var mine := float(teller.knowledge[fid]["acc"])
		if listener.knowledge.has(fid) and float(listener.knowledge[fid]["acc"]) >= mine * 0.9:
			continue
		var score := f.importance * 10.0 - (w.day() - f.day) * 3.0
		if score > best_score:
			best_score = score
			best_id = fid
	if best_id == null:
		return
	var acc := float(teller.knowledge[best_id]["acc"]) * decay(teller)
	if listener.learn(best_id, acc, w.day()):
		NpcAI.on_learn(w, listener, w.facts[best_id])


static func decay(n: NPC) -> float:
	var h := n.axis("honesty")
	if h > 20:
		return 0.97
	if h < -20:
		return 0.75
	return 0.88
