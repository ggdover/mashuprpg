extends Control
## HUD hover tooltip. Shows tooltip lines (Item.get_tooltip_lines() format) ABOVE the hovered HUD
## element (below it for elements at the top of the screen), using an embedded TooltipBox (the
## ui-items renderer, loaded at runtime) so it looks like every other tooltip. Falls back to the
## shared UI.show_tooltip() when that renderer is not available. Never takes the mouse.
## Internal: preload("res://scripts/ui/hud/hud_tooltip.gd").

const TOOLTIP_BOX_PATH := "res://scripts/ui/tooltip/tooltip_box.gd"
const GAP := 10.0
const MARGIN := 8.0
const MAX_WIDTH := 430.0
const FADE_TIME := 0.08

var _box: Control = null
var _source: WeakRef = null
var _using_fallback := false
var _fade: Tween = null
var _lines: Array = []


func _init() -> void:
	name = "HudTooltip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if ResourceLoader.exists(TOOLTIP_BOX_PATH):
		var scr := load(TOOLTIP_BOX_PATH) as GDScript
		if scr != null and scr.can_instantiate():
			var b: Variant = scr.new()
			if b is Control and (b as Control).has_method("set_lines"):
				_box = b
				_box.name = "Box"
				_box.visible = false
				_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(_box)
			elif b is Node:
				(b as Node).free()
	set_process(false)


## Show `lines` for the hovered control `source`. below = place under it (top-of-screen widgets).
func show_for(source: Control, lines: Array, below: bool = false) -> void:
	if source == null or lines.is_empty():
		hide_tooltip()
		return
	_source = weakref(source)
	_lines = lines
	var anchor := source.get_global_rect()
	if _box == null:
		_using_fallback = true
		UI.show_tooltip(lines, anchor)
		set_process(true)
		return
	var was_visible := _box.visible
	_box.set("max_width", MAX_WIDTH)
	var sz: Vector2 = _box.call("set_lines", lines, "", false)
	var screen := get_viewport_rect().size
	var pos := Vector2.ZERO
	if below:
		pos = Vector2(anchor.position.x, anchor.end.y + GAP)
	else:
		pos = Vector2(anchor.get_center().x - sz.x * 0.5, anchor.position.y - GAP - sz.y)
		if pos.y < MARGIN:
			pos.y = anchor.end.y + GAP
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, screen.x - MARGIN - sz.x))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, screen.y - MARGIN - sz.y))
	_box.global_position = pos.round()
	_box.visible = true
	move_to_front()
	if not was_visible:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_box.modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(_box, "modulate:a", 1.0, FADE_TIME)
	set_process(true)


## Hide if `source` is the control that showed the tooltip (null = hide unconditionally).
func hide_for(source: Control) -> void:
	if source != null and _source != null and _source.get_ref() != source:
		return
	hide_tooltip()


func hide_tooltip() -> void:
	_source = null
	_lines = []
	if _box != null:
		_box.visible = false
	if _using_fallback:
		_using_fallback = false
		UI.hide_tooltip()
	set_process(false)


func is_showing() -> bool:
	return (_box != null and _box.visible) or _using_fallback


## The control the tooltip currently belongs to (null when hidden).
func get_source() -> Control:
	return _source.get_ref() as Control if _source != null else null


## Lines currently shown (tests).
func get_lines() -> Array:
	return _lines


func _process(_delta: float) -> void:
	# The owner vanished, was hidden or the mouse left it without a mouse_exited (drags, rebinds).
	var src := get_source()
	if src == null or not is_instance_valid(src) or not src.is_visible_in_tree():
		hide_tooltip()
