extends TestCase
## ui-menus: PauseMenu (resume / save / save & quit / quit) and DeathScreen (XP penalty, respawn).

const SAVE_DIR := "user://test_saves_ui_menus_pause/"

var _events: Array = []
var _old_dir := ""


func _hook() -> void:
	_old_dir = GameState.save_dir
	GameState.save_dir = SAVE_DIR
	Events.return_to_menu_requested.connect(_on_menu)
	Events.quit_requested.connect(_on_quit)
	Events.respawn_requested.connect(_on_respawn)
	Events.game_saved.connect(_on_saved)


func _unhook() -> void:
	for s in GameState.list_saves():
		GameState.delete_save(String(s["save_id"]))
	GameState.save_dir = _old_dir if _old_dir != "" else GameState.SAVE_DIR
	for pair in [[Events.return_to_menu_requested, _on_menu], [Events.quit_requested, _on_quit],
			[Events.respawn_requested, _on_respawn], [Events.game_saved, _on_saved]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _on_menu() -> void:
	_events.append("menu")


func _on_quit() -> void:
	_events.append("quit")


func _on_respawn() -> void:
	_events.append("respawn")


func _on_saved() -> void:
	_events.append("saved")


func _settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func test_pause_save_writes_the_game() -> void:
	_hook()
	make_character("ranger")
	var p := PauseMenu.new()
	add_child(p)
	p.on_opened({})
	await _settle()
	p.save_button.pressed.emit()
	assert_has(_events, "saved", "Save emitted game_saved")
	assert_true(GameState.has_save(GameState.save_id), "save file written")
	_unhook()


func test_pause_quit_buttons_emit() -> void:
	_hook()
	make_character("warrior")
	var p := PauseMenu.new()
	add_child(p)
	p.on_opened({})
	await _settle()
	p.save_quit_button.pressed.emit()
	assert_has(_events, "menu", "Save & Quit emitted return_to_menu_requested")
	assert_true(GameState.has_save(GameState.save_id), "saved before returning")
	assert_true(p.quit_button.disabled, "buttons disabled while leaving")
	p.on_opened({})
	p.quit_button.pressed.emit()
	assert_has(_events, "quit", "Quit emitted quit_requested")
	_unhook()


func test_pause_resume_through_ui_root_unpauses() -> void:
	make_character("warrior")
	UI.open_panel("pause", {})
	var p: Control = UI.get_panel("pause")
	assert_true(p is PauseMenu, "panel class")
	assert_true(get_tree().paused, "pause menu pauses the tree")
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_STOP, "full screen root")
	var b: Button = p.get("resume_button")
	await get_tree().process_frame
	var pos := b.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(ev, true)
	await get_tree().process_frame
	assert_false(UI.is_panel_open("pause"), "Resume closed the pause menu")
	assert_false(get_tree().paused, "tree unpaused")
	get_tree().paused = false


func test_pause_without_character() -> void:
	var p := PauseMenu.new()
	add_child(p)
	p.on_opened({})
	assert_false(p.save(), "nothing to save without a character")
	p.resume_button.pressed.emit()
	assert_false(p.visible, "standalone resume hides it")


func test_death_screen_shows_penalty_and_respawns_once() -> void:
	_hook()
	var c := make_character("sorcerer")
	c.level = 10
	c.xp = 500
	var d := DeathScreen.new()
	add_child(d)
	d.on_opened({})
	await _settle()
	var expected := mini(int(roundf(float(c.xp_to_next()) * Balance.DEATH_XP_PENALTY)), 500)
	assert_eq(d.get_pending_xp_loss(), expected, "pending penalty")
	assert_eq(d.get_shown_xp_loss(), expected, "shown penalty")
	d.respawn_button.pressed.emit()
	d.respawn_button.pressed.emit()
	assert_eq(_events.count("respawn"), 1, "respawn_requested emitted once")
	assert_true(d.respawn_button.disabled, "button disabled after respawning")
	# Reopening re-arms it; a flow that already applied the loss can pass it in.
	c.lose_xp_fraction(Balance.DEATH_XP_PENALTY)
	d.on_opened({"xp_lost": c.last_xp_loss})
	assert_eq(d.get_shown_xp_loss(), c.last_xp_loss, "context xp_lost wins")
	assert_false(d.respawn_button.disabled, "re-armed")
	d.respawn()
	assert_eq(_events.count("respawn"), 2, "second death, second respawn")
	_unhook()


func test_death_screen_is_modal_in_ui_root() -> void:
	make_character("warrior")
	UI.open_panel("death", {})
	var d: Control = UI.get_panel("death")
	assert_true(d is DeathScreen, "panel class")
	assert_true(UI.is_modal_open(), "death screen is modal")
	assert_eq(d.mouse_filter, Control.MOUSE_FILTER_STOP, "full screen root")
	UI.close_panel("death")
	var d2 := DeathScreen.new()
	add_child(d2)
	GameState.character = null
	d2.on_opened({})
	assert_eq(d2.get_shown_xp_loss(), 0, "no character: no penalty shown")
