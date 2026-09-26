extends TestCase
## Potions: heal / mana over time, charges, no stacking of the same potion, full pool refusal,
## potion_effect scaling, HUD ratio, keyboard path, and charges gained per kill by rarity.


## An enemy-like dummy with a rarity (Enemy.rarity) for the potion charge test.
class RarityDummy extends TestDummy:
	var rarity := 0


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _collect_notes(notes: Array) -> Callable:
	var cb := func(text: String, _c: Color) -> void: notes.append(text)
	Events.notify.connect(cb)
	return cb


func test_life_potion_heals_over_time() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	assert_near(p.life_regen, 0.0, 0.0001, "no regen on starting gear (clean measurement)")
	var notes: Array = []
	var cb := _collect_notes(notes)
	assert_false(p.use_potion("life"), "refused at full life")
	assert_eq(c.get_potion_charges("life"), 3.0, "no charge used at full life")
	p.life = p.max_life * 0.25
	var start := p.life
	assert_true(p.use_potion("life"), "drink")
	assert_eq(c.get_potion_charges("life"), 2.0, "one charge used")
	assert_true(p.is_potion_active("life"), "active")
	assert_near(p.get_potion_active_ratio("life"), 1.0, 0.02, "ratio starts at 1")
	assert_false(p.use_potion("life"), "can't stack the same potion")
	assert_eq(c.get_potion_charges("life"), 2.0, "stacking refused without using a charge")
	assert_has(notes, "Potion already active", "message")
	await _wait(45)
	assert_between(p.get_potion_active_ratio("life"), 0.4, 0.6, "half way")
	assert_true(p.life > start + 0.1 * p.max_life and p.life < start + 0.3 * p.max_life, "heals gradually")
	await _wait(50)
	assert_false(p.is_potion_active("life"), "finished after 1.5 s")
	assert_near(p.get_potion_active_ratio("life"), 0.0, 0.0001, "ratio 0 when done")
	assert_near(p.life, start + Player.LIFE_POTION_FRACTION * p.max_life, 0.5, "healed 40% of max life")
	# The mana potion is independent of the life potion.
	p.mana = 5.0
	p.mana_regen = 0.0   # measure the potion alone (reset by the next recalculation)
	assert_true(p.use_potion("mana"), "mana potion")
	p.life = p.max_life * 0.5
	assert_true(p.use_potion("life"), "life potion while the mana potion runs")
	await _wait(95)
	assert_near(p.mana, minf(p.max_mana, 5.0 + Player.MANA_POTION_FRACTION * p.max_mana), 0.5, "restored 50% of max mana")
	Events.notify.disconnect(cb)


func test_no_charges_and_potion_effect() -> void:
	await make_world()
	var c := make_character("sorcerer")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var notes: Array = []
	var cb := _collect_notes(notes)
	c.life_potion_charges = 0.75
	p.life = p.max_life * 0.2
	assert_false(p.use_potion("life"), "less than one charge")
	assert_false(p.is_potion_active("life"), "not active")
	assert_has(notes, "No life potion charges", "message")
	assert_false(p.use_potion("elixir"), "unknown kind")
	Events.notify.disconnect(cb)
	c.life_potion_charges = 3.0
	p.add_buff("test_flask", {"name": "Flask", "mods": [StatBlock.mod("potion_effect", "inc", 50.0)], "duration": 0.0})
	p.life = p.max_life * 0.2
	var start := p.life
	assert_true(p.use_potion("life"), "drink")
	await _wait(95)
	assert_near(p.life, start + Player.LIFE_POTION_FRACTION * 1.5 * p.max_life, 0.5, "50% increased potion effect")


func test_potion_key_uses_the_same_path() -> void:
	await make_world()
	var c := make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	p.life = p.max_life * 0.5
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_1
	ev.pressed = true
	get_viewport().push_input(ev, true)
	await _wait(2)
	assert_true(p.is_potion_active("life"), "key 1 drinks the life potion")
	assert_eq(c.get_potion_charges("life"), 2.0, "charge used")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_1
	up.pressed = false
	get_viewport().push_input(up, true)
	p.mana = 1.0
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_2
	ev2.pressed = true
	get_viewport().push_input(ev2, true)
	await _wait(2)
	assert_true(p.is_potion_active("mana"), "key 2 drinks the mana potion")


func test_charges_from_kills_by_rarity() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	c.life_potion_charges = 0.0
	c.mana_potion_charges = 0.0
	var normal := spawn_dummy(Actor.Team.ENEMY, Vector3(4, 0, 0), 10.0)
	Events.enemy_killed.emit(normal)
	assert_near(c.get_potion_charges("life"), 0.25, 0.0001, "normal +0.25")
	assert_near(c.get_potion_charges("mana"), 0.25, 0.0001, "both potions")
	var magic := RarityDummy.new()
	magic.rarity = 1
	GameState.world.add_child(magic)
	Events.enemy_killed.emit(magic)
	assert_near(c.get_potion_charges("life"), 0.75, 0.0001, "magic +0.5")
	var rare := RarityDummy.new()
	rare.rarity = 2
	GameState.world.add_child(rare)
	Events.enemy_killed.emit(rare)
	assert_near(c.get_potion_charges("life"), 1.75, 0.0001, "rare +1")
	c.life_potion_charges = 0.0
	var boss := RarityDummy.new()
	boss.rarity = 3
	boss.add_to_group("boss")
	GameState.world.add_child(boss)
	Events.enemy_killed.emit(boss)
	assert_near(c.get_potion_charges("life"), 3.0, 0.0001, "boss +3 (capped at 3)")
	# A freed enemy still counts as a normal kill.
	c.life_potion_charges = 0.0
	Events.enemy_killed.emit(null)
	assert_near(c.get_potion_charges("life"), 0.25, 0.0001, "null enemy counts as normal")
	# Dead players gain nothing.
	p.die(null)
	Events.enemy_killed.emit(normal)
	assert_near(c.get_potion_charges("life"), 0.25, 0.0001, "no charges while dead")
	assert_false(p.use_potion("life"), "no potions while dead")
