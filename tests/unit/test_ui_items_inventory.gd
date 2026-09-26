extends "res://tests/unit/test_ui_items_util.gd"
## ui-items: InventoryPanel layout, equip / unequip / sell / stash / drag operations through the
## real CharacterData, tooltips with comparison and refresh on Events signals.


func _inv() -> InventoryPanel:
	return await open_panel_node(InventoryPanel.new())


func test_builds_layout() -> void:
	items_character()
	var p := await _inv()
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE, "panel root ignores the mouse")
	assert_eq(p.get_frame().mouse_filter, Control.MOUSE_FILTER_STOP, "frame stops the mouse")
	var n := 0
	while p.get_grid_slot(n) != null:
		n += 1
	assert_eq(n, Balance.INVENTORY_COLUMNS * Balance.INVENTORY_ROWS, "grid cells")
	var rects: Array[Rect2] = []
	for slot: String in CharacterData.EQUIP_SLOTS:
		var s := p.get_equip_slot(slot)
		assert_not_null(s, "paper doll slot " + slot)
		assert_eq(s.focus_mode, Control.FOCUS_NONE, "slots never take focus")
		assert_eq(s.mouse_filter, Control.MOUSE_FILTER_STOP, "slots stop the mouse")
		var r := s.get_global_rect()
		for o in rects:
			assert_false(r.intersects(o), "doll slot %s overlaps another" % slot)
		rects.append(r)
		assert_true(p.get_frame().get_global_rect().encloses(r), "slot %s inside the frame" % slot)
	var screen := get_viewport().get_visible_rect()
	assert_true(screen.encloses(p.get_frame().get_global_rect()), "frame inside the screen")
	# Weapons get tall slots, rings small ones.
	assert_true(p.get_equip_slot("main_hand").size.y > p.get_equip_slot("ring_1").size.y * 2.0, "tall weapon slot")


func test_shows_items_equipment_and_gold() -> void:
	var c := items_character("warrior", 1234)
	var it := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 10)
	c.put_in_inventory(5, it)
	var p := await _inv()
	assert_eq(p.get_grid_slot(5).item, it, "inventory cell shows the item")
	assert_eq(p.get_equip_slot("main_hand").item, c.get_equipped("main_hand"), "doll shows the weapon")
	assert_not_null(p.get_equip_slot("main_hand").item, "warrior starts with a weapon")
	assert_eq(p.get_equip_slot("helmet").item, null, "empty helmet slot")
	var gold_label := p.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "1,234")
	assert_eq(gold_label.size(), 1, "gold shown formatted")


func test_right_click_equips_and_swaps() -> void:
	var c := items_character()
	var old: Item = c.get_equipped("main_hand")
	var sword := ItemDB.create_item("sword_1", Item.Rarity.MAGIC, 3)
	c.put_in_inventory(7, sword)
	var p := await _inv()
	await click(p.get_grid_slot(7), MOUSE_BUTTON_RIGHT)
	assert_eq(c.get_equipped("main_hand"), sword, "right-click equipped the sword")
	assert_eq(c.inventory[7], old, "previous weapon went into the freed cell")
	await settle()
	assert_eq(p.get_equip_slot("main_hand").item, sword, "doll refreshed")
	assert_eq(p.get_grid_slot(7).item, old, "grid refreshed")


func test_right_click_unequips() -> void:
	var c := items_character()
	var body: Item = c.get_equipped("body")
	var p := await _inv()
	await click(p.get_equip_slot("body"), MOUSE_BUTTON_RIGHT)
	assert_eq(c.get_equipped("body"), null, "body armour removed")
	assert_true(c.find_inventory_index(body) >= 0, "it is in the inventory")


func test_unmet_requirements_marked_and_refused() -> void:
	var c := items_character()
	var big := ItemDB.create_item("greataxe_6", Item.Rarity.NORMAL, 55)
	c.put_in_inventory(0, big)
	var p := await _inv()
	assert_true(p.get_grid_slot(0).unmet, "red background for unmet requirements")
	assert_false(p.get_grid_slot(0).item == null, "item shown")
	var before: Item = c.get_equipped("main_hand")
	await click(p.get_grid_slot(0), MOUSE_BUTTON_RIGHT)
	assert_eq(c.get_equipped("main_hand"), before, "not equipped")
	assert_eq(c.inventory[0], big, "still in the inventory")
	# The tooltip colours the unmet requirement red.
	var lines := big.get_tooltip_lines(InvActions.get_attributes())
	var red := false
	for l: Dictionary in lines:
		for part: Dictionary in l.get("parts", []):
			if part["color"] == UIStyle.COLOR_BAD:
				red = true
	assert_true(red, "unmet requirement red in the tooltip")


func test_drag_inventory_to_equipment_and_back() -> void:
	var c := items_character()
	var helm := ItemDB.create_item("helmet_str_1", Item.Rarity.RARE, 5)
	c.put_in_inventory(3, helm)
	var p := await _inv()
	await drag(p.get_grid_slot(3), p.get_equip_slot("helmet"))
	assert_eq(c.get_equipped("helmet"), helm, "dragged onto the helmet slot")
	assert_eq(c.inventory[3], null, "left the inventory")
	await settle()
	await drag(p.get_equip_slot("helmet"), p.get_grid_slot(20))
	assert_eq(c.get_equipped("helmet"), null, "dragged off the doll")
	assert_eq(c.inventory[20], helm, "into the target cell")
	reset_mouse()


func test_drag_within_grid_and_swap() -> void:
	var c := items_character()
	var a := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 2)
	var b := ItemDB.create_item("amulet_1", Item.Rarity.NORMAL, 2)
	c.put_in_inventory(0, a)
	c.put_in_inventory(9, b)
	var p := await _inv()
	await drag(p.get_grid_slot(0), p.get_grid_slot(9))
	assert_eq(c.inventory[9], a, "moved")
	assert_eq(c.inventory[0], b, "swapped")
	reset_mouse()


func test_drag_to_wrong_slot_refused() -> void:
	var c := items_character()
	var ring := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 2)
	c.put_in_inventory(4, ring)
	var p := await _inv()
	assert_false(p.slot_can_drop(p.get_equip_slot("helmet"), InvActions.make_payload(ring, "inventory", 4)), "ring can't go on the head")
	await drag(p.get_grid_slot(4), p.get_equip_slot("helmet"))
	assert_eq(c.inventory[4], ring, "unchanged")
	assert_eq(c.get_equipped("helmet"), null, "no helmet")
	reset_mouse()


func test_ctrl_click_sells_when_vendor_open() -> void:
	var c := items_character("warrior", 100)
	var junk := ItemDB.create_item("boots_str_1", Item.Rarity.NORMAL, 10)
	c.put_in_inventory(2, junk)
	var v := await open_panel_node(VendorPanel.new()) as VendorPanel
	var p := await _inv()
	assert_true(InvActions.is_vendor_open(), "vendor registered")
	await click(p.get_grid_slot(2), MOUSE_BUTTON_LEFT, true)
	assert_eq(c.inventory[2], null, "sold")
	assert_eq(c.gold, 100 + junk.get_sell_value(), "gold received")
	assert_has(InvActions.buyback, junk, "in the buyback list")
	assert_false(v.get_confirm().is_open(), "normal items sell without confirmation")


func test_ctrl_click_rare_asks_first() -> void:
	var c := items_character("warrior", 0)
	var rare := ItemDB.create_item("gloves_str_1", Item.Rarity.RARE, 10)
	c.put_in_inventory(1, rare)
	var v := await open_panel_node(VendorPanel.new()) as VendorPanel
	var p := await _inv()
	await click(p.get_grid_slot(1), MOUSE_BUTTON_LEFT, true)
	assert_true(v.get_confirm().is_open(), "confirmation shown")
	assert_eq(c.inventory[1], rare, "not sold yet")
	v.get_confirm().cancel()
	assert_eq(c.inventory[1], rare, "cancel keeps it")
	await click(p.get_grid_slot(1), MOUSE_BUTTON_LEFT, true)
	await click(v.get_confirm().get_confirm_button())
	assert_eq(c.inventory[1], null, "sold after confirming")
	assert_eq(c.gold, rare.get_sell_value(), "gold")


func test_shift_click_to_stash_when_open() -> void:
	var c := items_character()
	var it := ItemDB.create_item("belt_1", Item.Rarity.MAGIC, 5)
	c.put_in_inventory(11, it)
	var s := await open_panel_node(StashPanel.new()) as StashPanel
	var p := await _inv()
	await click(p.get_grid_slot(11), MOUSE_BUTTON_LEFT, false, true)
	assert_eq(c.inventory[11], null, "left the inventory")
	assert_eq(c.stash.find(it), 0, "first stash cell")
	await settle()
	assert_eq(s.get_slot(0).item, it, "stash panel refreshed")
	# Equipped item shift+click goes to the stash too.
	var body: Item = c.get_equipped("body")
	await click(p.get_equip_slot("body"), MOUSE_BUTTON_LEFT, false, true)
	assert_true(c.stash.has(body), "body armour stashed")


func test_refreshes_on_signals() -> void:
	var c := items_character("warrior", 10)
	var p := await _inv()
	var it := ItemDB.create_item("amulet_2", Item.Rarity.RARE, 12)
	c.add_to_inventory(it)
	await settle()
	assert_eq(p.get_grid_slot(0).item, it, "inventory_changed refresh")
	var helm := ItemDB.create_item("helmet_dex_1", Item.Rarity.NORMAL, 2)
	c.equip(helm, "helmet")
	await settle()
	assert_eq(p.get_equip_slot("helmet").item, helm, "equipment_changed refresh")
	c.add_gold(990)
	await settle()
	var found := p.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "1,000")
	assert_eq(found.size(), 1, "gold_changed refresh")


func test_hover_tooltip_with_comparison() -> void:
	var c := items_character()
	var body := ItemDB.create_item("body_str_2", Item.Rarity.RARE, 12)
	c.put_in_inventory(6, body)
	var p := await _inv()
	var cell := p.get_grid_slot(6)
	move_mouse(cell.get_global_rect().get_center())
	await settle(2)
	assert_true(cell.is_hovered(), "hovered")
	var tp: TooltipPanel = UI.get("_tooltip")
	assert_not_null(tp, "tooltip exists")
	assert_true(tp.visible, "tooltip shown on hover")
	assert_true(tp.has_comparison(), "compared with the equipped body armour")
	assert_eq(tp.get_main_box().get_row_texts()[0], body.get_display_name(), "hovered item on top")
	var cmp_rows := tp.get_compare_box().get_row_texts()
	assert_eq(cmp_rows[1], c.get_equipped("body").get_display_name(), "equipped item in the comparison box")
	assert_false(tp.get_main_rect().intersects(p.get_frame().get_global_rect()), "tooltip beside the panel, not over it")
	# Equipped items show no comparison.
	move_mouse(p.get_equip_slot("body").get_global_rect().get_center())
	await settle(2)
	assert_true(tp.visible, "still shown")
	assert_false(tp.has_comparison(), "no comparison for equipped items")
	reset_mouse()
	await settle(2)
	assert_false(tp.visible, "hidden when the mouse leaves")


func test_drop_outside_spawns_ground_item() -> void:
	await make_world()
	var c := items_character()
	var pl := spawn_player(Vector3.ZERO)
	var it := ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 3)
	c.put_in_inventory(0, it)
	var p := await _inv()
	var empty_spot := Vector2(700, 500)
	await drag_to(p.get_grid_slot(0), empty_spot)
	assert_eq(c.inventory[0], null, "removed from the inventory")
	var found := false
	for n in get_tree().get_nodes_in_group("loot"):
		if n is GroundItem and (n as GroundItem).item == it:
			found = true
			assert_true((n as GroundItem).global_position.distance_to(pl.global_position) < 3.0, "near the player")
	assert_true(found, "ground item spawned")
	reset_mouse()


func test_payload_and_actions_through_character_data() -> void:
	var c := items_character()
	var it := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 2)
	c.put_in_inventory(3, it)
	var pl := InvActions.payload_for(it)
	assert_eq(pl["type"], "item", "type")
	assert_eq(pl["from"], "inventory", "from")
	assert_eq(pl["index"], 3, "index")
	assert_eq(pl["slot"], "", "slot")
	assert_true(InvActions.move(pl, "equipment", -1, "ring_2")["ok"], "equip via move")
	assert_eq(c.get_equipped("ring_2"), it, "ring_2")
	var pl2 := InvActions.payload_for(it)
	assert_eq(pl2["from"], "equipment", "now equipment")
	assert_eq(pl2["slot"], "ring_2", "slot id")
	assert_true(InvActions.move(pl2, "equipment", -1, "ring_1")["ok"], "move ring slot")
	assert_eq(c.get_equipped("ring_1"), it, "ring_1")
	# A stale payload does nothing.
	assert_false(InvActions.move(pl, "inventory", 5)["ok"], "stale payload refused")
