class_name Dialogue
extends RefCounted
## Разговор с NPC: игрок выбирает ДЕЙСТВИЕ и ТЕМУ. Темы берутся из мира (люди, места, фракции,
## события), поэтому их число растёт само. Ответ зависит от характера NPC, его отношения
## к игроку, страха, памяти и того, что он знает. Заранее написанных веток нет.

const PLAYER := 0
const MAX_FOLLOWERS := 5
const ACTIONS := [
	["ask", "Спросить"], ["tell", "Рассказать"], ["lie", "Соврать"], ["flatter", "Польстить"],
	["bribe", "Подкупить"], ["threaten", "Угрожать"], ["insult", "Оскорбить"],
	["recruit", "Позвать с собой"], ["trade", "Торговать"], ["collar", "Снять ошейник"], ["bye", "Уйти"],
]
const NEEDS_TOPIC := ["ask", "tell", "lie", "bribe", "trade"]
const FLATTERY := ["Сразу видно — бывалый человек.", "О тебе тут хорошо отзываются.",
	"Ты выглядишь как человек, который знает своё дело."]
const INSULTS := ["Ты жалкое ничтожество.", "От тебя несёт, как от дохлого варга.",
	"Таких, как ты, на рудниках за еду меняют."]


# ---------------- общее ----------------

static func attitude(w: World, n: NPC) -> int:
	var a := n.trust
	if n.faction != "" and w.factions.has(n.faction):
		a += w.factions[n.faction].player_rep / 2
	if n.grudges.has(PLAYER):
		a -= 60
	if n.follow_id == PLAYER:
		a += 40
	if w.player.flags.get("collar", false):
		a += 15 if n.role == "slave" else -10
	return clampi(a, -100, 100)


static func attitude_label(w: World, n: NPC) -> String:
	if w.is_hostile(n.id, PLAYER):
		return "враждебен"
	var a := attitude(w, n)
	if n.fear >= 40:
		return "боится тебя"
	if a >= 40:
		return "дружелюбен"
	if a >= 10:
		return "расположен"
	if a > -20:
		return "нейтрален"
	return "насторожен"


static func header(w: World, n: NPC) -> String:
	var fac := "без фракции"
	if n.faction != "" and w.factions.has(n.faction):
		fac = w.factions[n.faction].short()
	var text := "%s — %s, %s. Отношение: %s." % [n.full_name(), n.role_name().to_lower(), fac, attitude_label(w, n)]
	if n.revealed:
		var names := []
		for t in n.traits:
			names.append(str(DataDB.traits[t]["name"]).to_lower())
		text += " Характер: %s." % ", ".join(PackedStringArray(names))
	return text


static func greet(w: World, n: NPC) -> String:
	n.met_player = true
	w.player.known_people[n.id] = true
	var v := _vars(w, n)
	var att := attitude(w, n)
	var key := "greet.neutral"
	if w.is_hostile(n.id, PLAYER) or att <= -40:
		key = "greet.hostile"
	elif n.fear >= 40:
		key = "greet.afraid"
	elif n.role == "slave" and w.player.flags.get("collar", false):
		key = "greet.slave"
	elif att >= 30:
		key = "greet.friendly"
	elif att < 0 or n.axis("suspicion") > 30:
		key = "greet.wary"
	var text := DataDB.phrase(key, w.rng, v)
	if not n.memory.is_empty() and w.rng.randf() < 0.5:
		v["mem"] = DataDB.phrase(str(n.memory.back()["key"]), w.rng, v)
		text += " " + DataDB.phrase("greet.memory", w.rng, v)
	return text


static func actions_for(w: World, n: NPC) -> Array:
	var out := []
	var hostile := w.is_hostile(n.id, PLAYER)
	for a in ACTIONS:
		var id: String = a[0]
		if hostile and not (id in ["threaten", "bribe", "insult", "bye"]):
			continue
		if id == "trade" and not bool(n.role_info().get("trader", false)):
			continue
		if id == "collar" and not w.player.flags.get("collar", false):
			continue
		var label: String = a[1]
		if id == "recruit" and n.follow_id == PLAYER:
			label = "Отпустить"
		out.append([id, label])
	return out


## Темы для действия: [{"id", "label", "group"}].
static func topics_for(w: World, n: NPC, action: String) -> Array:
	var out := []
	match action:
		"ask":
			if n.pending.has("price"):
				out.append({"id": "pay", "label": "Заплатить %d₵" % int(n.pending["price"]), "group": "Сделка"})
			out.append({"id": "news", "label": "Что нового?", "group": "Общее"})
			out.append({"id": "self", "label": "Расскажи о себе", "group": "Общее"})
			if _market(w, n) != null:
				out.append({"id": "prices", "label": "Почём тут что?", "group": "Общее"})
			for fid in w.factions:
				out.append({"id": "f:" + fid, "label": w.factions[fid].short(), "group": "Фракции"})
			for sid in w.settlements:
				out.append({"id": "s:" + sid, "label": w.settlements[sid].name, "group": "Места"})
			var people: Array = w.player.known_people.keys()
			for i in range(people.size() - 1, maxi(-1, people.size() - 31), -1):
				var pid: int = people[i]
				if pid != n.id and w.npcs.has(pid):
					out.append({"id": "p:%d" % pid, "label": w.npcs[pid].full_name(), "group": "Люди"})
		"tell":
			var ids: Array = w.player.knowledge.keys().filter(func(k): return w.facts.has(k))
			ids.sort_custom(func(a, b): return w.facts[a].tick > w.facts[b].tick)
			for fid in ids.slice(0, 20):
				var t := FactText.describe(w, w.facts[fid], float(w.player.knowledge[fid]["acc"]))
				out.append({"id": "k:%d" % fid, "label": t, "group": "Что ты знаешь"})
		"lie":
			for sid in w.settlements:
				var s: Settlement = w.settlements[sid]
				if s.faction == "":
					continue
				var att: Faction = w.factions[_likely_attacker(w, s.faction)]
				out.append({"id": "lie_raid:" + sid, "label": "%s скоро нападут: %s" % [U.cap(att.members()), s.name], "group": "Нападение"})
			for pid in w.player.known_people:
				if w.npcs.has(pid) and w.npcs[pid].alive and not w.npcs[pid].jailed:
					out.append({"id": "lie_spy:%d" % pid, "label": "%s — шпион" % w.npcs[pid].full_name(), "group": "Обвинить в шпионаже"})
			for sid in w.settlements:
				out.append({"id": "lie_treasure:" + sid, "label": "Клад зарыт %s" % w.settlements[sid].near, "group": "Клад"})
		"bribe":
			for amount in [10, 30, 100]:
				out.append({"id": "b:%d" % amount, "label": "Дать %d₵" % amount, "group": "Сумма"})
		"trade":
			var s := _market(w, n)
			if s != null:
				var att := attitude(w, n)
				for g in DataDB.good_ids():
					var gn := DataDB.good_name(g)
					out.append({"id": "buy:" + g, "label": "Купить: %s — %d₵ (на складе %d)" % [gn, _buy_price(w, s, g, att), int(float(s.stock.get(g, 0.0)))], "group": "Купить"})
					if int(w.player.inv.get(g, 0)) > 0:
						out.append({"id": "sell:" + g, "label": "Продать: %s — %d₵ (у тебя %d)" % [gn, _sell_price(w, s, g, att), int(w.player.inv[g])], "group": "Продать"})
	return out


## Выполнить действие. Возвращает {"player": реплика игрока, "text": ответ NPC, "close": закрыть диалог}.
static func run(w: World, n: NPC, action: String, topic := "") -> Dictionary:
	var res := {"player": "", "text": "", "close": false}
	match action:
		"ask":
			_ask(w, n, topic, res)
		"tell":
			_tell(w, n, topic, res)
		"lie":
			_lie(w, n, topic, res)
		"flatter":
			_flatter(w, n, res)
		"bribe":
			_bribe(w, n, int(topic.trim_prefix("b:")), res)
		"threaten":
			_threaten(w, n, res)
		"insult":
			_insult(w, n, res)
		"recruit":
			_recruit(w, n, res)
		"trade":
			_trade(w, n, topic, res)
		"collar":
			_collar(w, n, res)
		_:
			_bye(w, n, res)
	n.trust = clampi(n.trust, -100, 100)
	n.fear = clampi(n.fear, 0, 100)
	return res


static func _p(key: String, w: World, v: Dictionary) -> String:
	return DataDB.phrase(key, w.rng, v)


static func _vars(w: World, n: NPC) -> Dictionary:
	var home: Settlement = w.settlements.get(n.home)
	var v := {"name": n.full_name(), "a": n.a(), "pname": w.player.name.split(" ")[0], "pa": w.player.a(),
		"role": n.role_name(), "role_lc": n.role_name().to_lower(),
		"home": home.where if home != null else "где придётся"}
	if n.faction != "" and w.factions.has(n.faction):
		var f: Faction = w.factions[n.faction]
		v["faction"] = f.title()
		v["members"] = f.members()
		v["members_cap"] = U.cap(f.members())
		v["goal"] = str(f.info().get("goal", ""))
		v["desc"] = str(f.info().get("desc", ""))
	return v


# ---------------- спросить ----------------

static func _ask(w: World, n: NPC, topic: String, res: Dictionary) -> void:
	var v := _vars(w, n)
	var att := attitude(w, n)
	if topic == "pay":
		var price := int(n.pending.get("price", 0))
		res["player"] = "Вот %d₵." % price
		if w.player.money < price:
			res["text"] = _p("trade.nomoney", w, v)
			return
		w.player.money -= price
		n.money += price
		var kind := str(n.pending.get("type", ""))
		n.pending.clear()
		match kind:
			"news":
				res["text"] = _share_news(w, n, 3)
			"recruit":
				_make_follower(w, n, res, "recruit.accept")
			"collar":
				_remove_collar(w, n, res)
		return
	match topic:
		"news":
			res["player"] = "Что нового?"
			if att <= -40:
				res["text"] = _p("ask.news.refuse", w, v)
			elif n.axis("talk") < -30 and att < 30 and n.fear < 40:
				res["text"] = _p("ask.news.silent", w, v)
			elif _unknown_facts(w, n).is_empty():
				res["text"] = _p("ask.news.none", w, v)
			elif n.axis("greed") > 20 and att < 50 and n.fear < 40:
				var price := 5 + 5 * mini(_unknown_facts(w, n).size(), 3)
				n.pending = {"type": "news", "price": price}
				v["price"] = price
				res["text"] = _p("ask.news.pay", w, v)
			else:
				var count := 1 + int(n.axis("talk") > 20) + int(att > 40)
				res["text"] = _share_news(w, n, count)
				if att >= 0:
					n.trust += 1
		"self":
			res["player"] = "Расскажи о себе."
			var parts := [_p("ask.self.intro", w, v)]
			if n.role == "slave" and n.faction == "syndicate":
				parts.append(_p("ask.self.faction.slave", w, v))
			elif n.faction == "":
				parts.append(_p("ask.self.faction.none", w, v))
			elif n.axis("loyalty") > 20:
				parts.append(_p("ask.self.faction.loyal", w, v))
			else:
				parts.append(_p("ask.self.faction.normal", w, v))
			var limit := 1 if n.axis("talk") < -30 else 2
			for t in n.traits.slice(0, limit):
				parts.append(_p("ask.self.trait." + t, w, v))
			n.revealed = true
			res["text"] = " ".join(PackedStringArray(parts))
		"prices":
			res["player"] = "Почём тут что?"
			res["text"] = _prices(w, n, v)
		_:
			if topic.begins_with("f:"):
				_ask_faction(w, n, topic.substr(2), res, v)
			elif topic.begins_with("s:"):
				_ask_place(w, n, topic.substr(2), res, v)
			elif topic.begins_with("p:"):
				_ask_person(w, n, int(topic.substr(2)), res, v)


## Факты, которые NPC знает, а игрок нет: сначала важные, потом свежие.
static func _unknown_facts(w: World, n: NPC) -> Array:
	var out := []
	for fid in n.knowledge:
		if w.facts.has(fid) and not w.player.knowledge.has(fid):
			out.append(fid)
	out.sort_custom(func(a, b):
		var fa: Fact = w.facts[a]
		var fb: Fact = w.facts[b]
		if fa.importance != fb.importance:
			return fa.importance > fb.importance
		return fa.tick > fb.tick)
	return out


static func _share_news(w: World, n: NPC, count: int) -> String:
	var fresh := _unknown_facts(w, n)
	if fresh.is_empty():
		return _p("ask.news.none", w, _vars(w, n))
	var parts := []
	for i in mini(count, fresh.size()):
		var text := _pass_fact(w, n, fresh[i])
		var v := _vars(w, n)
		v["fact"] = text
		parts.append(_p("ask.news.share" if i == 0 else "ask.news.more", w, v))
	return " ".join(PackedStringArray(parts))


## NPC пересказывает факт игроку: игрок узнаёт его с точностью рассказчика.
static func _pass_fact(w: World, n: NPC, fid: int) -> String:
	var acc := float(n.knowledge[fid]["acc"]) * Rumors.decay(n)
	var f: Fact = w.facts[fid]
	var text := FactText.describe(w, f, acc)
	if w.player.learn(fid, acc):
		w.journal("[Слух от %s] %s" % [n.full_name(), text])
	for key in ["victim_id", "killer_id"]:
		var pid := int(f.data.get(key, -1))
		if pid > 0 and w.npcs.has(pid):
			w.player.known_people[pid] = true
	return text


static func _prices(w: World, n: NPC, v: Dictionary) -> String:
	var s := _market(w, n)
	if s == null:
		return _p("ask.prices.nowhere", w, v)
	var items := []
	var hi := ""
	var lo := ""
	var hi_r := -1.0
	var lo_r := INF
	for g in DataDB.good_ids():
		var pr := Economy.price(w, s, g)
		items.append("%s — %d₵" % [DataDB.good_name(g).to_lower(), roundi(pr)])
		var ratio := pr / float(DataDB.goods[g]["base_price"])
		if ratio > hi_r:
			hi_r = ratio
			hi = DataDB.good_name(g).to_lower()
		if ratio < lo_r:
			lo_r = ratio
			lo = DataDB.good_name(g).to_lower()
	v["list"] = ", ".join(PackedStringArray(items))
	v["high"] = hi
	v["low"] = lo
	return _p("ask.prices.list", w, v) + " " + _p("ask.prices.extremes", w, v)


static func _ask_faction(w: World, n: NPC, fid: String, res: Dictionary, v: Dictionary) -> void:
	var f: Faction = w.factions[fid]
	res["player"] = "Что скажешь про них: %s?" % f.short()
	var fv := v.duplicate()
	fv["faction"] = f.title()
	fv["members"] = f.members()
	fv["members_cap"] = U.cap(f.members())
	fv["goal"] = str(f.info().get("goal", ""))
	fv["desc"] = str(f.info().get("desc", ""))
	var key := "ask.faction.self"
	if fid != n.faction:
		var rel := 0
		if n.faction != "":
			rel = w.factions[n.faction].rel(fid)
		rel += n.axis("kindness") / 4
		if rel <= -50:
			key = "ask.faction.hate"
		elif rel < -10:
			key = "ask.faction.dislike"
		elif rel >= 20:
			key = "ask.faction.like"
		else:
			key = "ask.faction.neutral"
	var text := _p(key, w, fv)
	for fid2 in _unknown_facts(w, n):
		var d: Dictionary = w.facts[fid2].data
		if str(d.get("attacker", "")) == fid or str(d.get("victim_faction", "")) == fid or str(d.get("faction", "")) == fid:
			text += " Слышал%s: %s" % [n.a(), _pass_fact(w, n, fid2)]
			break
	res["text"] = text


static func _ask_place(w: World, n: NPC, sid: String, res: Dictionary, v: Dictionary) -> void:
	var s: Settlement = w.settlements[sid]
	res["player"] = "Что за место — %s?" % s.name
	var pv := v.duplicate()
	pv["place"] = s.name
	pv["kind"] = s.kind_desc()
	pv["kind_cap"] = U.cap(s.kind_desc())
	var parts := []
	if s.faction != "":
		pv["members"] = w.factions[s.faction].members()
		parts.append(_p("ask.place.desc", w, pv))
	else:
		parts.append(_p("ask.place.wild", w, pv))
	if w.settlement_at(n.pos) == s:
		parts.append(_p("ask.place.here", w, pv))
	else:
		pv["dir"] = U.direction(n.pos, s.center)
		var hours := Vector2(s.center - n.pos).length() / 12.0
		pv["dist"] = "меньше часа ходу" if hours < 1.0 else "%d ч ходу" % roundi(hours)
		parts.append(_p("ask.place.dir", w, pv))
	if s.kind != "wreck":
		var cheap := ""
		var dear := ""
		for g in DataDB.good_ids():
			var ratio := Economy.price(w, s, g) / float(DataDB.goods[g]["base_price"])
			if ratio < 0.6 and cheap == "":
				cheap = DataDB.good_name(g).to_lower()
			if ratio > 1.8 and dear == "":
				dear = DataDB.good_name(g).to_lower()
		if cheap != "":
			pv["good"] = cheap
			parts.append(_p("ask.place.cheap", w, pv))
		if dear != "":
			pv["good"] = dear
			parts.append(_p("ask.place.expensive", w, pv))
	for fid in n.knowledge:
		var f: Fact = w.facts.get(fid)
		if f != null and str(f.data.get("place", "")) == sid and f.type in ["raid", "raid_village", "kill", "assault", "capture", "famine", "raid_planned"]:
			pv["fact"] = _pass_fact(w, n, fid)
			parts.append(_p("ask.place.danger", w, pv))
			break
	res["text"] = " ".join(PackedStringArray(parts))


static func _ask_person(w: World, n: NPC, pid: int, res: Dictionary, v: Dictionary) -> void:
	if not w.npcs.has(pid):
		return
	var t: NPC = w.npcs[pid]
	res["player"] = "Знаешь человека по имени %s?" % t.full_name()
	if t == n:
		res["text"] = _p("ask.person.self", w, v)
		return
	var pv := v.duplicate()
	var home: Settlement = w.settlements.get(t.home)
	pv["target"] = t.full_name()
	pv["target_a"] = t.a()
	pv["target_role"] = t.role_name().to_lower()
	pv["target_where"] = home.where if home != null else "где придётся"
	var knows := t.home == n.home or (t.faction != "" and t.faction == n.faction)
	for fid in n.knowledge:
		var f: Fact = w.facts.get(fid)
		if f != null and (int(f.data.get("victim_id", -1)) == pid or int(f.data.get("killer_id", -1)) == pid):
			knows = true
	if not knows:
		res["text"] = _p("ask.person.unknown", w, pv)
		return
	if not t.alive:
		res["text"] = _p("ask.person.dead", w, pv)
		return
	if t.jailed:
		res["text"] = "%s сидит в тюрьме. Говорят, за шпионаж." % t.full_name()
		return
	var parts := [_p("ask.person.known", w, pv)]
	if Vector2(t.pos - n.pos).length() < 12.0:
		parts.append(_p("ask.person.near", w, pv))
	if n.grudges.has(pid) or w.is_hostile(n.id, pid):
		parts.append(_p("ask.person.bad", w, pv))
	elif t.faction == n.faction and n.axis("kindness") >= 0:
		parts.append(_p("ask.person.good", w, pv))
	res["text"] = " ".join(PackedStringArray(parts))


# ---------------- рассказать и соврать ----------------

static func _tell(w: World, n: NPC, topic: String, res: Dictionary) -> void:
	var fid := int(topic.substr(2))
	var f: Fact = w.facts.get(fid)
	if f == null or not w.player.knowledge.has(fid):
		return
	var acc := float(w.player.knowledge[fid]["acc"])
	res["player"] = "Слышал%s? %s" % [w.player.a(), FactText.describe(w, f, acc)]
	var v := _vars(w, n)
	if n.knowledge.has(fid) and float(n.knowledge[fid]["acc"]) >= acc * 0.9:
		res["text"] = _p("tell.known", w, v)
		return
	var believe := 0.55 + attitude(w, n) / 150.0 - n.axis("suspicion") / 150.0
	if w.rng.randf() < believe:
		n.learn(fid, acc * 0.95, w.day())
		NpcAI.on_learn(w, n, f)
		if f.type == "secret_arms":
			w.flags["secret_told"] = true
		if _relevant(n, f):
			n.trust += 4
			n.remember(w.day(), "mem.help")
			res["text"] = _p("tell.useful", w, v)
		else:
			res["text"] = _p("tell.neutral", w, v)
	else:
		n.learn(fid, acc * 0.4, w.day())
		res["text"] = _p("tell.disbelieve", w, v)


static func _relevant(n: NPC, f: Fact) -> bool:
	if f.importance >= 2 or str(f.data.get("place", "")) == n.home:
		return true
	for k in ["attacker", "victim_faction", "defender", "faction"]:
		if n.faction != "" and str(f.data.get(k, "")) == n.faction:
			return true
	return false


static func _likely_attacker(w: World, fid: String) -> String:
	var best := "syndicate"
	var best_rel := 1000
	for other in w.factions:
		if other == fid or w.factions[other].defeated:
			continue
		var r: int = w.factions[other].rel(fid)
		if r < best_rel:
			best_rel = r
			best = other
	return best


static func _lie(w: World, n: NPC, topic: String, res: Dictionary) -> void:
	var parts := topic.split(":")
	var kind := parts[0]
	var arg := parts[1]
	var v := _vars(w, n)
	var type := ""
	var data := {}
	var at := n.pos
	var att := attitude(w, n)
	var believe := 0.45 + att / 150.0 - n.axis("suspicion") / 120.0
	match kind:
		"lie_raid":
			var s: Settlement = w.settlements[arg]
			type = "raid_planned"
			data = {"attacker": _likely_attacker(w, s.faction), "place": s.id, "where": s.where}
			at = s.center
		"lie_spy":
			var t: NPC = w.npcs[int(arg)]
			if t == n:
				res["player"] = "Ты шпион, %s." % n.first
				res["text"] = _p("lie.self", w, v)
				n.trust -= 20
				n.remember(w.day(), "mem.lie")
				return
			type = "spy"
			data = {"victim": t.full_name(), "victim_f": t.female, "victim_id": t.id,
				"spy_for": _likely_attacker(w, t.faction), "victim_faction": t.faction}
			at = t.pos
			if t.faction == n.faction:
				believe -= 0.15 + n.axis("loyalty") / 200.0
		_:
			var s2: Settlement = w.settlements[arg]
			type = "treasure"
			data = {"place": s2.id, "where": s2.near}
			at = s2.center
	var f := w.add_fact(type, at, data, 2, 0.0, false)
	f.origin = "player"
	w.player.learn(f.id, 1.0)
	var text := FactText.describe(w, f, 1.0)
	res["player"] = text
	w.log_event("[Ложь] %s говорит %s: «%s»" % [w.player.name, n.full_name(), text])
	var roll := w.rng.randf()
	if roll < believe:
		n.learn(f.id, 0.9, w.day())
		res["text"] = _p("lie.believed", w, v)
	elif roll < believe + 0.2:
		n.learn(f.id, 0.5, w.day())
		res["text"] = _p("lie.doubt", w, v)
	else:
		n.trust -= 15
		n.remember(w.day(), "mem.lie")
		res["text"] = _p("lie.caught", w, v)


# ---------------- отношения ----------------

static func _flatter(w: World, n: NPC, res: Dictionary) -> void:
	var v := _vars(w, n)
	res["player"] = FLATTERY[w.rng.randi() % FLATTERY.size()]
	n.flatter_count += 1
	if n.flatter_count > 2:
		n.trust -= 2
		res["text"] = _p("flatter.repeat", w, v)
	elif n.axis("suspicion") > 30:
		n.trust -= 3
		res["text"] = _p("flatter.suspicious", w, v)
	elif n.axis("vanity") > 30:
		n.trust += 12
		n.remember(w.day(), "mem.flatter")
		res["text"] = _p("flatter.vain", w, v)
	else:
		n.trust += 5
		res["text"] = _p("flatter.success", w, v)


static func _bribe(w: World, n: NPC, amount: int, res: Dictionary) -> void:
	var v := _vars(w, n)
	res["player"] = "Возьми %d₵. За понимание." % amount
	var greed := n.axis("greed")
	if w.player.money < amount:
		res["text"] = _p("bribe.nomoney", w, v)
		return
	if n.axis("honesty") > 30 and amount < 100:
		n.trust -= 5
		res["text"] = _p("bribe.honest", w, v)
		return
	if greed > 20 and amount < 30:
		res["text"] = _p("bribe.small", w, v)
		return
	w.player.money -= amount
	n.money += amount
	n.trust += mini(40, int(amount / 3.0 * (1.0 + greed / 100.0)))
	n.bribed_day = w.day()
	n.remember(w.day(), "mem.bribe")
	if n.grudges.has(PLAYER) and amount >= 30 and greed >= 0:
		n.grudges.erase(PLAYER)
		if n.engage_id == PLAYER:
			n.engage_id = -1
		res["text"] = _p("bribe.forgive", w, v)
	elif n.axis("kindness") > 20 and greed <= 0:
		res["text"] = _p("bribe.gift", w, v)
	else:
		res["text"] = _p("bribe.accept", w, v)


static func _threaten(w: World, n: NPC, res: Dictionary) -> void:
	var v := _vars(w, n)
	res["player"] = "Гони деньги. Или пожалеешь."
	n.remember(w.day(), "mem.threat")
	var allies := []
	for id in w.actors_near(w.actor_pos(n.id), 6.0):
		if id != PLAYER and id != n.id and w.npcs[id].faction == n.faction and n.faction != "" and w.npcs[id].is_fighter():
			allies.append(w.npcs[id])
	var mine := w.player.power() + w.followers().size() * 3.0
	var theirs := n.combat_power() + allies.size() * 3.0 + n.axis("courage") / 10.0
	var chance := clampf(0.5 + (mine - theirs) * 0.06 + n.fear / 200.0, 0.05, 0.95)
	w.add_fact("threat", n.pos, {"who": w.player.name, "who_f": w.player.female, "victim": n.full_name(),
		"victim_f": n.female, "victim_faction": n.faction}, 1, 6.0)
	if w.rng.randf() < chance:
		n.fear += 30
		n.trust -= 15
		var give := mini(n.money, w.rng.randi_range(10, 40))
		if give > 0:
			n.money -= give
			w.player.money += give
			v["money"] = give
			res["text"] = _p("threaten.success", w, v)
		else:
			res["text"] = _p("threaten.success_poor", w, v)
		if not _unknown_facts(w, n).is_empty():
			res["text"] += " " + _share_news(w, n, 1)
		return
	n.trust -= 20
	if n.is_fighter() or n.axis("aggression") >= 30:
		n.grudges[PLAYER] = true
		n.engage_id = PLAYER
		res["text"] = _p("threaten.attack", w, v)
		res["close"] = true
	elif not allies.is_empty():
		for al: NPC in allies:
			al.grudges[PLAYER] = true
			al.engage_id = PLAYER
		res["text"] = _p("threaten.guards", w, v)
		res["close"] = true
	else:
		res["text"] = _p("threaten.laugh", w, v)


static func _insult(w: World, n: NPC, res: Dictionary) -> void:
	var v := _vars(w, n)
	res["player"] = INSULTS[w.rng.randi() % INSULTS.size()]
	n.trust -= 20
	n.remember(w.day(), "mem.insult")
	if (n.axis("aggression") >= 30 or (n.is_fighter() and n.axis("courage") >= 0)) and w.rng.randf() < 0.6:
		n.grudges[PLAYER] = true
		n.engage_id = PLAYER
		res["text"] = _p("insult.attack", w, v)
		res["close"] = true
	elif n.axis("courage") < 0 or n.axis("kindness") > 20:
		res["text"] = _p("insult.sad", w, v)
	elif n.axis("courage") > 20:
		res["text"] = _p("insult.laugh", w, v)
	else:
		res["text"] = _p("insult.angry", w, v)


# ---------------- спутники ----------------

static func _recruit(w: World, n: NPC, res: Dictionary) -> void:
	var v := _vars(w, n)
	if n.follow_id == PLAYER:
		res["player"] = "Дальше я пойду один."
		n.follow_id = -1
		n.action = "return"
		NpcAI.go_home(w, n)
		res["text"] = _p("dismiss", w, v)
		return
	res["player"] = "Пойдёшь со мной?"
	var att := attitude(w, n)
	if w.followers().size() >= MAX_FOLLOWERS:
		res["text"] = _p("recruit.full", w, v)
	elif n.role == "leader" or n.role == "officer":
		res["text"] = _p("recruit.boss", w, v)
	elif n.role == "slave" and n.faction == "syndicate":
		if att < 20 or (n.axis("courage") < -20 and att < 50):
			res["text"] = _p("recruit.slave_afraid", w, v)
		else:
			n.faction = ""
			_make_follower(w, n, res, "recruit.slave_free")
	elif n.role in ["soldier", "guard", "pirate"] and n.axis("loyalty") > 20:
		res["text"] = _p("recruit.loyal", w, v)
	elif att < 0:
		res["text"] = _p("recruit.refuse", w, v)
	else:
		var price := maxi(0, 30 + int(float(n.role_info().get("combat", 3))) * 8 - att / 2 + n.axis("greed") / 2)
		if att >= 70:
			price = 0
		if price > 0:
			n.pending = {"type": "recruit", "price": price}
			v["price"] = price
			res["text"] = _p("recruit.price", w, v) + " (Спросить → Заплатить)"
		else:
			_make_follower(w, n, res, "recruit.accept")


static func _make_follower(w: World, n: NPC, res: Dictionary, key: String) -> void:
	n.follow_id = PLAYER
	n.action = "follow"
	n.path.clear()
	n.engage_id = -1
	n.trust += 10
	res["text"] = _p(key, w, _vars(w, n))
	w.notify("%s теперь идёт с тобой." % n.full_name())


# ---------------- торговля и прочее ----------------

static func _market(w: World, n: NPC) -> Settlement:
	var s := w.settlement_at(n.pos)
	if s == null or s.kind == "wreck":
		return null
	return s


static func _buy_price(w: World, s: Settlement, g: String, att: int) -> int:
	return maxi(1, roundi(Economy.price(w, s, g) * (1.15 - att / 400.0)))


static func _sell_price(w: World, s: Settlement, g: String, att: int) -> int:
	return maxi(1, roundi(Economy.price(w, s, g) * (0.8 + att / 400.0)))


static func _trade(w: World, n: NPC, topic: String, res: Dictionary) -> void:
	var v := _vars(w, n)
	var s := _market(w, n)
	var parts := topic.split(":")
	var g := parts[1] if parts.size() > 1 else "food"
	var gn := DataDB.good_name(g).to_lower()
	if s == null:
		res["text"] = _p("trade.noplace", w, v)
		return
	var att := attitude(w, n)
	if parts[0] == "buy":
		res["player"] = "Беру: %s." % gn
		var price := _buy_price(w, s, g, att)
		if float(s.stock.get(g, 0.0)) < 1.0:
			res["text"] = _p("trade.nostock", w, v)
		elif w.player.money < price:
			res["text"] = _p("trade.nomoney", w, v)
		else:
			w.player.money -= price
			Economy.add(s, g, -1.0)
			w.player.add_item(g, 1)
			v["price"] = price
			res["text"] = _p("trade.buy", w, v)
	else:
		res["player"] = "Продаю: %s." % gn
		if int(w.player.inv.get(g, 0)) <= 0:
			res["text"] = "У тебя этого нет."
			return
		var price := _sell_price(w, s, g, att)
		w.player.add_item(g, -1)
		Economy.add(s, g, 1.0)
		w.player.money += price
		v["price"] = price
		res["text"] = _p("trade.sell", w, v)


static func _collar(w: World, n: NPC, res: Dictionary) -> void:
	var v := _vars(w, n)
	res["player"] = "Можешь снять с меня ошейник?"
	if n.role != "smith":
		res["text"] = _p("collar.notsmith", w, v)
	elif n.faction == "syndicate" or attitude(w, n) < -10 or n.axis("courage") < -20:
		res["text"] = _p("collar.refuse", w, v)
	elif attitude(w, n) >= 50:
		_remove_collar(w, n, res)
	else:
		n.pending = {"type": "collar", "price": 40}
		v["price"] = 40
		res["text"] = _p("collar.price", w, v) + " (Спросить → Заплатить)"


static func _remove_collar(w: World, n: NPC, res: Dictionary) -> void:
	w.player.flags.erase("collar")
	res["text"] = _p("collar.done", w, _vars(w, n))
	w.notify("Ошейник снят. Шея горит, но дышится легче.")


static func _bye(w: World, n: NPC, res: Dictionary) -> void:
	res["player"] = "Бывай."
	var att := attitude(w, n)
	var key := "bye.neutral"
	if w.is_hostile(n.id, PLAYER) or att <= -40:
		key = "bye.hostile"
	elif att >= 30:
		key = "bye.friendly"
	res["text"] = _p(key, w, _vars(w, n))
	res["close"] = true
