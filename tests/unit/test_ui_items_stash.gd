extends "res://tests/unit/test_ui_items_util.gd"
## ui-items: StashPanel (120 cells), moves between stash / inventory / paper doll, sort and
## deposit, refresh on stash_changed.


func _stash() -> StashPanel:
	return await open_panel_node(StashPanel.new())


func test_builds_120_cells() -> void:
	items_character()
	var s := await _stash()
	assert_eq(s.get_slot_count(), Balance.STASH_SIZE, "120 cells")
	assert_eq(s.mouse_filter, Control.MOUSE_FILTER_IGNORE, "root ignores the mouse")
	assert_eq(s.get_frame().mouse_filter, Control.MOUSE_FILTER_STOP, "frame stops it")
	assert_true(get_viewport().get_visible_rect().encloses(s.get_frame().get_global_rect()), "inside the screen")
	assert_true(InvActions.is_stash_open(), "registered for shift+click")
	s.on_closed()
	assert_false(InvActions.is_stash_open(), "unregistered on close")


func test_shows_and_refreshes() -> void:
	var c := items_character()
	var it := ItemDB.create_item("ring_1", Item.Rarity.RARE, 5)
	c.put_in_stash(7, it)
	var s := await _stash()
	assert_eq(s.get_slot(7).item, it, "shown")
	var it2 := ItemDB.create_item("belt_1", Item.Rarity.NORMAL, 5)
	c.add_to_stash(it2)
	await settle()
	assert_eq(s.get_slot(0).item, it2, "stash_changed refresh")


func test_right_and_shift_click_to_inventory() -> void:
	var c := items_character()
	var a := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 5)
	var b := ItemDB.create_item("amulet_1", Item.Rarity.NORMAL, 5)
	c.put_in_stash(0, a)
	c.put_in_stash(1, b)
	var s := await _stash()
	await click(s.get_slot(0), MOUSE_BUTTON_RIGHT)
	assert_true(c.find_inventory_index(a) >= 0, "right-click moved it")
	assert_eq(c.stash[0], null, "left the stash")
	await click(s.get_slot(1), MOUSE_BUTTON_LEFT, false, true)
	assert_true(c.find_inventory_index(b) >= 0, "shift+click moved it")


func test_drag_between_stash_inventory_and_doll() -> void:
	var c := items_character()
	var ring := ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 5)
	var amu := ItemDB.create_item("amulet_1", Item.Rarity.MAGIC, 5)
	c.put_in_stash(3, ring)
	c.put_in_inventory(2, amu)
	var s := await _stash()
	var inv := await open_panel_node(InventoryPanel.new()) as InventoryPanel
	# stash -> inventory cell with an item: swap.
	await drag(s.get_slot(3), inv.get_grid_slot(2))
	assert_eq(c.inventory[2], ring, "ring in the inventory")
	assert_eq(c.stash[3], amu, "amulet swapped into the stash")
	# stash -> paper doll: equip straight from the stash.
	await drag(s.get_slot(3), inv.get_equip_slot("amulet"))
	assert_eq(c.get_equipped("amulet"), amu, "equipped from the stash")
	assert_eq(c.stash[3], null, "stash cell freed")
	# paper doll -> stash.
	await drag(inv.get_equip_slot("amulet"), s.get_slot(50))
	assert_eq(c.stash[50], amu, "unequipped into the stash")
	assert_eq(c.get_equipped("amulet"), null, "slot empty")
	# within the stash.
	await drag(s.get_slot(50), s.get_slot(119))
	assert_eq(c.stash[119], amu, "moved inside the stash")
	reset_mouse()


func test_sort_and_deposit() -> void:
	var c := items_character()
	var ring := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 5)
	var sword := ItemDB.create_item("sword_1", Item.Rarity.RARE, 5)
	var boots := ItemDB.create_item("boots_str_1", Item.Rarity.MAGIC, 5)
	c.put_in_stash(90, ring)
	c.put_in_stash(40, boots)
	c.put_in_stash(10, sword)
	var s := await _stash()
	s.sort_stash()
	assert_eq(c.stash[0], sword, "weapons first")
	assert_eq(c.stash[1], boots, "then armour")
	assert_eq(c.stash[2], ring, "then jewellery")
	assert_eq(c.stash[3], null, "packed")
	c.put_in_inventory(0, ItemDB.create_item("belt_1", Item.Rarity.NORMAL, 3))
	c.put_in_inventory(30, ItemDB.create_item("belt_1", Item.Rarity.NORMAL, 3))
	assert_eq(s.deposit_all(), 2, "deposited two")
	assert_eq(c.inventory_free_count(), c.inventory.size(), "inventory empty")
	assert_eq(c.stash.size() - c.stash.count(null), 5, "five stashed")


func test_stash_full_message() -> void:
	var c := items_character()
	for i in c.stash.size():
		c.stash[i] = ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 1)
	var it := ItemDB.create_item("belt_1", Item.Rarity.NORMAL, 1)
	c.put_in_inventory(0, it)
	var msgs: Array[String] = []
	var cb := func(t: String, _col: Color) -> void: msgs.append(t)
	Events.notify.connect(cb)
	var r := InvActions.inventory_to_stash(0)
	Events.notify.disconnect(cb)
	assert_false(r["ok"], "refused")
	assert_has(msgs, "Stash full", "message shown")
	assert_eq(c.inventory[0], it, "kept")
