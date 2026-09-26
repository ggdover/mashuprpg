extends Button
## One saved character in the main menu list: class emblem, name, level + class, deepest depth
## and when it was last played. Toggle button (in a ButtonGroup): pressed = selected.
## Double-click emits `activated(save_id)`. MOUSE_FILTER_PASS so the wheel still scrolls the list.
## Internal: preload("res://scripts/ui/menus/menu_save_row.gd").

signal activated(save_id: String)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuEmblem := preload("res://scripts/ui/menus/menu_emblem.gd")

## An entry of GameState.list_saves().
var info: Dictionary = {}
var save_id: String = ""


func _init(p_info: Dictionary = {}) -> void:
	info = p_info
	save_id = String(info.get("save_id", ""))
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0, 88)
	add_theme_stylebox_override("normal", MenuStyle.row_style("normal"))
	add_theme_stylebox_override("hover", MenuStyle.row_style("hover"))
	add_theme_stylebox_override("pressed", MenuStyle.row_style("selected"))
	add_theme_stylebox_override("hover_pressed", MenuStyle.row_style("selected"))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_build()


func _build() -> void:
	var cid := String(info.get("class_id", "warrior"))
	var col := ClassDefs.get_color(cid)
	var h := MenuStyle.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -18
	h.offset_top = 8
	h.offset_bottom = -8
	add_child(h)
	var em := MenuEmblem.new(cid, 68.0)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var left := MenuStyle.vbox(2)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := MenuStyle.title_label(String(info.get("char_name", "Hero")), 26, UIStyle.COLOR_TEXT)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(name_l)
	left.add_child(MenuStyle.label("Level %d %s" % [int(info.get("level", 1)), ClassDefs.get_display_name(cid)], UIStyle.FONT_NORMAL, col.lightened(0.25)))
	h.add_child(left)
	var right := MenuStyle.vbox(4)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	var depth := int(info.get("max_depth", 1))
	var theme_id := World.theme_for_depth(depth)
	var d_l := MenuStyle.label("Depth %d · %s" % [depth, World.theme_display_name(theme_id)], UIStyle.FONT_SMALL + 1, MenuStyle.theme_color(theme_id))
	d_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(d_l)
	var ago := MenuStyle.time_ago(int(info.get("modified", 0)))
	var t_l := MenuStyle.label(("Last played " + ago) if ago != "" else "", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	t_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(t_l)
	h.add_child(right)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
		button_pressed = true
		activated.emit(save_id)
