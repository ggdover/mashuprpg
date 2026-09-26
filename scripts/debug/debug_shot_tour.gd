extends Node
## Screenshot tour (§15): `-- --shots=DIR` (needs a real window: GTEST_WINDOWED=1; headless runs
## skip with a warning). Main creates it instead of showing the menu. It plays through the real
## flow and saves PNGs into DIR (relative paths are resolved against $GTEST_REPO, else the
## project folder):
##   01 main menu (with a few saved characters)   02 new character
##   03 town (area title card)                     04 vendor + inventory
##   05 stash + inventory                          06 waypoint
##   07-09 a dungeon fight with skill effects      10 loot on the ground
##   11 inventory with an item tooltip             12 character sheet
##   13 passive tree                               14 skill book (+ skill tooltip)
##   15 boss fight                                 16 death screen
##   17 town with the return portal                18 pause menu
## The character is boosted (level, gear, passives, skills — the autoplay bot's logic) so the
## screens show a mid-game build. Quits when done. OWNER: flow (wave 2).
##
##   GTEST_FULL=1 GTEST_WINDOWED=1 tools/gtest.sh flow-tour res://scenes/main.tscn -- --shots=docs/screenshots/flow

const DebugBotGear := preload("res://scripts/debug/debug_bot_gear.gd")
const DebugBotBuild := preload("res://scripts/debug/debug_bot_build.gd")

const SAVE_DIR := "user://tour_saves/"
const CLASS_ID := "sorcerer"
const LEVEL := 16
const DEPTH := 8

## Set by Main before _ready.
var main: Node = null
var config: Dictionary = {}

var out_dir := ""
var count := 0
var gear: DebugBotGear = null
var build: DebugBotBuild = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("Screenshot tour needs a window (GTEST_WINDOWED=1); skipping")
		get_tree().quit.call_deferred(0)
		return
	# Safety net: never leave a window open.
	get_tree().create_timer(170.0, true).timeout.connect(get_tree().quit)
	out_dir = _resolve_dir(String(config.get("shots", "")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.save_dir = SAVE_DIR
	_run.call_deferred()


func _exit_tree() -> void:
	if gear != null:
		gear.dispose()


static func _resolve_dir(d: String) -> String:
	var dir := d if d != "" else "docs/screenshots/flow"
	if dir.begins_with("/") or dir.begins_with("user://") or dir.begins_with("res://"):
		return dir if not dir.begins_with("res://") else ProjectSettings.globalize_path(dir)
	var repo := OS.get_environment("GTEST_REPO")
	var root := repo if repo != "" else ProjectSettings.globalize_path("res://")
	return root.path_join(dir)


# ------------------------------------------------------------------ the tour

func _run() -> void:
	print("[tour] saving screenshots to ", out_dir)
	_clear_saves()
	_make_saves()
	# 01 / 02 — title screen.
	main.call("show_main_menu")
	await _wait(1.6)
	var menu := UI.get_panel("main_menu")
	if menu != null and menu.has_method("refresh_saves"):
		menu.call("refresh_saves")
		if menu.has_method("show_list_view"):
			menu.call("show_list_view")
		await _wait(0.6)
	await _shot("01_main_menu")
	if menu != null and menu.has_method("show_create_view"):
		menu.call("show_create_view")
		if menu.has_method("set_character_name"):
			menu.call("set_character_name", "Morwen")
		if menu.has_method("select_class"):
			menu.call("select_class", CLASS_ID)
		await _wait(0.8)
	await _shot("02_new_character")

	# 03 — into town. The new character is boosted while the screen fades out (before the
	# player exists), so the town opens on a mid-game hero without level-up fanfare.
	if menu != null and menu.has_method("begin_new_game"):
		menu.call("begin_new_game")
	else:
		Events.new_game_requested.emit("Morwen", CLASS_ID)
	_boost()
	await _await_area()
	await _wait(0.9)
	await _shot("03_town")
	await _wait(2.0)

	# 04 — vendor.
	var p := _player()
	var w := GameState.world
	var merchant := _find(w, "WorldVendorNpc")
	if merchant != null:
		await _walk_near(merchant)
		merchant.interact(p)
		await _wait(0.9)
		await _shot("04_vendor")
		UI.close_all_panels()
	# 05 — stash.
	var stash := _find(w, "WorldStashChest")
	if stash != null:
		_fill_stash()
		await _walk_near(stash)
		stash.interact(_player())
		await _wait(0.9)
		await _shot("05_stash")
		UI.close_all_panels()
	# 06 — waypoint.
	var gate := _find(w, "WorldWaypointGate")
	if gate != null:
		await _walk_near(gate)
		gate.interact(_player())
		await _wait(0.9)
		var wp := UI.get_panel("waypoint")
		if wp != null and wp.has_method("preview_tooltip"):
			wp.call("preview_tooltip", DEPTH)
			await _wait(0.3)
		await _shot("06_waypoint")
		UI.close_all_panels()

	# 07-09 — a dungeon fight.
	main.call("request_area_change", "dungeon", {"depth": DEPTH, "seed": 20260926})
	await _await_area()
	p = _player()
	p.god_mode = true
	# Let the HUD's area banner (~3.5 s) fade before the fight shots.
	await _wait(3.2)
	await _fight_pack()
	# 10 — loot on the ground.
	await _loot_scene()
	# 11 — inventory + tooltip.
	await _inventory_tooltip()
	# 12 — character sheet.
	UI.close_all_panels()
	UI.open_panel("character", {})
	await _wait(0.8)
	await _shot("12_character_sheet")
	UI.close_all_panels()
	# 13 — passive tree.
	UI.open_panel("passives", {})
	await _wait(1.0)
	var tree := UI.get_panel("passives")
	if tree != null and tree.has_method("hover_node"):
		var c := GameState.character
		var alloc := TreeDB.get_allocatable(c.allocated_passives, c.class_id)
		if not alloc.is_empty():
			tree.call("hover_node", int(alloc[0]))
			await _wait(0.4)
	await _shot("13_passive_tree")
	UI.close_all_panels()
	# 14 — skill book.
	UI.open_panel("skills", {})
	await _wait(0.8)
	var sb := UI.get_panel("skills")
	if sb != null and sb.has_method("preview_tooltip"):
		sb.call("preview_tooltip", "chain_lightning")
		await _wait(0.3)
	await _shot("14_skill_book")
	UI.close_all_panels()
	# 15 — the boss.
	await _boss_fight()
	# 16 — death.
	p = _player()
	if p != null:
		p.god_mode = false
		p.invulnerable_time = 0.0
		p.take_damage(p.max_life * 20.0 + p.max_es * 20.0 + 5000.0, "fire")
		await _wait(1.5 + 1.9)
		await _shot("16_death_screen")
		var d := UI.get_panel("death")
		if d != null and d.has_method("respawn"):
			d.call("respawn")
		else:
			Events.respawn_requested.emit()
		await _await_area()
		await _wait(2.8)
		# 17 — town with the portal back into the kept dungeon.
		var rp := _find_portal(GameState.world, "return")
		if rp != null:
			await _walk_near(rp, 5.0)
			await _wait(0.4)
		await _shot("17_town_return_portal")
	# 18 — pause menu.
	UI.open_panel("pause", {})
	await _wait(0.8)
	await _shot("18_pause_menu")
	UI.close_all_panels()
	print("[tour] done: %d screenshots in %s" % [count, out_dir])
	get_tree().quit(0)


# ------------------------------------------------------------------ scenes

func _fight_pack() -> void:
	var w := GameState.world
	var p := _player()
	if w == null or p == null:
		return
	# The nearest pack of several monsters away from the start.
	var start := p.global_position
	var best: Enemy = null
	var best_score := -INF
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			continue
		var n := 0
		for o in EnemyDB.get_enemies(w):
			if CombatQuery.distance_xz(o.global_position, e.global_position) < 5.0:
				n += 1
		var d := CombatQuery.distance_xz(start, e.global_position)
		var s := float(n) * 10.0 - d * 0.3 + (8.0 if e.rarity >= 1 else 0.0)
		if s > best_score:
			best_score = s
			best = e
	if best == null:
		return
	var center := best.global_position
	var spot := _stand_spot(w, center, 7.5)
	_teleport(spot)
	await _wait(0.5)
	for e in EnemyDB.get_enemies(w):
		if CombatQuery.distance_xz(e.global_position, center) < 9.0:
			e.aggro(p, false)
	var bar := GameState.character.skill_bar
	var order := ["meteor", "fireball", "chain_lightning", "frost_nova", "spark", "ice_spear"]
	var shots := 0
	for sid in order:
		var slot := bar.find(sid)
		if slot < 0:
			continue
		var tgt := _nearest_enemy(p)
		if tgt == null:
			break
		p.refill_pools()
		p.ai_aim(tgt.global_position, tgt)
		p.ai_hold_skill(slot, true)
		await _wait(0.45 if sid != "meteor" else 1.05)
		p.ai_hold_skill(slot, false)
		if shots < 3:
			await _shot("%02d_dungeon_fight_%s" % [7 + shots, sid])
			shots += 1
		await _wait(0.35)
	p.ai_release_all()


func _loot_scene() -> void:
	var p := _player()
	if p == null:
		return
	# Clear the fight so the loot stands out.
	for e in EnemyDB.get_enemies(GameState.world):
		if not e.is_boss and CombatQuery.distance_xz(e.global_position, p.global_position) < 14.0:
			e.die(p)
	await _wait(0.6)
	var drops: Array = []
	var lvl := int(GameState.current_area.get("level", DEPTH))
	for r in [Item.Rarity.UNIQUE, Item.Rarity.RARE, Item.Rarity.RARE, Item.Rarity.MAGIC, Item.Rarity.MAGIC, Item.Rarity.NORMAL]:
		var it: Item = ItemDB.generate_random_item(lvl, r)
		if it != null:
			drops.append({"type": "item", "item": it})
	drops.append({"type": "gold", "amount": 57})
	LootSystem.spawn_drops(drops, p.global_position + Vector3(0, 0, -3.0))
	await _wait(1.6)
	await _shot("10_loot")


func _inventory_tooltip() -> void:
	UI.close_all_panels()
	UI.open_panel("inventory", {})
	await _wait(0.8)
	var inv := UI.get_panel("inventory")
	var c := GameState.character
	var shown := false
	if inv != null and inv.has_method("get_grid_slot"):
		for i in c.inventory.size():
			var it: Item = c.inventory[i]
			if it == null or it.rarity < Item.Rarity.RARE:
				continue
			var slot: Control = inv.call("get_grid_slot", i)
			if slot == null:
				continue
			var ev := InputEventMouseMotion.new()
			ev.position = slot.get_global_rect().get_center()
			ev.global_position = ev.position
			get_viewport().push_input(ev, true)
			await _wait(0.5)
			shown = true
			break
	if not shown:
		for it in c.inventory:
			if it != null:
				UI.show_tooltip((it as Item).get_tooltip_lines(c.compute_attributes()), Rect2(Vector2(1100, 300), Vector2(60, 60)))
				break
		await _wait(0.3)
	await _shot("11_inventory_tooltip")
	UI.hide_tooltip()


func _boss_fight() -> void:
	var w := GameState.world
	var p := _player()
	if w == null or p == null:
		return
	var boss: Enemy = null
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			boss = e
	if boss == null:
		return
	p.god_mode = true
	var spot := _stand_spot(w, boss.global_position, 8.0)
	_teleport(spot)
	await _wait(0.4)
	boss.aggro(p, true)
	await _wait(1.8)
	var slot := GameState.character.skill_bar.find("fireball")
	if slot < 0:
		slot = 0
	p.ai_aim(boss.global_position, boss)
	p.ai_hold_skill(slot, true)
	await _wait(1.6)
	await _shot("15_boss_fight")
	p.ai_release_all()


# ------------------------------------------------------------------ setup

## A few saved characters for the title screen.
func _make_saves() -> void:
	var defs := [["Aelric", "warrior", 14, 9], ["Sylwen", "ranger", 7, 4], ["Thorne", "warrior", 3, 2]]
	for d in defs:
		var c := GameState.new_character(String(d[0]), String(d[1]))
		while c.level < int(d[2]):
			c.add_xp(c.xp_to_next() - c.xp)
		c.max_depth = int(d[3])
		c.add_gold(int(d[2]) * 137)
		GameState.save_game()
	GameState.character = null
	GameState.save_id = ""


func _clear_saves() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for f in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR.path_join(f))


## Level, gear, passives and skills of a mid-game character (the autoplay bot's logic). Works
## without a live player (the evaluation stand-in resolves the skills).
func _boost() -> void:
	var c := GameState.character
	if c == null:
		return
	gear = DebugBotGear.new(c.class_id)
	build = DebugBotBuild.new(gear.eval, c.class_id)
	while c.level < LEVEL:
		c.add_xp(c.xp_to_next() - c.xp)
	c.max_depth = DEPTH + 1
	for dd in range(1, DEPTH + 1):
		c.mark_depth_cleared(dd)
	c.add_gold(4321)
	for it in gear.boost_items(LEVEL):
		c.add_to_inventory(it)
	for k in 12:
		var up := gear.best_upgrade(c)
		if up.is_empty():
			break
		c.equip_from_inventory(int(up["index"]), String(up["slot"]))
	var guard := 0
	while c.passive_points_unspent() > 0 and guard < 60:
		var id := build.next_passive(c)
		if id < 0 or not c.allocate_passive(id):
			break
		guard += 1
	gear.eval.configure(c, c.equipment)
	build.apply_bar(c, gear.eval)
	# Some extra loot to look at in the inventory.
	for r in [Item.Rarity.RARE, Item.Rarity.UNIQUE, Item.Rarity.MAGIC, Item.Rarity.MAGIC, Item.Rarity.NORMAL]:
		var it: Item = ItemDB.generate_random_item(LEVEL, r)
		if it != null:
			c.add_to_inventory(it)
	GameState.save_game()


func _fill_stash() -> void:
	var c := GameState.character
	for k in 14:
		var it: Item = ItemDB.generate_random_item(randi_range(1, LEVEL), -1, "", 120.0)
		if it != null:
			c.add_to_stash(it)


# ------------------------------------------------------------------ helpers

func _player() -> Player:
	var p: Variant = GameState.player
	return p as Player if p != null and is_instance_valid(p) else null


func _find(w: World, cls: String) -> Interactable:
	if w == null:
		return null
	for n in w.get_interactables():
		var s: Script = (n as Node).get_script()
		if s != null and s.get_global_name() == cls:
			return n
	return null


func _find_portal(w: World, destination: String) -> WorldPortal:
	if w == null:
		return null
	for n in w.get_interactables():
		if n is WorldPortal and (n as WorldPortal).destination == destination:
			return n
	return null


func _nearest_enemy(p: Player) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in EnemyDB.get_enemies(GameState.world):
		var d := CombatQuery.distance_xz(p.global_position, e.global_position)
		if d < bd and d < 20.0:
			bd = d
			best = e
	return best


## A walkable spot about `dist` from `center` with line of sight to it, preferably south of it
## (the action up-screen) and in open floor (away from the map edge).
func _stand_spot(w: World, center: Vector3, dist: float) -> Vector3:
	var best := w.get_nearest_walkable(center + Vector3(0, 0, dist))
	var best_score := -INF
	for k in 16:
		var a := TAU * float(k) / 16.0
		var cand := w.get_nearest_walkable(center + Vector3(sin(a), 0, cos(a)) * dist)
		if not w.has_line_of_sight(cand, center) or CombatQuery.distance_xz(cand, center) < dist * 0.6:
			continue
		var open := 0
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if w.is_walkable(cand + Vector3(dx * 2.0, 0, dz * 2.0)):
					open += 1
		var score := float(open) + 6.0 * cos(a)
		if score > best_score:
			best_score = score
			best = cand
	return best


func _teleport(pos: Vector3) -> void:
	var p := _player()
	if p == null:
		return
	p.global_position = pos
	if p.camera_rig != null and is_instance_valid(p.camera_rig):
		p.camera_rig.snap_to_target()
	if is_instance_valid(GameState.world):
		GameState.world.snap_light_pool()
	EnemyDB.apply_sleep(pos)


## Walk (auto-walk, like a click) to within `dist` of an interactable; teleports if it takes long.
func _walk_near(target: Interactable, dist: float = 3.0) -> void:
	var p := _player()
	if p == null or target == null:
		return
	var goal := target.get_interact_position()
	var t := 0.0
	var path := GameState.world.find_path(p.global_position, goal)
	var i := 0
	while t < 6.0 and i < path.size():
		p = _player()
		if p == null:
			return
		var to := path[i] - p.global_position
		to.y = 0.0
		if CombatQuery.distance_xz(p.global_position, goal) <= dist:
			break
		if to.length() < 0.5:
			i += 1
			continue
		p.ai_move(to.normalized())
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p = _player()
	if p != null:
		p.ai_move(Vector3.ZERO)
		if CombatQuery.distance_xz(p.global_position, goal) > dist + 1.0:
			_teleport(GameState.world.get_nearest_walkable(goal))
	await _wait(0.2)


func _await_area() -> void:
	var t := 0.0
	while t < 10.0 and not bool(main.call("is_changing")):
		await get_tree().process_frame
		t += get_process_delta_time()
	if bool(main.call("is_changing")):
		await main.area_change_finished
	await _wait(0.8)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	if err == OK:
		count += 1
		print("[tour] ", path)
	else:
		push_warning("tour: can't save %s (%s)" % [path, error_string(err)])
