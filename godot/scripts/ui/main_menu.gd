class_name MainMenu
extends PanelContainer
## The VRT menu: library browser plus session actions. Built in code; shown on
## a 3D panel in XR (MenuPanel3D) or as an overlay in the flat desktop mode.

signal launch(entry: ContentLibrary.Entry)
signal action(name: String)

const ACTIONS := [
	["resume", "Resume"], ["stop", "Stop"], ["save_state", "Save state"],
	["load_state", "Load state"], ["input", "Input"], ["signal", "Signal"], ["detail", "Detail"], ["resolution", "Resolution"], ["passthrough", "VR / AR"], ["recenter", "Recenter"],
]

## 30 for the XR panel (1280x800 px at ~0.9 m); smaller on a desktop window.
@export var font_size := 30

var library: ContentLibrary
var _systems: ItemList
var _titles: ItemList
var _status: Label
var _perf: Label
var _shown: Array[ContentLibrary.Entry] = []
var _buttons := {}


func _ready() -> void:
	var th := Theme.new()
	th.default_font_size = font_size
	theme = th

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_status = Label.new()
	_status.text = "VRT"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_status)
	_perf = Label.new()
	_perf.modulate = Color(1, 1, 1, 0.6)
	header.add_child(_perf)

	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(lists)
	_systems = ItemList.new()
	_systems.custom_minimum_size.x = 280
	_systems.item_selected.connect(_on_system_selected)
	lists.add_child(_systems)
	_titles = ItemList.new()
	_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titles.item_activated.connect(func(i): launch.emit(_shown[i]))
	_titles.item_clicked.connect(func(i, _pos, _btn): launch.emit(_shown[i]))
	lists.add_child(_titles)

	var bar := HFlowContainer.new()  # wraps onto a second row as actions grow
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	root.add_child(bar)
	for a in ACTIONS:
		var b := Button.new()
		b.text = a[1]
		b.custom_minimum_size = Vector2(180, 64)
		b.pressed.connect(func(): action.emit(a[0]))
		bar.add_child(b)
		_buttons[a[0]] = b


func set_library(lib: ContentLibrary) -> void:
	library = lib
	_systems.clear()
	for s in lib.systems():
		_systems.add_item("%s (%d)" % [s, lib.by_system(s).size()])
		_systems.set_item_metadata(_systems.item_count - 1, s)
	if _systems.item_count > 0:
		_systems.select(0)
		_on_system_selected(0)
	else:
		_status.text = "No content found. Put ROMs in VRT/roms/<System>/ and DVD images in VRT/video/."


## Right-aligned performance readout (for testers without adb).
func set_perf(text: String) -> void:
	_perf.text = text


func set_status(text: String) -> void:
	_status.text = text


func set_action_visible(name: String, visible_: bool) -> void:
	if name in _buttons:
		_buttons[name].visible = visible_


## Scroll the title list (or system list if the pointer is over it) by
## `amount` items; called with thumbstick input while the menu is open.
func scroll(amount: float) -> void:
	var list := _titles
	if _systems.get_global_rect().has_point(_systems.get_global_mouse_position()):
		list = _systems
	var bar := list.get_v_scroll_bar()
	bar.value += amount * 48.0


func focus_default() -> void:
	(_titles if _titles.item_count > 0 else _systems).grab_focus()


func _on_system_selected(i: int) -> void:
	_shown = library.by_system(_systems.get_item_metadata(i))
	_titles.clear()
	for e in _shown:
		_titles.add_item(e.title)
