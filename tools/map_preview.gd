extends SceneTree
## Отладка генератора: рисует крупную карту планеты в PNG.
##   godot --headless --path . --script res://tools/map_preview.gd -- --seed=7 --out=/tmp/map.png

const COLORS := [Color(0.13, 0.27, 0.42), Color(0.86, 0.8, 0.58), Color(0.45, 0.62, 0.3), Color(0.22, 0.42, 0.2),
	Color(0.25, 0.38, 0.3), Color(0.72, 0.74, 0.7), Color(0.68, 0.64, 0.38), Color(0.9, 0.76, 0.45), Color(0.7, 0.45, 0.3),
	Color(0.66, 0.6, 0.3), Color(0.12, 0.45, 0.18), Color(0.3, 0.38, 0.25), Color(0.45, 0.42, 0.4), Color(0.95, 0.96, 0.98),
	Color(0.3, 0.27, 0.25)]


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t0 := Time.get_ticks_msec()
	PlanetGen.verbose = true
	var p := PlanetGen.generate(int(args.get("seed", "7")))
	print("планета за %d мс: рек %d, дорог %d, поселений %d" % [Time.get_ticks_msec() - t0, p.rivers.size(), p.roads.size(), p.sites.size()])
	var total := 0
	var by_kind := {}
	for id in p.site_order:
		var st: Site = p.sites[id]
		total += st.population()
		by_kind[st.kind] = int(by_kind.get(st.kind, 0)) + 1
	print("население: %d, по видам: %s" % [total, by_kind])
	var own := {}
	for i in p.mw * p.mh:
		if p.m_owner[i] != 255:
			var f: String = p.factions_order[p.m_owner[i]]
			own[f] = int(own.get(f, 0)) + 1
	print("территории (клеток): ", own, ", перешейков: ", p.bridges.size())
	for id in ["arkon", "svoboda", "meridian", "chernaya", "glotka", "pepel_imp", "pepel_front", "rodnik"]:
		if p.sites.has(id):
			var st: Site = p.sites[id]
			print("  %s: %s, клетка %s, хозяин территории %s, высота %.1f" % [id, st.name, st.center / Planet.MACRO, p.owner_at(st.center.x, st.center.y), st.base_h])
	var sc := 2
	var img := Image.create(p.mw * sc, p.mh * sc, false, Image.FORMAT_RGB8)
	for my in p.mh:
		for mx in p.mw:
			var i := my * p.mw + mx
			var c: Color = COLORS[p.m_biome[i]]
			var hh := p.m_height[i]
			if hh >= 0.0:
				c = c.darkened(clampf(-(hh - 40.0) / 300.0, -0.25, 0.0)).lightened(clampf((hh - 60.0) / 500.0, 0.0, 0.35))
				if p.m_owner[i] != 255:
					var fc: Color = [Color.RED, Color.BLUE, Color.PURPLE, Color.GOLD, Color.ORANGE, Color.GREEN][p.m_owner[i]]
					c = c.lerp(fc, 0.22 if (mx + my) % 4 != 0 else 0.6)
			else:
				c = c.darkened(clampf(-hh / 120.0, 0.0, 0.6))
			img.fill_rect(Rect2i(mx * sc, my * sc, sc, sc), c)
	var f := float(sc) / Planet.MACRO
	for r: Dictionary in p.rivers:
		var pts: PackedVector2Array = r["pts"]
		for k in pts.size() - 1:
			_line(img, pts[k] * f, pts[k + 1] * f, Color(0.25, 0.5, 0.9))
	for r: Dictionary in p.roads:
		var pts: PackedVector2Array = r["pts"]
		var col: Color = [Color(0.55, 0.45, 0.3), Color(0.75, 0.6, 0.4), Color(0.95, 0.85, 0.6)][int(r["kind"])]
		for k in pts.size() - 1:
			_line(img, pts[k] * f, pts[k + 1] * f, col)
	for id in p.site_order:
		var st: Site = p.sites[id]
		var c := Vector2(st.center) * f
		var rad := maxf(1.0, st.radius * f)
		var col := Color.WHITE if st.landmark else Color(0.1, 0.1, 0.1)
		if st.kind == "ruins":
			col = Color(0.5, 0.5, 0.5)
		elif st.kind == "trench":
			col = Color(1, 0.2, 0.1)
		for a in 24:
			var v := c + Vector2.from_angle(a * TAU / 24.0) * rad
			var px := Vector2i(v)
			if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
				img.set_pixelv(px, col)
	img.save_png(str(args.get("out", "/tmp/map.png")))
	quit()


func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(a.distance_to(b)) + 1
	for k in n + 1:
		var q := Vector2i(a.lerp(b, float(k) / n))
		if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
			img.set_pixelv(q, c)
