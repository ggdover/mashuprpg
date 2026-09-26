extends TestCase
## Skill input logic with an injected FakeRunner: hold = repeat, update_target while held,
## release on key up, tap buffering, press-while-busy buffering, empty slots, aim target from
## the hovered enemy, no use while frozen / dodging, channel release, keyboard + mouse press
## paths (push_input) and facing rules while busy.

const FakeRunner := preload("res://tests/unit/test_player_fake_runner.gd")


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _spawn_with_runner(pos: Vector3 = Vector3.ZERO) -> Player:
	if GameState.character == null:
		make_character()
	var p := Player.new()
	p.setup(GameState.character)
	p.position = pos
	p.skill_runner = FakeRunner.new()
	GameState.world.add_child(p)
	GameState.player = p
	return p


func test_hold_repeats_updates_and_releases() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 0.25
	await _wait(2)
	var id := p.get_skill_in_slot(0)
	assert_eq(id, c.skill_bar[0], "slot 0 skill")
	p.ai_aim(Vector3(0, 0, -5))
	p.ai_hold_skill(0, true)
	assert_true(p.is_slot_held(0), "held")
	await _wait(62)   # ~1 s
	var n := r.fk_use_count(id)
	assert_between(n, 3, 5, "repeats while held (%d uses in 1 s at 0.25 s each)" % n)
	assert_true(r.fk_updates > 10, "update_target while held and busy")
	assert_near(r.fk_last_update_pos.z, -5.0, 0.01, "update_target gets the aim")
	assert_near((r.fk_uses[0]["pos"] as Vector3).z, -5.0, 0.01, "try_use gets the aim position")
	p.ai_hold_skill(0, false)
	assert_false(p.is_slot_held(0), "released")
	assert_has(r.fk_releases, id, "release() on key up")
	await _wait(20)
	var n2 := r.fk_use_count(id)
	await _wait(30)
	assert_eq(r.fk_use_count(id), n2, "no more uses after release")


func test_tap_and_busy_buffering() -> void:
	await make_world()
	var c := make_character("warrior")
	c.set_skill_in_slot(2, "heavy_strike")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 0.2
	await _wait(2)
	# Press + release before the next physics tick = exactly one use.
	p.ai_hold_skill(2, true)
	p.ai_hold_skill(2, false)
	await _wait(30)
	assert_eq(r.fk_use_count("heavy_strike"), 1, "a tap uses the skill once")
	# A press while busy is buffered and fires when the runner is free.
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_true(r.is_busy(), "busy with slot 0")
	p.ai_hold_skill(2, true)
	p.ai_hold_skill(2, false)
	await _wait(20)
	assert_eq(r.fk_use_count("heavy_strike"), 2, "buffered press used after the current skill")
	assert_eq(r.fk_use_count(c.skill_bar[0]), 1, "slot 0 used once")
	# A buffered press expires after INPUT_BUFFER_TIME.
	await _wait(20)
	assert_false(r.is_busy(), "idle again")
	r.fk_use_time = 0.8
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	p.ai_hold_skill(2, true)
	p.ai_hold_skill(2, false)
	await _wait(60)
	assert_eq(r.fk_use_count("heavy_strike"), 2, "stale buffered press dropped")
	# Empty slots do nothing.
	var before := r.fk_attempts.size()
	p.ai_hold_skill(5, true)
	await _wait(5)
	p.ai_hold_skill(5, false)
	assert_eq(r.fk_attempts.size(), before, "empty slot never calls try_use")


func test_hovered_enemy_is_the_target() -> void:
	await make_world()
	make_character("ranger")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	var enemy := spawn_dummy(Actor.Team.ENEMY, Vector3(5, 0, 3), 500.0)
	await _wait(2)
	var hovered: Array = []
	var cb := func(n: Node) -> void: hovered.append(n)
	Events.hovered_target_changed.connect(cb)
	p.ai_aim(Vector3(4.5, 0, 3.2), enemy)
	await _wait(2)
	assert_eq(p.get_hovered(), enemy, "enemy hovered")
	assert_eq(p.get_aim_target(), enemy, "enemy targeted")
	assert_near(p.get_aim_position().x, 5.0, 0.001, "aim snaps to the enemy position")
	assert_eq(hovered.size(), 1, "hovered_target_changed emitted once")
	p.ai_hold_skill(0, true)
	await _wait(3)
	p.ai_hold_skill(0, false)
	assert_eq(r.fk_uses.size(), 1, "used")
	assert_eq(r.fk_uses[0]["target"], enemy, "try_use target = hovered enemy")
	assert_near(p.get_forward().dot(Vector3(5, 0, 3).normalized()), 1.0, 0.01, "faces the target")
	# Friendly actors are hovered but not targeted.
	var friend := spawn_dummy(Actor.Team.PLAYER, Vector3(-3, 0, 0), 100.0)
	p.ai_aim(Vector3(-3, 0, 0), friend)
	await _wait(2)
	assert_eq(p.get_aim_target(), null, "allies are not skill targets")
	# A dead enemy is dropped from hover.
	p.ai_aim(Vector3(5, 0, 3), enemy)
	await _wait(2)
	enemy.die(null)
	await _wait(2)
	assert_eq(p.get_hovered(), null, "dead enemy unhovered")
	assert_eq(hovered.back(), null, "hover cleared event")
	Events.hovered_target_changed.disconnect(cb)


func test_no_skills_while_frozen_dodging_or_dead() -> void:
	await make_world()
	make_character("warrior")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	await _wait(2)
	p.apply_ailment("freeze", {"duration": 0.3})
	p.ai_hold_skill(0, true)
	await _wait(10)
	assert_eq(r.fk_uses.size(), 0, "no use while frozen")
	await _wait(20)
	assert_true(r.fk_uses.size() >= 1, "used once thawed (still held)")
	p.ai_hold_skill(0, false)
	await _wait(30)
	var n := r.fk_uses.size()
	p.ai_dodge(Vector3(1, 0, 0))
	p.ai_hold_skill(0, true)
	await _wait(8)
	assert_eq(r.fk_uses.size(), n, "no use while dodging")
	await _wait(20)
	assert_true(r.fk_uses.size() > n, "used after the roll")
	p.ai_hold_skill(0, false)
	await _wait(30)
	n = r.fk_uses.size()
	p.die(null)
	p.ai_hold_skill(0, true)
	await _wait(10)
	assert_eq(r.fk_uses.size(), n, "no use when dead")


func test_channel_holds_until_release() -> void:
	await make_world()
	var c := make_character("warrior")
	c.set_skill_in_slot(3, "whirlwind")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	r.fk_channel_ids.assign(["whirlwind"])
	r.fk_move_mult = 0.6
	await _wait(2)
	p.ai_hold_skill(3, true)
	await _wait(5)
	assert_true(r.is_busy(), "channelling")
	assert_eq(p.visuals.action_anim, "channel", "channel animation loops")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(absf(p.model.rotation.y) > 0.01, "the model spins while channelling")
	p.ai_move(Vector3(1, 0, 0))
	await _wait(3)
	assert_near(Vector2(p.velocity.x, p.velocity.z).length(), Balance.PLAYER_BASE_MOVE_SPEED * 0.6, 0.05, "moves at the channel's move_mult")
	p.ai_move(Vector3.ZERO)
	await _wait(30)
	assert_eq(r.fk_use_count("whirlwind"), 1, "one channel while held")
	p.ai_hold_skill(3, false)
	assert_false(r.is_busy(), "released")
	await get_tree().process_frame
	assert_eq(p.visuals.action_anim, "", "back to locomotion")
	assert_near(p.model.rotation.y, 0.0, 0.0001, "model spin reset")
	# A tapped channel skill stops right away.
	p.ai_hold_skill(3, true)
	p.ai_hold_skill(3, false)
	await _wait(3)
	assert_eq(r.fk_use_count("whirlwind"), 2, "tap starts it")
	assert_false(r.is_busy(), "tap releases it immediately")


func test_keyboard_and_mouse_presses() -> void:
	await make_world()
	var c := make_character("warrior")
	c.set_skill_in_slot(2, "heavy_strike")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 0.15
	await _wait(2)
	# Q (skill_3) through _unhandled_input; held while Input says so.
	Input.action_press("skill_3")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	get_viewport().push_input(q, true)
	await _wait(40)
	Input.action_release("skill_3")
	assert_true(r.fk_use_count("heavy_strike") >= 2, "held Q repeats (%d)" % r.fk_use_count("heavy_strike"))
	await _wait(5)
	assert_has(r.fk_releases, "heavy_strike", "released when the key is up")
	# LMB press: one use (tap) when not over UI and nothing interactable is hovered.
	var n := r.fk_use_count(c.skill_bar[0])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(960, 540)
	get_viewport().push_input(mb, true)
	await _wait(20)
	assert_eq(r.fk_use_count(c.skill_bar[0]), n + 1, "LMB uses skill slot 1")
	# Echo key events are ignored; ai_control ignores real input.
	p.ai_move(Vector3.ZERO)
	var before := r.fk_uses.size()
	get_viewport().push_input(q.duplicate(), true)
	await _wait(20)
	assert_eq(r.fk_uses.size(), before, "real input ignored under ai_control")


func test_facing_rules() -> void:
	await make_world()
	make_character("warrior")
	var p := _spawn_with_runner()
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 1.0
	r.fk_move_mult = 0.5
	await _wait(2)
	p.ai_aim(Vector3(0, 0, 8))
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_near(p.get_forward().z, 1.0, 0.01, "faces the aim when attacking")
	p.ai_move(Vector3(-1, 0, 0))
	await _wait(20)
	assert_near(p.get_forward().z, 1.0, 0.01, "keeps facing the target while busy")
	await _wait(50)
	assert_near(p.get_forward().x, -1.0, 0.02, "turns to the movement once free")
