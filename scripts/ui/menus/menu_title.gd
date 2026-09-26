extends Control
## Big glowing title text (title font, soft coloured glow, dark outline), centred in its rect.
## Layout-only (MOUSE_FILTER_IGNORE). Internal: preload("res://scripts/ui/menus/menu_title.gd").

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

var text: String = "":
	set(v):
		text = v
		_update_min_size()
		queue_redraw()
var font_size: int = 64:
	set(v):
		font_size = v
		_update_min_size()
		queue_redraw()
var color: Color = MenuStyle.GOLD:
	set(v):
		color = v
		queue_redraw()
var glow: Color = Color(MenuStyle.EMBER, 0.9):
	set(v):
		glow = v
		queue_redraw()
## 0..1 extra glow pulse amplitude (animated when > 0).
var pulse: float = 0.0
var _t := 0.0


func _init(p_text: String = "", p_size: int = 64, p_color: Color = MenuStyle.GOLD, p_glow: Color = Color(MenuStyle.EMBER, 0.9)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = p_text
	font_size = p_size
	color = p_color
	glow = p_glow


func _ready() -> void:
	_update_min_size()
	set_process(pulse > 0.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _update_min_size() -> void:
	var f := MenuStyle.title_font()
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	custom_minimum_size = Vector2(sz.x + 24.0, f.get_height(font_size) + 12.0)


func _draw() -> void:
	if text == "":
		return
	var f := MenuStyle.title_font()
	var ascent := f.get_ascent(font_size)
	var h := f.get_height(font_size)
	var y := (size.y - h) * 0.5 + ascent
	var g := glow
	if pulse > 0.0:
		g.a *= 1.0 - pulse * 0.5 + pulse * 0.5 * sin(_t * 2.2)
	MenuStyle.draw_glow_text(self, f, Vector2(0, y), text, font_size, color, g, HORIZONTAL_ALIGNMENT_CENTER, size.x)
