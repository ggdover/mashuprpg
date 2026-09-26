extends TestCase
## Game flow: save / load round trip through the flow (new game -> play -> return to menu ->
## load), autosave triggers, load sanitation, failed loads, menu return while a change runs,
## Events-driven new game / load. OWNER: flow.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_flow_save/"


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
	var m: Main = Main.new()
	m.auto_boot = false
	m.use_fade = false
	m.show_titles = false
	add_child(m)
	return m


func _exit_tree() -> void:
	UI.close_all_panels()
	UI.show_hud(false)
	GameState.save_dir = GameState.SAVE_DIR


func _await_change(m: Main) -> void:
	if m.is_changing():
		await m.area_change_finished
	await get_tree().physics_frame


func _read_save(sid: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(GameState.get_save_path(sid))
	var d: Variant = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func test_round_trip_through_menu() -> void:
	var m := _make_main()
	Events.new_game_requested.emit("Roundtrip", "sorcerer")
	await _await_change(m)
	var c := GameState.character
	var sid := GameState.save_id
	assert_true(GameState.has_save(sid), "saved at creation")
	# Play a bit: gold, a level, an item, a passive, a skill on the bar, a dungeon visit.
	c.add_gold(321)
	c.add_xp(c.xp_to_next())
	assert_eq(c.level, 2, "level 2")
	var node_id := int(TreeDB.get_allocatable(c.allocated_passives, c.class_id)[0])
	assert_true(c.allocate_passive(node_id), "passive allocated")
	var it := ItemDB.generate_random_item(5, Item.Rarity.RARE)
	assert_true(c.add_to_inventory(it), "item added")
	c.set_skill_in_slot(3, "frost_nova")
	m.request_area_change("dungeon", {"depth": 1})
	await _await_change(m)
	# Autosave on area change.
	var saved := _read_save(sid)
	assert_eq(int(saved["character"]["gold"]), 321, "autosaved on area change")
	# Back to the menu.
	Events.return_to_menu_requested.emit()
	await m.returned_to_menu
	assert_true(GameState.character == null, "character cleared")
	assert_true(GameState.world == null and GameState.player == null, "world and player cleared")
	assert_true(UI.is_panel_open("main_menu"), "main menu")
	assert_eq(get_tree().get_nodes_in_group("world").size(), 0, "no world left")
	# Load it back.
	Events.load_game_requested.emit(sid)
	await _await_change(m)
	var l := GameState.character
	assert_not_null(l, "loaded")
	assert_eq(l.char_name, "Roundtrip", "name")
	assert_eq(l.class_id, "sorcerer", "class")
	assert_eq(l.level, 2, "level")
	assert_eq(l.gold, 321, "gold")
	assert_true(l.allocated_passives.has(node_id), "passive kept")
	assert_eq(l.get_skill_in_slot(3), "frost_nova", "skill bar kept")
	var found := false
	for x in l.inventory:
		if x != null and (x as Item).get_display_name() == it.get_display_name():
			found = true
	assert_true(found, "item kept")
	assert_true(GameState.world.is_town(), "loads into town")
	assert_false(UI.is_panel_open("main_menu"), "menu closed")
	assert_eq(GameState.save_id, sid, "same save id")


func test_level_up_autosave_and_load_sanitation() -> void:
	var m := _make_main()
	m.start_new_game("Sanity", "warrior")
	await _await_change(m)
	var c := GameState.character
	var sid := GameState.save_id
	c.add_xp(c.xp_to_next() * 3)
	await get_tree().process_frame
	assert_eq(int(_read_save(sid)["character"]["level"]), c.level, "autosaved on level up")
	# Corrupt the allocation / skill bar in the file, then load: the flow cleans it.
	m.return_to_menu()
	await m.returned_to_menu
	var data := _read_save(sid)
	data["character"]["allocated_passives"] = [999999, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
	data["character"]["skill_bar"] = ["basic_attack", "no_such_skill", "", "", "", ""]
	var f := FileAccess.open(GameState.get_save_path(sid), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(m.load_game(sid), "load accepted")
	await _await_change(m)
	var l := GameState.character
	assert_true(l.allocated_passives.size() <= l.passive_points_total(), "no more passives than points")
	assert_false(l.allocated_passives.has(999999), "unknown node dropped")
	assert_eq(TreeDB.sanitize_allocation(l.allocated_passives, l.class_id).size(), l.allocated_passives.size(), "connected allocation")
	assert_eq(l.get_skill_in_slot(1), "", "unknown skill removed")
	assert_eq(l.get_skill_in_slot(0), "basic_attack", "known skill kept")


func test_failed_load_stays_in_menu() -> void:
	var m := _make_main()
	assert_false(m.load_game("does_not_exist"), "missing save refused")
	assert_false(m.is_changing(), "no change")
	assert_true(GameState.character == null, "no character")


func test_menu_request_during_change_is_queued() -> void:
	var m := _make_main()
	m.start_new_game("Queue", "ranger")
	await _await_change(m)
	m.request_area_change("dungeon", {"depth": 1})
	assert_true(m.is_changing(), "changing")
	assert_true(m.return_to_menu(), "menu request accepted (queued)")
	await m.returned_to_menu
	assert_true(GameState.character == null, "back in the menu")
	assert_true(UI.is_panel_open("main_menu"), "menu open")
