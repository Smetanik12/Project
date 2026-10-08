extends SceneTree
## Безголовый тест симуляции. Запуск:
##   godot --headless --path . --script res://tests/test_sim.gd
## Для каждого сценария: генерация мира, 5 игровых дней, случайные диалоги, сохранение и загрузка.

const DAYS := 8

var failures := 0


func _initialize() -> void:
	DataDB.ensure_loaded()
	for sc in Scenarios.ORDER:
		_run_scenario(sc)
	print("")
	if failures == 0:
		print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ")
	else:
		print("ОШИБОК: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("  ✗ " + msg)


func _run_scenario(sc: String) -> void:
	print("\n=== Сценарий: %s ===" % Scenarios.LIST[sc]["title"])
	var t0 := Time.get_ticks_msec()
	var w := Scenarios.create(sc, 1234, sc == "officer")
	check(w.npcs.size() > 80, "мало NPC: %d" % w.npcs.size())
	check(w.map.is_passable(w.player.tile()), "игрок стоит в стене")
	print("  мир создан за %d мс, NPC: %d" % [Time.get_ticks_msec() - t0, w.npcs.size()])
	t0 = Time.get_ticks_msec()
	for i in World.TICKS_PER_DAY * DAYS:
		w.step()
		if i % 60 == 0 and w.player.alive:
			_random_dialogue(w)
	var ms := Time.get_ticks_msec() - t0
	print("  %d дней симуляции за %d мс (%.2f мс/тик)" % [DAYS, ms, float(ms) / (World.TICKS_PER_DAY * DAYS)])
	var alive := 0
	for n: NPC in w.npcs.values():
		if n.alive:
			alive += 1
			check(w.map.is_passable(n.pos), "%s в непроходимой клетке %s" % [n.full_name(), n.pos])
	for s: Settlement in w.settlements.values():
		for g in s.stock:
			check(float(s.stock[g]) >= 0.0, "отрицательный склад %s/%s" % [s.id, g])
	print("  живых NPC: %d / %d, фактов: %d, событий в хронике: %d, игрок жив: %s" % [alive, w.npcs.size(), w.facts.size(), w.chronicle.size(), w.player.alive])
	check(alive > 40, "слишком много смертей")
	check(w.facts.size() > 10, "мир не живёт: мало фактов")
	_print_stats(w)
	_print_chronicle(w)
	_save_load(w)


func _random_dialogue(w: World) -> void:
	var ids := w.npcs.keys()
	var n: NPC = w.npcs[ids[w.rng.randi() % ids.size()]]
	if not n.alive:
		return
	# в тесте «телепортируем» игрока к NPC, чтобы проверить все ветки
	Dialogue.greet(w, n)
	var actions := Dialogue.actions_for(w, n)
	var a: Array = actions[w.rng.randi() % actions.size()]
	var topic := ""
	if a[0] in Dialogue.NEEDS_TOPIC:
		var topics := Dialogue.topics_for(w, n, a[0])
		if topics.is_empty():
			return
		topic = topics[w.rng.randi() % topics.size()]["id"]
	var res := Dialogue.run(w, n, a[0], topic)
	check(res["text"] is String, "диалог вернул не строку")
	check(not str(res["text"]).contains("{"), "неподставленная переменная: %s / %s → %s" % [a[0], topic, res["text"]])


func _print_stats(w: World) -> void:
	var types := {}
	for f: Fact in w.facts.values():
		types[f.type] = int(types.get(f.type, 0)) + 1
	print("  факты по типам: ", types)
	var owners := []
	for s: Settlement in w.settlements.values():
		owners.append("%s=%s" % [s.id, s.faction])
	print("  владельцы: ", ", ".join(PackedStringArray(owners)))
	print("  Империя↔Фронт: %d, Гильдия↔Синдикат: %d, Вольные↔Империя: %d" % [w.factions["empire"].rel("front"), w.factions["guild"].rel("syndicate"), w.factions["free"].rel("empire")])
	var food := []
	for s: Settlement in w.settlements.values():
		food.append("%s:%d" % [s.id, int(float(s.stock.get("food", 0)))])
	print("  еда на складах: ", ", ".join(PackedStringArray(food)))


func _print_chronicle(w: World) -> void:
	print("  --- последние события мира ---")
	var tail: Array = w.chronicle.slice(maxi(0, w.chronicle.size() - 14))
	for e in tail:
		var m := int(e["tick"]) * World.TICK_MINUTES
		print("  [д%d %02d:%02d] %s" % [m / 1440 + 1, (m % 1440) / 60, m % 60, e["text"]])


func _save_load(w: World) -> void:
	var text := var_to_str(w.to_dict())
	var w2 := World.from_dict(str_to_var(text))
	check(w2.npcs.size() == w.npcs.size(), "после загрузки другое число NPC")
	check(w2.tick == w.tick, "после загрузки другой тик")
	check(w2.player.name == w.player.name, "после загрузки другой игрок")
	for i in 100:
		w2.step()
	print("  сохранение: %d КБ, загрузка и 100 тиков после неё — ок" % (text.length() / 1024))
