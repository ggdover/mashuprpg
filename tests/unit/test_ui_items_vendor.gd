extends "res://tests/unit/test_ui_items_util.gd"
## ui-items: VendorPanel buy / sell / buyback / crafting through the real CharacterData and
## GameState.vendor_stock.


func _stock() -> Array:
	return [
		ItemDB.create_item("sword_1", Item.Rarity.NORMAL, 5),
		ItemDB.create_item("bow_1", Item.Rarity.MAGIC, 5),
		ItemDB.create_item("ring_1", Item.Rarity.RARE, 5),
	]


func _vendor() -> VendorPanel:
	return await open_panel_node(VendorPanel.new())


func test_builds_with_prices() -> void:
	items_character("warrior", 10)
	GameState.vendor_stock = _stock()
	var v := await _vendor()
	assert_eq(v.mouse_filter, Control.MOUSE_FILTER_IGNORE, "root ignores the mouse")
	assert_eq(v.get_frame().mouse_filter, Control.MOUSE_FILTER_STOP, "frame stops it")
	assert_eq(v.get_tab(), "trade", "trade tab first")
	for i in 3:
		var s := v.get_stock_slot(i)
		assert_eq(s.item, GameState.vendor_stock[i], "stock cell %d" % i)
		assert_eq(s.price, (GameState.vendor_stock[i] as Item).get_buy_value(), "buy price shown")
	assert_false(v.get_stock_slot(0).price_ok and GameState.character.gold < v.get_stock_slot(0).price, "price colour reflects gold")
	assert_eq(v.get_stock_slot(5).item, null, "empty cells")
	assert_true(get_viewport().get_visible_rect().encloses(v.get_frame().get_global_rect()), "inside the screen")
	v.set_tab("craft")
	await settle()
	assert_true(get_viewport().get_visible_rect().encloses(v.get_frame().get_global_rect()), "craft tab inside the screen")


func test_buy_by_right_click() -> void:
	var c := items_character("warrior", 10000)
	GameState.vendor_stock = _stock()
	var bow: Item = GameState.vendor_stock[1]
	var price := bow.get_buy_value()
	var v := await _vendor()
	await click(v.get_stock_slot(1), MOUSE_BUTTON_RIGHT)
	assert_eq(c.gold, 10000 - price, "paid")
	assert_true(c.find_inventory_index(bow) >= 0, "in the inventory")
	assert_false(GameState.vendor_stock.has(bow), "removed from the stock")
	assert_eq(GameState.vendor_stock.size(), 2, "stock not regenerated")
	await settle()
	assert_ne(v.get_stock_slot(1).item, bow, "grid refreshed")


func test_buy_needs_gold_and_space() -> void:
	var c := items_character("warrior", 1)
	GameState.vendor_stock = _stock()
	var v := await _vendor()
	var r := v.buy_stock(0)
	assert_false(r["ok"], "not enough gold")
	assert_eq(r["reason"], "Not enough gold", "reason")
	assert_eq(GameState.vendor_stock.size(), 3, "nothing bought")
	c.add_gold(100000)
	for i in c.inventory.size():
		c.inventory[i] = ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 1)
	r = v.buy_stock(0)
	assert_false(r["ok"], "inventory full")
	assert_eq(GameState.vendor_stock.size(), 3, "still nothing bought")


func test_drag_stock_into_inventory_buys() -> void:
	var c := items_character("warrior", 10000)
	GameState.vendor_stock = _stock()
	var ring: Item = GameState.vendor_stock[2]
	var v := await _vendor()
	var inv := await open_panel_node(InventoryPanel.new()) as InventoryPanel
	await drag(v.get_stock_slot(2), inv.get_grid_slot(17))
	assert_eq(c.inventory[17], ring, "bought into the target cell")
	assert_eq(c.gold, 10000 - ring.get_buy_value(), "paid")
	reset_mouse()


func test_sell_and_buyback() -> void:
	var c := items_character("warrior", 0)
	GameState.vendor_stock = _stock()
	var junk := ItemDB.create_item("gloves_dex_1", Item.Rarity.MAGIC, 8)
	c.put_in_inventory(4, junk)
	var v := await _vendor()
	assert_true(v.request_sell(InvActions.make_payload(junk, "inventory", 4)), "magic sells at once")
	var value := junk.get_sell_value()
	assert_eq(c.gold, value, "gold")
	await settle()
	assert_eq(v.get_buyback_slot(0).item, junk, "buyback row")
	assert_eq(v.get_buyback_slot(0).price, value, "buyback price = sell value")
	await click(v.get_buyback_slot(0), MOUSE_BUTTON_RIGHT)
	assert_eq(c.gold, 0, "bought back for the same price")
	assert_true(c.find_inventory_index(junk) >= 0, "back in the inventory")
	assert_true(InvActions.buyback.is_empty(), "buyback emptied")


func test_sell_equipped_by_dropping_on_zone() -> void:
	var c := items_character("warrior", 0)
	var body: Item = c.get_equipped("body")
	var v := await _vendor()
	var inv := await open_panel_node(InventoryPanel.new()) as InventoryPanel
	await drag(inv.get_equip_slot("body"), v.get_sell_zone())
	assert_eq(c.get_equipped("body"), null, "sold from the paper doll")
	assert_eq(c.gold, body.get_sell_value(), "gold")
	reset_mouse()


func test_unique_sale_confirmation() -> void:
	var c := items_character("warrior", 0)
	var u := ItemDB.create_unique("voidheart_ring")
	c.put_in_inventory(0, u)
	var v := await _vendor()
	assert_false(v.request_sell(InvActions.make_payload(u, "inventory", 0)), "asks first")
	assert_true(v.get_confirm().is_open(), "dialog open")
	# Esc cancels.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc, true)
	await settle()
	assert_false(v.get_confirm().is_open(), "Esc cancelled")
	assert_eq(c.inventory[0], u, "kept")
	v.request_sell(InvActions.make_payload(u, "inventory", 0))
	v.get_confirm().confirm()
	assert_eq(c.inventory[0], null, "sold")
	assert_eq(c.gold, u.get_sell_value(), "gold")


func test_craft_upgrade_and_reroll() -> void:
	var c := items_character("warrior", 100000)
	var it := ItemDB.create_item("boots_str_2", Item.Rarity.NORMAL, 14)
	c.put_in_inventory(9, it)
	var v := await _vendor()
	v.select_for_craft(it)
	assert_eq(v.get_tab(), "craft", "craft tab")
	assert_eq(v.get_bench_item(), it, "on the bench")
	assert_eq(v.get_bench_slot().item, it, "bench slot shows it")
	assert_eq(c.inventory[9], it, "item stays in the inventory")
	assert_true(v.get_service_button("reroll").disabled, "normal items can't be rerolled")
	assert_false(v.get_service_button("upgrade").disabled, "upgrade available")
	var cost := ItemDB.upgrade_cost(it)
	await click(v.get_service_button("upgrade"))
	assert_eq(it.rarity, Item.Rarity.MAGIC, "upgraded to magic")
	assert_false(it.affixes.is_empty(), "rolled affixes")
	assert_eq(c.gold, 100000 - cost, "paid the ItemDB cost")
	var gold := c.gold
	var rcost := ItemDB.reroll_cost(it)
	assert_true(v.craft("reroll")["ok"], "reroll")
	assert_eq(c.gold, gold - rcost, "paid reroll")
	assert_eq(it.rarity, Item.Rarity.MAGIC, "still magic")
	gold = c.gold
	var ucost := ItemDB.upgrade_cost(it)
	assert_true(v.craft("upgrade")["ok"], "magic -> rare")
	assert_eq(it.rarity, Item.Rarity.RARE, "rare now")
	assert_ne(it.name, "", "rare name")
	assert_eq(c.gold, gold - ucost, "paid")
	assert_false(v.craft("upgrade")["ok"], "rare can't be upgraded")
	await settle()
	assert_true(v.get_service_button("upgrade").disabled, "button disabled at rare")


func test_craft_equipped_item_updates_equipment() -> void:
	var c := items_character("warrior", 100000)
	var body: Item = c.get_equipped("body")
	var slots: Array[String] = []
	var cb := func(s: String) -> void: slots.append(s)
	Events.equipment_changed.connect(cb)
	var v := await _vendor()
	v.select_for_craft(body)
	assert_true(v.craft("upgrade")["ok"], "crafted the equipped body armour")
	Events.equipment_changed.disconnect(cb)
	assert_eq(c.get_equipped("body"), body, "still equipped")
	assert_has(slots, "body", "equipment_changed emitted so the player recalculates")


func test_craft_needs_gold_and_bench_follows_item() -> void:
	var c := items_character("warrior", 0)
	var it := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 12)
	c.put_in_inventory(0, it)
	var v := await _vendor()
	v.select_for_craft(it)
	assert_false(v.craft("reroll")["ok"], "no gold")
	assert_true(v.get_service_button("reroll").disabled, "button disabled without gold")
	# Uniques can't be crafted.
	var u := ItemDB.create_unique("glasswork_amulet")
	c.put_in_inventory(1, u)
	v.select_for_craft(u)
	c.add_gold(99999)
	assert_false(v.craft("reroll")["ok"], "unique refused")
	assert_false(v.craft("upgrade")["ok"], "unique refused")
	# Selling the bench item clears the bench.
	v.request_sell(InvActions.make_payload(u, "inventory", 1))
	v.get_confirm().confirm()
	assert_eq(v.get_bench_item(), null, "bench cleared when its item is sold")


func test_drop_on_bench_selects_without_moving() -> void:
	var c := items_character("warrior", 0)
	var it := ItemDB.create_item("amulet_1", Item.Rarity.MAGIC, 3)
	c.put_in_inventory(5, it)
	var v := await _vendor()
	v.set_tab("craft")
	await settle()
	var inv := await open_panel_node(InventoryPanel.new()) as InventoryPanel
	await drag(inv.get_grid_slot(5), v.get_bench_slot())
	assert_eq(v.get_bench_item(), it, "on the bench")
	assert_eq(c.inventory[5], it, "not moved")
	reset_mouse()
	# Shift+click in the inventory selects too.
	var other := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 3)
	c.put_in_inventory(6, other)
	await settle()
	await click(inv.get_grid_slot(6), MOUSE_BUTTON_LEFT, false, true)
	assert_eq(v.get_bench_item(), other, "shift+click selects for crafting")


## Rares with 6 affixes (and the Before / After pair after a craft) keep the frame inside a
## 1080-px screen: the preview scrolls instead of growing past the bottom edge.
func test_craft_tab_fits_1080_with_big_items() -> void:
	var c := items_character("warrior", 10000000)
	c.level = 60
	var v := await open_panel_in(host_1080(), VendorPanel.new()) as VendorPanel
	var bottom := screen_bottom_1080()
	var width := v.get_frame().size.x
	var scroll := v.get_preview_scroll()
	for base: String in ["greataxe_6", "staff_6", "bow_6", "sword_6"]:
		var it := rare_with_affixes(base, 60)
		assert_eq(it.affixes.size(), 6, "%s rolled 6 affixes" % base)
		c.put_in_inventory(0, it)
		v.select_for_craft(it)
		await settle()
		var end_y := v.get_frame().get_global_rect().end.y
		assert_true(end_y <= bottom + 0.5, "%s on the bench: frame ends at %d" % [base, end_y])
		assert_near(v.get_frame().size.x, width, 0.5, "%s: frame keeps its width" % base)
		# Reroll until Before and After both have 6 affixes (the tallest pair), checking every step.
		var prev := it.affixes.size()
		for k in 150:
			assert_true(v.craft("reroll")["ok"], "reroll")
			await settle()
			end_y = v.get_frame().get_global_rect().end.y
			if end_y > bottom + 0.5:
				fail("%s after craft %d: frame ends at %d" % [base, k + 1, end_y])
				break
			if prev == 6 and it.affixes.size() == 6:
				break
			prev = it.affixes.size()
		assert_near(v.get_frame().size.x, width, 0.5, "%s: frame keeps its width after a craft" % base)
		var content := v.get_node("Frame").find_child("Preview", true, false) as Control
		var needs_scroll := content.get_combined_minimum_size().y > scroll.size.y + 0.5
		assert_eq(scroll.get_v_scroll_bar().visible, needs_scroll, "%s: scrollbar only when the pair doesn't fit" % base)
		assert_true(scroll.size.y >= VendorPanel.PREVIEW_MIN_HEIGHT - 0.5, "preview keeps a usable height")
	# The gold stays on screen.
	var gold := v.get_frame().find_child("Gold", true, false) as Control
	assert_not_null(gold, "gold row")
	assert_true(gold.is_visible_in_tree() and gold.get_global_rect().end.y <= bottom + 0.5, "gold on screen")
	# Back to a small item: no scrollbar, the frame shrinks again.
	var small := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 5)
	c.put_in_inventory(1, small)
	v.select_for_craft(small)
	await settle()
	assert_false(scroll.get_v_scroll_bar().visible, "small item: no scrollbar")
	assert_near(scroll.size.y, v.get_node("Frame").find_child("Preview", true, false).get_combined_minimum_size().y, 1.0, "scroll area fits the preview exactly")
	v.set_tab("trade")
	await settle()
	assert_true(v.get_frame().get_global_rect().end.y <= bottom + 0.5, "trade tab on screen")
	var hint := v.get_frame().find_child("Hint", true, false) as Control
	assert_true(hint.is_visible_in_tree() and hint.get_global_rect().end.y <= bottom + 0.5, "trade hint on screen")


## The mouse wheel scrolls a tall preview; the fade hides at the end.
func test_craft_preview_scrolls_with_wheel() -> void:
	var c := items_character("warrior", 10000000)
	c.level = 60
	var v := await open_panel_in(host_1080(), VendorPanel.new()) as VendorPanel
	var it := rare_with_affixes("greataxe_6", 60)
	c.put_in_inventory(0, it)
	v.select_for_craft(it)
	for k in 40:
		v.craft("reroll")
		if it.affixes.size() >= 5:
			break
	await settle()
	var scroll := v.get_preview_scroll() as VendorPanel.InvPreviewScroll
	if not scroll.get_v_scroll_bar().visible:
		push_warning("preview fits without scrolling here; nothing to scroll")
		return
	assert_true(scroll.has_more_below(), "more below at the top")
	var pos := scroll.get_global_rect().get_center()
	move_mouse(pos)
	for k in 30:
		for pressed: bool in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = pressed
			ev.factor = 1.0
			ev.position = pos
			ev.global_position = pos
			get_viewport().push_input(ev, true)
		await settle(1)
	await settle()
	assert_true(scroll.scroll_vertical > 0, "wheel scrolled (%d)" % scroll.scroll_vertical)
	assert_false(scroll.has_more_below(), "scrolled to the end")
	# A new craft starts at the top again.
	v.craft("reroll")
	await settle()
	assert_eq(scroll.scroll_vertical, 0, "back to the top after a craft")
	reset_mouse()


## A full stock (two dozen items) and a full buyback row fit a 1080-px screen.
func test_trade_tab_fits_1080() -> void:
	var c := items_character("warrior", 100000)
	var stock: Array = []
	for k in 24:
		stock.append(ItemDB.generate_random_item(40, Item.Rarity.MAGIC))
	GameState.vendor_stock = stock
	InvActions.sync_buyback()
	for k in InvActions.MAX_BUYBACK:
		var it := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 3)
		c.add_to_inventory(it)
		InvActions.sell(InvActions.payload_for(it))
	var v := await open_panel_in(host_1080(), VendorPanel.new()) as VendorPanel
	assert_eq(v.get_buyback_slot(InvActions.MAX_BUYBACK - 1).item != null, true, "buyback row full")
	assert_true(v.get_frame().get_global_rect().end.y <= screen_bottom_1080() + 0.5, "frame ends at %d" % v.get_frame().get_global_rect().end.y)


## The buyback row belongs to the character who sold the items: loading or creating another
## character while the same stock array is in place clears it.
func test_buyback_belongs_to_the_character() -> void:
	var c := items_character("warrior", 0)
	GameState.vendor_stock = _stock()
	var boots := ItemDB.create_item("boots_str_1", Item.Rarity.NORMAL, 3)
	c.put_in_inventory(0, boots)
	var v := await _vendor()
	assert_true(v.request_sell(InvActions.make_payload(boots, "inventory", 0)), "sold")
	assert_eq(InvActions.buyback.size(), 1, "in the buyback")
	var other := make_character("ranger")
	other.gold = 100000
	v.refresh()
	assert_eq(v.get_buyback_slot(0).item, null, "the other character doesn't see it")
	assert_true(InvActions.buyback.is_empty(), "buyback cleared")
	var p := InvActions.make_payload(boots, "vendor", 0)
	p["buyback"] = true
	assert_false(InvActions.buy(p)["ok"], "can't buy the other character's item back")
	assert_eq(other.gold, 100000, "no gold spent")


func test_closing_unregisters() -> void:
	items_character()
	var v := await _vendor()
	assert_true(InvActions.is_vendor_open(), "registered")
	v.on_closed()
	assert_false(InvActions.is_vendor_open(), "unregistered")
