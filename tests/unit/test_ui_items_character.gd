extends "res://tests/unit/test_ui_items_util.gd"
## ui-items: CharacterPanel values (attributes, pools, defences, resistances with the dungeon
## penalty, offence rows), standalone use, and live refresh on Events.


func _sheet() -> CharacterPanel:
	return await open_panel_node(CharacterPanel.new())


func test_builds_standalone_with_class_values() -> void:
	var c := items_character("ranger")
	var p := await _sheet()
	var v := p.get_values()
	var attrs := c.compute_attributes()
	for a: String in ["strength", "dexterity", "intelligence"]:
		assert_near(float(v[a]), float(attrs[a]), 0.01, a)
	# Life per §5.2 / Balance: base + 1 per 2 strength (+ gear / passives).
	var sheet := p.get_stat_actor()
	assert_not_null(sheet, "stat actor")
	assert_near(float(v["max_life"]), sheet.max_life, 0.01, "life from the stat actor")
	assert_true(float(v["max_life"]) >= Balance.player_base_life(1) + floorf(float(attrs["strength"]) / 2.0) - 0.01, "life includes strength")
	assert_true(float(v["evasion"]) >= Balance.PLAYER_BASE_EVASION, "base evasion + dex")
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE, "root ignores the mouse")
	assert_eq(p.get_frame().mouse_filter, Control.MOUSE_FILTER_STOP, "frame stops it")
	assert_true(get_viewport().get_visible_rect().encloses(p.get_frame().get_global_rect()), "inside the screen")


func test_refresh_on_equipment_change() -> void:
	var c := items_character("warrior")
	var p := await _sheet()
	var life0 := float(p.get_values()["max_life"])
	var armour0 := float(p.get_values()["armour"])
	var belt := ItemDB.create_item("belt_1", Item.Rarity.NORMAL, 1)
	belt.affixes = [{"id": "test", "kind": "prefix", "tier": 1, "name": "Test", "mods": [StatBlock.mod("max_life", "flat", 40.0)]}]
	c.equip(belt, "belt")
	var helm := ItemDB.create_item("helmet_str_1", Item.Rarity.NORMAL, 1)
	c.equip(helm, "helmet")
	await settle()
	var added := 0.0
	for m: Dictionary in belt.get_global_mods():
		if m["stat"] == "max_life" and m["op"] == "flat":
			added += float(m["value"])
	assert_true(added >= 40.0, "belt adds life")
	assert_near(float(p.get_values()["max_life"]), life0 + added, 0.5, "life refreshed from equipment_changed")
	assert_true(float(p.get_values()["armour"]) > armour0, "armour went up")
	var row := p.get_row("life")
	assert_not_null(row, "life row")
	assert_eq(String(row.get("value")), str(roundi(life0 + added)), "row text updated")


func test_dungeon_penalty_shown() -> void:
	items_character("sorcerer")
	GameState.current_area = {"id": "dungeon", "depth": 30, "level": 30, "theme": "crypt", "name": "Depth 30"}
	var p := await _sheet()
	var pen := Balance.resist_penalty(30)
	assert_near(float(p.get_values()["resist_penalty"]), pen, 0.01, "penalty")
	assert_near(float(p.get_values()["fire_res"]), maxf(-100.0, pen), 0.01, "fire resistance includes the penalty")
	var labels := p.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.contains("%d%%" % roundi(pen)))
	assert_true(labels.size() >= 1, "penalty text shown")
	GameState.current_area = {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
	Events.area_entered.emit(GameState.current_area)
	await settle()
	assert_near(float(p.get_values()["fire_res"]), 0.0, 0.01, "no penalty in town")


func test_offence_rows_without_skill_data() -> void:
	var c := items_character("warrior")
	c.set_skill_in_slot(0, "basic_attack")
	var p := await _sheet()
	var rows := p.get_skill_rows()
	assert_true(rows.size() >= 1, "at least one offence row (%d)" % rows.size())
	assert_true(float(p.get_values().get("dps_0", 0.0)) > 0.0, "DPS computed")
	assert_true(String(rows[0].get("title")) != "", "row has a title")
	# Every bar skill SkillDB knows gets its own row.
	var known := 0
	for i in c.skill_bar.size():
		if c.get_skill_in_slot(i) != "" and SkillDB.has_skill(c.get_skill_in_slot(i)):
			known += 1
	assert_eq(rows.size(), maxi(1, known), "one row per known bar skill")


func test_offence_uses_weapon() -> void:
	var c := items_character("warrior")
	var p := await _sheet()
	var dps0 := float(p.get_values()["dps_0"])
	var big := ItemDB.create_item("sword_2", Item.Rarity.NORMAL, 20)
	c.level = 20
	c.equip(big, "main_hand")
	await settle()
	assert_true(float(p.get_values()["dps_0"]) > dps0, "a better weapon raises DPS (%s -> %s)" % [dps0, p.get_values()["dps_0"]])


func test_live_player_is_the_source() -> void:
	await make_world()
	items_character("warrior")
	var pl := spawn_player()
	await settle()
	var p := await _sheet()
	assert_eq(p.get_stat_actor(), pl, "reads the live player")
	Events.player_stats_changed.emit()
	await settle()
	assert_near(float(p.get_values()["max_life"]), pl.max_life, 0.01, "shows the player's life")


func test_hover_rows_show_tooltips() -> void:
	items_character("warrior")
	var p := await _sheet()
	var row := p.get_row("armour")
	move_mouse(row.get_global_rect().get_center())
	await settle(2)
	var tp: TooltipPanel = UI.get("_tooltip")
	assert_not_null(tp, "tooltip")
	assert_true(tp.visible, "shown")
	assert_eq(tp.get_main_box().get_row_texts()[0], "Armour", "armour explanation")
	assert_false(tp.get_main_rect().intersects(p.get_frame().get_global_rect()), "beside the sheet")
	reset_mouse()
	await settle(2)
	assert_false(tp.visible, "hidden after leaving")


func test_level_and_xp_refresh() -> void:
	var c := items_character("sorcerer")
	var p := await _sheet()
	c.add_xp(c.xp_to_next() + 5)
	await settle()
	var found := p.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "Level 2 Sorcerer")
	assert_eq(found.size(), 1, "level label refreshed")


## Opened next to the vendor or the stash (which dock on the left edge too), the sheet docks
## beside them instead of on top; back on the left edge once they close.
func test_sheet_docks_beside_vendor_and_stash() -> void:
	items_character("warrior")
	GameState.vendor_stock = [ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 3)]
	var cp := UI.get_panel("character") as CharacterPanel
	for other: String in ["vendor", "stash"]:
		UI.open_panel(other, {})
		UI.open_panel("character", {})
		await settle(4)
		var of: Control = UI.get_panel(other).call("get_frame")
		var inv := UI.get_panel("inventory") as InventoryPanel
		var cr := cp.get_frame().get_global_rect()
		assert_false(cr.intersects(of.get_global_rect()), "sheet beside the %s" % other)
		assert_true(cr.position.x >= of.get_global_rect().end.x, "right of the %s" % other)
		assert_false(cr.intersects(inv.get_frame().get_global_rect()), "left of the inventory (%s)" % other)
		UI.close_panel(other)
		await settle(3)
		assert_near(cp.get_frame().get_global_rect().position.x, InvStyle.SCREEN_MARGIN, 0.5, "back on the left edge after the %s closed" % other)
		# Opening the other panel while the sheet is already open moves it too.
		UI.open_panel(other, {})
		await settle(4)
		assert_false(cp.get_frame().get_global_rect().intersects(of.get_global_rect()), "moves aside when the %s opens later" % other)
		UI.close_all_panels()
		await settle(2)
