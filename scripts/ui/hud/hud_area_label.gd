extends Control
## Area name + level under the minimap (right-aligned): "Depth 3 — The Crypts" / "Monster Level 3"
## (dungeons, "· Cleared" after the boss), "Emberfall" / "Town" (town). Display only.
## Internal: preload("res://scripts/ui/hud/hud_area_label.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const THEME_COLORS := {
	"crypt": Color(0.72, 0.82, 0.66),
	"cave": Color(0.5, 0.78, 0.95),
	"inferno": Color(1.0, 0.58, 0.3),
	"town": Color(0.95, 0.84, 0.55),
}

var area_name: String = ""
var sub_text: String = ""
var accent: Color = UIStyle.COLOR_TITLE
var cleared: bool = false
var _info: Dictionary = {}


func _init() -> void:
	name = "AreaLabel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(420, 48)


func set_area(info: Dictionary) -> void:
	_info = info
	cleared = false
	var id := String(info.get("id", ""))
	area_name = String(info.get("name", ""))
	if area_name == "":
		area_name = id.capitalize()
	var theme_id := String(info.get("theme", "town" if id == "town" else ""))
	accent = THEME_COLORS.get(theme_id, UIStyle.COLOR_TITLE)
	_update_sub()
	queue_redraw()


func set_cleared(on: bool) -> void:
	cleared = on
	_update_sub()
	queue_redraw()


func _update_sub() -> void:
	var id := String(_info.get("id", ""))
	if id == "town":
		sub_text = "Town"
	elif _info.is_empty():
		sub_text = ""
	else:
		sub_text = "Monster Level %d" % int(_info.get("level", 1))
		if cleared:
			sub_text += "  ·  Cleared"


func _draw() -> void:
	if area_name == "":
		return
	var right := size.x
	HudStyle.text_right(self, HudStyle.serif_font(), right, 20.0, area_name, 19, accent, 5)
	if sub_text != "":
		var col := HudStyle.TEXT_DIM if not cleared else UIStyle.COLOR_GOOD
		HudStyle.text_right(self, HudStyle.font(), right, 40.0, sub_text, 14, col, 4)
