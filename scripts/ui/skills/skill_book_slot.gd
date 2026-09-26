extends Control
## One slot of the skill bar shown at the top of the skill book: the assigned skill's icon and the
## key label (Controls.skill_slot_label). Drop target for {"type": "skill"} payloads (assigns via
## the panel), drag source for its own skill (move it to another slot), right-click clears it.
## Visible slot => MOUSE_FILTER_STOP. Internal: preload("res://scripts/ui/skills/skill_book_slot.gd").

signal dropped(slot: int, skill_id: String)
signal clear_requested(slot: int)
signal hovered(slot: int, ctrl: Control)
signal unhovered(slot: int)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

var slot: int = 0
var skill_id: String = ""
## A skill is being dragged over the slot (highlight).
var _drop_hover := false
var _hover := false
var _flash := 0.0


func _init(p_slot: int = 0) -> void:
	slot = p_slot
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(72, 92)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		hovered.emit(slot, self))
	mouse_exited.connect(func() -> void:
		_hover = false
		_drop_hover = false
		queue_redraw()
		unhovered.emit(slot))


func set_skill(id: String) -> void:
	if id != skill_id and id != "":
		_flash = 1.0
		set_process(true)
	skill_id = id
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func _ready() -> void:
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and skill_id != "":
		clear_requested.emit(slot)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_hover = false
		queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok := data is Dictionary and String((data as Dictionary).get("type", "")) == "skill" and String((data as Dictionary).get("skill_id", "")) != ""
	if ok != _drop_hover:
		_drop_hover = ok
		queue_redraw()
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_hover = false
	dropped.emit(slot, String((data as Dictionary).get("skill_id", "")))


## The drag payload of the assigned skill ({} when empty).
func get_drag_payload() -> Dictionary:
	if skill_id == "":
		return {}
	return {"type": "skill", "skill_id": skill_id, "from_slot": slot}


func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := get_drag_payload()
	if payload.is_empty():
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = Assets.skill_icon(skill_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(56, 56)
	icon.position = Vector2(-28, -28)
	icon.modulate = Color(1, 1, 1, 0.85)
	holder.add_child(icon)
	set_drag_preview(holder)
	return payload


func _draw() -> void:
	var box := Rect2(Vector2(4, 0), Vector2(size.x - 8, size.x - 8))
	var c := box.get_center()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.028, 0.026, 0.95)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = MenuStyle.GOLD if _drop_hover else (UIStyle.COLOR_BORDER_BRIGHT if _hover else UIStyle.COLOR_BORDER)
	if _drop_hover:
		sb.shadow_color = Color(MenuStyle.GOLD, 0.35)
		sb.shadow_size = 10
	draw_style_box(sb, box)
	if skill_id != "":
		var tex := Assets.skill_icon(skill_id)
		if tex != null:
			draw_texture_rect(tex, box.grow(-5.0), false)
	else:
		MenuStyle.draw_diamond(self, c, 5.0, Color(UIStyle.COLOR_BORDER, 0.5))
	if _flash > 0.0:
		MenuStyle.draw_glow(self, c, box.size.x * (0.6 + 0.4 * (1.0 - _flash)), Color(MenuStyle.GOLD, 0.6 * _flash))
	var font := get_theme_default_font()
	var key := Controls.skill_slot_label(slot)
	var fs := 15
	var tw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var kp := Vector2(size.x * 0.5 - tw * 0.5, size.y - 4)
	draw_string_outline(font, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuStyle.GOLD if skill_id != "" else UIStyle.COLOR_TEXT_DIM)
