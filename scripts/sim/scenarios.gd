class_name Scenarios
extends RefCounted
## Стартовые сценарии в духе Kenshi. Мир один и тот же, меняется только твоё место в нём.

const PLAYER := 0
const ORDER := ["slave", "officer", "crash", "soldier"]
const LIST := {
	"slave": {"title": "Раб",
		"desc": "Рудник Синдиката. Ошейник, кирка, надсмотрщики. Сбеги, подними бунт или сгинь здесь."},
	"officer": {"title": "Офицер, который узнал лишнее",
		"desc": "Лейтенант Империи. Ты видел накладные: генерал продаёт оружие пиратам. Скоро за тобой придут."},
	"crash": {"title": "Аварийная посадка",
		"desc": "Твой корабль рухнул в пустоши. Экипаж мёртв, вокруг чужая планета, а дым видно за десятки километров."},
	"soldier": {"title": "Солдат в окопе",
		"desc": "Рядовой Империи на линии фронта. Третий месяц войны. На рассвете фронтовики снова пойдут в атаку."},
}


static func create(id: String, world_seed: int, female := false) -> World:
	var w := WorldGen.generate(world_seed)
	w.scenario = id
	w.tick = 5 * World.TICKS_PER_HOUR  # 05:00 первого дня
	var p := w.player
	p.female = female
	var firsts: Array = DataDB.names["female" if female else "male"]
	var lasts: Array = DataDB.names["last"]
	var last: String = lasts[w.rng.randi() % lasts.size()]
	p.name = str(firsts[w.rng.randi() % firsts.size()]) + " " + (U.female_surname(last) if female else last)
	match id:
		"slave":
			_slave(w)
		"officer":
			_officer(w)
		"crash":
			_crash(w)
		_:
			_soldier(w)
	w._update_residents()
	w._build_buckets()
	return w


static func _place_player(w: World, sid: String) -> void:
	w.player.pos = Vector2(w.random_point_in(w.settlements[sid])) + Vector2(0.5, 0.5)


static func _meet(w: World, sid: String, trust: int, roles: Array = []) -> void:
	for n: NPC in w.npcs.values():
		if n.home == sid and (roles.is_empty() or n.role in roles):
			n.trust = trust
			n.met_player = true
			w.player.known_people[n.id] = true


static func _slave(w: World) -> void:
	var p := w.player
	_place_player(w, "glotka")
	p.hp = 75.0
	p.hunger = 40.0
	p.flags["slave"] = true
	p.flags["collar"] = true
	_meet(w, "glotka", 25, ["slave"])
	_meet(w, "glotka", -10, ["guard", "officer"])
	w.notify("Рудник «Глотка». Ты раб Синдиката. Ошейник натёр шею до крови, а надсмотрщики сегодня злее обычного.")
	w.journal("Подсказка: поговори (E) с другими рабами. Охрану можно подкупить или запугать. Позови рабов с собой и уходи. Ошейник может снять оружейник.")


static func _officer(w: World) -> void:
	var p := w.player
	_place_player(w, "arkon")
	p.faction = "empire"
	p.money = 250
	p.inv = {"weapons": 1, "medicine": 2, "food": 3}
	p.flags["officer"] = true
	w.factions["empire"].player_rep = 40
	w.factions["front"].player_rep = -30
	_meet(w, "arkon", 10)
	var general: NPC = null
	for n: NPC in w.npcs.values():
		if n.home == "arkon" and n.role == "leader":
			general = n
	if general != null:
		var f := w.add_fact("secret_arms", general.pos, {"general": general.full_name(), "general_f": general.female}, 3, 0.0)
		p.learn(f.id, 1.0)
		general.learn(f.id, 1.0, 1)
		w.factions["empire"].known_facts[f.id] = true
		w.factions["syndicate"].known_facts[f.id] = true
	w.flags["reveal_tick"] = w.tick + 9 * World.TICKS_PER_HOUR
	w.notify("Цитадель Аркон. Ночью ты видел%s накладные: генерал тайно продаёт оружие Синдикату. Тебя заметили у сейфа." % p.a())
	w.journal("Подсказка: через несколько часов тебя объявят предателем. Уходи из Цитадели. Расскажи о сделке тем, кому это выгодно: Фронту, Гильдии, вольным. Слух разойдётся сам.")


static func _crash(w: World) -> void:
	var p := w.player
	var site := _find_crash_site(w)
	var s := Settlement.new()
	s.id = "wreck"
	s.name = "Обломки корабля"
	s.where = "у обломков корабля"
	s.from = "с места крушения"
	s.near = "у обломков корабля"
	s.kind = "wreck"
	s.center = site
	s.radius = 3
	s.lootable = true
	s.stock = {"food": 6.0, "water": 6.0, "metal": 25.0, "medicine": 4.0, "fuel": 12.0, "weapons": 2.0}
	WorldGen._clear_area(w, site, 3)
	s.buildings = WorldGen._buildings(w, s)
	w.settlements["wreck"] = s
	w.map.build_astar()
	w.build_settle_grid()
	w.player.pos = Vector2(site + Vector2i(0, 2)) + Vector2(0.5, 0.5)
	p.hp = 55.0
	p.money = 40
	p.inv = {"food": 2}
	w._build_buckets()
	var near := w.nearest_settlement(site)
	w.add_fact("crash", site, {"where": near.near, "wreck": "wreck"}, 2, 35.0)
	w.notify("Удар. Огонь. Тишина. Твой транспорт лежит грудой металла посреди чужой пустоши. Экипаж мёртв.")
	w.journal("Подсказка: обыщи обломки (E рядом с ними), пока не пришли мусорщики. Найди людей и узнай, где ты.")


static func _find_crash_site(w: World) -> Vector2i:
	var best := Vector2i(w.map.w / 2, w.map.h / 2)
	for i in 300:
		var p := Vector2i(w.rng.randi_range(15, w.map.w - 15), w.rng.randi_range(25, w.map.h - 20))
		if not w.map.is_passable(p) or w.map.is_road(p):
			continue
		var near := w.nearest_settlement(p)
		var d := Vector2(near.center - p).length()
		if d < 16.0 or d > 32.0:
			continue
		if w.map.find_path(p, near.center).is_empty():
			continue
		return p
	return w.map.nearest_passable(best)


static func _soldier(w: World) -> void:
	var p := w.player
	_place_player(w, "pepel_imp")
	p.faction = "empire"
	p.money = 15
	p.inv = {"weapons": 1, "food": 2}
	p.flags["soldier"] = true
	w.factions["empire"].player_rep = 30
	w.factions["front"].player_rep = -70
	w.flags["force_assault"] = "front"
	_meet(w, "pepel_imp", 15)
	w.notify("Окоп «Пепельный хребет». Третий месяц войны. Рация хрипит, сержант орёт. Говорят, на рассвете фронтовики снова пойдут в атаку.")
	w.journal("Подсказка: держи позицию (F — удар) или беги. Если уйдёшь далеко от окопа, тебя сочтут дезертиром.")


## Проверки сценариев раз в час: побег, дезертирство, разоблачение, бунт.
static func hourly(w: World) -> void:
	var p := w.player
	if not p.alive:
		return
	if p.flags.get("slave", false):
		var mine: Settlement = w.settlements.get("glotka")
		if mine != null and Vector2(p.tile() - mine.center).length() > mine.radius + 6:
			p.flags.erase("slave")
			p.flags["escaped"] = true
			w.add_fact("escape", mine.center, {"who": p.name, "who_f": p.female, "faction": mine.faction}, 2, mine.radius + 3.0)
			w.notify("Ты вырвал%s за пределы рудника! Скоро охрана поднимет тревогу." % p.a())
	if p.flags.get("soldier", false) and not p.flags.get("deserter", false) and p.faction == "empire":
		var trench: Settlement = w.settlements.get("pepel_imp")
		if trench != null and trench.faction == "empire" and Vector2(p.tile() - trench.center).length() > 28.0:
			p.flags["deserter"] = true
			p.faction = ""
			w.add_fact("desertion", trench.center, {"who": p.name, "who_f": p.female, "faction": "empire"}, 2, trench.radius + 3.0)
			w.notify("Окоп остался далеко позади. Для Империи ты теперь дезертир.")
	if p.flags.get("officer", false) and not p.flags.get("traitor", false) and w.tick >= int(w.flags.get("reveal_tick", 0)):
		p.flags["traitor"] = true
		p.faction = ""
		var emp: Faction = w.factions["empire"]
		emp.player_rep = -100
		FactionAI.bounty_player(w, emp, 150)
		w.notify("Тревога в Цитадели! Тебя объявили предателем Трона.")
	_check_liberation(w)


## Если игрок рядом, а охраны на руднике не осталось — рабы свободны.
static func _check_liberation(w: World) -> void:
	var mine: Settlement = w.settlements.get("glotka")
	if mine == null or mine.faction != "syndicate":
		return
	if Vector2(w.player.tile() - mine.center).length() > mine.radius + 3:
		return
	for n: NPC in w.npcs.values():
		if n.alive and not n.jailed and n.home == mine.id and n.faction == "syndicate" and n.is_fighter():
			return
	mine.faction = "free"
	for n: NPC in w.npcs.values():
		if n.alive and n.home == mine.id and n.role == "slave":
			n.faction = "free"
			n.role = "miner"
			n.trust += 40
	w.factions["free"].player_rep = mini(100, w.factions["free"].player_rep + 40)
	w.player.flags.erase("slave")
	w.add_fact("liberation", mine.center, {"prev": "syndicate"}, 3, 20.0)
	w.notify("Рудник «Глотка» свободен! Бывшие рабы смотрят на тебя как на героя.")
