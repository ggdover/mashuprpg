extends Button
## Class selection card of the New Character screen: emblem, name, main attribute, description,
## attribute bars, starting equipment and starting skills. A toggle button (use a ButtonGroup):
## pressed = selected (gold frame, glow in the class colour). Emits `chosen(class_id)`.
## Internal: preload("res://scripts/ui/menus/menu_class_card.gd").

signal chosen(class_id: String)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuEmblem := preload("res://scripts/ui/menus/menu_emblem.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")

const ATTR_SHORT := {"strength": "STR", "dexterity": "DEX", "intelligence": "INT"}
const ATTR_COLORS := {"strength": Color(0.86, 0.32, 0.27), "dexterity": Color(0.4, 0.8, 0.38), "intelligence": Color(0.42, 0.55, 0.98)}
const ROLE_TEXT := {
	"warrior": "Life · Armour · Melee",
	"ranger": "Evasion · Speed · Projectiles",
	"sorcerer": "Mana · Energy Shield · Spells",
}

var class_id: String = ""
var _emblem: Control
var _t := 0.0


func _init(p_class: String = "warrior") -> void:
	class_id = p_class
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 590)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := ClassDefs.get_color(class_id)
	add_theme_stylebox_override("normal", _style(Color(0.075, 0.066, 0.058, 0.96), col.darkened(0.45), 2, 0.0))
	add_theme_stylebox_override("hover", _style(Color(0.11, 0.095, 0.08, 0.98), col.lightened(0.1), 2, 0.2))
	add_theme_stylebox_override("pressed", _style(Color(0.12, 0.1, 0.075, 0.99), MenuStyle.GOLD, 3, 0.45))
	add_theme_stylebox_override("hover_pressed", _style(Color(0.14, 0.115, 0.085, 1.0), MenuStyle.GOLD_BRIGHT, 3, 0.55))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_build()
	toggled.connect(_on_toggled)


func _style(bg: Color, border: Color, bw: int, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(ClassDefs.get_color(class_id), glow * 0.5) if glow > 0.0 else Color(0, 0, 0, 0.5)
	sb.shadow_size = int(8 + 18 * glow)
	return sb


func _build() -> void:
	var def := ClassDefs.get_class_def(class_id)
	var col := ClassDefs.get_color(class_id)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var v := MenuStyle.vbox(8)
	margin.add_child(v)
	_emblem = MenuEmblem.new(class_id, 112.0)
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_emblem)
	var name_l := MenuStyle.title_label(ClassDefs.get_display_name(class_id).to_upper(), 34, col.lightened(0.2))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var role := MenuStyle.label(ROLE_TEXT.get(class_id, ""), UIStyle.FONT_SMALL, MenuStyle.GOLD.darkened(0.1))
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(role)
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(10, ci.size.y * 0.5), Vector2(ci.size.x - 10, ci.size.y * 0.5), Color(col, 0.7)), Vector2(0, 16)))
	var desc := MenuStyle.label(String(def.get("description", "")), UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(0, 72)
	v.add_child(desc)
	v.add_child(MenuCanvas.new(_paint_attributes, Vector2(0, 92)))
	v.add_child(MenuStyle.label("STARTING EQUIPMENT", 13, UIStyle.COLOR_TEXT_DIM))
	var gear: PackedStringArray = []
	for base_id in def.get("start_items", []):
		var base: Dictionary = ItemDB.get_base(String(base_id))
		gear.append(String(base.get("name", String(base_id).capitalize())))
	var gear_l := MenuStyle.label(", ".join(gear), UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT)
	gear_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(gear_l)
	v.add_child(MenuStyle.label("STARTING SKILLS", 13, UIStyle.COLOR_TEXT_DIM))
	var skills := MenuStyle.hbox(10)
	for sid in ClassDefs.get_start_skill_bar(class_id):
		if sid == "":
			continue
		var cell := MenuStyle.hbox(6)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = Assets.skill_icon(sid)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		cell.add_child(icon)
		var sname := String(SkillDB.get_skill(sid).get("name", sid.capitalize()))
		var sl := MenuStyle.label(sname, UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(sl)
		skills.add_child(cell)
	v.add_child(skills)


func _paint_attributes(ci: Control) -> void:
	var attrs := ClassDefs.get_attributes(class_id)
	var main := ClassDefs.get_main_attribute(class_id)
	var font := ci.get_theme_default_font()
	var row_h := ci.size.y / 3.0
	var bar_x := 56.0
	var bar_w := ci.size.x - bar_x - 44.0
	var i := 0
	for a in ClassDefs.ATTRIBUTES:
		var y := row_h * i + row_h * 0.5
		var col: Color = ATTR_COLORS[a]
		var is_main: bool = a == main
		ci.draw_string(font, Vector2(4, y + 6), ATTR_SHORT[a], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.2) if is_main else UIStyle.COLOR_TEXT_DIM)
		var bg := Rect2(bar_x, y - 6, bar_w, 12)
		ci.draw_rect(bg, Color(0, 0, 0, 0.55))
		var frac := clampf(float(attrs[a]) / 24.0, 0.0, 1.0)
		var fill := Rect2(bg.position, Vector2(bg.size.x * frac, bg.size.y))
		ci.draw_rect(fill, col.darkened(0.15) if is_main else col.darkened(0.45))
		ci.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 4)), Color(1, 1, 1, 0.16))
		ci.draw_rect(bg, Color(col, 0.5), false, 1.0)
		ci.draw_string(font, Vector2(bar_x + bar_w + 10, y + 6), str(attrs[a]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIStyle.COLOR_TEXT if is_main else UIStyle.COLOR_TEXT_DIM)
		i += 1


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
		chosen.emit(class_id)


func _on_toggled(on: bool) -> void:
	if _emblem != null:
		_emblem.set("glow", 1.0 if on else 0.0)
	if on:
		Sfx.play_ui("ui_click")
