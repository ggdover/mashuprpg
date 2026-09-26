extends TestCase
## ui-menus: MainMenu — save list from GameState.list_saves() (test save_dir), Continue emits
## load_game_requested, Delete (confirmed) removes the save, New Character emits
## new_game_requested(name, class), Quit emits quit_requested.

const SAVE_DIR := "user://test_saves_ui_menus/"

var _loads: Array = []
var _news: Array = []
var _quits: Array = []
var _old_dir := ""


func _setup_saves(names: Array) -> void:
	_old_dir = GameState.save_dir
	GameState.save_dir = SAVE_DIR
	for s in GameState.list_saves():
		GameState.delete_save(String(s["save_id"]))
	var i := 0
	for n in names:
		GameState.new_character(String(n), ["warrior", "ranger", "sorcerer"][i % 3])
		GameState.character.level = 3 + i
		GameState.save_game()
		i += 1
	GameState.character = null
	Events.load_game_requested.connect(_on_load)
	Events.new_game_requested.connect(_on_new)
	Events.quit_requested.connect(_on_quit)


func _teardown() -> void:
	for s in GameState.list_saves():
		GameState.delete_save(String(s["save_id"]))
	GameState.save_dir = _old_dir if _old_dir != "" else GameState.SAVE_DIR
	for pair in [[Events.load_game_requested, _on_load], [Events.new_game_requested, _on_new], [Events.quit_requested, _on_quit]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _on_load(save_id: String) -> void:
	_loads.append(save_id)


func _on_new(char_name: String, class_id: String) -> void:
	_news.append([char_name, class_id])


func _on_quit() -> void:
	_quits.append(true)


func _menu() -> MainMenu:
	var m := MainMenu.new()
	add_child(m)
	m.on_opened({})
	return m


func _settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _click_button(b: Button) -> void:
	var pos := b.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(ev, true)


func test_lists_saves_and_continue_emits_load() -> void:
	_setup_saves(["Alpha", "Beta"])
	var m := _menu()
	await _settle()
	assert_false(m.is_create_view(), "list view when saves exist")
	var ids := m.get_save_ids()
	assert_eq(ids.size(), 2, "two saves listed")
	var target := String(ids[1])
	m.select_save(target)
	assert_eq(m.get_selected_save(), target, "selection")
	_click_button(m.continue_button)
	await _settle()
	assert_eq(_loads, [target], "Continue emitted load_game_requested(save_id)")
	# Busy after a request: a second click does nothing.
	m.continue_button.pressed.emit()
	assert_eq(_loads.size(), 1, "no duplicate request")
	_teardown()


func test_delete_needs_confirmation() -> void:
	_setup_saves(["Gamma", "Delta"])
	var m := _menu()
	await _settle()
	var victim := m.get_selected_save()
	m.delete_button.pressed.emit()
	assert_true(GameState.has_save(victim), "not deleted before confirming")
	m.confirm_no_button.pressed.emit()
	assert_true(GameState.has_save(victim), "cancel keeps it")
	m.delete_button.pressed.emit()
	m.confirm_yes_button.pressed.emit()
	assert_false(GameState.has_save(victim), "confirmed delete removes the file")
	assert_eq(m.get_save_ids().size(), 1, "list refreshed")
	assert_false(m.get_save_ids().has(victim), "victim gone from the list")
	# Deleting the last one switches to the create view.
	m.delete_button.pressed.emit()
	m.confirm_yes_button.pressed.emit()
	assert_eq(GameState.list_saves().size(), 0, "all gone")
	assert_true(m.is_create_view(), "create view when no saves remain")
	_teardown()


func test_new_character_emits_name_and_class() -> void:
	_setup_saves([])
	var m := _menu()
	await _settle()
	assert_true(m.is_create_view(), "no saves: create view first")
	m.set_character_name("")
	assert_true(m.begin_button.disabled, "no name: Begin disabled")
	m.begin_new_game()
	assert_eq(_news.size(), 0, "empty name refused")
	m.name_edit.text = "  Ysolde  "
	m.name_edit.text_changed.emit(m.name_edit.text)
	m.select_class("sorcerer")
	assert_eq(m.get_selected_class(), "sorcerer", "class selected")
	await _settle()
	_click_button(m.begin_button)
	await _settle()
	assert_eq(_news, [["Ysolde", "sorcerer"]], "new_game_requested(name, class)")
	_teardown()


func test_create_view_from_list_and_back() -> void:
	_setup_saves(["Epsilon"])
	var m := _menu()
	await _settle()
	m.new_button.pressed.emit()
	assert_true(m.is_create_view(), "New Character opens the create view")
	assert_true(m.name_edit.text.strip_edges() != "", "a random name is suggested")
	m.select_class("ranger")
	m.back_button.pressed.emit()
	assert_false(m.is_create_view(), "Back returns to the list")
	m.quit_button.pressed.emit()
	assert_eq(_quits.size(), 1, "Quit emitted quit_requested")
	_teardown()


func test_opens_through_ui_root_as_modal() -> void:
	_setup_saves(["Zeta"])
	UI.show_main_menu()
	var m: Control = UI.get_panel("main_menu")
	assert_true(m is MainMenu, "panel class")
	assert_true(UI.is_panel_open("main_menu"), "open")
	assert_true(UI.is_modal_open(), "modal")
	assert_eq(m.mouse_filter, Control.MOUSE_FILTER_STOP, "full screen root stops the mouse")
	UI.close_panel("main_menu")
	_teardown()
