class_name FlatCamera
extends Camera3D
## Desktop flat mode: orbit the TV with the mouse (right-drag to orbit,
## middle-drag to pan, wheel to zoom), so the CRT can be inspected up close
## without a headset. Works with the Deck's trackpads.

var target := Vector3(0, 0.81, -1.6)
var distance := 1.4
var yaw := 0.0
var pitch := -0.05

const MIN_DIST := 0.03
const MAX_DIST := 4.0


func _ready() -> void:
	fov = 50.0
	near = 0.005
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.005
			pitch = clampf(pitch - event.relative.y * 0.005, -1.4, 1.4)
			_apply()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			target += (-global_basis.x * event.relative.x + global_basis.y * event.relative.y) * 0.001 * distance
			_apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(MIN_DIST, distance * 0.9)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(MAX_DIST, distance / 0.9)
			_apply()


func _apply() -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	global_position = target + dir * distance
	look_at(target)
