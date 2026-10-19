class_name InputRouter
extends Node
## Maps physical input to RetroPad port 0 and VRT menu toggles.
##
## Sources, merged every frame:
##   - Godot joypad 0 (Bluetooth pad on Quest, the Deck's controls on desktop),
##     SDL layout, bottom face = RetroPad B (SNES convention).
##   - Keyboard (desktop).
##   - Quest Touch controllers, when XR is up and the menu is closed.
## Menu: Touch left menu button, Select+Start held on a pad, or Esc.

signal menu_toggled

# RETRO_DEVICE_ID_JOYPAD_*
enum { R_B, R_Y, R_SELECT, R_START, R_UP, R_DOWN, R_LEFT, R_RIGHT, R_A, R_X, R_L, R_R, R_L2, R_R2, R_L3, R_R3 }

const JOY_MAP := {
	JOY_BUTTON_A: R_B, JOY_BUTTON_B: R_A, JOY_BUTTON_X: R_Y, JOY_BUTTON_Y: R_X,
	JOY_BUTTON_BACK: R_SELECT, JOY_BUTTON_START: R_START,
	JOY_BUTTON_LEFT_SHOULDER: R_L, JOY_BUTTON_RIGHT_SHOULDER: R_R,
	JOY_BUTTON_LEFT_STICK: R_L3, JOY_BUTTON_RIGHT_STICK: R_R3,
	JOY_BUTTON_DPAD_UP: R_UP, JOY_BUTTON_DPAD_DOWN: R_DOWN,
	JOY_BUTTON_DPAD_LEFT: R_LEFT, JOY_BUTTON_DPAD_RIGHT: R_RIGHT,
}
const KEY_MAP := {
	KEY_UP: R_UP, KEY_DOWN: R_DOWN, KEY_LEFT: R_LEFT, KEY_RIGHT: R_RIGHT,
	KEY_Z: R_B, KEY_X: R_A, KEY_A: R_Y, KEY_S: R_X, KEY_Q: R_L, KEY_W: R_R,
	KEY_ENTER: R_START, KEY_SHIFT: R_SELECT,
}
const STICK_DEADZONE := 0.5
const MENU_COMBO_HOLD := 0.4  # seconds Select+Start must be held

var host: RetroHost
var left: XRController3D
var right: XRController3D
var menu_open := false
## Left stick also drives the d-pad (8/16-bit games are all d-pad).
var stick_as_dpad := true

var _combo_t := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: menu_toggled.emit()
			KEY_F2: host.quick_save()
			KEY_F4: host.quick_load()


func bind_controllers(l: XRController3D, r: XRController3D) -> void:
	left = l
	right = r
	l.button_pressed.connect(func(b: String): if b == "menu_button": menu_toggled.emit())


func _process(delta: float) -> void:
	if host == null or not host.is_running():
		return
	var mask := 0
	var lx := 0.0
	var ly := 0.0
	var rx := 0.0
	var ry := 0.0

	for jb in JOY_MAP:
		if Input.is_joy_button_pressed(0, jb):
			mask |= 1 << JOY_MAP[jb]
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5:
		mask |= 1 << R_L2
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
		mask |= 1 << R_R2
	lx = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	ly = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	rx = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	ry = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	for k in KEY_MAP:
		if Input.is_physical_key_pressed(k):
			mask |= 1 << KEY_MAP[k]

	if left and right and not menu_open:
		var s := left.get_vector2("primary")
		if s.length() > absf(lx) + absf(ly):
			lx = s.x
			ly = -s.y  # OpenXR up is +y, RetroPad up is -y
		if left.is_button_pressed("ax_button"): mask |= 1 << R_Y
		if left.is_button_pressed("by_button"): mask |= 1 << R_X
		if left.is_button_pressed("trigger_click"): mask |= 1 << R_L
		if left.is_button_pressed("grip_click"): mask |= 1 << R_L2
		if left.is_button_pressed("primary_click"): mask |= 1 << R_SELECT
		if right.is_button_pressed("ax_button"): mask |= 1 << R_B
		if right.is_button_pressed("by_button"): mask |= 1 << R_A
		if right.is_button_pressed("trigger_click"): mask |= 1 << R_R
		if right.is_button_pressed("grip_click"): mask |= 1 << R_R2
		if right.is_button_pressed("primary_click"): mask |= 1 << R_START

	if stick_as_dpad:
		if ly < -STICK_DEADZONE: mask |= 1 << R_UP
		if ly > STICK_DEADZONE: mask |= 1 << R_DOWN
		if lx < -STICK_DEADZONE: mask |= 1 << R_LEFT
		if lx > STICK_DEADZONE: mask |= 1 << R_RIGHT

	# Select+Start held opens the VRT menu instead of reaching the game.
	var combo := (1 << R_SELECT) | (1 << R_START)
	if mask & combo == combo:
		_combo_t += delta
		if _combo_t >= MENU_COMBO_HOLD and _combo_t - delta < MENU_COMBO_HOLD:
			menu_toggled.emit()
	else:
		_combo_t = 0.0

	if menu_open:
		mask = 0
	host.set_joypad(0, mask, _axis(lx), _axis(ly), _axis(rx), _axis(ry))


static func _axis(v: float) -> int:
	return int(clampf(v, -1.0, 1.0) * 32767.0)
