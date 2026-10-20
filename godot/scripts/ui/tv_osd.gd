class_name TvOsd
extends Node
## The TV's own on-screen display: a 320x240 overlay (one OSD pixel per
## 240p raster pixel) that the raster pass mixes into the picture signal, so it
## goes through the same beam, mask and glass as the picture, like the
## character generator of a real set.
##
## Menu pages are lists of items built by the app:
##   {"label": String, "value": Callable -> String,        (choice)
##    "change": Callable(dir: int)}                          left/right
##   {"label": String, "level": Callable -> int,            (0..100 bar)
##    "change": Callable(dir: int)}
##   {"label": String, "enter": Callable}                    (action / sub-page)
##
## The programme guide (TvGuide) is the OSD's other full screen.

signal closed

enum Style { GREEN, WHITE }
enum Key { UP, DOWN, LEFT, RIGHT, ENTER, BACK, CLOSE, PAGE_UP, PAGE_DOWN, FAVORITE }

const SIZE := Vector2i(320, 240)
const ORIGIN := Vector2(22, 20)   # inside the overscan-safe area
const ROW_STEP := 18.0            # fits ten rows above the bottom overscan
const VISIBLE_ROWS := 10
const BANNER_POS := Vector2(26, 22)
const IDLE_CLOSE_S := 30.0
const GREEN := Color(0.30, 1.0, 0.30)
const WHITE := Color(0.95, 0.95, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0)
const BACKING := Color(0.0, 0.0, 0.0, 0.85)

var style := Style.GREEN
var pages := {}
var is_open := false          # menu or guide on screen, taking the buttons
var guide := TvGuide.new()
var guide_open := false

var _viewport := SubViewport.new()
var _canvas := Canvas.new()
var _page := ""
var _title := ""
var _sel := 0
var _first := 0                   # first visible row on a long page
var _stack: Array = []
var _banner := ""
var _banner_t := 0.0
var _idle_t := 0.0


class Canvas extends Control:
	var osd: TvOsd

	func _draw() -> void:
		osd._draw_to(self)


func _init() -> void:
	_viewport.size = SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_canvas.osd = self
	_canvas.size = Vector2(SIZE)
	_viewport.add_child(_canvas)
	add_child(_viewport)


func texture() -> Texture2D:
	return _viewport.get_texture()


## Anything on screen right now (menu or banner).
func visible_now() -> bool:
	return is_open or _banner_t > 0.0


func open(page: String, title: String) -> void:
	is_open = true
	guide_open = false
	_stack.clear()
	_show_page(page, title)


func open_guide() -> void:
	is_open = true
	guide_open = true
	_idle_t = 0.0
	_redraw()


func close() -> void:
	if is_open:
		is_open = false
		guide_open = false
		_redraw()
		closed.emit()


## Pointer on the screen at OSD pixel px (guide only). True if it hit a row.
func point(px: Vector2, click: bool) -> bool:
	if not guide_open:
		return false
	var prev := [guide.ch, guide.sel, guide.top]
	var hit := guide.point(px, click)
	if click or prev != [guide.ch, guide.sel, guide.top]:
		_redraw()
	return hit


func scroll(rows: int) -> void:
	if guide_open:
		guide.scroll(rows)
		_redraw()


## Push a sub-page; BACK returns to the previous one.
func enter_page(page: String, title: String) -> void:
	_stack.append([_page, _title, _sel])
	_show_page(page, title)


func banner(text: String, seconds := 3.0) -> void:
	_banner = text
	_banner_t = seconds
	_redraw()


func set_style(s: int) -> void:
	style = s
	_redraw()


## Refresh after values changed elsewhere.
func refresh() -> void:
	_redraw()


func press(b: int) -> void:
	if not is_open:
		return
	_idle_t = 0.0
	if guide_open:
		if b == Key.BACK or b == Key.CLOSE:
			close()
		else:
			guide.press(b)
			_redraw()
		return
	var items: Array = pages.get(_page, [])
	if items.is_empty():
		return
	var it: Dictionary = items[_sel]
	match b:
		Key.UP:
			_sel = (_sel - 1 + items.size()) % items.size()
		Key.DOWN:
			_sel = (_sel + 1) % items.size()
		Key.LEFT, Key.RIGHT:
			if it.has("change"):
				it.change.call(-1 if b == Key.LEFT else 1)
		Key.ENTER:
			if it.has("enter"):
				it.enter.call()
			elif it.has("change"):
				it.change.call(1)
		Key.BACK:
			if _stack.is_empty():
				close()
				return
			var prev: Array = _stack.pop_back()
			_page = prev[0]
			_title = prev[1]
			_sel = prev[2]
		Key.CLOSE:
			close()
			return
	_redraw()


func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_redraw()
	if is_open and not guide_open:
		_idle_t += delta
		if _idle_t > IDLE_CLOSE_S:
			close()


func _show_page(page: String, title: String) -> void:
	_page = page
	_title = title
	_sel = 0
	_idle_t = 0.0
	_redraw()


func _redraw() -> void:
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _text(ci: CanvasItem, pos: Vector2, text: String) -> void:
	var ink := GREEN if style == Style.GREEN else WHITE
	if style == Style.WHITE:
		ci.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(OsdFont.width(text) + 6, OsdFont.H * OsdFont.SCALE + 6)), BACKING)
	OsdFont.draw_text(ci, pos + Vector2(OsdFont.SCALE, OsdFont.SCALE), text, SHADOW)
	OsdFont.draw_text(ci, pos, text, ink)


func _draw_to(ci: CanvasItem) -> void:
	if guide_open:
		guide.draw(ci)
	elif is_open:
		var y := ORIGIN.y
		_text(ci, Vector2(ORIGIN.x + OsdFont.ADVANCE, y), _title)
		y += OsdFont.LINE + 2
		var items: Array = pages.get(_page, [])
		_first = clampi(_first, maxi(_sel - VISIBLE_ROWS + 1, 0), _sel)
		for i in range(_first, mini(_first + VISIBLE_ROWS, items.size())):
			_text(ci, Vector2(ORIGIN.x, y), _line(items[i], i == _sel))
			y += ROW_STEP
	elif _banner_t > 0.0:
		_text(ci, BANNER_POS, _banner)


## One menu row: cursor, label padded to 7, then the value or a bar.
func _line(it: Dictionary, selected: bool) -> String:
	var s := (">" if selected else " ") + str(it.label).rpad(8)
	if it.has("level"):
		var lv: int = it.level.call()
		var cells := int(round(lv / 100.0 * 8.0))
		s += OsdFont.BAR_FULL.repeat(cells) + OsdFont.BAR_EMPTY.repeat(8 - cells) + str(lv).lpad(4)
	elif it.has("value"):
		s += str(it.value.call())
	return s
