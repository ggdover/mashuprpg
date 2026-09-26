extends TestCase
## HUD skill bar: mirrors character.skill_bar, cooldown sweeps, red tint codes, drops / drags,
## tooltips. OWNER: ui-hud.


func _make_hud() -> HUD:
	var layer := CanvasLayer.new()
	add_child(layer)
	var h := HUD.new()
	layer.add_child(h)
	return h


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func test_slots_mirror_character_skill_bar() -> void:
	await make_world()
	var c := make_character("warrior")
	spawn_player()
	var hud := _make_hud()
	await _frames(1)
	assert_eq(hud.skill_slots.size(), 6, "six slots")
	for i in 6:
		assert_eq(hud.skill_slots[i].get("skill_id"), c.skill_bar[i], "slot %d mirrors the bar" % i)
	c.set_skill_in_slot(2, "war_cry")
	assert_eq(hud.skill_slots[2].get("skill_id"), "war_cry", "updates on skill_bar_changed")
	c.set_skill_in_slot(5, "")
	await _frames(1)
	assert_eq(hud.skill_slots[5].get("skill_id"), "", "cleared slot")


func test_cooldown_sweep_follows_runner() -> void:
	await make_world()
	var c := make_character("warrior")
	c.level = 10
	c.set_skill_in_slot(3, "war_cry")
	var p := spawn_player()
	var hud := _make_hud()
	await get_tree().physics_frame
	assert_true(p.skill_runner.try_use("war_cry", p.global_position + Vector3(0, 0, -3)), "war cry used")
	for i in 3:
		await get_tree().physics_frame
	await _frames(2)
	var ratio := p.skill_runner.get_cooldown_ratio("war_cry")
	assert_true(ratio > 0.0, "runner has a cooldown")
	var slot: Variant = hud.skill_slots[3]
	assert_near(slot.cooldown_ratio, ratio, 0.05, "slot sweep = runner ratio")
	assert_near(slot.cooldown_left, p.skill_runner.get_cooldown_remaining("war_cry"), 0.2, "seconds left")
	p.skill_runner.reset_cooldowns()
	await _frames(2)
	assert_near(slot.cooldown_ratio, 0.0, 0.0001, "ready again")


func test_red_tint_codes() -> void:
	await make_world()
	var c := make_character("warrior")
	c.set_skill_in_slot(3, "power_shot")   # needs a bow -> "weapon"
	c.set_skill_in_slot(4, "meteor")       # level 14 -> "level"
	c.set_skill_in_slot(5, "cleave")       # costs mana -> "cost" when empty
	var p := spawn_player()
	var hud := _make_hud()
	await get_tree().physics_frame
	await _frames(2)
	assert_eq(hud.skill_slots[3].get("unusable_code"), "weapon", "weapon requirement tints")
	assert_eq(hud.skill_slots[4].get("unusable_code"), "level", "level requirement tints")
	assert_eq(hud.skill_slots[5].get("unusable_code"), "", "cleave usable with mana")
	assert_true(hud.skill_slots[3].call("is_tinted_red"), "red")
	p.mana = 0.0
	p.mana_regen = 0.0
	await get_tree().create_timer(0.5).timeout
	assert_eq(hud.skill_slots[5].get("unusable_code"), "cost", "no mana -> cost tint")
	assert_eq(hud.skill_slots[0].get("unusable_code"), "", "basic attack costs nothing")


func test_drop_assigns_and_drag_between_slots_swaps() -> void:
	await make_world()
	var c := make_character("warrior")
	spawn_player()
	var hud := _make_hud()
	await _frames(1)
	var slot4: Variant = hud.skill_slots[4]
	var payload := {"type": "skill", "skill_id": "ground_slam"}
	assert_true(slot4._can_drop_data(Vector2.ZERO, payload), "accepts skill payloads")
	assert_false(slot4._can_drop_data(Vector2.ZERO, {"type": "item"}), "rejects items")
	assert_false(slot4._can_drop_data(Vector2.ZERO, {"type": "skill", "skill_id": "m_melee"}), "rejects monster skills")
	assert_false(slot4._can_drop_data(Vector2.ZERO, {"type": "skill", "skill_id": "nope"}), "rejects unknown skills")
	slot4._drop_data(Vector2.ZERO, payload)
	assert_eq(c.skill_bar[4], "ground_slam", "drop assigns through CharacterData")
	assert_eq(slot4.skill_id, "ground_slam", "slot shows it")
	# Drag slot 0 onto slot 4: they swap.
	var first := c.skill_bar[0]
	var drag: Dictionary = hud.skill_slots[0].call("get_drag_payload")
	assert_eq(drag.get("type"), "skill", "drag payload type")
	assert_eq(drag.get("skill_id"), first, "drag payload skill")
	assert_eq(drag.get("from_slot"), 0, "drag payload slot")
	slot4._drop_data(Vector2.ZERO, drag)
	assert_eq(c.skill_bar[4], first, "dragged skill moved")
	assert_eq(c.skill_bar[0], "ground_slam", "and swapped")
	assert_eq(hud.skill_slots[0].get("skill_id"), "ground_slam", "slot 0 updated")
	# Empty slots have no drag payload.
	c.set_skill_in_slot(5, "")
	assert_true((hud.skill_slots[5].call("get_drag_payload") as Dictionary).is_empty(), "empty slot drags nothing")


func test_tooltip_and_key_labels() -> void:
	await make_world()
	var c := make_character("sorcerer")
	var p := spawn_player()
	var hud := _make_hud()
	await _frames(1)
	var slot: Variant = hud.skill_slots[0]
	var lines: Array = slot.get_tooltip_lines()
	var expected: Array = SkillDB.get_tooltip_lines(c.skill_bar[0], p)
	assert_true(lines.size() >= expected.size(), "skill tooltip lines")
	assert_eq(String(lines[0].get("text", "")), String(expected[0].get("text", "")), "tooltip title = skill name")
	hud.show_tooltip_for(slot, lines, false)
	assert_true(hud.tooltip.call("is_showing"), "tooltip shown")
	var box_rect: Rect2 = Rect2()
	var box: Variant = hud.tooltip.get("_box")
	if box != null:
		box_rect = (box as Control).get_global_rect()
		assert_true(box_rect.end.y <= slot.get_global_rect().position.y + 1.0, "tooltip sits above the skill bar")
	hud.hide_tooltip_for(slot)
	assert_false(hud.tooltip.call("is_showing"), "tooltip hidden")
	# Empty slot hint.
	c.set_skill_in_slot(5, "")
	var empty_lines: Array = hud.skill_slots[5].get_tooltip_lines()
	assert_true(String(empty_lines[0].get("text", "")).begins_with("Empty"), "empty slot tooltip")
	# Clicking a slot asks for the skill book.
	var opened: Array = []
	var cb := func(panel: String, _ctx: Dictionary) -> void: opened.append(panel)
	Events.panel_open_requested.connect(cb)
	hud.open_skill_book(1)
	Events.panel_open_requested.disconnect(cb)
	assert_has(opened, "skills", "skill book requested")
	UI.close_all_panels()


func test_click_on_slot_opens_skill_book_and_blocks_gameplay() -> void:
	await make_world()
	make_character("warrior")
	spawn_player()
	var hud := _make_hud()
	await _frames(2)
	var slot: Control = hud.skill_slots[3]
	var pos := slot.get_global_rect().get_center()
	var opened: Array = []
	var cb := func(panel: String, _ctx: Dictionary) -> void: opened.append(panel)
	Events.panel_open_requested.connect(cb)
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	get_viewport().push_input(move, true)
	await _frames(1)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(1)
	Events.panel_open_requested.disconnect(cb)
	assert_has(opened, "skills", "clicking a skill slot opens the skill book")
	assert_true(UI.is_mouse_over_ui(), "the slot takes the mouse (gameplay ignores the click)")
	UI.close_all_panels()
	var away := InputEventMouseMotion.new()
	away.position = Vector2(960, 400)
	away.global_position = Vector2(960, 400)
	get_viewport().push_input(away, true)
	await _frames(1)
