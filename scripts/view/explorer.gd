extends Node3D
## Обзор планеты без симуляции: камера над поселением, свободный полёт, скриншоты.
##   godot --path . res://scenes/explorer.tscn -- --site=rodnik --time=10 --dist=60 --pitch=50 --yaw=30 --shot=/tmp/a.png
## Флаги: --seed, --site=<id> или --at=x,y (тайлы), --time (часы), --winter (0..1),
##        --dist, --pitch, --yaw, --shot=<png>.
## Управление: WASD — лететь, колесо — приближение, Q/E — поворот, R/F — наклон.

var planet: Planet
var view: PlanetView
var sky: SkyController
var rig: CameraRig
var cli := {}
var hour := 10.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DataDB.ensure_loaded()
	planet = PlanetGen.generate(int(cli.get("seed", "7")))
	sky = SkyController.new()
	add_child(sky)
	view = PlanetView.new()
	add_child(view)
	view.setup(planet)
	rig = CameraRig.new()
	add_child(rig)
	var tile := Vector2(planet.w * 0.5, planet.h * 0.5)
	if cli.has("site") and planet.sites.has(cli["site"]):
		tile = Vector2(planet.sites[cli["site"]].center) + Vector2(0.5, 0.5)
	elif cli.has("at"):
		var xy: PackedStringArray = str(cli["at"]).split(",")
		tile = Vector2(float(xy[0]), float(xy[1]))
	_set_focus(tile)
	hour = float(cli.get("time", "10"))
	var w := float(cli.get("winter", "0"))
	sky.set_winter(w)
	view.set_winter(w)
	sky.set_time(hour)
	rig.dist = float(cli.get("dist", "60"))
	rig.pitch = float(cli.get("pitch", "50"))
	rig.yaw = float(cli.get("yaw", "30"))
	rig.snap = true
	if cli.has("shot"):
		_shot.call_deferred(str(cli["shot"]))


func _set_focus(tile: Vector2) -> void:
	view.focus_tile = tile
	rig.focus = Vector3(tile.x * Planet.TILE_M, planet.height_at(tile.x, tile.y), tile.y * Planet.TILE_M)
	rig.snap = true


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	var axes := rig.ground_axes()
	if Input.is_key_pressed(KEY_W):
		move += axes[0]
	if Input.is_key_pressed(KEY_S):
		move -= axes[0]
	if Input.is_key_pressed(KEY_D):
		move += axes[1]
	if Input.is_key_pressed(KEY_A):
		move -= axes[1]
	if Input.is_key_pressed(KEY_Q):
		rig.rotate_by(70.0 * delta)
	if Input.is_key_pressed(KEY_E):
		rig.rotate_by(-70.0 * delta)
	if Input.is_key_pressed(KEY_R):
		rig.tilt(-40.0 * delta)
	if Input.is_key_pressed(KEY_F):
		rig.tilt(40.0 * delta)
	if move != Vector3.ZERO:
		var p := rig.focus + move.normalized() * delta * rig.dist * 1.2
		var tile := Vector2(p.x, p.z) / Planet.TILE_M
		rig.focus = Vector3(p.x, planet.height_at(tile.x, tile.y), p.z)
	view.focus_tile = Vector2(rig.focus.x, rig.focus.z) / Planet.TILE_M
	view.flora.mat.set_shader_parameter("focus_world", rig.focus + Vector3(0, 1.0, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				hour = fposmod(hour + 1.0, 24.0)
				sky.set_time(hour)
			KEY_ESCAPE:
				get_tree().quit()


func _shot(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	while not view.settled() and Time.get_ticks_msec() - t0 < 900000:
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("скриншот: %s (%d мс)" % [path, Time.get_ticks_msec() - t0])
	get_tree().quit()
