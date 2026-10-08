class_name Hud
extends CanvasLayer
## Интерфейс поверх мира: время, состояние игрока, журнал, инспектор, подсказки.

signal new_game_requested

const ACTIONS_RU := {"idle": "бездельничает", "work": "работает", "sleep": "спит",
	"travel_trade": "везёт товар", "escort": "охраняет караван", "assault": "идёт в атаку",
	"hold": "держит позицию", "raid": "идёт в набег", "pillage": "грабит", "hunt": "охотится за караваном",
	"patrol": "идёт в патруль", "guard": "охраняет", "goto_post": "идёт на пост", "loot": "идёт мародёрствовать",
	"treasure": "ищет клад", "return": "возвращается домой", "wander_trip": "путешествует", "flee": "убегает",
	"follow": "идёт с тобой", "captive": "в плену", "jailed": "в тюрьме"}

var world: World
var god_mode := false
var top: Label
var status: Label
var journal_title: Label
var journal: RichTextLabel
var hint: Label
var inspector_panel: PanelContainer
var inspector: RichTextLabel
var toasts: VBoxContainer
var help_panel: PanelContainer
var over_panel: PanelContainer
var over_text: RichTextLabel
var _shown_len := -1
var _shown_mode := false


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := UiStyle.make_panel(0.8)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 40
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	bar.add_child(hb)
	top = UiStyle.label("", 17, UiStyle.ACCENT)
	hb.add_child(top)
	status = UiStyle.label("", 16)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(status)

	var jp := UiStyle.make_panel(0.78)
	jp.anchor_left = 1.0
	jp.anchor_right = 1.0
	jp.anchor_top = 0.0
	jp.anchor_bottom = 1.0
	jp.offset_left = -430
	jp.offset_right = -8
	jp.offset_top = 48
	jp.offset_bottom = -44
	root.add_child(jp)
	var jv := VBoxContainer.new()
	jp.add_child(jv)
	journal_title = UiStyle.label("", 15, UiStyle.ACCENT)
	jv.add_child(journal_title)
	journal = RichTextLabel.new()
	journal.bbcode_enabled = true
	journal.scroll_following = true
	journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal.add_theme_font_size_override("normal_font_size", 14)
	jv.add_child(journal)

	hint = UiStyle.label("", 14, Color(0.85, 0.85, 0.8, 0.95))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -8
	hint.offset_left = 14
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(hint)

	inspector_panel = UiStyle.make_panel()
	inspector_panel.anchor_top = 1.0
	inspector_panel.anchor_bottom = 1.0
	inspector_panel.offset_left = 10
	inspector_panel.offset_right = 420
	inspector_panel.offset_top = -330
	inspector_panel.offset_bottom = -42
	inspector_panel.visible = false
	root.add_child(inspector_panel)
	inspector = RichTextLabel.new()
	inspector.bbcode_enabled = true
	inspector.add_theme_font_size_override("normal_font_size", 14)
	inspector_panel.add_child(inspector)

	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_top = 54
	toasts.offset_left = -330
	toasts.offset_right = 330
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	help_panel = UiStyle.make_panel(0.93)
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.offset_left = -330
	help_panel.offset_right = 330
	help_panel.offset_top = -230
	help_panel.offset_bottom = 230
	help_panel.visible = false
	root.add_child(help_panel)
	var ht := RichTextLabel.new()
	ht.bbcode_enabled = true
	ht.add_theme_font_size_override("normal_font_size", 16)
	ht.text = "[b]Управление[/b]\n\nWASD / стрелки — идти\nE — поговорить с ближайшим / обыскать обломки\nF — ударить ближайшего (или выбранного)\nH — использовать медикаменты\nЛКМ — осмотреть человека или поселение\nКолесо мыши — масштаб\nПробел — пауза, 1 / 2 / 3 — скорость времени\nTab — журнал ↔ хроника всего мира\nF5 — сохранить, F9 — загрузить\nF1 — эта справка\n\n[b]Как устроен мир[/b]\nМир живёт без тебя: фракции воюют, торговцы возят товар, пираты грабят. Новости расходятся слухами от человека к человеку и по дороге искажаются. Что ты скажешь одному NPC, может дойти до целой фракции."
	help_panel.add_child(ht)

	over_panel = UiStyle.make_panel(0.95)
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	over_panel.offset_left = -300
	over_panel.offset_right = 300
	over_panel.offset_top = -170
	over_panel.offset_bottom = 170
	over_panel.visible = false
	root.add_child(over_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 14)
	over_panel.add_child(ov)
	over_text = RichTextLabel.new()
	over_text.bbcode_enabled = true
	over_text.fit_content = true
	over_text.add_theme_font_size_override("normal_font_size", 17)
	ov.add_child(over_text)
	var b := UiStyle.button("Новая игра", 18)
	b.pressed.connect(func(): new_game_requested.emit())
	ov.add_child(b)
	var b2 := UiStyle.button("Смотреть, как мир живёт дальше", 15)
	b2.pressed.connect(func():
		over_panel.visible = false
		god_mode = true)
	ov.add_child(b2)


func setup(w: World) -> void:
	world = w
	_shown_len = -1


func update_hud(speed_name: String, hint_text: String) -> void:
	if world == null:
		return
	var p := world.player
	top.text = "%s   %s" % [world.time_str(), speed_name]
	var parts := ["♥ %d" % roundi(p.hp), "Голод %d%%" % roundi(p.hunger), "%d₵" % p.money]
	var inv := []
	for g in p.inv:
		inv.append("%s %d" % [DataDB.good_name(g), int(p.inv[g])])
	parts.append(", ".join(PackedStringArray(inv)) if not inv.is_empty() else "пусто в карманах")
	var f := world.followers().size()
	if f > 0:
		parts.append("Спутники: %d" % f)
	var tags := []
	if p.faction != "":
		tags.append(world.factions[p.faction].short())
	for flag in [["collar", "Ошейник"], ["slave", "Раб"], ["escaped", "Беглец"], ["deserter", "Дезертир"], ["traitor", "Предатель"]]:
		if p.flags.get(flag[0], false):
			tags.append(flag[1])
	var wanted := []
	for fac: Faction in world.factions.values():
		if fac.bounties.has("player"):
			wanted.append(fac.short())
	if not wanted.is_empty():
		tags.append("Розыск: " + ", ".join(PackedStringArray(wanted)))
	if not tags.is_empty():
		parts.append("[" + " · ".join(PackedStringArray(tags)) + "]")
	status.text = "   ".join(PackedStringArray(parts))
	hint.text = hint_text
	_update_journal()
	while not world.notices.is_empty():
		_toast(str(world.notices.pop_front()))


func _update_journal() -> void:
	var src: Array = world.chronicle if god_mode else world.player.journal
	if src.size() == _shown_len and god_mode == _shown_mode:
		return
	_shown_len = src.size()
	_shown_mode = god_mode
	journal_title.text = "Хроника мира — всё, что происходит (Tab)" if god_mode else "Журнал — что знаешь ты (Tab)"
	var lines := []
	for e in src.slice(maxi(0, src.size() - 80)):
		var m := int(e["tick"]) * World.TICK_MINUTES
		lines.append("[color=#8a8070]д%d %02d:%02d[/color] %s" % [m / 1440 + 1, (m % 1440) / 60, m % 60, UiStyle.esc(str(e["text"]))])
	journal.text = "\n".join(PackedStringArray(lines))


func toggle_god() -> void:
	god_mode = not god_mode


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func _toast(text: String) -> void:
	var p := UiStyle.make_panel(0.9)
	var l := UiStyle.label(text, 16, Color(1, 0.95, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	toasts.add_child(p)
	if toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()
	var tw := p.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.0)
	tw.tween_callback(p.queue_free)


func show_npc(n: NPC) -> void:
	var fac := "без фракции"
	if n.faction != "" and world.factions.has(n.faction):
		fac = world.factions[n.faction].title()
	var t := "[b]%s[/b]\n%s · %s\n" % [n.full_name(), n.role_name(), fac]
	t += "Сейчас: %s\nЗдоровье: %d\n" % [ACTIONS_RU.get(n.action, n.action), roundi(n.hp)]
	if n.met_player:
		t += "К тебе: %s\n" % Dialogue.attitude_label(world, n)
	if n.revealed:
		var names := []
		for tr in n.traits:
			names.append(str(DataDB.traits[tr]["name"]))
		t += "Характер: %s\n" % ", ".join(PackedStringArray(names))
	else:
		t += "Характер: [i]поговори, чтобы узнать[/i]\n"
	t += "Знает новостей: %d" % n.knowledge.size()
	inspector.text = t
	inspector_panel.visible = true


func show_settlement(s: Settlement) -> void:
	var owner := "никто"
	if s.faction != "":
		owner = world.factions[s.faction].title()
	var t := "[b]%s[/b]\n%s\nХозяева: %s\nЖителей: %d\n\n" % [s.name, U.cap(s.kind_desc()), owner, world.residents(s.id)]
	if s.kind == "wreck":
		t += "Внутри ещё что-то есть." if s.lootable else "Растащено подчистую."
	else:
		t += "[b]Склад и цены[/b]\n"
		for g in DataDB.good_ids():
			t += "%s: %d шт. — %d₵\n" % [DataDB.good_name(g), int(float(s.stock.get(g, 0.0))), roundi(Economy.price(world, s, g))]
	inspector.text = t
	inspector_panel.visible = true


func hide_inspector() -> void:
	inspector_panel.visible = false


func show_game_over() -> void:
	var p := world.player
	over_text.text = "[center][b]Ты погиб%s.[/b]\n\n%s\n%s, %s\nУбито врагов: %d\n\nМир продолжает жить без тебя.[/center]" % [
		U.la(p.female), p.name, world.time_str(), Scenarios.LIST[world.scenario]["title"], p.kills]
	over_panel.visible = true
