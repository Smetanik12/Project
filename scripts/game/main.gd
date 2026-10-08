extends Node
## Точка входа: меню сценариев → игра. Ввод, скорость времени, камера, сохранения.
## Вся логика мира — в scripts/sim, здесь только управление и связка с отображением.
##
## Запуск без окна для проверок и скриншотов (аргументы после «--»):
##   godot --path . -- --scenario=soldier --seed=7 --ticks=300 --screenshot=/tmp/shot.png
##   доп. флаги: --godview (хроника мира), --talk (открыть диалог с ближайшим), --zoom=1.5

const SPEEDS := [0.0, 4.0, 10.0, 25.0]  # тиков симуляции в секунду
const SPEED_NAMES := ["⏸ Пауза (Пробел)", "▶ x1", "▶▶ x2", "▶▶▶ x3"]
const SAVE_PATH := "user://save.txt"
const PLAYER_SPEED := 1.3  # тайлов за тик
const TILE := WorldView.TILE

var world: World
var view: WorldView
var hud: Hud
var dialogue: DialogueUI
var camera: Camera2D
var shade: CanvasModulate
var menu: Control
var speed := 1
var last_speed := 1
var acc := 0.0
var cli := {}
var female := false


func _ready() -> void:
	DataDB.ensure_loaded()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if not cli.has("scenario"):
		_show_menu()
		return
	start_game(cli["scenario"], int(cli.get("seed", "1")), cli.get("female", "0") == "1")
	for i in int(cli.get("ticks", "0")):
		world.step()
	if cli.has("godview"):
		hud.god_mode = true
	if cli.has("zoom"):
		camera.zoom = Vector2.ONE * float(cli["zoom"])
	if cli.has("talk"):
		var near := _nearest_npc(999.0)
		if near != null:
			world.player.pos = Vector2(near.pos) + Vector2(1.5, 0.5)
			camera.position = world.player.pos * TILE
		_interact()
		if dialogue.visible:
			dialogue._do("ask", "self")
			dialogue._do("ask", "news")
			dialogue._on_action("ask")
	if cli.has("screenshot"):
		_screenshot.call_deferred(cli["screenshot"])


func _screenshot(path: String) -> void:
	for i in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# ---------------- меню ----------------

func _show_menu() -> void:
	_clear_game()
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(720, 0)
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)
	var title := UiStyle.label("РУБЕЖ", 64, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UiStyle.label("Живой мир на краю галактики. Он не ждёт тебя. Кем ты начнёшь?", 18, Color(0.8, 0.78, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var g := UiStyle.button("", 15)
	g.text = "Пол персонажа: женский" if female else "Пол персонажа: мужской"
	g.pressed.connect(func():
		female = not female
		g.text = "Пол персонажа: женский" if female else "Пол персонажа: мужской")
	v.add_child(g)
	for id in Scenarios.ORDER:
		var info: Dictionary = Scenarios.LIST[id]
		var b := UiStyle.button("%s\n%s" % [info["title"], info["desc"]], 16)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 74)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): start_game(id, randi(), female))
		v.add_child(b)
	if FileAccess.file_exists(SAVE_PATH):
		var lb := UiStyle.button("Продолжить сохранённую игру", 16)
		lb.pressed.connect(_load)
		v.add_child(lb)


# ---------------- игра ----------------

func start_game(scenario: String, world_seed: int, is_female: bool) -> void:
	_clear_game()
	world = Scenarios.create(scenario, world_seed, is_female)
	_build_game()


func _build_game() -> void:
	view = WorldView.new()
	add_child(view)
	view.setup(world)
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	camera.make_current()
	camera.position = world.player.pos * TILE
	camera.reset_smoothing()
	shade = CanvasModulate.new()
	add_child(shade)
	hud = Hud.new()
	add_child(hud)
	hud.setup(world)
	hud.new_game_requested.connect(_show_menu)
	dialogue = DialogueUI.new()
	hud.add_child(dialogue)
	dialogue.hide()
	dialogue.closed.connect(func(): view.selected_npc = -1)
	speed = 1
	acc = 0.0


func _clear_game() -> void:
	for node in [view, camera, shade, hud, menu]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	view = null
	camera = null
	shade = null
	hud = null
	menu = null
	dialogue = null


func _process(delta: float) -> void:
	if world == null or view == null:
		return
	var talking := dialogue.visible
	if not talking and world.player.alive:
		_move_player(delta)
	if speed > 0 and not talking:
		acc += delta * SPEEDS[speed]
		var steps := 0
		while acc >= 1.0 and steps < 50:
			world.step()
			acc -= 1.0
			steps += 1
		if steps >= 50:
			acc = 0.0
	view.alpha = clampf(acc, 0.0, 1.0)
	if world.player.alive:
		camera.position = world.player.pos * TILE
	shade.color = _daylight()
	hud.update_hud(SPEED_NAMES[0] if talking else SPEED_NAMES[speed], _context_hint())
	if world.game_over and not hud.over_panel.visible and not hud.god_mode:
		hud.show_game_over()


func _move_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir == Vector2.ZERO or speed == 0:
		return
	var step: Vector2 = dir.normalized() * SPEEDS[speed] * PLAYER_SPEED * delta
	var p := world.player.pos
	var nx := p + Vector2(step.x, 0)
	if world.map.is_passable(Vector2i(nx.floor())):
		p = nx
	var ny := p + Vector2(0, step.y)
	if world.map.is_passable(Vector2i(ny.floor())):
		p = ny
	world.player.pos = p


func _daylight() -> Color:
	var h := float(world.minutes() % 1440) / 60.0
	var day_amt := clampf(minf(h - 5.0, 20.0 - h) / 2.0, 0.0, 1.0)
	return Color(0.38, 0.42, 0.62).lerp(Color.WHITE, day_amt)


func _nearest_npc(max_d: float) -> NPC:
	var best: NPC = null
	var best_d := max_d
	for n: NPC in world.npcs.values():
		if not n.alive or n.jailed:
			continue
		var d := (Vector2(n.pos) + Vector2(0.5, 0.5)).distance_to(world.player.pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _context_hint() -> String:
	if not world.player.alive:
		return "Ты мёртв. Tab — хроника мира, мир живёт дальше."
	var n := _nearest_npc(2.2)
	if n != null:
		var fac: String = world.factions[n.faction].short() if n.faction != "" else "сам по себе"
		var extra := "  ·  F — ударить" if world.is_hostile(n.id, World.PLAYER) else ""
		return "E — поговорить: %s (%s, %s)%s" % [n.full_name(), n.role_name().to_lower(), fac, extra]
	var s := world.settlement_at(world.player.tile())
	if s != null and s.lootable:
		return "E — обыскать обломки"
	return "WASD — идти · E — говорить · F — бить · H — лечиться · Пробел — пауза · 1-3 — скорость · Tab — хроника мира · F1 — помощь"


# ---------------- ввод ----------------

func _unhandled_input(event: InputEvent) -> void:
	if world == null or view == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if dialogue.visible:
			if event.keycode == KEY_ESCAPE:
				dialogue.close()
			return
		match event.keycode:
			KEY_SPACE:
				if speed == 0:
					speed = last_speed
				else:
					last_speed = speed
					speed = 0
			KEY_1, KEY_2, KEY_3:
				speed = event.keycode - KEY_0
				last_speed = speed
			KEY_E:
				_interact()
			KEY_F:
				_attack()
			KEY_H:
				_heal()
			KEY_TAB:
				hud.toggle_god()
			KEY_F1:
				hud.toggle_help()
			KEY_F5:
				if world.save_to(SAVE_PATH):
					world.notify("Игра сохранена.")
			KEY_F9:
				_load()
			KEY_ESCAPE:
				hud.hide_inspector()
				view.selected_npc = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom * 1.12).clamp(Vector2(0.5, 0.5), Vector2(5, 5))
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom / 1.12).clamp(Vector2(0.5, 0.5), Vector2(5, 5))
			MOUSE_BUTTON_LEFT:
				_select(view.get_global_mouse_position())


func _interact() -> void:
	if not world.player.alive:
		return
	var n := _nearest_npc(2.2)
	if n != null:
		if n.engage_id == World.PLAYER:
			world.notify("%s не станет разговаривать — он%s дерётся с тобой!" % [n.first, "а" if n.female else ""])
			return
		dialogue.open(world, n)
		view.selected_npc = n.id
		return
	var s := world.settlement_at(world.player.tile())
	if s != null and s.lootable:
		var got := []
		for g in s.stock.keys():
			var q := int(float(s.stock[g]))
			if q > 0:
				world.player.add_item(g, q)
				s.stock[g] = float(s.stock[g]) - q
				got.append("%s ×%d" % [DataDB.good_name(g), q])
		s.lootable = false
		world.notify("Из обломков удалось вытащить: " + (", ".join(PackedStringArray(got)) if not got.is_empty() else "ничего"))
		return
	world.notify("Рядом никого нет.")


func _attack() -> void:
	if not world.player.alive or not Combat.player_can_attack(world):
		return
	var target: NPC = null
	if view.selected_npc >= 0 and world.actor_alive(view.selected_npc):
		var sel: NPC = world.npcs[view.selected_npc]
		if (Vector2(sel.pos) + Vector2(0.5, 0.5)).distance_to(world.player.pos) <= Combat.REACH + 0.3:
			target = sel
	if target == null:
		var best_d := Combat.REACH + 0.3
		for n: NPC in world.npcs.values():
			if not n.alive or n.jailed or n.follow_id == World.PLAYER:
				continue
			var d := (Vector2(n.pos) + Vector2(0.5, 0.5)).distance_to(world.player.pos)
			if world.is_hostile(n.id, World.PLAYER):
				d -= 0.5  # враги в приоритете
			if d < best_d:
				best_d = d
				target = n
	if target == null:
		world.notify("Некого бить. Подойди вплотную.")
		return
	Combat.attack(world, World.PLAYER, target.id)
	if speed == 0:
		speed = last_speed


func _heal() -> void:
	if int(world.player.inv.get("medicine", 0)) <= 0:
		world.notify("Нет медикаментов.")
		return
	world.player.add_item("medicine", -1)
	world.player.hp = minf(100.0, world.player.hp + 35.0)
	world.notify("Ты перевязал%s раны." % world.player.a())


func _select(world_px: Vector2) -> void:
	var id := view.npc_at(world_px)
	if id >= 0:
		view.selected_npc = id
		hud.show_npc(world.npcs[id])
		return
	view.selected_npc = -1
	var s := world.settlement_at(Vector2i((world_px / TILE).floor()))
	if s != null:
		hud.show_settlement(s)
	else:
		hud.hide_inspector()


func _load() -> void:
	var w := World.load_from(SAVE_PATH)
	if w == null:
		if world != null:
			world.notify("Сохранения нет.")
		return
	_clear_game()
	world = w
	_build_game()
	world.notify("Игра загружена.")
