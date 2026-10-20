class_name TvGuide
extends RefCounted
## The on-TV programme guide, after the 90s Prevue Channel: the live picture
## keeps playing in the top of the screen (the OSD is transparent there) and
## the guide scrolls underneath. Channels are VRT's actions, recent and
## favourite titles, then one channel per system.
##
## Up/down pick a programme, left/right change channel, L/R jump to the
## previous/next first letter, X toggles a favourite, enter tunes in.

signal launch(entry: ContentLibrary.Entry)
signal action(name: String)

const ROWS := 6
# Layout in OSD pixels, inside the overscan-safe area (the bezel hides ~19 px
# at the sides and ~12 px top and bottom, more at the rounded corners).
const VIDEO_BOTTOM := 94            # OSD rows above this show the live picture
const HEADER := Rect2(0, 94, 320, 19)
const LIST_X := 26.0
const LIST_W := 268.0
const ROW_Y := 115.0
const ROW_H := 17.0
const NARROW := Vector2i(1, 2)      # narrow guide face: 6 px advance, 14 px tall
const MAX_CHARS := 43

const BAR := Color(0.04, 0.06, 0.30)
const ROW := Color(0.10, 0.17, 0.55)
const ROW_SEL := Color(0.98, 0.82, 0.16)
const INK := Color(0.96, 0.96, 0.96)
const INK_SEL := Color(0.02, 0.02, 0.05)
const HEAD_INK := Color(1.0, 0.86, 0.25)
const SHADOW := Color(0, 0, 0)

const ACTIONS := [
	["resume", "RESUME PROGRAM"], ["tv_menu", "TV MENU"], ["move_tv", "MOVE TV"], ["save_state", "SAVE STATE"],
	["load_state", "LOAD STATE"], ["stop", "STOP"], ["passthrough", "VR / AR"],
	["recenter", "RECENTER"], ["panel", "FLOATING PANEL"],
]

## Each: {"name": String, "items": Array} where an item is an Entry or an
## action pair [id, label].
var channels: Array = []
var ch := 0
var sel := 0
var top := 0
var favorites: PackedStringArray = []


func set_channels(library: ContentLibrary, recent: PackedStringArray, favs: PackedStringArray,
		action_ids: Array) -> void:
	favorites = favs
	var current := _channel_name()
	channels.clear()
	channels.append({"name": "VRT", "items": ACTIONS.filter(func(a): return a[0] in action_ids)})
	var rec := _entries_for(library, recent)
	if not rec.is_empty():
		channels.append({"name": "RECENT", "items": rec})
	var fav := _entries_for(library, favs)
	fav.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	if not fav.is_empty():
		channels.append({"name": "FAVORITES", "items": fav})
	for s in library.systems():
		var items: Array = library.by_system(s)
		items.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
		channels.append({"name": s, "items": items})
	ch = 0
	for i in channels.size():
		if channels[i].name == current:
			ch = i
	_clamp()


## Start on the first system channel (or wherever a launch happened).
func tune(channel_name: String) -> void:
	for i in channels.size():
		if channels[i].name == channel_name:
			ch = i
			sel = 0
			top = 0


func press(key: int) -> void:
	var items := _items()
	match key:
		TvOsd.Key.UP:
			sel = (sel - 1 + maxi(items.size(), 1)) % maxi(items.size(), 1)
		TvOsd.Key.DOWN:
			sel = (sel + 1) % maxi(items.size(), 1)
		TvOsd.Key.LEFT, TvOsd.Key.RIGHT:
			ch = (ch + (-1 if key == TvOsd.Key.LEFT else 1) + channels.size()) % channels.size()
			sel = 0
			top = 0
		TvOsd.Key.PAGE_UP, TvOsd.Key.PAGE_DOWN:
			_jump_letter(-1 if key == TvOsd.Key.PAGE_UP else 1)
		TvOsd.Key.FAVORITE:
			if sel < items.size() and items[sel] is ContentLibrary.Entry:
				action.emit("favorite:" + items[sel].path)
		TvOsd.Key.ENTER:
			_activate()
	_clamp()


## Pointer at OSD pixel px: hover selects a row; click activates it. Returns
## true when the point is on the list.
func point(px: Vector2, click: bool) -> bool:
	if px.y < ROW_Y or px.y >= ROW_Y + ROWS * ROW_H or px.x < LIST_X or px.x > LIST_X + LIST_W:
		if click and HEADER.has_point(px):
			press(TvOsd.Key.LEFT if px.x < 160.0 else TvOsd.Key.RIGHT)
			return true
		return false
	var row := top + int((px.y - ROW_Y) / ROW_H)
	if row < _items().size():
		sel = row
		if click:
			_activate()
	return true


func scroll(rows: int) -> void:
	sel = clampi(sel + rows, 0, maxi(_items().size() - 1, 0))
	_clamp()


func draw(ci: CanvasItem) -> void:
	var items := _items()
	# Header bar: channel on the left, position on the right.
	ci.draw_rect(Rect2(0, VIDEO_BOTTOM, 320, 240 - VIDEO_BOTTOM), BAR)
	var head := "< %02d %s >" % [ch + 2, _channel_name()]
	_text(ci, Vector2(LIST_X + 2, HEADER.position.y + 3), head.substr(0, 22), HEAD_INK, Vector2i(2, 2))
	var pos := "%d/%d" % [mini(sel + 1, items.size()), items.size()]
	_text(ci, Vector2(LIST_X + LIST_W - OsdFont.width(pos, 1) - 2, HEADER.position.y + 3), pos, INK, NARROW)
	if items.is_empty():
		_row(ci, 0, "NO PROGRAMS", false, false)
		return
	for r in ROWS:
		var i := top + r
		if i >= items.size():
			break
		var it = items[i]
		var label: String
		var fav := false
		if it is ContentLibrary.Entry:
			label = display_title(it.title)
			fav = it.path in favorites
		else:
			label = it[1]
		_row(ci, r, label, i == sel, fav)


func _row(ci: CanvasItem, r: int, label: String, selected: bool, fav: bool) -> void:
	var y := ROW_Y + r * ROW_H
	ci.draw_rect(Rect2(LIST_X, y, LIST_W, ROW_H - 2), ROW_SEL if selected else ROW)
	var max_chars := MAX_CHARS - (2 if fav else 0)
	if label.length() > max_chars:
		label = label.substr(0, max_chars - 1) + "."
	var ink := INK_SEL if selected else INK
	var p := Vector2(LIST_X + 4, y + 1)
	if selected:
		OsdFont.draw_text(ci, p, label, ink, NARROW)
	else:
		_text(ci, p, label, ink, NARROW)
	if fav:
		OsdFont.draw_text(ci, Vector2(LIST_X + LIST_W - 9, y + 1), OsdFont.STAR, ROW_SEL if not selected else INK_SEL, NARROW)


func _text(ci: CanvasItem, p: Vector2, s: String, ink: Color, scale: Vector2i) -> void:
	OsdFont.draw_text(ci, p + Vector2(1, 1), s, SHADOW, scale)
	OsdFont.draw_text(ci, p, s, ink, scale)


func _activate() -> void:
	var items := _items()
	if sel >= items.size():
		return
	var it = items[sel]
	if it is ContentLibrary.Entry:
		launch.emit(it)
	else:
		action.emit(it[0])


func _jump_letter(dir: int) -> void:
	var items := _items()
	if items.is_empty() or not items[0] is ContentLibrary.Entry:
		return
	var cur := _initial(items[sel])
	var i := sel
	while true:
		i += dir
		if i < 0 or i >= items.size():
			i = clampi(i, 0, items.size() - 1)
			break
		if _initial(items[i]) != cur:
			if dir < 0:  # land on the first title of that letter
				var l := _initial(items[i])
				while i > 0 and _initial(items[i - 1]) == l:
					i -= 1
			break
	sel = i


## A title as the guide lists it: underscores as spaces, ROM-set tags such as
## "(U) [!]" dropped.
static func display_title(title: String) -> String:
	var t := title.replace("_", " ")
	for mark in [" (", " ["]:
		var i := t.find(mark)
		if i > 0:
			t = t.left(i)
	return t.strip_edges()


static func _initial(e: ContentLibrary.Entry) -> String:
	var c := e.title.left(1).to_upper()
	return c if c >= "A" and c <= "Z" else "#"


func _items() -> Array:
	return channels[ch].items if ch < channels.size() else []


func _channel_name() -> String:
	return channels[ch].name if ch < channels.size() else ""


func _clamp() -> void:
	var n := _items().size()
	sel = clampi(sel, 0, maxi(n - 1, 0))
	if sel < top:
		top = sel
	elif sel >= top + ROWS:
		top = sel - ROWS + 1


static func _entries_for(library: ContentLibrary, paths: PackedStringArray) -> Array:
	var out := []
	for p in paths:
		for e in library.entries:
			if e.path == p:
				out.append(e)
				break
	return out
