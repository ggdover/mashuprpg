extends TestCase
## Game flow: debug keys (F9 level up, F10 loot, F11 god mode that survives area changes, F12
## screenshot skipped headless), command-line parsing, the missing-death-screen fallback timer.
## OWNER: flow.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_flow_debug/"


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
	var m: Main = Main.new()
	m.auto_boot = false
	m.use_fade = false
	m.show_titles = false
	m.debug_keys_enabled = true
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


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	get_viewport().push_input(ev, true)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame


func test_debug_keys() -> void:
	var m := _make_main()
	m.start_new_game("Debugger", "ranger")
	await _await_change(m)
	var c := GameState.character
	var lvl := c.level
	await _press(KEY_F9)
	assert_eq(c.level, lvl + 1, "F9 levels up")
	var loot_before := get_tree().get_nodes_in_group("loot").size()
	await _press(KEY_F10)
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("loot").size() - loot_before, 6, "F10 spawns 6 items")
	await _press(KEY_F11)
	assert_true(GameState.player.god_mode, "F11 god mode on")
	# God mode survives an area change (it is a session toggle).
	m.request_area_change("dungeon", {"depth": 1})
	await _await_change(m)
	assert_true(GameState.player.god_mode, "god mode kept in the new area")
	await _press(KEY_F11)
	assert_false(GameState.player.god_mode, "F11 god mode off")
	await _press(KEY_F12)   # headless: skipped with a warning, no error


func test_debug_keys_off() -> void:
	var m := _make_main()
	m.debug_keys_enabled = false
	m.start_new_game("NoDebug", "warrior")
	await _await_change(m)
	var lvl := GameState.character.level
	await _press(KEY_F9)
	assert_eq(GameState.character.level, lvl, "F9 ignored when debug keys are off")


func test_parse_args() -> void:
	var a := Main.parse_args(PackedStringArray(["--autoplay=90", "--class=sorcerer", "--depth=4", "--seed=77", "--shots=docs/x", "--filter=test", "junk"]))
	assert_near(float(a["autoplay"]), 90.0, 0.001, "autoplay seconds")
	assert_eq(a["class"], "sorcerer", "class")
	assert_eq(a["depth"], 4, "depth")
	assert_eq(a["seed"], 77, "seed")
	assert_eq(a["shots"], "docs/x", "shots dir")
	assert_eq(a["filter"], "test", "other keys kept")
	var b := Main.parse_args(PackedStringArray(["--autoplay", "--depth=abc"]))
	assert_near(float(b["autoplay"]), 120.0, 0.001, "default autoplay length")
	assert_false(b.has("depth"), "bad depth ignored")


func test_death_timer_opens_death_screen() -> void:
	var m := _make_main()
	m.death_panel_delay = 0.2
	m.start_new_game("Timer", "sorcerer")
	await _await_change(m)
	m.request_area_change("dungeon", {"depth": 1})
	await _await_change(m)
	GameState.player.take_damage(1.0e7, "chaos")
	assert_false(UI.is_panel_open("death"), "not right away")
	# Main counts the delay in game time (frame deltas): count it the same way (wall-clock time
	# measured mid-frame disagrees with it on a busy machine).
	var shown := [false]
	m.death_screen_shown.connect(func() -> void: shown[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not shown[0] and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_true(shown[0], "death screen signal")
	assert_between(waited, 0.15, 1.0, "after the delay (%.3f s game time)" % waited)
	assert_true(UI.is_panel_open("death"), "death screen")
	assert_true(UI.is_modal_open(), "modal")
	m.respawn()
	await _await_change(m)
	assert_true(GameState.world.is_town(), "respawned")
