extends CanvasLayer
## Full-screen black fade used by the game flow around area changes, plus the short area title
## card ("DEPTH 3" / "The Crypts · Monster Level 3") shown when a new area is entered.
## Sits above the UI (layer 60), never takes the mouse, runs while the tree is paused (the pause
## menu's "Save & Quit to Menu" fades too). OWNER: flow (wave 2).
##
##   fade.fade_out(0.2, func(): ...)   # overlay to black, then the callback (deferred)
##   fade.fade_in(0.45)                # back to the game
##   fade.show_title("DEPTH 3", "The Crypts · Monster Level 3", accent)

const LAYER := 60
const TITLE_FONT_NAMES: PackedStringArray = [
	"Cinzel", "Trajan Pro", "Cormorant Garamond", "Noto Serif Display", "Noto Serif", "C059",
	"DejaVu Serif", "Liberation Serif", "Nimbus Roman", "Georgia", "serif",
]
const TITLE_SIZE := 58
const SUBTITLE_SIZE := 22
## Title card timing (seconds): fade in, hold, fade out.
const TITLE_IN := 0.55
const TITLE_HOLD := 1.9
const TITLE_OUT := 0.9

var overlay: ColorRect
var title_root: Control
var title_label: Label
var subtitle_label: Label
var rule: TextureRect

var _tween: Tween = null
var _title_tween: Tween = null
var _gradient: Gradient = null


func _init() -> void:
	name = "FlowFade"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	_build_title()


## Tween the overlay to opaque black over `duration` s (from its current alpha), then call
## `on_black` (deferred, outside the tween step). duration <= 0: black at once, callback deferred.
func fade_out(duration: float, on_black: Callable = Callable()) -> void:
	_kill(_tween)
	overlay.visible = true
	var cb := func() -> void:
		if on_black.is_valid():
			on_black.call_deferred()
	if duration <= 0.0 or not is_inside_tree():
		overlay.color.a = 1.0
		cb.call()
		return
	var remaining := duration * (1.0 - overlay.color.a)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(overlay, "color:a", 1.0, maxf(remaining, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(cb)


## Tween the overlay back to transparent over `duration` s (hidden when done).
func fade_in(duration: float) -> void:
	_kill(_tween)
	if duration <= 0.0 or not is_inside_tree():
		overlay.color.a = 0.0
		overlay.visible = false
		return
	overlay.visible = true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(overlay, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void: overlay.visible = false)


## Opaque black right now (no tween).
func set_black() -> void:
	_kill(_tween)
	overlay.visible = true
	overlay.color.a = 1.0


## Transparent right now (no tween).
func clear() -> void:
	_kill(_tween)
	overlay.color.a = 0.0
	overlay.visible = false


func is_fading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Current overlay opacity (0 = game visible, 1 = black).
func get_alpha() -> float:
	return overlay.color.a if overlay.visible else 0.0


## Show the area title card: a large spaced title, a thin gold rule and a subtitle, fading in,
## holding and fading out by itself.
func show_title(title: String, subtitle: String, accent: Color = Color(0.98, 0.8, 0.36)) -> void:
	_kill(_title_tween)
	title_label.text = _spaced(title.to_upper())
	subtitle_label.text = subtitle
	title_label.add_theme_color_override("font_color", accent.lerp(Color(1.0, 0.95, 0.85), 0.35))
	if _gradient != null:
		var c := accent
		_gradient.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0)])
	title_root.visible = true
	title_root.modulate.a = 0.0
	if not is_inside_tree():
		return
	_title_tween = create_tween()
	_title_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_title_tween.tween_property(title_root, "modulate:a", 1.0, TITLE_IN).set_trans(Tween.TRANS_SINE)
	_title_tween.tween_interval(TITLE_HOLD)
	_title_tween.tween_property(title_root, "modulate:a", 0.0, TITLE_OUT).set_trans(Tween.TRANS_SINE)
	_title_tween.tween_callback(func() -> void: title_root.visible = false)


func hide_title() -> void:
	_kill(_title_tween)
	title_root.visible = false


func is_title_visible() -> bool:
	return title_root.visible


# ------------------------------------------------------------------ internals

func _build_title() -> void:
	title_root = Control.new()
	title_root.name = "AreaTitle"
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root.visible = false
	add_child(title_root)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	# A band across the upper third of the screen (above the player, below notifications).
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 0.29
	box.anchor_bottom = 0.29
	box.offset_top = 0.0
	box.offset_bottom = 130.0
	title_root.add_child(box)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_override("font", _title_font())
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title_label.add_theme_constant_override("outline_size", 10)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title_label.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(title_label)

	var rule_row := CenterContainer.new()
	rule_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule_row)
	rule = TextureRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(520, 2)
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gradient = Gradient.new()
	_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_gradient.colors = PackedColorArray([Color(0.98, 0.8, 0.36, 0.0), Color(0.98, 0.8, 0.36, 0.9), Color(0.98, 0.8, 0.36, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = _gradient
	gt.width = 256
	gt.height = 2
	rule.texture = gt
	rule_row.add_child(rule)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	subtitle_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	subtitle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	subtitle_label.add_theme_constant_override("outline_size", 6)
	box.add_child(subtitle_label)


func _title_font() -> Font:
	var sf := SystemFont.new()
	sf.font_names = TITLE_FONT_NAMES
	sf.font_weight = 600
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 4
	return fv


## "DEPTH 3" -> "D E P T H  3"-like airy spacing is done by the font's glyph spacing; words get
## a wider gap.
static func _spaced(s: String) -> String:
	return s.replace(" ", "   ")


static func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()
