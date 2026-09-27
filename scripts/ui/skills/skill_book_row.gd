extends PanelContainer
## One skill in the skill book: icon (greyed + padlock while locked), name, unlock level, tag
## chips, weapon requirement (red when the equipped weapon can't use it), cost / cooldown, and six
## slot buttons (LMB, MMB, Q, E, R, F) that assign it to the skill bar (gold = assigned there;
## clicking a gold one clears that slot). Drag source: {"type": "skill", "skill_id": id} (onto the
## HUD skill bar or the book's own bar). Visible frame => MOUSE_FILTER_STOP; buttons FOCUS_NONE.
## Internal: preload("res://scripts/ui/skills/skill_book_row.gd").

signal assign_requested(skill_id: String, slot: int)
signal hovered(skill_id: String, row: Control)
signal unhovered(skill_id: String)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")

const ICON_SIZE := 64.0

var skill_id: String = ""
var skill: Dictionary = {}
var locked: bool = false
var weapon_ok: bool = true
## Slot buttons in slot order.
var slot_buttons: Array[Button] = []

var _hover := false
var _name_label: Label
var _level_label: Label
var _req_label: Label
var _info_label: Label
var _chips: Control
var _icon: Control
var _slots: Array = []   # current skill bar (for the gold state)


func _init(p_skill: Dictionary = {}) -> void:
	skill = p_skill
	skill_id = String(skill.get("id", ""))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 94)
	_build()
	mouse_entered.connect(func() -> void:
		_hover = true
		_apply_style()
		hovered.emit(skill_id, self))
	mouse_exited.connect(func() -> void:
		_hover = false
		_apply_style()
		unhovered.emit(skill_id))


func _build() -> void:
	var h := MenuStyle.hbox(14)
	add_child(h)
	_icon = MenuCanvas.new(_paint_icon, Vector2(ICON_SIZE, ICON_SIZE))
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_icon)
	var mid := MenuStyle.vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := MenuStyle.hbox(10)
	_name_label = MenuStyle.title_label(String(skill.get("name", skill_id.capitalize())), 22, UIStyle.COLOR_TITLE)
	top.add_child(_name_label)
	_level_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_level_label)
	mid.add_child(top)
	var chips := MenuStyle.hbox(5)
	for tag in _display_tags():
		chips.add_child(_chip(tag))
	mid.add_child(chips)
	_chips = chips
	var info := MenuStyle.hbox(0)
	_req_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	info.add_child(_req_label)
	_info_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	info.add_child(_info_label)
	mid.add_child(info)
	h.add_child(mid)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in CharacterData.SKILL_BAR_SIZE:
		var b := Button.new()
		b.text = Controls.skill_slot_label(i)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.custom_minimum_size = Vector2(50, 32)
		b.add_theme_font_size_override("font_size", UIStyle.FONT_SMALL)
		var slot := i
		b.pressed.connect(func() -> void:
			Sfx.play_ui("ui_click")
			assign_requested.emit(skill_id, slot))
		MenuStyle.style_key_button(b, false)
		grid.add_child(b)
		slot_buttons.append(b)
	h.add_child(grid)


func _display_tags() -> Array[String]:
	var out: Array[String] = []
	var tags: Array = skill.get("tags", [])
	var order := ["attack", "spell", "warcry", "melee", "projectile", "area", "channel", "movement", "duration", "chain", "nova", "physical", "fire", "cold", "lightning", "chaos"]
	for t in order:
		if tags.has(t):
			out.append(t)
	for t in tags:
		if not out.has(String(t)):
			out.append(String(t))
	return out


func _chip(tag: String) -> Control:
	var col := MenuStyle.tag_color(tag)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.72), 0.9)
	sb.border_color = Color(col.darkened(0.3), 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(MenuStyle.label(tag.capitalize(), 12, col.lightened(0.15)))
	return p


## Refresh the locked / weapon / slot state. `bar` = the character's skill bar (6 ids).
func refresh(level: int, weapon_type: String, bar: Array, actor: Actor = null) -> void:
	var unlock := int(skill.get("unlock_level", 1))
	locked = level < unlock
	weapon_ok = weapon_type == "" or SkillDB.is_weapon_compatible(skill_id, weapon_type)
	_slots = bar
	_name_label.add_theme_color_override("font_color", UIStyle.COLOR_TEXT_DIM if locked else UIStyle.COLOR_TITLE)
	_chips.modulate = Color(1, 1, 1, 0.45 if locked else 1.0)
	if locked:
		_level_label.text = "Unlocks at level %d" % unlock
		_level_label.add_theme_color_override("font_color", UIStyle.COLOR_BAD.lightened(0.1))
	else:
		_level_label.text = "Level %d" % unlock if unlock > 1 else ""
		_level_label.add_theme_color_override("font_color", UIStyle.COLOR_TEXT_DIM)
	var parts: PackedStringArray = []
	var req := SkillDB.get_weapon_requirement_text(skill_id)
	# Same number as the tooltip (SkillDB uses DamageCalc.get_cost with the player, or level 1).
	var cost := DamageCalc.get_cost(actor, skill)
	if cost > 0.0:
		var pool := "Life" if actor != null and actor.stats.has_flag("blood_magic") else "Mana"
		parts.append("Cost %s %s" % [StatDefs.fmt(roundf(cost)), pool])
	var cd := float(skill.get("cooldown", 0.0))
	if cd > 0.0:
		parts.append("Cooldown %s s" % StatDefs.fmt(cd))
	_req_label.text = req
	_req_label.add_theme_color_override("font_color", UIStyle.COLOR_BAD if (req != "" and not weapon_ok) else UIStyle.COLOR_TEXT_DIM)
	_info_label.text = ("  ·  " if req != "" and not parts.is_empty() else "") + "  ·  ".join(parts)
	for i in slot_buttons.size():
		var b := slot_buttons[i]
		var active := i < bar.size() and String(bar[i]) == skill_id
		MenuStyle.style_key_button(b, active)
		b.disabled = locked
	_apply_style()
	_icon.queue_redraw()


func is_assigned() -> bool:
	return _slots.has(skill_id)


func _apply_style() -> void:
	var state := "normal"
	if locked:
		state = "disabled"
	elif _hover:
		state = "hover"
	var sb := MenuStyle.row_style(state)
	if is_assigned() and not _hover:
		sb.border_color = Color(MenuStyle.GOLD, 0.55)
	add_theme_stylebox_override("panel", sb)


func _paint_icon(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var tex := Assets.skill_icon(skill_id)
	var c := r.get_center()
	if not locked and is_assigned():
		MenuStyle.draw_glow(ci, c, ci.size.x * 0.75, Color(MenuStyle.GOLD, 0.25))
	ci.draw_circle(c, ci.size.x * 0.5, Color(0.02, 0.02, 0.02), true, -1.0, true)
	if tex != null:
		ci.draw_texture_rect(tex, r, false, Color(0.32, 0.32, 0.32) if locked else Color.WHITE)
	var ring := UIStyle.COLOR_BORDER.darkened(0.3) if locked else (MenuStyle.GOLD if is_assigned() else UIStyle.COLOR_BORDER_BRIGHT)
	ci.draw_arc(c, ci.size.x * 0.5 - 1.0, 0, TAU, 48, ring, 2.0, true)
	if locked:
		ci.draw_circle(c, ci.size.x * 0.5 - 2.0, Color(0, 0, 0, 0.35), true, -1.0, true)
		MenuStyle.draw_lock(ci, c + Vector2(0, -2), 26.0, Color(0.85, 0.8, 0.7, 0.9))
	elif not weapon_ok:
		ci.draw_arc(c, ci.size.x * 0.5 - 3.0, 0, TAU, 48, Color(UIStyle.COLOR_BAD, 0.8), 2.0, true)


## The drag payload ({"type": "skill", "skill_id": id}); {} while locked.
func get_drag_payload() -> Dictionary:
	if locked or skill_id == "":
		return {}
	return {"type": "skill", "skill_id": skill_id}


func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := get_drag_payload()
	if payload.is_empty():
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = Assets.skill_icon(skill_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(56, 56)
	icon.position = Vector2(-28, -28)
	icon.modulate = Color(1, 1, 1, 0.85)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	set_drag_preview(holder)
	return payload
