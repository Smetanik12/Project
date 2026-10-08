class_name WorldView
extends Node2D
## Отрисовка мира сверху. Логики здесь нет: только читает World и рисует.
## Земля запекается в одну текстуру, всё остальное рисуется каждый кадр.

const TILE := 16
const PX := 4  # пикселей текстуры на тайл
const TERRAIN := [
	Color(0.16, 0.3, 0.42),   # WATER
	Color(0.78, 0.68, 0.46),  # SAND
	Color(0.36, 0.48, 0.27),  # GRASS
	Color(0.47, 0.38, 0.27),  # DIRT
	Color(0.4, 0.38, 0.36),   # ASH
	Color(0.52, 0.5, 0.46),   # ROCK
	Color(0.3, 0.28, 0.27),   # MOUNTAIN
	Color(0.56, 0.53, 0.48),  # FLOOR
]
const ROAD := Color(0.62, 0.54, 0.4)
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.62, 0.45), Color(0.55, 0.38, 0.26)]
const NEUTRAL := Color(0.62, 0.6, 0.56)

var world: World
## Доля пути до следующего тика — для плавного движения.
var alpha := 0.0
var selected_npc := -1
var font: Font
var terrain_sprite: Sprite2D
var time := 0.0


func setup(w: World) -> void:
	world = w
	font = ThemeDB.fallback_font
	if terrain_sprite == null:
		terrain_sprite = Sprite2D.new()
		terrain_sprite.centered = false
		terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		terrain_sprite.z_index = -10
		add_child(terrain_sprite)
	terrain_sprite.texture = _bake_terrain()
	terrain_sprite.scale = Vector2(TILE / PX, TILE / PX)


func _bake_terrain() -> ImageTexture:
	var m := world.map
	var img := Image.create(m.w * PX, m.h * PX, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = world.world_seed + 3
	noise.frequency = 0.08
	var r := RandomNumberGenerator.new()
	r.seed = world.world_seed
	for y in m.h:
		for x in m.w:
			var p := Vector2i(x, y)
			var t := m.get_t(p)
			var road := m.is_road(p)
			var c: Color = ROAD if road else TERRAIN[t]
			var v := 1.0 + noise.get_noise_2d(x, y) * 0.14
			c = Color(c.r * v, c.g * v, c.b * v)
			img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), c)
			for k in 3:
				var dc := c.darkened(0.12) if r.randf() < 0.5 else c.lightened(0.08)
				if not road:
					match t:
						MapData.T.GRASS:
							dc = c.darkened(0.2) if r.randf() < 0.6 else Color(0.45, 0.6, 0.3)
						MapData.T.WATER:
							dc = c.lightened(0.12)
						MapData.T.MOUNTAIN:
							dc = c.darkened(0.3)
				img.set_pixel(x * PX + r.randi() % PX, y * PX + r.randi() % PX, dc)
			# обрывы гор и пена у берега
			if t == MapData.T.MOUNTAIN and y + 1 < m.h and m.get_t(p + Vector2i(0, 1)) != MapData.T.MOUNTAIN:
				img.fill_rect(Rect2i(x * PX, y * PX + PX - 1, PX, 1), c.darkened(0.45))
			if t == MapData.T.WATER and y > 0 and m.get_t(p - Vector2i(0, 1)) != MapData.T.WATER:
				img.fill_rect(Rect2i(x * PX, y * PX, PX, 1), c.lightened(0.35))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func npc_px(n: NPC) -> Vector2:
	return (Vector2(n.prev_pos).lerp(Vector2(n.pos), alpha) + Vector2(0.5, 0.5)) * TILE


func npc_at(world_px: Vector2) -> int:
	var best := -1
	var best_d := 12.0
	for n: NPC in world.npcs.values():
		if not n.alive or n.jailed:
			continue
		var d := npc_px(n).distance_to(world_px)
		if d < best_d:
			best_d = d
			best = n.id
	return best


func _view_rect() -> Rect2:
	var inv := get_canvas_transform().affine_inverse()
	return (inv * Rect2(Vector2.ZERO, get_viewport_rect().size)).grow(64)


func _fcolor(fid: String) -> Color:
	if fid == "" or not world.factions.has(fid):
		return NEUTRAL
	return world.factions[fid].color()


func _draw() -> void:
	if world == null:
		return
	var view := _view_rect()
	for s: Settlement in world.settlements.values():
		var c := Vector2(s.center) * TILE
		if view.grow(s.radius * TILE).has_point(c):
			_draw_settlement(s)
	_draw_corpses(view)
	_draw_hits()
	var ppx := world.player.pos * TILE
	for n: NPC in world.npcs.values():
		if not n.alive or n.jailed:
			continue
		var p := npc_px(n)
		if view.has_point(p):
			_draw_npc(n, p, ppx)
	if world.player.alive:
		_draw_player(ppx)
	_draw_labels(view, ppx)


func _draw_settlement(s: Settlement) -> void:
	var fc := _fcolor(s.faction)
	var c := (Vector2(s.center) + Vector2(0.5, 0.5)) * TILE
	draw_arc(c, s.radius * TILE + 6, 0, TAU, 64, Color(fc, 0.35), 2.0)
	for b in s.buildings:
		var r: Rect2i = b["r"]
		var rect := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		match b["t"]:
			"wall":
				draw_rect(rect, Color(0.22, 0.2, 0.19), false, 5.0)
				for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
					draw_rect(Rect2(corner - Vector2(9, 9), Vector2(18, 18)), Color(0.28, 0.25, 0.23))
					draw_rect(Rect2(corner - Vector2(5, 5), Vector2(10, 10)), fc.darkened(0.35))
			"house":
				draw_rect(rect.grow(2), Color(0, 0, 0, 0.25))
				draw_rect(rect, Color(0.3, 0.27, 0.24))
				var roof := fc.darkened(0.45).lerp(Color(0.42, 0.38, 0.33), 0.55)
				draw_rect(rect.grow(-3), roof)
				draw_line(Vector2(rect.position.x + 3, rect.get_center().y), Vector2(rect.end.x - 3, rect.get_center().y), roof.darkened(0.3), 2.0)
				draw_rect(Rect2(Vector2(rect.get_center().x - 3, rect.end.y - 4), Vector2(6, 4)), Color(0.1, 0.08, 0.07))
			"tent":
				var pts := PackedVector2Array([Vector2(rect.position.x, rect.end.y), Vector2(rect.get_center().x, rect.position.y + 2), rect.end])
				draw_colored_polygon(pts, fc.darkened(0.25).lerp(Color(0.62, 0.56, 0.44), 0.55))
				pts.append(pts[0])
				draw_polyline(pts, Color(0.2, 0.17, 0.14), 1.5)
			"trench":
				draw_rect(rect.grow_individual(2, 4, 2, 4), Color(0.2, 0.15, 0.11))
				for i in int(rect.size.x / 6.0) + 1:
					draw_circle(Vector2(rect.position.x + 2 + i * 6, rect.position.y - 5), 3.4, Color(0.62, 0.54, 0.37))
			"mine":
				draw_rect(rect, Color(0.24, 0.21, 0.19))
				draw_rect(rect.grow(-5), Color(0.04, 0.03, 0.03))
				draw_line(Vector2(rect.get_center().x - 4, rect.end.y), Vector2(rect.get_center().x - 4, rect.end.y + 28), Color(0.35, 0.3, 0.26), 2.0)
				draw_line(Vector2(rect.get_center().x + 4, rect.end.y), Vector2(rect.get_center().x + 4, rect.end.y + 28), Color(0.35, 0.3, 0.26), 2.0)
			"field":
				draw_rect(rect, Color(0.4, 0.31, 0.19))
				for i in range(2, int(rect.size.y), 5):
					draw_line(Vector2(rect.position.x + 1, rect.position.y + i), Vector2(rect.end.x - 1, rect.position.y + i), Color(0.4, 0.6, 0.26), 2.0)
			"stall":
				draw_rect(rect, Color(0.45, 0.32, 0.2))
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5)), fc)
			"junk":
				draw_rect(rect.grow(-1), Color(0.38, 0.33, 0.29))
				draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size * 0.5), Color(0.55, 0.32, 0.18))
				draw_rect(Rect2(rect.get_center(), rect.size * 0.35), Color(0.3, 0.3, 0.32))
			"hull":
				_draw_wreck(rect)
	if s.faction != "":
		var top := c + Vector2(0, -s.radius * TILE + 4)
		draw_line(top, top + Vector2(0, 22), Color(0.18, 0.16, 0.14), 2.0)
		var wave := sin(time * 3.0) * 1.5
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(15, 2 + wave), top + Vector2(14, 10 + wave), top + Vector2(0, 9)]), fc)


func _draw_wreck(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, rect.size.x * 0.7, Color(0.08, 0.07, 0.06, 0.55))
	var hull := PackedVector2Array([c + Vector2(-46, -6), c + Vector2(-20, -18), c + Vector2(30, -14), c + Vector2(50, 2),
		c + Vector2(26, 16), c + Vector2(-30, 14)])
	draw_colored_polygon(hull, Color(0.46, 0.47, 0.5))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -16), c + Vector2(6, -34), c + Vector2(14, -14)]), Color(0.36, 0.37, 0.4))
	draw_line(c + Vector2(-30, 0), c + Vector2(30, -2), Color(0.25, 0.25, 0.28), 2.0)
	for i in 4:
		var f := c + Vector2(-24 + i * 16, -4 + sin(time * 5.0 + i) * 3.0)
		draw_circle(f, 5.0 + sin(time * 9.0 + i * 2.0) * 1.5, Color(1.0, 0.45, 0.1, 0.8))
		draw_circle(f + Vector2(0, -3), 2.5, Color(1.0, 0.85, 0.3, 0.9))
	for i in 3:
		var age := fmod(time * 0.5 + i * 0.33, 1.0)
		draw_circle(c + Vector2(10 + age * 20, -20 - age * 50), 6.0 + age * 12.0, Color(0.25, 0.25, 0.25, 0.4 * (1.0 - age)))


func _draw_corpses(view: Rect2) -> void:
	for cp in world.corpses:
		var p := (Vector2(cp["pos"]) + Vector2(0.5, 0.5)) * TILE
		if not view.has_point(p):
			continue
		draw_circle(p + Vector2(2, 2), 6.0, Color(0.4, 0.06, 0.05, 0.55))
		var col := _fcolor(str(cp["faction"])).darkened(0.5)
		draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.5)
		draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), col, 2.5)


func _draw_hits() -> void:
	for h in world.hits:
		var age := float(world.tick - int(h["tick"])) + alpha
		var a := clampf(1.0 - age / 3.0, 0.0, 1.0)
		var from: Vector2 = h["a"] * TILE
		var to: Vector2 = h["b"] * TILE
		if h["hit"]:
			draw_line(from, to, Color(1, 0.3, 0.2, a), 2.0)
			draw_circle(to, 3.0 + age * 2.0, Color(1, 0.25, 0.15, a * 0.6))
		else:
			draw_line(from, to, Color(1, 1, 1, a * 0.5), 1.0)


func _draw_pawn(p: Vector2, body: Color, skin: Color) -> void:
	draw_circle(p + Vector2(1, 3), 6.0, Color(0, 0, 0, 0.28))
	draw_circle(p, 5.5, body)
	draw_arc(p, 5.5, 0, TAU, 16, body.darkened(0.55), 1.2)
	draw_circle(p + Vector2(0, -6), 3.3, skin)


func _draw_bar(p: Vector2, value: float, col: Color) -> void:
	draw_rect(Rect2(p + Vector2(-8, -16), Vector2(16, 3)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p + Vector2(-8, -16), Vector2(16 * clampf(value / 100.0, 0, 1), 3)), col)


func _draw_npc(n: NPC, p: Vector2, ppx: Vector2) -> void:
	var fc := _fcolor(n.faction)
	if n.role == "slave":
		fc = Color(0.5, 0.46, 0.42)
	_draw_pawn(p, fc.darkened(0.1), SKIN[n.id % 3])
	if n.is_fighter():
		draw_arc(p + Vector2(0, -6.6), 3.5, PI, TAU, 8, fc.darkened(0.5), 2.2)
	if n.role == "merchant":
		draw_rect(Rect2(p + Vector2(-8, -3), Vector2(3, 7)), Color(0.45, 0.3, 0.15))
	if n.role == "slave":
		draw_arc(p + Vector2(0, -3.5), 2.4, 0, TAU, 8, Color(0.2, 0.2, 0.22), 1.5)
	if n.follow_id == World.PLAYER:
		draw_arc(p, 8.5, 0, TAU, 20, Color(0.4, 1.0, 0.45, 0.9), 1.6)
	elif world.player.alive and p.distance_to(ppx) < 18 * TILE and world.is_hostile(n.id, World.PLAYER):
		draw_arc(p, 8.5, 0, TAU, 20, Color(1, 0.2, 0.15, 0.9), 1.6)
	if n.hp < 99.0:
		_draw_bar(p, n.hp, Color(0.9, 0.2, 0.15))
	if n.action == "sleep":
		draw_string(font, p + Vector2(5, -9), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.7))
	if n.id == selected_npc:
		draw_arc(p, 11.0, 0, TAU, 24, Color(1, 0.9, 0.3), 1.5)


func _draw_player(p: Vector2) -> void:
	var pl := world.player
	draw_arc(p, 10.0, 0, TAU, 28, Color(1, 0.85, 0.2, 0.55 + sin(time * 4.0) * 0.25), 2.0)
	_draw_pawn(p, Color(0.93, 0.9, 0.82), SKIN[0])
	if pl.flags.get("collar", false):
		draw_arc(p + Vector2(0, -3.5), 2.6, 0, TAU, 8, Color(0.25, 0.25, 0.28), 1.6)
	if int(pl.inv.get("weapons", 0)) > 0:
		draw_line(p + Vector2(5, 1), p + Vector2(10, -7), Color(0.22, 0.22, 0.26), 2.0)
	if pl.hp < 99.0:
		_draw_bar(p, pl.hp, Color(0.3, 0.9, 0.3))


func _label(p: Vector2, text: String, size: int, col: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := p - Vector2(tw / 2.0, 0)
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_labels(view: Rect2, ppx: Vector2) -> void:
	for s: Settlement in world.settlements.values():
		var c := (Vector2(s.center) + Vector2(0.5, 0.5)) * TILE
		if view.has_point(c):
			_label(c + Vector2(0, -s.radius * TILE - 10), s.name, 12, Color(1, 0.95, 0.85))
	var mouse := get_global_mouse_position()
	for n: NPC in world.npcs.values():
		if not n.alive or n.jailed:
			continue
		var p := npc_px(n)
		if p.distance_to(ppx) < 4.0 * TILE or p.distance_to(mouse) < 14.0 or n.id == selected_npc:
			_label(p + Vector2(0, 17), n.first, 8, Color(1, 1, 1, 0.9))
