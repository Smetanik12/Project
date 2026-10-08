class_name DialogueUI
extends PanelContainer
## Окно разговора. Логика ответа — в Dialogue (scripts/sim), здесь только кнопки и текст.

signal closed

var world: World
var npc: NPC
var header: Label
var log_box: RichTextLabel
var actions_box: HFlowContainer
var topics_box: VBoxContainer
var current_action := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(0.94))
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 12
	offset_right = 940
	offset_top = -640
	offset_bottom = -44
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	header = UiStyle.label("", 16, UiStyle.ACCENT)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(header)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(0, 230)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 16)
	v.add_child(log_box)
	actions_box = HFlowContainer.new()
	actions_box.add_theme_constant_override("h_separation", 6)
	actions_box.add_theme_constant_override("v_separation", 6)
	v.add_child(actions_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	topics_box = VBoxContainer.new()
	topics_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(topics_box)


func open(w: World, n: NPC) -> void:
	world = w
	npc = n
	current_action = ""
	log_box.clear()
	_say_npc(Dialogue.greet(w, n))
	_refresh()
	show()


func close() -> void:
	hide()
	closed.emit()


func _say_npc(text: String) -> void:
	log_box.append_text("[color=#ffd27f]%s:[/color] %s\n\n" % [npc.first, UiStyle.esc(text)])


func _refresh() -> void:
	header.text = Dialogue.header(world, npc)
	for c in actions_box.get_children():
		c.queue_free()
	for a in Dialogue.actions_for(world, npc):
		var id: String = a[0]
		var b := UiStyle.button(a[1], 15)
		if id == current_action:
			b.add_theme_color_override("font_color", UiStyle.ACCENT)
		b.pressed.connect(_on_action.bind(id))
		actions_box.add_child(b)
	_show_topics()


func _on_action(id: String) -> void:
	current_action = id
	if id in Dialogue.NEEDS_TOPIC:
		_refresh()
	else:
		_do(id, "")


func _show_topics() -> void:
	for c in topics_box.get_children():
		c.queue_free()
	if not (current_action in Dialogue.NEEDS_TOPIC):
		topics_box.add_child(UiStyle.label("Выбери действие. Спросить и рассказать можно о чём угодно из того, что знаешь.", 14, Color(0.7, 0.7, 0.65)))
		return
	var list := Dialogue.topics_for(world, npc, current_action)
	if list.is_empty():
		topics_box.add_child(UiStyle.label("Тут нечего выбрать.", 14, Color(0.7, 0.7, 0.65)))
		return
	var group := ""
	for t in list:
		if t["group"] != group:
			group = t["group"]
			topics_box.add_child(UiStyle.label(group, 13, Color(0.65, 0.6, 0.5)))
		var b := UiStyle.button(t["label"], 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_do.bind(current_action, t["id"]))
		topics_box.add_child(b)


func _do(action: String, topic: String) -> void:
	var res := Dialogue.run(world, npc, action, topic)
	if str(res["player"]) != "":
		log_box.append_text("[color=#9fc5ff]Ты:[/color] %s\n" % UiStyle.esc(str(res["player"])))
	if str(res["text"]) != "":
		_say_npc(str(res["text"]))
	if res["close"]:
		if action != "bye":
			world.notices.append("%s: «%s»" % [npc.first, res["text"]])
		close()
	else:
		_refresh()
