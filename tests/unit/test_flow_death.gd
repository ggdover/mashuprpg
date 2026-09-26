extends TestCase
## Game flow: death -> death screen -> respawn in town with the dungeon kept (portal at its start,
## the boss reset), XP penalty, requests ignored while dead, quitting while dead keeps the penalty.
## OWNER: flow.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_flow_death/"


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
	var m: Main = Main.new()
	m.auto_boot = false
	m.use_fade = false
	m.show_titles = false
	m.death_panel_delay = 0.1
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


func _boss_of(w: World) -> Enemy:
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			return e
	return null


func _enter_dungeon(m: Main, class_id: String, depth: int) -> World:
	m.start_new_game("Mortal", class_id)
	await _await_change(m)
	m.request_area_change("dungeon", {"depth": depth, "seed": 99})
	await _await_change(m)
	return GameState.world


func test_death_respawn_keeps_dungeon() -> void:
	var m := _make_main()
	var dw := await _enter_dungeon(m, "warrior", 1)
	assert_true(dw.is_dungeon(), "in the dungeon")
	var c := GameState.character
	c.add_xp(60)
	var xp_before := c.xp
	# The boss is hurt and fighting when the player dies.
	var boss := _boss_of(dw)
	assert_not_null(boss, "boss")
	boss.life = boss.max_life * 0.4
	boss.aggro(GameState.player, false)
	var p := GameState.player
	p.take_damage(p.max_life * 10.0 + p.max_es * 10.0 + 1000.0, "physical")
	assert_true(p.dead, "player died")
	assert_true(m.is_awaiting_respawn(), "awaiting respawn")
	assert_false(m.request_area_change("town", {"keep_dungeon": true}), "no area change while dead")
	await m.death_screen_shown
	assert_true(UI.is_panel_open("death"), "death screen open")
	var expected_loss := mini(int(roundf(float(c.xp_to_next()) * Balance.DEATH_XP_PENALTY)), xp_before)
	# Respawn the way the death screen does.
	Events.respawn_requested.emit()
	assert_true(m.is_changing(), "respawn change running")
	Events.respawn_requested.emit()   # double click: ignored
	await _await_change(m)
	assert_false(UI.is_panel_open("death"), "death screen closed")
	assert_true(GameState.world.is_town(), "respawned in town")
	assert_eq(c.xp, xp_before - expected_loss, "10% of the level's XP lost")
	assert_eq(c.last_xp_loss, expected_loss, "last_xp_loss")
	var np := GameState.player
	assert_false(np.dead, "alive")
	assert_near(np.life_ratio(), 1.0, 0.001, "full life")
	assert_eq(m.get_kept_world(), dw, "dungeon kept")
	var pos: Vector3 = GameState.town_portal_state.get("position", Vector3.INF)
	assert_true(pos.distance_to(dw.get_player_start()) < 0.01, "portal position = dungeon start")
	assert_true(is_instance_valid(boss) and not boss.dead, "boss alive")
	assert_near(boss.life, boss.max_life, 0.01, "boss reset to full life")
	assert_false(boss.is_in_combat(), "boss left combat")
	# Back into the same dungeon at its start.
	m.request_area_change("dungeon_return", {})
	await _await_change(m)
	assert_eq(GameState.world, dw, "same dungeon")
	assert_true(CombatQuery.distance_xz(GameState.player.global_position, dw.get_player_start()) < 2.1, "at the start")
	assert_true(m.changes_done == 4, "four changes")


func test_quit_while_dead_keeps_penalty() -> void:
	var m := _make_main()
	await _enter_dungeon(m, "ranger", 1)
	var c := GameState.character
	c.add_xp(80)
	var xp_before := c.xp
	var sid := GameState.save_id
	var p := GameState.player
	p.take_damage(1.0e7, "fire")
	assert_true(m.is_awaiting_respawn(), "dead")
	m.return_to_menu()
	await m.returned_to_menu
	assert_null_character()
	assert_true(UI.is_panel_open("main_menu"), "main menu shown")
	assert_true(GameState.load_game(sid), "save loads")
	assert_true(GameState.character.xp < xp_before, "the death penalty was saved")
	GameState.character = null


func assert_null_character() -> void:
	assert_true(GameState.character == null, "character cleared")
	assert_true(GameState.player == null, "player cleared")
	assert_true(GameState.world == null, "world cleared")
	assert_true(GameState.town_portal_state.is_empty(), "no kept dungeon")
