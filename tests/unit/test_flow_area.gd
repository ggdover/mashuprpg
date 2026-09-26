extends TestCase
## Game flow: the §15 area change sequence through the real Main node (town -> dungeon -> town
## portal -> return -> boss kill -> next depth), pool ratios, town services, guarded requests.
## OWNER: flow.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_flow_area/"

var main: Main = null


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
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


func _await_change(m: Main) -> Dictionary:
	if not m.is_changing():
		return GameState.current_area
	var info: Dictionary = await m.area_change_finished
	await get_tree().physics_frame
	return info


func _find_portal(w: World, destination: String) -> WorldPortal:
	for n in w.get_interactables():
		if n is WorldPortal and (n as WorldPortal).destination == destination:
			return n
	return null


func _boss_of(w: World) -> Enemy:
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			return e
	return null


func test_full_sequence() -> void:
	var m := _make_main()
	assert_true(m.start_new_game("Flow Tester", "warrior"), "new game starts")
	assert_true(m.is_changing(), "change running")
	await _await_change(m)
	var c := GameState.character
	assert_not_null(c, "character")
	assert_eq(String(GameState.current_area.get("id", "")), "town", "in town")
	assert_true(is_instance_valid(GameState.world) and GameState.world.is_town(), "town world")
	assert_true(GameState.world.is_inside_tree(), "town in tree")
	var p := GameState.player
	assert_true(is_instance_valid(p) and p.is_inside_tree(), "player spawned")
	assert_eq(p.get_parent(), GameState.world, "player is a child of the world")
	assert_true(is_instance_valid(p.camera_rig) and p.camera_rig.get_parent() == GameState.world, "rig in world")
	assert_true(GameState.vendor_stock.size() > 0, "vendor stock built")
	assert_near(c.get_potion_charges("life"), Balance.POTION_MAX_CHARGES, 0.001, "potions full")
	assert_true(GameState.has_save(GameState.save_id), "saved on new game")
	assert_eq(m.changes_done, 1, "one change")

	# Town -> depth 2.
	Events.area_change_requested.emit("dungeon", {"depth": 2, "seed": 4242})
	assert_true(m.is_changing(), "dungeon change running")
	var info := await _await_change(m)
	var dw := GameState.world
	assert_true(dw.is_dungeon(), "dungeon world")
	assert_eq(int(info.get("depth", 0)), 2, "depth 2")
	assert_eq(int(GameState.current_area.get("level", 0)), Balance.area_level_for_depth(2), "area level")
	assert_eq(int(info.get("seed", 0)), 4242, "seed passed through")
	assert_eq(String(info.get("theme", "")), World.theme_for_depth(2), "theme")
	assert_true(String(info.get("name", "")).begins_with("Depth 2"), "name")
	assert_true(EnemyDB.get_enemies(dw).size() > 10, "dungeon populated")
	assert_not_null(_boss_of(dw), "boss spawned")
	p = GameState.player
	assert_true(CombatQuery.distance_xz(p.global_position, dw.get_player_start()) < 0.5, "player at the start")
	assert_eq(get_tree().get_nodes_in_group("world").size(), 1, "only one world in the tree")

	# Town portal from a spot in the dungeon: the dungeon is kept, detached.
	var spot := dw.get_nearest_walkable(dw.get_player_start() + Vector3(4, 0, 0))
	p.global_position = spot
	p.life = p.max_life * 0.5
	Events.town_portal_requested.emit()
	await _await_change(m)
	assert_true(GameState.world.is_town(), "back in town")
	assert_eq(m.get_kept_world(), dw, "dungeon kept")
	assert_false(dw.is_inside_tree(), "kept dungeon detached")
	var st_pos: Vector3 = GameState.town_portal_state.get("position", Vector3.INF)
	assert_true(st_pos.distance_to(Vector3(spot.x, 0, spot.z)) < 0.01, "portal position = where it was cast")
	assert_near(GameState.player.life_ratio(), 1.0, 0.001, "town entry: full life")
	assert_not_null(_find_portal(GameState.world, "return"), "return portal in town")
	assert_eq(get_tree().get_nodes_in_group("enemies").size(), 0, "no enemies in town")

	# Back through the portal: the same dungeon, re-attached; a town portal next to the player.
	_find_portal(GameState.world, "return").interact(GameState.player)
	await _await_change(m)
	assert_eq(GameState.world, dw, "same dungeon World")
	assert_true(dw.is_inside_tree(), "re-attached")
	assert_true(GameState.town_portal_state.is_empty(), "portal state cleared")
	assert_true(CombatQuery.distance_xz(GameState.player.global_position, spot) < 2.1, "player back where the portal was cast")
	var tp := _find_portal(dw, "town")
	assert_not_null(tp, "town portal in the dungeon")
	var near := false
	for n in dw.get_interactables():
		if n is WorldPortal and (n as WorldPortal).destination == "town" and CombatQuery.distance_xz((n as Node3D).global_position, spot) < 6.0:
			near = true
	assert_true(near, "a town portal stands near the return spot")

	# Boss kill: cleared depth, bonus point, max depth, exit portals.
	var boss := _boss_of(dw)
	assert_not_null(boss, "boss alive")
	var bonus_before := c.bonus_passive_points
	boss.die(GameState.player)
	var depth: int = await m.boss_cleared
	assert_eq(depth, 2, "cleared depth 2")
	assert_true(c.cleared_depths.has(2), "cleared_depths")
	assert_eq(c.bonus_passive_points, bonus_before + 1, "bonus passive point")
	assert_eq(c.max_depth, 3, "max depth unlocked")
	var next := _find_portal(dw, "next")
	assert_not_null(next, "descend portal")
	assert_not_null(_find_portal(dw, "town"), "town portal")
	if next != null:
		assert_eq(next.target_depth, 3, "descend target")

	# A second kill of the same depth gives no second bonus point.
	c.mark_depth_cleared(2)
	assert_eq(c.bonus_passive_points, bonus_before + 1, "still one bonus point")

	# Descend: a fresh depth 3, the old dungeon freed, pool ratios carried.
	GameState.player.life = GameState.player.max_life * 0.6
	var ratio := GameState.player.life_ratio()
	next.interact(GameState.player)
	await _await_change(m)
	assert_eq(int(GameState.current_area.get("depth", 0)), 3, "depth 3")
	assert_ne(GameState.world, dw, "new World")
	assert_near(GameState.player.life_ratio(), ratio, 0.02, "life ratio carried into the next depth")
	await get_tree().process_frame
	assert_false(is_instance_valid(dw), "old dungeon freed")
	assert_eq(m.changes_done, 5, "five changes")


func test_guarded_double_requests() -> void:
	var m := _make_main()
	m.start_new_game("Double", "ranger")
	# A second new game / area request while the first change runs is ignored.
	assert_false(m.start_new_game("Other", "sorcerer"), "second new game ignored")
	Events.area_change_requested.emit("dungeon", {"depth": 1})
	await _await_change(m)
	assert_eq(String(GameState.current_area.get("id", "")), "town", "first request won")
	assert_eq(GameState.character.char_name, "Double", "first character kept")
	assert_eq(m.changes_done, 1, "one change")
	# Two requests in the same frame: one change.
	Events.area_change_requested.emit("dungeon", {"depth": 1, "seed": 11})
	Events.area_change_requested.emit("dungeon", {"depth": 2, "seed": 22})
	Events.town_portal_requested.emit()
	await _await_change(m)
	assert_eq(int(GameState.current_area.get("depth", 0)), 1, "first request wins")
	await get_tree().process_frame
	assert_false(m.is_changing(), "no second change queued")
	assert_eq(m.changes_done, 2, "two changes")
	# Town while in town is ignored; a return without a kept dungeon is ignored.
	Events.area_change_requested.emit("town", {"keep_dungeon": true})
	await _await_change(m)
	assert_true(GameState.world.is_town(), "town")
	assert_false(m.request_area_change("town", {}), "town -> town ignored")
	assert_true(m.get_kept_world() != null, "dungeon kept")
	# The waypoint to a fresh depth discards the kept dungeon.
	var kept := m.get_kept_world()
	Events.area_change_requested.emit("dungeon", {"depth": 1})
	await _await_change(m)
	await get_tree().process_frame
	assert_true(GameState.town_portal_state.is_empty(), "kept dungeon discarded")
	assert_false(is_instance_valid(kept), "kept dungeon freed")
	assert_false(m.request_area_change("dungeon_return", {}), "nothing to return to")
	assert_false(m.request_area_change("nowhere", {}), "unknown id ignored")


func test_fade_blocks_requests() -> void:
	var m := _make_main()
	m.use_fade = true
	m.start_new_game("Fader", "sorcerer")
	await get_tree().process_frame
	assert_true(m.is_changing(), "still fading out")
	assert_true(m.fade.get_alpha() > 0.0, "fading")
	assert_false(m.request_area_change("dungeon", {"depth": 1}), "ignored while fading")
	await _await_change(m)
	assert_eq(String(GameState.current_area.get("id", "")), "town", "town")
	# The fade-in runs; the next change works.
	assert_true(m.request_area_change("dungeon", {"depth": 1}), "accepted after the change")
	await _await_change(m)
	assert_true(GameState.world.is_dungeon(), "dungeon")
