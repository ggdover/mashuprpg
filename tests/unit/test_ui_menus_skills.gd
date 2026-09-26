extends TestCase
## ui-menus: SkillsPanel (skill book) — rows from SkillDB.get_player_skills (the list may be empty
## while the skills module is a stub), assignment through the slot buttons, locked skills, filters,
## drag payloads, the book's own skill bar (drop / clear by right-click).


func _panel(class_id: String = "warrior", level: int = 1) -> SkillsPanel:
	var c := make_character(class_id)
	c.level = level
	var p := SkillsPanel.new()
	add_child(p)
	p.on_opened({})
	return p


func _settle(frames: int = 2) -> void:
	for i in frames:
		await get_tree().process_frame


func _player_skills() -> Array:
	return SkillDB.get_player_skills()


func _first_skill(pred: Callable) -> Dictionary:
	for s: Dictionary in _player_skills():
		if pred.call(s):
			return s
	return {}


func test_rows_match_skill_db() -> void:
	var p := _panel()
	await _settle()
	var skills := _player_skills()
	assert_eq(p.get_rows().size(), skills.size(), "one row per player skill")
	if skills.is_empty():
		# The skills module is still a stub in this environment: the book must cope.
		assert_eq(p.get_visible_skill_ids().size(), 0, "nothing listed")
		return
	for s: Dictionary in skills:
		assert_true(p.get_rows().has(String(s["id"])), "row for %s" % s["id"])


func test_bar_slots_show_skill_bar_and_clear() -> void:
	var p := _panel("warrior")
	await _settle()
	var c := GameState.character
	assert_eq(p.bar_slots.size(), 6, "six bar slots")
	for i in 6:
		assert_eq(String(p.bar_slots[i].get("skill_id")), c.skill_bar[i], "slot %d mirrors the skill bar" % i)
	# Right-click on slot 1 (cleave) clears it.
	var slot: Control = p.bar_slots[1]
	var pos := slot.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
	await _settle()
	assert_eq(c.skill_bar[1], "", "right-click cleared the slot")
	assert_eq(String(slot.get("skill_id")), "", "slot view refreshed")


func test_slot_buttons_assign_and_toggle() -> void:
	var p := _panel("warrior", 20)
	await _settle()
	var c := GameState.character
	var s := _first_skill(func(d: Dictionary) -> bool: return String(d["id"]) != "basic_attack" and not c.skill_bar.has(String(d["id"])))
	if s.is_empty():
		assert_false(p.assign_skill("fireball", 2), "unknown skills can't be assigned")
		return
	var id := String(s["id"])
	var row: Control = p.get_rows()[id]
	var buttons: Array = row.get("slot_buttons")
	assert_eq(buttons.size(), 6, "six slot buttons")
	assert_eq((buttons[4] as Button).text, Controls.skill_slot_label(4), "key labels from Controls")
	(buttons[4] as Button).pressed.emit()
	assert_eq(c.skill_bar[4], id, "button assigned the skill to slot 4")
	assert_eq(String(p.bar_slots[4].get("skill_id")), id, "bar view updated")
	# Moving it to another slot swaps (CharacterData rule).
	(buttons[2] as Button).pressed.emit()
	assert_eq(c.skill_bar[2], id, "moved to slot 2")
	assert_ne(c.skill_bar[4], id, "left slot 4")
	# Clicking the active slot button clears it.
	(buttons[2] as Button).pressed.emit()
	assert_eq(c.skill_bar[2], "", "toggled off")


func test_locked_skills_greyed_and_refused() -> void:
	var p := _panel("sorcerer", 1)
	await _settle()
	var c := GameState.character
	var s := _first_skill(func(d: Dictionary) -> bool: return int(d.get("unlock_level", 1)) > 1)
	if s.is_empty():
		assert_eq(p.get_rows().size(), 0, "no skills in this environment")
		return
	var id := String(s["id"])
	var row: Control = p.get_rows()[id]
	assert_true(bool(row.get("locked")), "locked at level 1")
	assert_true((row.get("slot_buttons")[0] as Button).disabled, "slot buttons disabled while locked")
	assert_true((row.call("get_drag_payload") as Dictionary).is_empty(), "locked rows can't be dragged")
	assert_false(p.assign_skill(id, 3), "assign refused")
	assert_ne(c.skill_bar[3], id, "bar unchanged")
	c.level = int(s["unlock_level"])
	p.refresh()
	assert_false(bool(row.get("locked")), "unlocked at its level")
	assert_true(p.assign_skill(id, 3), "assign works once unlocked")
	assert_eq(c.skill_bar[3], id, "assigned")


func test_drag_payload_and_drop_on_book_slot() -> void:
	var p := _panel("ranger", 30)
	await _settle()
	var c := GameState.character
	var s := _first_skill(func(d: Dictionary) -> bool: return String(d["id"]) != "basic_attack")
	if s.is_empty():
		var slot: Control = p.bar_slots[0]
		assert_false(bool(slot.call("_can_drop_data", Vector2.ZERO, {"type": "item"})), "items are not skills")
		return
	var id := String(s["id"])
	var payload: Dictionary = p.get_rows()[id].call("get_drag_payload")
	assert_eq(payload, {"type": "skill", "skill_id": id}, "row drag payload (§16)")
	var slot5: Control = p.bar_slots[5]
	assert_true(bool(slot5.call("_can_drop_data", Vector2.ZERO, payload)), "bar slot accepts skills")
	assert_false(bool(slot5.call("_can_drop_data", Vector2.ZERO, {"type": "item", "item": null})), "bar slot rejects items")
	slot5.call("_drop_data", Vector2.ZERO, payload)
	assert_eq(c.skill_bar[5], id, "dropped skill assigned to slot 5")
	var from_slot: Dictionary = slot5.call("get_drag_payload")
	assert_eq(String(from_slot.get("skill_id", "")), id, "slots are drag sources too")


func test_filters_group_skills() -> void:
	var p := _panel("warrior", 60)
	await _settle()
	if p.get_rows().is_empty():
		p.set_filter("spells")
		assert_eq(p.get_filter(), "spells", "filter kept even without skills")
		p.set_filter("bogus")
		assert_eq(p.get_filter(), "all", "unknown filter -> all")
		return
	p.set_filter("spells")
	var ids := p.get_visible_skill_ids()
	assert_true(not ids.is_empty(), "spells listed")
	for id in ids:
		var cat := SkillsPanel.skill_category(SkillDB.get_skill(id))
		assert_true(cat == "spells" or cat == "general", "%s is a spell (or general): %s" % [id, cat])
	p.set_filter("ranged")
	for id in p.get_visible_skill_ids():
		var cat := SkillsPanel.skill_category(SkillDB.get_skill(id))
		assert_true(cat == "ranged" or cat == "general", "%s is bow/crossbow: %s" % [id, cat])
	p.set_filter("all")
	assert_eq(p.get_visible_skill_ids().size(), p.get_rows().size(), "all shows everything")


func test_skill_categories() -> void:
	assert_eq(SkillsPanel.skill_category({"tags": ["spell", "fire"], "weapon_types": []}), "spells", "spell")
	assert_eq(SkillsPanel.skill_category({"tags": ["attack", "projectile"], "weapon_types": ["bow"]}), "ranged", "bow")
	assert_eq(SkillsPanel.skill_category({"tags": ["attack", "melee"], "weapon_types": ["melee"]}), "melee", "melee")
	assert_eq(SkillsPanel.skill_category({"tags": ["warcry", "area"], "weapon_types": []}), "melee", "warcry")
	assert_eq(SkillsPanel.skill_category({"tags": ["attack"], "weapon_types": []}), "general", "basic attack")


func test_close_and_mouse_filters() -> void:
	var p := _panel()
	await _settle()
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE, "windowed panel root ignores the mouse")
	assert_eq(p.close_button.focus_mode, Control.FOCUS_NONE, "no focus on buttons")
	p.close_button.pressed.emit()
	assert_false(p.visible, "Close hides the standalone panel")


## Building and opening the book leaves no orphan nodes (e.g. an unused "empty list" label), and
## reopening reuses the rows.
func test_no_orphan_nodes() -> void:
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var p := _panel("ranger", 10)
	await _settle()
	p.on_closed()
	p.on_opened({})
	await _settle()
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_eq(after - before, 0, "no orphan nodes while the book is open")
	var empty: Variant = p.get("_empty_label")
	if _player_skills().is_empty():
		assert_true(empty != null and (empty as Node).is_inside_tree(), "empty-list label shown in the list")
	else:
		assert_true(empty == null, "no empty-list label with skills listed")
