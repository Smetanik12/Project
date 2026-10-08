class_name CameraRig
extends Node3D
## Камера под углом вокруг точки (игрока): поворот, наклон, приближение — всё плавно.
## Колесо — приближение, Q/E или средняя кнопка — поворот, R/F — наклон.

const MIN_DIST := 6.0
const MAX_DIST := 140.0

var cam: Camera3D
## Куда смотрим (мировые метры).
var focus := Vector3.ZERO
var yaw := 30.0
var pitch := 52.0
var dist := 45.0
var _yaw := yaw
var _pitch := pitch
var _dist := dist
var _focus := focus
var _drag := false
var snap := true


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.3
	cam.far = 1600.0
	add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	var k := 1.0 if snap else 1.0 - exp(-delta * 9.0)
	snap = false
	_yaw = lerp_angle_deg(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, dist, k)
	_focus = _focus.lerp(focus, k)
	var rot := Basis.from_euler(Vector3(deg_to_rad(-_pitch), deg_to_rad(_yaw), 0.0))
	var back := rot * Vector3(0, 0, 1)
	cam.global_position = _focus + back * _dist
	cam.look_at(_focus, Vector3.UP)


static func lerp_angle_deg(a: float, b: float, t: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), t))


func zoom(f: float) -> void:
	dist = clampf(dist * f, MIN_DIST, MAX_DIST)


func rotate_by(deg: float) -> void:
	yaw += deg


func tilt(deg: float) -> void:
	pitch = clampf(pitch + deg, 28.0, 82.0)


## Направление «вперёд» и «вправо» на земле с учётом поворота камеры.
func ground_axes() -> Array:
	var f := Vector3(-sin(deg_to_rad(_yaw)), 0, -cos(deg_to_rad(_yaw)))
	var r := Vector3(cos(deg_to_rad(_yaw)), 0, -sin(deg_to_rad(_yaw)))
	return [f, r]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom(0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom(1.14)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		yaw -= event.relative.x * 0.3
		tilt(event.relative.y * 0.2)
