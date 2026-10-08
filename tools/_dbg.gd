extends SceneTree
func _initialize() -> void:
	DataDB.ensure_loaded()
	var p := PlanetGen.generate(7)
	var st: Site = p.sites["arkon"]
	var r := 110
	var area := Rect2i(st.center - Vector2i(r, r), Vector2i(r * 2, r * 2))
	var shown := 0
	for s: Dictionary in LayoutGen.structures_in(p, st, area):
		if s["t"] in ["path", "trench", "parapet", "wire", "park", "plaza", "market", "landing_pad", "gate", "pier", "field"]:
			continue
		var sr: Rect2i = s["r"]
		var wet := 0
		var road := 0
		for y in range(sr.position.y, sr.end.y):
			for x in range(sr.position.x, sr.end.x):
				var ch := p.chunk_of_tile(x, y)
				var i := ch.li(x, y)
				if ch.ground[i] <= 1:
					wet += 1
				if ch.flags[i] & Chunk.F_ROAD:
					road += 1
		if (wet > 0 or road > 0) and shown < 8:
			shown += 1
			var q := sr.get_center()
			var ch2 := p.chunk_of_tile(q.x, q.y)
			print(s["t"], " ", sr, " wet ", wet, " road ", road, " hb ", p.height_base(q.x, q.y), " tileh ", ch2.tile_height(q.x, q.y), " water ", ch2.water[ch2.li(q.x, q.y)], " river ", p.river_at(q.x, q.y), " street ", LayoutGen.city_street_at(st, q.x, q.y), " road ", p.road_at(q.x, q.y))
	# pier door
	var v: Site = null
	for id in p.site_order:
		if p.sites[id].name == "Деревня Грибново":
			v = p.sites[id]
	if v != null:
		var door := Vector2i(11786, 12895)
		for dy in range(-2, 3):
			var line := ""
			for dx in range(-3, 4):
				var t := door + Vector2i(dx, dy)
				var ch := p.chunk_of_tile(t.x, t.y)
				var i := ch.li(t.x, t.y)
				line += "[g%d c%d f%d w%d] " % [ch.ground[i], ch.cost[i], ch.flags[i], ch.walls[i]]
			print(line)
		print("center ", v.center, " door dist ", Vector2(door).distance_to(Vector2(v.center)), " radius ", v.radius)
	quit()
