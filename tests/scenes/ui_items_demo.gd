extends Node
## ui-items demo: a level 28 warrior in town with a full inventory of generated items (every
## rarity, uniques), equipped gear, a stocked stash, vendor stock and buyback. Opens every item
## panel through the real UIRoot (UI autoload) over the town and saves screenshots to
## docs/screenshots/ui-items/ (windowed runs only); headless it walks through every screen as a
## smoke test.
##
##   GTEST_WINDOWED=1 tools/gtest.sh ui-items-demo res://tests/scenes/ui_items_demo.tscn
##   ... -- --only=inventory_compare,vendor_craft     (subset; names in SHOTS)
##   ... -- --no-world                                 (plain backdrop, faster)

const SHOTS: Array[String] = ["inventory_compare", "inventory_unique", "inventory_twohand_alt", "character", "character_dungeon", "vendor_trade", "vendor_sell_confirm", "vendor_craft_bench", "vendor_craft", "vendor_character", "stash", "stash_drag"]
const LEVEL := 28

var _dir := ""
var _windowed := false
var _cam: Camera3D = null
var _world: World = null
## Mouse release pushed after the capture of a shot that holds a drag.
var _release: InputEventMouseButton = null
var _alt_held := false


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	_windowed = DisplayServer.get_name() != "headless"
	var repo := OS.get_environment("GTEST_REPO")
	if repo == "":
		repo = ProjectSettings.globalize_path("res://")
	_dir = repo.path_join("docs/screenshots/ui-items")
	DirAccess.make_dir_recursive_absolute(_dir)
	var only: PackedStringArray = []
	var no_world := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",", false)
		elif a == "--no-world":
			no_world = true
	RenderingServer.set_default_clear_color(Color(0.06, 0.055, 0.05))
	seed(20260925)
	var t0 := Time.get_ticks_msec()
	if not no_world:
		_build_backdrop()
	print("[ui_items_demo] backdrop %d ms" % (Time.get_ticks_msec() - t0))
	_make_character()
	print("[ui_items_demo] character %d ms" % (Time.get_ticks_msec() - t0))
	await _settle(4)
	for shot in SHOTS:
		if not only.is_empty() and not only.has(shot):
			continue
		await call("_shot_" + shot)
		# Let fades / tweens finish (time based: frames can be very fast when windowed).
		await get_tree().create_timer(0.3).timeout
		await _settle(2)
		_capture(shot)
		if _release != null:
			get_viewport().push_input(_release, true)
			_release = null
			await _settle(2)
		if _alt_held:
			_set_alt(false)
		_clear_hover()
		UI.close_all_panels()
		UI.hide_tooltip()
		GameState.current_area = {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
		await _settle(2)
	print("[ui_items_demo] done")
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		if _windowed:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame


func _capture(shot: String) -> void:
	if not _windowed:
		print("[ui_items_demo] %s ok (headless: no screenshot)" % shot)
		return
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%s.png" % shot)
	img.save_png(path)
	print("[ui_items_demo] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


# ------------------------------------------------------------------ scene

func _build_backdrop() -> void:
	_world = World.new()
	add_child(_world)
	GameState.world = _world
	var info := {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
	GameState.current_area = info
	_world.build(info)
	var start := _world.get_player_start()
	var hero := Assets.model("char_player")
	if hero != null:
		hero.position = start
		_world.add_child(hero)
		var ap := Assets.prepare_animations(hero)
		if ap != null and ap.has_animation("idle"):
			ap.play("idle")
	_cam = Camera3D.new()
	_cam.fov = 45.0
	var p := deg_to_rad(56.0)
	_cam.position = start + Vector3(0, sin(p) * 16.0, cos(p) * 16.0)
	_cam.rotation = Vector3(-p, 0, 0)
	_world.add_child(_cam)
	_cam.make_current()


# ------------------------------------------------------------------ data

func _make_character() -> void:
	var c := GameState.new_character("Aldric", "warrior")
	c.level = LEVEL
	c.max_depth = 24
	c.xp = int(c.xp_to_next() * 0.62)
	c.gold = 0
	c.add_gold(24380)
	var bar := ["basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam", "war_cry"]
	for i in bar.size():
		c.set_skill_in_slot(i, bar[i])
	# Passives: walk out from the start, preferring strength / life nodes.
	for n in LEVEL - 1:
		var opts := TreeDB.get_allocatable(c.allocated_passives, c.class_id)
		if opts.is_empty():
			break
		var best: int = opts[0]
		var best_score := -1.0
		for id: int in opts:
			var score := 0.0
			for line in TreeDB.get_node_lines(id):
				if "Strength" in line or "Life" in line or "Armour" in line or "Melee" in line:
					score += 1.0
			score += randf() * 0.5
			if score > best_score:
				best_score = score
				best = id
		c.allocate_passive(best)
	# Equipment (explicit bases so the requirements fit a strength character).
	for slot: String in c.EQUIP_SLOTS:
		var old := c.unequip(slot)
		if old != null:
			pass
	var R := Item.Rarity
	_equip(c, ItemDB.create_item("sword_3", R.RARE, LEVEL), "main_hand")
	_equip(c, ItemDB.create_unique("bulwark_of_the_fallen", LEVEL), "off_hand")
	_equip(c, ItemDB.create_item("helmet_str_3", R.RARE, LEVEL), "helmet")
	_equip(c, ItemDB.create_item("body_str_3", R.MAGIC, LEVEL), "body")
	_equip(c, ItemDB.create_item("gloves_str_2", R.RARE, LEVEL), "gloves")
	_equip(c, ItemDB.create_item("boots_str_3", R.MAGIC, LEVEL), "boots")
	_equip(c, ItemDB.create_item("amulet_3", R.RARE, LEVEL), "amulet")
	_equip(c, ItemDB.create_item("ring_3", R.MAGIC, LEVEL), "ring_1")
	_equip(c, ItemDB.create_unique("voidheart_ring", LEVEL), "ring_2")
	_equip(c, ItemDB.create_item("belt_3", R.RARE, LEVEL), "belt")
	# Inventory: a spread of rarities and slots, with a few uniques.
	for i in c.inventory.size():
		c.put_in_inventory(i, null)
	var inv: Array = [
		ItemDB.create_item("body_str_4", R.RARE, LEVEL),
		ItemDB.create_item("helmet_str_3", R.RARE, LEVEL),
		ItemDB.create_unique("emberheart", LEVEL),
		ItemDB.create_item("greataxe_3", R.RARE, LEVEL),
		ItemDB.create_item("bow_3", R.MAGIC, LEVEL),
		ItemDB.create_unique("stormcrown", LEVEL),
		ItemDB.create_item("gloves_str_dex_3", R.MAGIC, LEVEL),
		ItemDB.create_item("ring_3", R.RARE, LEVEL),
		ItemDB.create_unique("windshear", LEVEL),
		ItemDB.create_item("wand_3", R.NORMAL, LEVEL),
		ItemDB.create_item("boots_dex_3", R.RARE, LEVEL),
		ItemDB.create_item("amulet_3", R.MAGIC, LEVEL),
		ItemDB.create_item("shield_str_4", R.RARE, 40),
		ItemDB.create_item("maul_4", R.NORMAL, LEVEL),
	]
	for k in 26:
		inv.append(ItemDB.generate_random_item(randi_range(18, 30), [R.NORMAL, R.MAGIC, R.MAGIC, R.RARE][k % 4]))
	for k in inv.size():
		# Leave a few gaps so the grid looks lived-in.
		var idx := k + int(k / 9)
		if idx < c.inventory.size():
			c.put_in_inventory(idx, inv[k])
	# Stash.
	for k in 58:
		var rar: int = [R.NORMAL, R.MAGIC, R.MAGIC, R.RARE, R.RARE][k % 5]
		c.put_in_stash(k, ItemDB.generate_random_item(randi_range(8, 30), rar))
	c.put_in_stash(60, ItemDB.create_unique("glasswork_amulet", LEVEL))
	c.put_in_stash(61, ItemDB.create_unique("the_arbalest", LEVEL))
	c.put_in_stash(62, ItemDB.create_unique("seraphs_cord", LEVEL))
	# Vendor stock + a few sold items in the buyback.
	GameState.vendor_stock = ItemDB.generate_vendor_stock(LEVEL)
	InvActions.sync_buyback()
	for k in 3:
		var it := ItemDB.generate_random_item(LEVEL - 4, [R.NORMAL, R.MAGIC, R.NORMAL][k])
		c.add_to_inventory(it)
		InvActions.sell(InvActions.payload_for(it))


func _equip(c: CharacterData, it: Item, slot: String) -> void:
	var back := c.equip(it, slot)
	for d: Item in back:
		if d != it:
			c.add_to_inventory(d)


# ------------------------------------------------------------------ hover helpers

## Synthesise a mouse motion over `ctrl` (real GUI hover: highlight + tooltip).
func _hover(ctrl: Control) -> void:
	if ctrl == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = ctrl.get_global_rect().get_center()
	ev.global_position = ev.position
	get_viewport().push_input(ev, true)
	await _settle(2)
	if ctrl is InvSlot and not (ctrl as InvSlot).is_hovered():
		(ctrl as InvSlot).show_tooltip()


func _clear_hover() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(960, 540)
	ev.global_position = ev.position
	get_viewport().push_input(ev, true)


func _find_inventory(pred: Callable) -> int:
	var c := GameState.character
	for i in c.inventory.size():
		var it: Item = c.inventory[i]
		if it != null and pred.call(it):
			return i
	return -1


# ------------------------------------------------------------------ shots

func _shot_inventory_compare() -> void:
	UI.open_panel("inventory", {})
	await _settle(3)
	var inv := UI.get_panel("inventory") as InventoryPanel
	var idx := _find_inventory(func(it: Item) -> bool: return it.base_id == "body_str_4")
	await _hover(inv.get_grid_slot(idx))


func _shot_inventory_unique() -> void:
	UI.open_panel("inventory", {})
	await _settle(3)
	var inv := UI.get_panel("inventory") as InventoryPanel
	var idx := _find_inventory(func(it: Item) -> bool: return it.unique_id == "stormcrown")
	await _hover(inv.get_grid_slot(idx))


func _set_alt(on: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ALT
	ev.physical_keycode = KEY_ALT
	ev.pressed = on
	Input.parse_input_event(ev)
	_alt_held = on


func _shot_inventory_twohand_alt() -> void:
	var c := GameState.character
	var idx := _find_inventory(func(it: Item) -> bool: return it.base_id == "greataxe_3")
	if idx >= 0:
		c.equip_from_inventory(idx, "main_hand")
	UI.open_panel("inventory", {})
	await _settle(3)
	var inv := UI.get_panel("inventory") as InventoryPanel
	var ring := _find_inventory(func(it: Item) -> bool: return it.get_slot_type() == "ring" and it.rarity == Item.Rarity.RARE)
	_set_alt(true)
	await _settle(2)
	await _hover(inv.get_grid_slot(ring))


func _shot_character() -> void:
	UI.open_panel("inventory", {})
	UI.open_panel("character", {})
	await _settle(3)
	var cp := UI.get_panel("character") as CharacterPanel
	await _hover(cp.get_row("armour"))


func _shot_character_dungeon() -> void:
	GameState.current_area = {"id": "dungeon", "depth": 18, "level": 18, "theme": "inferno", "name": "Depth 18"}
	UI.open_panel("character", {})
	await _settle(3)
	var cp := UI.get_panel("character") as CharacterPanel
	cp.refresh()
	var rows := cp.get_skill_rows()
	if not rows.is_empty():
		await _hover(rows[0])


func _shot_vendor_trade() -> void:
	UI.open_panel("vendor", {})
	await _settle(3)
	var vp := UI.get_panel("vendor") as VendorPanel
	vp.set_tab("trade")
	var pick := 0
	for i in GameState.vendor_stock.size():
		if (GameState.vendor_stock[i] as Item).rarity >= Item.Rarity.MAGIC and (GameState.vendor_stock[i] as Item).is_weapon():
			pick = i
			break
	await _hover(vp.get_stock_slot(pick))


func _shot_vendor_sell_confirm() -> void:
	UI.open_panel("vendor", {})
	await _settle(3)
	var vp := UI.get_panel("vendor") as VendorPanel
	var idx := _find_inventory(func(it: Item) -> bool: return it.rarity == Item.Rarity.RARE)
	vp.request_sell(InvActions.make_payload(GameState.character.inventory[idx], "inventory", idx))


## A rare `base` with 6 affixes (the tallest crafting preview).
func _rare6(base: String) -> Item:
	var best: Item = null
	for k in 400:
		var it := ItemDB.create_item(base, Item.Rarity.RARE, LEVEL)
		if best == null or it.affixes.size() > best.affixes.size():
			best = it
		if best.affixes.size() >= 6:
			break
	return best


## A 6-affix rare staff on the bench (fits without scrolling), hovering the bench slot.
func _shot_vendor_craft_bench() -> void:
	UI.open_panel("vendor", {})
	await _settle(3)
	var vp := UI.get_panel("vendor") as VendorPanel
	var it := _rare6("staff_4")
	GameState.character.add_to_inventory(it)
	vp.select_for_craft(it)
	await _settle(3)
	await _hover(vp.get_bench_slot())


## Reroll a 6-affix rare greataxe: the Before / After pair scrolls inside the frame.
func _shot_vendor_craft() -> void:
	UI.open_panel("vendor", {})
	await _settle(3)
	var vp := UI.get_panel("vendor") as VendorPanel
	var it := _rare6("greataxe_4")
	GameState.character.add_to_inventory(it)
	vp.select_for_craft(it)
	for k in 30:
		vp.craft("reroll")
		if it.affixes.size() >= 5:
			break
	await _settle(3)
	await _hover(vp.get_service_button("reroll"))


## The character sheet opened at the vendor docks beside it.
func _shot_vendor_character() -> void:
	UI.open_panel("vendor", {})
	UI.open_panel("character", {})
	await _settle(4)


func _shot_stash() -> void:
	UI.open_panel("stash", {})
	await _settle(3)
	var sp := UI.get_panel("stash") as StashPanel
	await _hover(sp.get_slot(60))


func _shot_stash_drag() -> void:
	UI.open_panel("stash", {})
	await _settle(3)
	var sp := UI.get_panel("stash") as StashPanel
	var inv := UI.get_panel("inventory") as InventoryPanel
	# Start a real drag from a stash cell and hold it over the paper doll's helmet slot.
	var from := sp.get_slot(3)
	var to := inv.get_equip_slot("helmet")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from.get_global_rect().get_center()
	press.global_position = press.position
	get_viewport().push_input(press, true)
	await _settle(1)
	var last := press.position
	for k in 6:
		var mv := InputEventMouseMotion.new()
		mv.position = press.position.lerp(to.get_global_rect().get_center(), float(k + 1) / 6.0)
		mv.global_position = mv.position
		# The GUI starts a drag from the accumulated *relative* motion.
		mv.relative = mv.position - last
		last = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(mv, true)
		await _settle(1)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	# Released over the inventory frame's title bar: nothing happens (no drop target).
	rel.position = inv.get_frame().get_global_rect().position + Vector2(30, 20)
	rel.global_position = rel.position
	_release = rel
