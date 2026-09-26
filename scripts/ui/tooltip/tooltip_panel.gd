class_name TooltipPanel
extends Control
## The shared tooltip box used via UI.show_tooltip(). Renders Item.get_tooltip_lines()-style
## lines, stays inside the screen, optional second comparison box.
## OWNER: UI items module (wave 2). CONTRACT STUB — keep every public member/signature.
##
## Layout: the main box sits beside the anchor rect (right of it when there is room, else left),
## top-aligned with it; the comparison box ("Currently Equipped") sits on the far side of the main
## box, or on the other side of the anchor when it doesn't fit. Both are clamped inside the
## viewport. Holding Alt shows the affix hints ("hint" keys). Never takes the mouse.

const GAP := 10.0
const COMPARE_GAP := 6.0
const MARGIN := 8.0
const FADE_TIME := 0.07
const COMPARE_CAPTION := "Currently Equipped"

var _main: TooltipBox
var _compare: TooltipBox
var _lines: Array = []
var _compare_lines: Array = []
var _anchor := Rect2()
var _alt := false
var _fade: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = TooltipBox.new()
	_main.name = "Main"
	add_child(_main)
	_compare = TooltipBox.new()
	_compare.name = "Compare"
	_compare.visible = false
	add_child(_compare)
	visible = false


func show_lines(lines: Array, anchor: Rect2, compare_lines: Array = []) -> void:
	var was_visible := visible and not _lines.is_empty()
	_lines = lines
	_compare_lines = compare_lines
	_anchor = anchor
	_alt = Input.is_key_pressed(KEY_ALT)
	_relayout()
	visible = not lines.is_empty()
	if visible and not was_visible and is_inside_tree():
		if _fade != null and _fade.is_valid():
			_fade.kill()
		modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	elif visible:
		modulate.a = 1.0


func hide_tooltip() -> void:
	visible = false
	_lines = []
	_compare_lines = []


## Screen rect of the main box.
func get_main_rect() -> Rect2:
	return Rect2(_main.global_position if _main.is_inside_tree() else _main.position, _main.size)


## Screen rect of the comparison box (empty size when hidden).
func get_compare_rect() -> Rect2:
	if not _compare.visible:
		return Rect2()
	return Rect2(_compare.global_position if _compare.is_inside_tree() else _compare.position, _compare.size)


## The main box (tests / callers that need its rect).
func get_main_box() -> TooltipBox:
	return _main


## The comparison box (hidden when there is no comparison).
func get_compare_box() -> TooltipBox:
	return _compare


func has_comparison() -> bool:
	return _compare.visible


func _process(_delta: float) -> void:
	if not visible or _lines.is_empty():
		return
	var alt := Input.is_key_pressed(KEY_ALT)
	if alt != _alt:
		_alt = alt
		_relayout()


func _screen_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(1920, 1080)


func _relayout() -> void:
	var screen := _screen_size()
	# Keep each box comfortably inside the screen.
	var max_w := clampf(screen.x * 0.3, 320.0, 500.0)
	_main.max_width = max_w
	_compare.max_width = max_w
	var ms: Vector2 = _main.set_lines(_lines, "", _alt)
	var has_cmp := not _compare_lines.is_empty()
	_compare.visible = has_cmp
	var cs := Vector2.ZERO
	if has_cmp:
		cs = _compare.set_lines(_compare_lines, COMPARE_CAPTION, _alt)
	var right_room := screen.x - MARGIN - (_anchor.end.x + GAP)
	var left_room := (_anchor.position.x - GAP) - MARGIN
	var main_pos := Vector2.ZERO
	var cmp_pos := Vector2.ZERO
	var both_w: float = ms.x + (COMPARE_GAP + cs.x if has_cmp else 0.0)
	if right_room >= both_w or (right_room >= ms.x and right_room >= left_room):
		main_pos.x = _anchor.end.x + GAP
		if has_cmp:
			if right_room >= both_w:
				cmp_pos.x = main_pos.x + ms.x + COMPARE_GAP
			else:
				cmp_pos.x = _anchor.position.x - GAP - cs.x
	elif left_room >= ms.x:
		main_pos.x = _anchor.position.x - GAP - ms.x
		if has_cmp:
			if left_room >= both_w:
				cmp_pos.x = main_pos.x - COMPARE_GAP - cs.x
			else:
				cmp_pos.x = _anchor.end.x + GAP
	else:
		# Neither side fits: centre below/above the anchor.
		main_pos.x = _anchor.get_center().x - ms.x * 0.5
		cmp_pos.x = main_pos.x - COMPARE_GAP - cs.x
	# Both boxes share one top edge: the anchor's top, moved up just enough for the taller box.
	var tallest := maxf(ms.y, cs.y) if has_cmp else ms.y
	var top := clampf(_anchor.position.y, MARGIN, maxf(MARGIN, screen.y - MARGIN - tallest))
	main_pos.y = top
	cmp_pos.y = top
	var origin := get_global_position() if is_inside_tree() else position
	main_pos = _clamp_box(main_pos, ms, screen)
	_main.position = (main_pos - origin).round()
	if has_cmp:
		cmp_pos = _clamp_box(cmp_pos, cs, screen)
		_compare.position = (cmp_pos - origin).round()


func _clamp_box(pos: Vector2, box: Vector2, screen: Vector2) -> Vector2:
	var p := pos
	p.x = clampf(p.x, MARGIN, maxf(MARGIN, screen.x - MARGIN - box.x))
	p.y = clampf(p.y, MARGIN, maxf(MARGIN, screen.y - MARGIN - box.y))
	return p
