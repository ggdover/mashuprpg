extends "res://tests/unit/test_ui_items_util.gd"
## ui-items: §16 mouse-filter and focus rules for every item panel, and opening / closing the
## panels through the real UIRoot.


const PANEL_SCRIPTS := {
	"inventory": "res://scripts/ui/inventory/inventory_panel.gd",
	"character": "res://scripts/ui/character/character_panel.gd",
	"stash": "res://scripts/ui/stash/stash_panel.gd",
	"vendor": "res://scripts/ui/vendor/vendor_panel.gd",
}


## Controls allowed to take the mouse: frames, slots, buttons, hover widgets, drop zones, scroll
## areas (wheel) with their scrollbars and the (hidden, modal) confirmation overlay.
func _may_stop(c: Control, frame: Control) -> bool:
	if c == frame or c is InvSlot or c is BaseButton or c is InvConfirm:
		return true
	if c is ScrollContainer or c is ScrollBar:
		return true
	# Inside the (hidden unless asking) modal confirmation box everything may block.
	var a := c.get_parent()
	while a != null:
		if a is InvConfirm:
			return true
		a = a.get_parent()
	if c.get_script() != null and (c.has_method("is_hovered") or c.has_method("_can_drop_data")):
		return true
	return false


func test_mouse_filter_and_focus_rules() -> void:
	items_character()
	GameState.vendor_stock = [ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 3)]
	for id: String in PANEL_SCRIPTS:
		var p: Control = (load(PANEL_SCRIPTS[id]) as GDScript).new()
		await open_panel_node(p)
		assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s root" % id)
		var frame: Control = p.call("get_frame")
		assert_eq(frame.mouse_filter, Control.MOUSE_FILTER_STOP, "%s frame" % id)
		var bad: PackedStringArray = []
		var focus_bad: PackedStringArray = []
		for n in p.find_children("*", "Control", true, false):
			var c := n as Control
			if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and not _may_stop(c, frame):
				bad.append("%s (%s)" % [c.name, c.get_class()])
			var scroll_part := c is ScrollContainer or (c is ScrollBar and c.get_parent() is ScrollContainer)
			if (c is BaseButton or c is InvSlot or scroll_part) and c.focus_mode != Control.FOCUS_NONE:
				focus_bad.append(String(c.name))
		assert_eq(bad, PackedStringArray(), "%s: layout-only controls must ignore the mouse" % id)
		assert_eq(focus_bad, PackedStringArray(), "%s: buttons/slots never take focus" % id)
		p.call("on_closed")
		p.queue_free()
		await settle(1)


func test_open_and_close_through_ui_root() -> void:
	items_character()
	GameState.vendor_stock = [ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 3)]
	UI.open_panel("vendor", {})
	await settle()
	assert_true(UI.is_panel_open("vendor"), "vendor open")
	assert_true(UI.is_panel_open("inventory"), "inventory auto-opened")
	assert_true(InvActions.is_vendor_open(), "vendor registered")
	var inv := UI.get_panel("inventory") as InventoryPanel
	assert_eq(inv.mouse_filter, Control.MOUSE_FILTER_IGNORE, "UIRoot keeps the root ignoring the mouse")
	# The close button goes through Events.panel_close_requested.
	var close: Button = null
	for b in (UI.get_panel("vendor") as VendorPanel).get_frame().find_children("*", "Button", true, false):
		if (b as Button).text == "✕":
			close = b
			break
	assert_not_null(close, "close button")
	close.pressed.emit()
	await settle()
	assert_false(UI.is_panel_open("vendor"), "vendor closed")
	assert_false(UI.is_panel_open("inventory"), "auto-opened inventory closed too")
	assert_false(InvActions.is_vendor_open(), "unregistered")
	UI.open_panel("stash", {})
	UI.open_panel("character", {})
	await settle()
	assert_true(InvActions.is_stash_open(), "stash registered")
	UI.close_all_panels()
	await settle()
	assert_false(InvActions.is_stash_open(), "stash unregistered")
	assert_false(UI.any_panel_open(), "all closed")


func test_mouse_over_ui_only_on_frames() -> void:
	items_character()
	var p := await open_panel_node(InventoryPanel.new()) as InventoryPanel
	move_mouse(Vector2(500, 500))
	await settle(2)
	assert_false(UI.is_mouse_over_ui(), "empty screen area is not UI")
	move_mouse(p.get_grid_slot(0).get_global_rect().get_center())
	await settle(2)
	assert_true(UI.is_mouse_over_ui(), "a slot is UI")
	reset_mouse()
