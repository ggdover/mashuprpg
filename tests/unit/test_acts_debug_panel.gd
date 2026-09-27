extends TestCase
## The F1 debug menu through the real Main node: zone list (every zone, "you are here"), travel,
## teleport points (start, services, boss, next pack), cheats (level, gold, god mode, far camera,
## kill boss, remove monsters, monsters off for dungeons). OWNER: acts framework.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_debug_panel/"

var main: Main = null
var _old_options: Dictionary = {}


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
	_old_options = GameState.act_options.duplicate()
	var m: Main = Main.new()
	m.auto_boot = false
	m.use_fade = false
	m.show_titles = false
	add_child(m)
	main = m
	return m


func _exit_tree() -> void:
	UI.close_all_panels()
	UI.show_hud(false)
	GameState.save_dir = GameState.SAVE_DIR
	if not _old_options.is_empty():
		GameState.act_options = _old_options


func _await_change(m: Main) -> Dictionary:
	if not m.is_changing():
		return GameState.current_area
	var info: Dictionary = await m.area_change_finished
	await get_tree().physics_frame
	return info


func _open() -> DebugPanel:
	UI.open_panel("debug", {})
	return UI.get_panel("debug") as DebugPanel


func _labels(panel: DebugPanel) -> Array:
	var out: Array = []
	for e in panel.teleport_entries:
		out.append(String(e["label"]))
	return out


func test_debug_menu() -> void:
	var m := _make_main()
	GameState.act_options = {"level_mode": "custom", "level": 5, "monsters": true}
	assert_true(m.start_new_game("Debug Tester", "warrior"), "new game")
	await _await_change(m)
	var panel := _open()
	assert_not_null(panel, "debug panel")
	assert_true(UI.is_panel_open("debug"), "open")
	# Every zone is listed.
	for key in ["town", "dungeon:1", "dungeon:4", "dungeon:7", "dungeon:any"]:
		assert_true(panel.zone_buttons.has(key), "zone %s listed" % key)
	for act in ActDefs.ACT_ORDER:
		for zone in ActDefs.region_ids(act):
			assert_true(panel.zone_buttons.has("act:%s:%s" % [act, zone]), "%s %s listed" % [act, zone])
		assert_true(panel.zone_buttons.has("act_dungeon:%s" % act), "%s dungeon listed" % act)
	# Teleport points in town.
	var labels := _labels(panel)
	assert_has(labels, "Start", "start")
	assert_has(labels, "Merchant", "merchant")
	assert_has(labels, "Stash", "stash")
	# Teleport to the stash.
	var w := GameState.world
	var stash_pos: Vector3 = Vector3.ZERO
	for pt in panel.get_teleport_points():
		if String(pt["label"]) == "Stash":
			stash_pos = pt["pos"]
	assert_true(panel.teleport_to(stash_pos), "teleport")
	assert_true(CombatQuery.distance_xz(GameState.player.global_position, stash_pos) < 2.5, "next to the stash")
	assert_true(w.is_walkable(GameState.player.global_position), "on walkable ground")
	# Cheats.
	var lvl := GameState.character.level
	panel.level_up(2)
	assert_eq(GameState.character.level, lvl + 2, "level up x2")
	var gold := GameState.character.gold
	panel.add_gold(1000)
	assert_eq(GameState.character.gold, gold + 1000, "gold")
	panel.set_god_mode(true)
	assert_true(GameState.player.god_mode, "god mode on")
	panel.toggle_far_camera()
	assert_true(GameState.player.camera_rig.zoom_target > CameraRig.MAX_DISTANCE, "far camera")
	panel.toggle_far_camera()
	assert_near(GameState.player.camera_rig.zoom_target, CameraRig.DEFAULT_DISTANCE, 0.01, "normal camera")

	# Travel to the forest's outskirts from the list.
	assert_true(panel.travel("act", "forest", "outskirts"), "travel")
	await _await_change(m)
	var w2 := GameState.world
	assert_true(w2.is_act_wilds(), "in the forest outskirts")
	assert_true(GameState.player.god_mode, "god mode carried over")
	panel = _open()
	assert_eq(panel.zone_buttons["act:forest:outskirts"].get_child(0).text, "you are here", "current zone marked")
	labels = _labels(panel)
	assert_has(labels, "Next monster pack", "pack teleport")
	for r in w2.get_regions():
		var tagged := false
		for l in labels:
			if String(l).begins_with(String(r["name"]) + " ("):
				tagged = true
		assert_true(tagged, "teleport to %s" % r["name"])
	var boss_pt := {}
	for pt in panel.get_teleport_points():
		if String(pt["label"]).begins_with("Boss: "):
			boss_pt = pt
	assert_false(boss_pt.is_empty(), "boss teleport (the zone boss, not spawned yet)")
	var before := GameState.player.global_position
	assert_true(panel.teleport_to_next_pack(), "teleported to a pack")
	assert_true(CombatQuery.distance_xz(before, GameState.player.global_position) > 5.0, "moved")
	# At the zone boss: it spawns when the player comes near; killing it clears its zone.
	panel.teleport_to(boss_pt["pos"])
	w2.lazy_spawn_tick(true)
	assert_true(panel.kill_boss(), "zone boss killed")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(w2.cleared_regions.has(String(ActDefs.dungeon("forest")["region"])), "its zone is cleared")
	assert_true(panel.remove_monsters() > 0, "monsters removed")
	await get_tree().process_frame
	assert_eq(EnemyDB.get_enemies(w2).size(), 0, "none left")
	assert_eq(w2.pending_spawn_count(), 0, "and none will come")

	# Monsters off also applies to dungeons.
	panel.set_monsters(false)
	assert_true(panel.travel("dungeon", 3), "to depth 3")
	await _await_change(m)
	assert_true(GameState.world.is_dungeon(), "in the dungeon")
	assert_eq(int(GameState.current_area.get("depth", 0)), 3, "depth 3")
	assert_eq(EnemyDB.get_enemies(GameState.world).size(), 0, "monsters off: empty dungeon")
	panel = _open()
	assert_has(_labels(panel), "Boss room", "boss room teleport")
	assert_true(panel.travel("town"), "back to town")
	await _await_change(m)
	assert_true(GameState.world.is_town(), "in Emberfall")
