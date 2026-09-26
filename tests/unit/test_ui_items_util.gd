extends TestCase
## ui-items test helpers (no tests here): panel creation, synthesised clicks and drags through
## get_viewport().push_input(ev, true), and a character with known items. The other
## test_ui_items_* files extend this script.


## Fresh character with an empty inventory and `gold` gold.
func items_character(class_id: String = "warrior", gold: int = 5000) -> CharacterData:
	var c := make_character(class_id)
	for i in c.inventory.size():
		c.inventory[i] = null
	c.gold = gold
	InvActions.buyback.clear()
	InvActions.vendor_panel = null
	InvActions.stash_panel = null
	GameState.vendor_stock = []
	return c


## Add a standalone panel (Panel.new(); add_child; on_opened({})) and let containers lay out.
func open_panel_node(p: Control, context: Dictionary = {}) -> Control:
	add_child(p)
	p.call("on_opened", context)
	await settle()
	return p


func settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _mouse_button(pos: Vector2, button: int, pressed: bool, ctrl_key: bool, shift: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.ctrl_pressed = ctrl_key
	ev.shift_pressed = shift
	if pressed:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(ev, true)


func move_mouse(pos: Vector2, relative: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	mv.relative = relative
	mv.button_mask = mask
	get_viewport().push_input(mv, true)


## Click the centre of `ctrl` (press + release).
func click(ctrl: Control, button: int = MOUSE_BUTTON_LEFT, ctrl_key: bool = false, shift: bool = false) -> void:
	var pos := ctrl.get_global_rect().get_center()
	move_mouse(pos)
	_mouse_button(pos, button, true, ctrl_key, shift)
	_mouse_button(pos, button, false, ctrl_key, shift)
	await settle(2)


## Drag from the centre of `from` to `to_pos` (screen position) with the left button.
func drag_to(from: Control, to_pos: Vector2) -> void:
	var a := from.get_global_rect().get_center()
	move_mouse(a)
	_mouse_button(a, MOUSE_BUTTON_LEFT, true, false, false)
	await settle(1)
	var last := a
	for k in 8:
		var p := a.lerp(to_pos, float(k + 1) / 8.0)
		move_mouse(p, p - last, MOUSE_BUTTON_MASK_LEFT)
		last = p
		await settle(1)
	_mouse_button(to_pos, MOUSE_BUTTON_LEFT, false, false, false)
	await settle(2)


func drag(from: Control, to: Control) -> void:
	await drag_to(from, to.get_global_rect().get_center())


## A 1920 x 1080 host control for panels (anchored FULL_RECT inside it). The headless test viewport
## is taller than the real 1080-px screen, so screen-fit checks must use this host.
func host_1080() -> Control:
	var host := Control.new()
	host.name = "Host1080"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.position = Vector2.ZERO
	host.size = Vector2(1920, 1080)
	add_child(host)
	return host


## Like open_panel_node, but inside `host` (see host_1080).
func open_panel_in(host: Control, p: Control, context: Dictionary = {}) -> Control:
	host.add_child(p)
	p.call("on_opened", context)
	await settle()
	return p


## Bottom edge (px) that panels must stay above on a 1080-px screen.
func screen_bottom_1080() -> float:
	return 1080.0 - InvStyle.SCREEN_MARGIN


## A rare `base` item with as many affixes as possible (up to `want`).
func rare_with_affixes(base: String, ilvl: int, want: int = 6) -> Item:
	var best: Item = null
	for k in 400:
		var it := ItemDB.create_item(base, Item.Rarity.RARE, ilvl)
		if best == null or it.affixes.size() > best.affixes.size():
			best = it
		if best.affixes.size() >= want:
			break
	return best


## Park the mouse in a corner (no hover) and release any stuck drag.
func reset_mouse() -> void:
	move_mouse(Vector2(2, 2))
	UI.hide_tooltip()
