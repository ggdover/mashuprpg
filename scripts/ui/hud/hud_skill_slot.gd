extends Control
## One skill-bar slot: icon (Assets.skill_icon), key label (Controls.skill_slot_label), cooldown
## sweep with the seconds left, red tint while the skill can't be used (can_use code cost / weapon
## / level; level also shows a lock), gold glow while the skill is held / in use, a flash when it
## comes off cooldown. Hover shows SkillDB.get_tooltip_lines(id, player). Drop target for
## {"type": "skill", "skill_id"} payloads (skill book -> slot, slot -> slot); drag source for its
## own skill (dropping it on the world clears the slot); a click opens the skill book.
## Internal: preload("res://scripts/ui/hud/hud_skill_slot.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const SLOT_SIZE := 64.0
const RED_CODES: Array[String] = ["cost", "weapon", "level"]

var slot: int = 0
## The HUD that owns this slot (character / player / tooltip / assignment helpers).
var hud: Control = null
var skill_id: String = ""
## 0 = ready, 1 = just used.
var cooldown_ratio: float = 0.0
var cooldown_left: float = 0.0
## can_use code when it is one of RED_CODES, else "".
var unusable_code: String = ""
var unusable_reason: String = ""
## Held key / skill running.
var active: bool = false

var _icon: Texture2D = null
var _hover := false
var _drop_hover := false
var _pressed := false
var _dragging := false
var _flash := 0.0
var _assign_flash := 0.0
var _unlock_level := 0


func _init(p_slot: int = 0) -> void:
	slot = p_slot
	name = "SkillSlot%d" % (slot + 1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	size = custom_minimum_size
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _ready() -> void:
	set_process(false)


func set_skill(id: String) -> void:
	if id == skill_id:
		return
	skill_id = id
	_icon = Assets.skill_icon(id) if id != "" else null
	_unlock_level = int(SkillDB.get_skill(id).get("unlock_level", 1)) if id != "" else 0
	cooldown_ratio = 0.0
	cooldown_left = 0.0
	unusable_code = ""
	if id != "":
		_assign_flash = 1.0
		set_process(true)
	queue_redraw()
	if _hover:
		_refresh_tooltip()


## Per-frame state from the HUD.
func set_state(p_cd_ratio: float, p_cd_left: float, p_active: bool) -> void:
	var changed := false
	if p_cd_ratio <= 0.0 and cooldown_ratio > 0.0:
		_flash = 1.0
		set_process(true)
	if absf(p_cd_ratio - cooldown_ratio) > 0.0001 or absf(p_cd_left - cooldown_left) > 0.0001:
		changed = true
	if p_active != active:
		changed = true
	cooldown_ratio = p_cd_ratio
	cooldown_left = p_cd_left
	active = p_active
	if changed:
		queue_redraw()


## can_use result (checked a few times per second by the HUD).
func set_usable(code: String, reason: String) -> void:
	var c := code if code in RED_CODES else ""
	if c != unusable_code or reason != unusable_reason:
		unusable_code = c
		unusable_reason = reason
		queue_redraw()


func is_tinted_red() -> bool:
	return unusable_code != ""


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_assign_flash = maxf(0.0, _assign_flash - delta * 2.2)
	queue_redraw()
	if _flash <= 0.0 and _assign_flash <= 0.0:
		set_process(false)


# ------------------------------------------------------------------ mouse

func _on_mouse_entered() -> void:
	_hover = true
	queue_redraw()
	_refresh_tooltip()


func _on_mouse_exited() -> void:
	_hover = false
	_pressed = false
	_drop_hover = false
	queue_redraw()
	if hud != null and hud.has_method("hide_tooltip_for"):
		hud.call("hide_tooltip_for", self)


func _refresh_tooltip() -> void:
	if hud == null or not hud.has_method("show_tooltip_for"):
		return
	hud.call("show_tooltip_for", self, get_tooltip_lines(), false)


## Tooltip lines for the current skill (or the empty-slot hint).
func get_tooltip_lines() -> Array:
	var key := Controls.skill_slot_label(slot)
	if skill_id == "":
		return [
			{"text": "Empty Skill Slot (%s)" % key, "color": UIStyle.COLOR_TITLE, "size": "title"},
			{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
			{"text": "Drag a skill here from the Skill Book (%s)" % Controls.label_for("toggle_skills"), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
		]
	var player: Actor = hud.call("get_player") if hud != null and hud.has_method("get_player") else null
	var lines: Array = SkillDB.get_tooltip_lines(skill_id, player)
	if lines.is_empty():
		lines = [{"text": skill_id.capitalize(), "color": UIStyle.COLOR_TITLE, "size": "title"}]
	lines = lines.duplicate()
	if unusable_reason != "":
		lines.append({"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true})
		lines.append({"text": unusable_reason, "color": UIStyle.COLOR_BAD, "size": "normal"})
	lines.append({"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true})
	lines.append({"text": "Key: %s  ·  Click: Skill Book  ·  Drag to move" % key, "color": UIStyle.COLOR_TEXT_DIM, "size": "small"})
	return lines


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressed = true
		accept_event()
	elif _pressed:
		_pressed = false
		accept_event()
		if hud != null and hud.has_method("open_skill_book"):
			hud.call("open_skill_book", slot)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill_id == "":
		return null
	_pressed = false
	_dragging = true
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = _icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.size = Vector2(56, 56)
	icon.position = Vector2(-28, -28)
	icon.modulate = Color(1, 1, 1, 0.85)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	set_drag_preview(holder)
	if hud != null and hud.has_method("hide_tooltip_for"):
		hud.call("hide_tooltip_for", self)
	return get_drag_payload()


## The payload this slot produces when dragged ({} when empty).
func get_drag_payload() -> Dictionary:
	if skill_id == "":
		return {}
	return {"type": "skill", "skill_id": skill_id, "from_slot": slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok := accepts_payload(data)
	if ok != _drop_hover:
		_drop_hover = ok
		queue_redraw()
	return ok


## True for {"type": "skill", "skill_id": <player skill>} while a character is bound.
func accepts_payload(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	if String(d.get("type", "")) != "skill":
		return false
	var id := String(d.get("skill_id", ""))
	if id == "" or not SkillDB.has_skill(id) or bool(SkillDB.get_skill(id).get("monster_only", false)):
		return false
	return hud != null and hud.has_method("get_character") and hud.call("get_character") != null


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_hover = false
	queue_redraw()
	if not accepts_payload(data):
		return
	if hud != null and hud.has_method("assign_skill"):
		hud.call("assign_skill", slot, String((data as Dictionary).get("skill_id", "")))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if _drop_hover:
			_drop_hover = false
			queue_redraw()
		if _dragging:
			_dragging = false
			var vp := get_viewport()
			# Dropped on the world (not on any UI): clear the slot.
			if vp != null and not vp.gui_is_drag_successful() and vp.gui_get_hovered_control() == null and skill_id != "":
				if hud != null and hud.has_method("assign_skill"):
					hud.call("assign_skill", slot, "")


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var inner := rect.grow(-3.0)
	# Glow behind the frame while active / drop target.
	if active or _drop_hover:
		var gc := HudStyle.GOLD if not _drop_hover else HudStyle.GOLD_BRIGHT
		draw_style_box(HudStyle.box(Color(gc, 0.0), Color(gc, 0.35), 4, 9), rect.grow(3.0))
	draw_style_box(HudStyle.box(HudStyle.SLOT_BG, Color(0, 0, 0, 0), 0, 6), rect)
	if skill_id == "":
		HudStyle.draw_diamond(self, rect.get_center(), 6.0, Color(HudStyle.BRONZE, 0.45))
		HudStyle.draw_diamond(self, rect.get_center(), 3.0, Color(HudStyle.BRONZE_DARK, 0.9))
	elif _icon != null:
		var mod := Color.WHITE
		if unusable_code != "":
			mod = Color(0.62, 0.45, 0.45)
		elif cooldown_ratio > 0.0:
			mod = Color(0.8, 0.8, 0.8)
		draw_texture_rect(_icon, inner.grow(-1.0), false, mod)
	if unusable_code != "" and skill_id != "":
		draw_style_box(HudStyle.box(HudStyle.UNUSABLE, Color(0, 0, 0, 0), 0, 4), inner)
		if unusable_code == "level":
			_draw_lock(rect.get_center() + Vector2(0, -5), 9.0)
			HudStyle.text_centered(self, HudStyle.bold_font(), rect.get_center().x, rect.get_center().y + 20.0, "Lv %d" % _unlock_level, 13, Color(1, 0.8, 0.75), 4)
	if cooldown_ratio > 0.0 and skill_id != "":
		var poly := HudStyle.sweep_polygon(inner, cooldown_ratio)
		if poly.size() >= 3:
			draw_colored_polygon(poly, HudStyle.COOLDOWN_SHADE)
		if cooldown_ratio < 0.999:
			var a := -PI * 0.5 + TAU * (1.0 - cooldown_ratio)
			var d := Vector2(cos(a), sin(a))
			var tx := inner.size.x * 0.5 / maxf(0.0001, absf(d.x))
			var ty := inner.size.y * 0.5 / maxf(0.0001, absf(d.y))
			draw_line(inner.get_center(), inner.get_center() + d * minf(tx, ty), Color(1, 0.9, 0.6, 0.55), 1.5, true)
		if cooldown_left >= 0.05:
			var txt := "%.1f" % cooldown_left if cooldown_left < 10.0 else str(int(ceilf(cooldown_left)))
			HudStyle.text_centered(self, HudStyle.number_font(), rect.get_center().x, rect.get_center().y + 9.0, txt, 24, Color(1, 0.97, 0.9), 5)
	if _flash > 0.0:
		draw_style_box(HudStyle.box(Color(1, 0.95, 0.75, 0.35 * _flash), Color(0, 0, 0, 0), 0, 5), inner)
	if _assign_flash > 0.0:
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0), Color(HudStyle.GOLD_BRIGHT, _assign_flash), 3, 7), rect.grow(2.0 + 4.0 * (1.0 - _assign_flash)))
	var hl := 0.0
	if _hover:
		hl = 0.55
	if active:
		hl = 1.0
	HudStyle.draw_bronze_frame(self, rect, 6, hl)
	if active:
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0), HudStyle.GOLD_BRIGHT, 2, 6), rect)
	if _drop_hover:
		draw_style_box(HudStyle.box(Color(HudStyle.GOLD, 0.12), HudStyle.GOLD_BRIGHT, 2, 6), rect)
	_draw_key_tag(rect)


func _draw_key_tag(rect: Rect2) -> void:
	var key := Controls.skill_slot_label(slot)
	var f := HudStyle.bold_font()
	var fs := 12
	var w := HudStyle.text_width(f, key, fs) + 10.0
	var tag := Rect2(Vector2(rect.position.x + 2.0, rect.end.y - 17.0), Vector2(maxf(18.0, w), 15.0))
	draw_style_box(HudStyle.box(Color(0.02, 0.018, 0.016, 0.92), HudStyle.BRONZE_DARK, 1, 3), tag)
	var col := HudStyle.GOLD if skill_id != "" else HudStyle.TEXT_DIM
	HudStyle.text_centered(self, f, tag.get_center().x, tag.end.y - 3.0, key, fs, col, 0)


func _draw_lock(c: Vector2, s: float) -> void:
	draw_arc(c + Vector2(0, -s * 0.35), s * 0.55, PI, TAU, 12, Color(0.95, 0.85, 0.8), 2.5, true)
	draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.3), Vector2(s * 1.6, s * 1.25)), Color(0.95, 0.85, 0.8))
	draw_circle(c + Vector2(0, s * 0.25), s * 0.2, Color(0.3, 0.05, 0.05))
