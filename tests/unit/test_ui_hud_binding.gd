extends TestCase
## HUD binding to a real Player, globes, potions, XP bar, passive points, hover/mouse rules, Tab.
## OWNER: ui-hud.


func _make_hud() -> HUD:
	var layer := CanvasLayer.new()
	add_child(layer)
	var h := HUD.new()
	layer.add_child(h)
	return h


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func test_binds_on_ready_and_on_player_spawned() -> void:
	await make_world()
	var p := spawn_player()
	var hud := _make_hud()
	assert_eq(hud.get_player(), p, "binds GameState.player on _ready")
	assert_eq(hud.get_character(), p.character, "character of the player")
	# A second player announced through the event.
	var c2 := CharacterData.new()
	c2.class_id = "ranger"
	var p2 := Player.new()
	p2.setup(c2)
	GameState.world.add_child(p2)
	Events.player_spawned.emit(p2)
	assert_eq(hud.get_player(), p2, "binds on Events.player_spawned")
	assert_eq(hud.get_character(), c2, "character follows the player")
	p2.queue_free()
	await _frames(2)


func test_player_freed_then_new_player() -> void:
	await make_world()
	var hud := _make_hud()
	assert_true(hud.get_player() == null, "no player yet")
	var p := spawn_player()
	await _frames(2)
	assert_eq(hud.get_player(), p, "re-binds by itself when GameState.player appears")
	GameState.player = null
	p.queue_free()
	await _frames(3)
	assert_true(hud.get_player() == null, "freed player is dropped")
	var p2 := spawn_player(Vector3(2, 0, 0))
	Events.player_spawned.emit(p2)
	await _frames(2)
	assert_eq(hud.get_player(), p2, "binds the new player")


func test_globe_values_follow_the_player() -> void:
	await make_world()
	var p := spawn_player()
	var hud := _make_hud()
	await _frames(2)
	p.life = p.max_life * 0.5
	p.mana = p.max_mana * 0.25
	await _frames(3)
	var lg: Variant = hud.life_globe
	var mg: Variant = hud.mana_globe
	assert_near(lg.value, p.life, 1.0, "life value")
	assert_near(lg.max_value, p.max_life, 0.01, "max life")
	assert_near(lg.get_target_fill(), p.life / p.max_life, 0.02, "life fill target")
	assert_near(mg.get_target_fill(), p.mana / p.max_mana, 0.02, "mana fill target")
	# Eases toward the target.
	await _frames(40)
	assert_near(lg.display_fill, p.life / p.max_life, 0.03, "displayed life fill converges")
	# Energy shield ring appears with a pool.
	assert_near(lg.max_es, 0.0, 0.001, "no ES yet")
	p.add_buff("test_es", {"name": "Ward", "duration": 0.0, "icon": "", "mods": [StatBlock.mod("max_energy_shield", "flat", 60.0)]})
	await _frames(2)
	assert_near(lg.max_es, p.max_es, 0.01, "ES max shown")
	assert_true(p.max_es > 0.0, "buff gave ES")


func test_potions_xp_and_passive_points() -> void:
	await make_world()
	var c := make_character("sorcerer")
	c.level = 5
	c.life_potion_charges = 1.5
	c.mana_potion_charges = 0.25
	var p := spawn_player()
	var hud := _make_hud()
	await _frames(2)
	assert_near(hud.life_potion.get("charges"), 1.5, 0.001, "life charges")
	assert_near(hud.mana_potion.get("charges"), 0.25, 0.001, "mana charges")
	assert_true(hud.passive_button.visible, "passive points indicator visible")
	assert_eq(hud.passive_button.get("points"), c.passive_points_unspent(), "unspent points")
	c.add_xp(50)
	await _frames(1)
	assert_eq(hud.xp_bar.get("xp"), c.xp, "xp shown")
	assert_eq(hud.xp_bar.get("level"), c.level, "level shown")
	# Potion activity shows as a sweep ratio.
	p.life = p.max_life * 0.3
	assert_true(p.use_potion("life"), "potion used")
	await _frames(2)
	assert_between(hud.life_potion.get("active_ratio"), 0.01, 1.0, "active potion sweep")
	# Spending the points hides the indicator.
	c.bonus_passive_points = 0
	c.level = 1
	Events.passives_changed.emit()
	await _frames(2)
	assert_false(hud.passive_button.visible, "no points -> hidden")


func test_mouse_rules_and_point_over_hud() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	await _frames(2)
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE, "HUD root ignores the mouse")
	assert_eq(hud.damage_numbers.mouse_filter, Control.MOUSE_FILTER_IGNORE, "numbers layer ignores")
	assert_eq(hud.minimap.mouse_filter, Control.MOUSE_FILTER_IGNORE, "minimap ignores")
	assert_eq(hud.boss_bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "boss bar ignores")
	assert_eq(hud.vignette.mouse_filter, Control.MOUSE_FILTER_IGNORE, "vignette ignores")
	for s in hud.skill_slots:
		assert_eq(s.mouse_filter, Control.MOUSE_FILTER_STOP, "skill slots stop")
	assert_eq(hud.life_globe.mouse_filter, Control.MOUSE_FILTER_STOP, "globe stops")
	var slot_center: Vector2 = hud.skill_slots[2].get_global_rect().get_center()
	assert_true(hud.is_point_over_hud(slot_center), "over a skill slot")
	var globe_center: Vector2 = hud.life_globe.get_global_rect().get_center()
	assert_true(hud.is_point_over_hud(globe_center), "over the life globe")
	assert_false(hud.is_point_over_hud(hud.size * 0.5), "screen centre is gameplay")
	# The globe's square corner is outside its circle.
	var corner: Vector2 = hud.life_globe.get_global_rect().position + Vector2(2, 2)
	assert_false(hud.is_point_over_hud(corner), "globe corner is not the globe")


func test_tab_toggles_large_minimap() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	await _frames(2)
	assert_false(hud.is_minimap_large(), "starts small")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	get_viewport().push_input(ev, true)
	await _frames(1)
	assert_true(hud.is_minimap_large(), "Tab -> large overlay")
	assert_true(hud.minimap_large.visible, "overlay visible")
	assert_false(hud.minimap.visible, "corner map hidden while large")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_TAB
	up.pressed = false
	get_viewport().push_input(up, true)
	get_viewport().push_input(ev.duplicate(), true)
	await _frames(1)
	assert_false(hud.is_minimap_large(), "Tab again -> small")


func test_area_label_and_banner() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	var info := {"id": "dungeon", "depth": 3, "level": 3, "theme": "crypt", "name": "Depth 3 — The Crypts"}
	Events.area_entered.emit(info)
	assert_eq(hud.area_label.get("area_name"), "Depth 3 — The Crypts", "area name")
	assert_eq(hud.area_label.get("sub_text"), "Monster Level 3", "area level")
	assert_true(hud.area_banner.call("is_playing"), "title banner plays")
	Events.area_cleared.emit(info)
	assert_true(String(hud.area_label.get("sub_text")).contains("Cleared"), "cleared after the boss")
	Events.area_entered.emit({"id": "town", "name": "Emberfall", "level": 1, "theme": "town"})
	assert_eq(hud.area_label.get("sub_text"), "Town", "town label")
