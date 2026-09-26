extends Node
## Headless unit-test runner. Discovers res://tests/unit/**/test_*.gd and runs every method named
## test_* on a fresh instance of the script (added to the tree). OWNER: orchestrator.
##
##   tools/gtest.sh <env> res://tests/test_runner.tscn                         # all tests
##   tools/gtest.sh <env> res://tests/test_runner.tscn -- --filter=test_items  # path contains
##
## A test FAILS if an assertion fails, if any engine/script error (SCRIPT ERROR, push_error) is
## logged while it runs, or if it takes longer than TEST_TIMEOUT seconds (async tests).
## After each test GameState's live references are reset. Exit code = number of failed tests.

const TEST_DIR := "res://tests/unit"
const TEST_TIMEOUT := 20.0

var _logger: Logger


func _ready() -> void:
	_logger = preload("res://tests/error_logger.gd").new()
	OS.add_logger(_logger)
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files := _find_tests(TEST_DIR)
	files.sort()
	var passed := 0
	var failed := 0
	var failed_names: PackedStringArray = []
	for path in files:
		if filter != "" and path.find(filter) == -1:
			continue
		_logger.take()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("[FAIL] could not load test script %s" % path)
			for e in _logger.take():
				print("       - engine error: ", e)
			failed += 1
			failed_names.append(path)
			continue
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var inst: Node = script.new()
			inst.name = "Test_" + mname
			inst.set("current_test", mname)
			add_child(inst)
			_logger.take()
			var st: Variant = inst.call(mname)
			if st is Object and (st as Object).has_signal("completed"):
				var done := [false]
				(st as Object).connect("completed", func(_r: Variant = null) -> void: done[0] = true)
				var start := Time.get_ticks_msec()
				while not done[0] and Time.get_ticks_msec() - start < int(TEST_TIMEOUT * 1000.0):
					await get_tree().process_frame
				if not done[0]:
					inst.get("failures").append("timed out after %ds (awaiting something that never happened?)" % int(TEST_TIMEOUT))
			var fails: Array = inst.get("failures")
			for e in _logger.take():
				fails.append("engine error: " + e)
			var label := "%s::%s" % [path.get_file(), mname]
			if fails.is_empty():
				passed += 1
				print("[PASS] ", label)
			else:
				failed += 1
				failed_names.append(label)
				print("[FAIL] ", label)
				for f in fails:
					print("       - ", f)
			if is_instance_valid(inst):
				inst.queue_free()
			_reset_game_state()
			await get_tree().process_frame
			await get_tree().process_frame
	print("")
	print("=== TESTS: %d passed, %d failed ===" % [passed, failed])
	for n in failed_names:
		print("    failed: ", n)
	get_tree().quit(failed)


func _reset_game_state() -> void:
	GameState.player = null
	GameState.world = null
	GameState.character = null
	GameState.current_area = {}
	GameState.town_portal_state = {}
	if get_tree().paused:
		get_tree().paused = false


func _find_tests(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_find_tests(full))
		elif f.begins_with("test_") and f.ends_with(".gd"):
			out.append(full)
		f = dir.get_next()
	return out
