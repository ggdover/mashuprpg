extends RefCounted
## Debug key actions of the game flow (§15, debug builds only; Main routes F9-F12 here):
##   F9  level up            F10 spawn 6 random items around the player
##   F11 toggle god mode     F12 screenshot -> user://screenshots/ (skipped headless)
## OWNER: flow (wave 2).

const SCREENSHOT_DIR := "user://screenshots/"
const LOOT_COUNT := 6
## Rarity bonus of debug loot (more magic / rare items to look at).
const LOOT_RARITY_BONUS := 150.0


## One level up for the current character (no-op at the level cap). Returns the new level.
static func level_up() -> int:
	var c := GameState.character
	if c == null:
		return 0
	if c.is_max_level():
		Events.notify.emit("Already at the level cap", UIStyle.COLOR_TEXT_DIM)
		return c.level
	c.add_xp(maxi(1, c.xp_to_next() - c.xp))
	return c.level


## Spawn LOOT_COUNT random items (item level = area level or character level, whichever is
## higher) scattered around the player. Returns the items.
static func spawn_loot() -> Array:
	var p: Variant = GameState.player
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		return []
	var c := GameState.character
	var ilvl := int(GameState.current_area.get("level", 1))
	if c != null:
		ilvl = maxi(ilvl, c.level)
	var drops: Array = []
	var items: Array = []
	for i in LOOT_COUNT:
		var it: Item = ItemDB.generate_random_item(ilvl, -1, "", LOOT_RARITY_BONUS)
		if it != null:
			items.append(it)
			drops.append({"type": "item", "item": it})
	LootSystem.spawn_drops(drops, (p as Node3D).global_position)
	return items


## Toggle god mode on the live player. Returns the new state.
static func toggle_god_mode() -> bool:
	var p: Variant = GameState.player
	if not is_instance_valid(p):
		return false
	var pl := p as Actor
	pl.god_mode = not pl.god_mode
	Events.notify.emit("God mode %s" % ("ON" if pl.god_mode else "OFF"), UIStyle.COLOR_GOLD if pl.god_mode else UIStyle.COLOR_TEXT_DIM)
	return pl.god_mode


## Save the current frame as a PNG in SCREENSHOT_DIR (after the frame is drawn). Returns the path,
## "" when headless or on failure.
static func screenshot(vp: Viewport) -> String:
	if DisplayServer.get_name() == "headless":
		push_warning("Screenshot skipped: running headless")
		return ""
	if vp == null:
		return ""
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("Screenshot: empty viewport image")
		return ""
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var dt := Time.get_datetime_dict_from_system()
	var file := "shot_%04d%02d%02d_%02d%02d%02d_%03d.png" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"], Time.get_ticks_msec() % 1000]
	var path := SCREENSHOT_DIR.path_join(file)
	var err := img.save_png(path)
	if err != OK:
		push_warning("Screenshot: can't write %s (%s)" % [path, error_string(err)])
		return ""
	Events.notify.emit("Screenshot saved", UIStyle.COLOR_TEXT_DIM)
	print("Screenshot: ", ProjectSettings.globalize_path(path))
	return path
