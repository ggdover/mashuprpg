extends "res://tests/unit/test_kernel_util.gd"
## GameState: save / load / list / delete (in a test save_dir), save ids, kill XP awards,
## area helpers.

const TEST_DIR := "user://test_saves_kernel/"

var _old_dir := ""
var _saved := 0
var _area_requests: Array = []


func _use_test_dir() -> void:
	_old_dir = GameState.save_dir
	GameState.save_dir = TEST_DIR
	_wipe()


func _restore_dir() -> void:
	_wipe()
	GameState.save_dir = _old_dir if _old_dir != "" else GameState.SAVE_DIR


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for f in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR.path_join(f))


func _on_saved() -> void:
	_saved += 1


func _on_area(id: String, params: Dictionary) -> void:
	_area_requests.append([id, params])


func test_save_load_round_trip() -> void:
	_use_test_dir()
	Events.game_saved.connect(_on_saved)
	var c := GameState.new_character("Saver", "sorcerer")
	c.add_gold(77)
	c.add_xp(200)
	c.put_in_inventory(7, ItemDB.create_item("ring_1"))
	var id := GameState.save_id
	assert_true(GameState.save_game(), "saved")
	assert_eq(_saved, 1, "game_saved emitted")
	var path := GameState.get_save_path(id)
	assert_true(FileAccess.file_exists(path), "file exists")
	assert_false(FileAccess.file_exists(path + ".tmp"), "no temp file left")
	assert_true(path.begins_with(TEST_DIR), "in the test dir")
	assert_true(GameState.has_save(id), "has_save")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(data["version"]), 1, "version")
	assert_true(data["character"] is Dictionary, "character dict")
	GameState.character = null
	assert_true(GameState.load_game(id), "loaded")
	var l := GameState.character
	assert_not_null(l, "character set")
	assert_eq(l.char_name, "Saver", "name")
	assert_eq(l.class_id, "sorcerer", "class")
	assert_eq(l.gold, 77, "gold")
	assert_eq(l.level, c.level, "level")
	assert_eq(l.xp, c.xp, "xp")
	assert_eq((l.inventory[7] as Item).base_id, "ring_1", "inventory")
	assert_eq(l.get_equipped("main_hand").base_id, "wand_1", "equipment")
	assert_eq(GameState.save_id, id, "save id")
	# Overwrite keeps one file.
	l.add_gold(1)
	assert_true(GameState.save_game(), "saved again")
	assert_eq(DirAccess.get_files_at(TEST_DIR).size(), 1, "one file")
	Events.game_saved.disconnect(_on_saved)
	_restore_dir()


func test_list_and_delete() -> void:
	_use_test_dir()
	assert_eq(GameState.list_saves(), [], "empty")
	GameState.new_character("Alpha", "warrior")
	GameState.character.level = 3
	GameState.character.max_depth = 4
	var a := GameState.save_id
	GameState.save_game()
	GameState.new_character("Beta", "ranger")
	var b := GameState.save_id
	assert_ne(a, b, "unique ids")
	GameState.save_game()
	# Make Alpha the newest by rewriting its timestamp.
	var pa := GameState.get_save_path(a)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pa))
	d["saved_at"] = int(Time.get_unix_time_from_system()) + 100
	var f := FileAccess.open(pa, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var list := GameState.list_saves()
	assert_eq(list.size(), 2, "two saves")
	assert_eq(list[0]["save_id"], a, "newest first")
	assert_eq(list[0]["char_name"], "Alpha", "name")
	assert_eq(list[0]["class_id"], "warrior", "class")
	assert_eq(list[0]["level"], 3, "level")
	assert_eq(list[0]["max_depth"], 4, "depth")
	assert_eq(typeof(list[0]["modified"]), TYPE_INT, "modified int")
	assert_eq(list[1]["char_name"], "Beta", "second")
	GameState.delete_save(a)
	assert_false(GameState.has_save(a), "deleted")
	assert_eq(GameState.list_saves().size(), 1, "one left")
	GameState.delete_save("../../evil")
	GameState.delete_save("missing_save")
	_restore_dir()


func test_load_missing_and_corrupt() -> void:
	_use_test_dir()
	assert_false(GameState.load_game("does_not_exist"), "missing")
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(TEST_DIR.path_join("broken.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var f2 := FileAccess.open(TEST_DIR.path_join("nochar.json"), FileAccess.WRITE)
	f2.store_string("{\"version\": 1}")
	f2.close()
	GameState.character = null
	assert_false(GameState.load_game("broken"), "corrupt")
	assert_false(GameState.load_game("nochar"), "no character")
	assert_eq(GameState.character, null, "character untouched")
	assert_eq(GameState.list_saves(), [], "broken saves are not listed")
	assert_false(GameState.load_game("../x"), "path traversal refused")
	assert_false(GameState.save_game(), "nothing to save")
	_restore_dir()


func test_save_ids() -> void:
	_use_test_dir()
	var id := GameState.make_save_id("Sir Robin of Camelot!")
	assert_true(id.begins_with("sir_robin_of_camelot_"), "sanitized: " + id)
	assert_true(GameState.make_save_id("   ").begins_with("hero_"), "fallback")
	assert_true(GameState.make_save_id("../../x").begins_with("x_"), "no path chars")
	GameState.new_character("Dup", "warrior")
	GameState.save_game()
	var first := GameState.save_id
	var second := GameState.make_save_id("Dup")
	assert_ne(first, second, "unique even within the same second")
	_restore_dir()


func test_award_kill_xp() -> void:
	GameState.character = null
	GameState.award_kill_xp(1, 1.0)
	var c := GameState.new_character("Killer", "warrior")
	GameState.award_kill_xp(1, 1.0)
	assert_eq(c.xp, 10, "10.9 floored")
	assert_eq(GameState.last_xp_award, 10, "last award")
	GameState.award_kill_xp(1, 1.0)
	assert_eq(c.xp, 21, "fraction carried (10.9 + 10.9)")
	GameState.award_kill_xp(1, 8.0)
	assert_eq(c.xp, 21 + int(floorf(10.9 * 8.0 + 0.8)), "rarity multiplier")
	var before := c.xp
	GameState.award_kill_xp(20, 1.0)
	var expected_raw := Balance.monster_xp(20) * Balance.xp_penalty(1, 20)
	assert_between(float(c.xp - before), floorf(expected_raw) - 1.0, expected_raw + 1.0, "penalty applied")
	assert_true(Balance.xp_penalty(1, 20) < 1.0, "penalised")


func test_award_kill_xp_levels_and_number() -> void:
	capture_numbers()
	var c := GameState.new_character("Lvl", "ranger")
	var p := spawn_player(Vector3.ZERO)
	var levels := [0]
	var cb := func(_l: int) -> void: levels[0] += 1
	Events.level_up.connect(cb)
	GameState.award_kill_xp(3, 40.0)
	Events.level_up.disconnect(cb)
	assert_true(c.level >= 3, "boss kill levels up several times (level %d)" % c.level)
	assert_eq(levels[0], c.level - 1, "one level_up per level")
	var xp_numbers := numbers_of("xp")
	assert_eq(xp_numbers.size(), 1, "xp number over the player")
	assert_eq(float(xp_numbers[0]["amount"]), float(GameState.last_xp_award), "xp number amount")
	assert_true((xp_numbers[0]["pos"] as Vector3).y > p.get_aim_point().y, "above the player")
	c.level = Balance.MAX_LEVEL
	c.xp = 0
	GameState.award_kill_xp(60, 40.0)
	assert_eq(c.xp, 0, "no xp at the cap")
	assert_eq(GameState.last_xp_award, 0, "nothing awarded")


func test_area_helpers() -> void:
	Events.area_change_requested.connect(_on_area)
	GameState.change_area("dungeon", {"depth": 3})
	Events.area_change_requested.disconnect(_on_area)
	assert_eq(_area_requests, [["dungeon", {"depth": 3}]], "request emitted")
	GameState.current_area = {"id": "town"}
	assert_true(GameState.is_in_town(), "town")
	GameState.current_area = {"id": "dungeon", "depth": 2}
	assert_false(GameState.is_in_town(), "dungeon")
	GameState.current_area = {}
	assert_false(GameState.is_in_town(), "menu")
