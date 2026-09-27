extends TestCase
## Player movement: ai_move speed / direction / facing, run animation, wall collision and
## sliding, SkillRunner movement multiplier, knockback, freeze, movement speed modifiers, WASD
## polling (screen space) and the LineEdit focus rule, the walking legs under a skill and the walk
## for slow movement.

const FakeRunner := preload("res://tests/unit/test_player_fake_runner.gd")
const PlayerVisualsScript := preload("res://scripts/entities/player/player_visuals.gd")


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## A Player with an injected FakeRunner, in GameState.world.
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


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_ai_move_speed_direction_and_facing() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	assert_eq(p.collision_layer, 2, "player layer")
	assert_eq(p.collision_mask, 5, "player mask (world + enemies)")
	assert_true(p.is_in_group("player"), "group player")
	assert_near(p.get_move_speed(), Balance.PLAYER_BASE_MOVE_SPEED, 0.001, "base move speed")
	var start := p.global_position
	p.ai_move(Vector3(1, 0, 0))
	assert_true(p.ai_control, "ai_move takes control")
	await _wait(31)
	var moved := p.global_position - start
	# 30 physics ticks at 5.2 m/s = 2.6 m.
	assert_between(moved.x, 2.3, 2.8, "moved along +X")
	assert_near(moved.z, 0.0, 0.02, "no drift")
	assert_near(p.global_position.y, 0.0, 0.0001, "stays on the floor plane")
	assert_near(p.get_forward().x, 1.0, 0.02, "faces the movement direction")
	await get_tree().process_frame
	assert_eq(p.visuals.loco_anim, "run", "run animation while moving")
	if p.anim_player != null:
		assert_near(p.anim_player.speed_scale, 1.0, 0.05, "run speed_scale = speed / 5.2")
	p.ai_move(Vector3.ZERO)
	await _wait(3)
	var stop := p.global_position
	await _wait(10)
	assert_true(p.global_position.distance_to(stop) < 0.001, "stops")
	await get_tree().process_frame
	assert_eq(p.visuals.loco_anim, "idle", "idle when standing")
	# Longer input vectors are clamped to length 1.
	p.ai_move(Vector3(0, 0, -5))
	await _wait(2)
	assert_near(_xz(p.velocity).length(), Balance.PLAYER_BASE_MOVE_SPEED, 0.05, "speed capped")


func test_walls_block_and_slide() -> void:
	await make_world()
	make_character()
	# The 16x16 arena spans -16..16 m (walls beyond).
	var p := spawn_player(Vector3(13, 0, 0))
	await _wait(2)
	p.ai_move(Vector3(1, 0, 0))
	await _wait(60)
	assert_between(p.global_position.x, 15.2, 15.7, "stopped by the east wall")
	p.ai_move(Vector3(1, 0, -1).normalized())
	await _wait(40)
	assert_between(p.global_position.x, 15.2, 15.7, "still against the wall")
	assert_true(p.global_position.z < -1.5, "slides along the wall (z=%.2f)" % p.global_position.z)
	assert_near(p.global_position.y, 0.0, 0.0001, "no vertical motion")


func test_movement_multiplier_and_knockback() -> void:
	await make_world()
	make_character()
	var p := _spawn_with_runner(Vector3.ZERO)
	var r: FakeRunner = p.skill_runner
	assert_eq(r.actor, p, "injected runner set up with the player")
	assert_eq(r.get_parent(), p, "injected runner added as a child")
	r.fk_use_time = 0.6
	r.fk_move_mult = 0.0
	await _wait(2)
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_true(r.is_busy(), "using a skill")
	var start := p.global_position
	p.ai_move(Vector3(1, 0, 0))
	await _wait(10)
	assert_true(p.global_position.distance_to(start) < 0.01, "rooted while move_mult = 0")
	await _wait(40)
	assert_false(r.is_busy(), "use finished")
	assert_true(p.global_position.x - start.x > 0.5, "moves again after the skill")
	# A partial multiplier slows the walk.
	r.fk_move_mult = 0.5
	r.fk_use_time = 2.0
	p.ai_move(Vector3.ZERO)
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	p.ai_move(Vector3(0, 0, 1))
	await _wait(3)
	assert_near(_xz(p.velocity).length(), Balance.PLAYER_BASE_MOVE_SPEED * 0.5, 0.05, "move_mult 0.5 halves the speed")
	r.cancel()
	# Knockback pushes even without input and decays.
	p.ai_move(Vector3.ZERO)
	await _wait(2)
	var before := p.global_position
	p.knockback_velocity = Vector3(-8, 0, 0)
	await _wait(30)
	assert_true(before.x - p.global_position.x > 0.8, "knocked back")
	assert_true(p.knockback_velocity.length() < 0.01, "knockback decayed")


func test_frozen_and_speed_modifiers() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	p.apply_ailment("freeze", {"duration": 0.4})
	assert_true(p.is_frozen(), "frozen")
	p.ai_move(Vector3(1, 0, 0))
	await _wait(12)
	assert_true(absf(p.global_position.x) < 0.01, "can't move while frozen")
	await _wait(24)
	assert_false(p.is_frozen(), "freeze expired")
	assert_true(p.global_position.x > 0.5, "moves after the freeze")
	p.ai_move(Vector3.ZERO)
	p.add_buff("test_haste", {"name": "Haste", "mods": [StatBlock.mod("movement_speed", "inc", 50.0)], "duration": 0.0})
	assert_near(p.get_move_speed(), Balance.PLAYER_BASE_MOVE_SPEED * 1.5, 0.01, "50% increased movement speed")
	p.ai_move(Vector3(0, 0, 1))
	await _wait(3)
	assert_near(_xz(p.velocity).length(), Balance.PLAYER_BASE_MOVE_SPEED * 1.5, 0.05, "faster walk")
	p.apply_ailment("chill", {"effect": 0.3, "duration": 2.0})
	await _wait(2)
	assert_near(_xz(p.velocity).length(), Balance.PLAYER_BASE_MOVE_SPEED * 1.5 * 0.7, 0.05, "chill slows")


func test_keyboard_polling_screen_space_and_lineedit_focus() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	assert_false(p.ai_control, "real input by default")
	Input.action_press("move_up")
	await _wait(20)
	Input.action_release("move_up")
	assert_true(p.global_position.z < -1.0, "W moves toward -Z (screen up)")
	assert_near(p.global_position.x, 0.0, 0.02, "straight up")
	await _wait(3)
	var edit := LineEdit.new()
	add_child(edit)
	edit.grab_focus()
	await get_tree().process_frame
	var here := p.global_position
	Input.action_press("move_right")
	await _wait(15)
	assert_true(p.global_position.distance_to(here) < 0.01, "no movement while typing in a LineEdit")
	edit.release_focus()
	edit.queue_free()
	await _wait(15)
	Input.action_release("move_right")
	assert_true(p.global_position.x > 0.8, "D moves toward +X once the LineEdit lost focus")
	# ai_control ignores the keyboard.
	var mark := p.global_position
	p.ai_move(Vector3.ZERO)
	Input.action_press("move_left")
	await _wait(10)
	Input.action_release("move_left")
	assert_true(p.global_position.distance_to(mark) < 0.01, "keyboard ignored under ai_control")
	p.ai_release_control()
	assert_false(p.ai_control, "control handed back")


func test_walking_legs_while_using_a_skill() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var v := p.visuals
	assert_not_null(v.legs, "leg layer built (the model has the walk clips)")
	if v.legs == null:
		return
	# Attacking toward -Z (the facing) while moving: the legs walk under the attack, by direction.
	p.ai_aim(Vector3(0, 0, -5))
	p.ai_hold_skill(0, true)
	for case in [[Vector3(1, 0, 0), "walk_right"], [Vector3(0, 0, 1), "walk_back"], [Vector3(-1, 0, 0), "walk_left"],
			[Vector3(0, 0, -1), "walk"]]:
		p.ai_move(case[0])
		await _wait(14)
		await get_tree().process_frame
		assert_ne(v.action_anim, "", "attacking")
		assert_true(v.get_legs_weight() > 0.8, "walking legs under the attack (%.2f)" % v.get_legs_weight())
		assert_eq(v.legs.dominant_clip(), String(case[1]), "moving %s: %s" % [case[0], case[1]])
		var ph := v.legs.phase
		await _wait(4)
		await get_tree().process_frame
		var step := fposmod(v.legs.phase - ph, 1.0)
		assert_true(step > 0.01 and step < 0.6, "the legs step in time (%.3f)" % step)
	# Standing still: the attack's own legs.
	p.ai_move(Vector3.ZERO)
	await _wait(15)
	await get_tree().process_frame
	assert_true(v.get_legs_weight() < 0.05, "standing: no walking legs")
	p.ai_hold_skill(0, false)
	await _wait(60)
	# Moving slowly without a skill (chilled): the walk plays instead of the run.
	p.apply_ailment("chill", {"effect": 0.5, "duration": 3.0})
	p.ai_move(Vector3(1, 0, 0))
	await _wait(10)
	await get_tree().process_frame
	assert_true(p.get_move_speed() < PlayerVisualsScript.WALK_BELOW, "slowed below the walk threshold")
	assert_eq(v.loco_anim, "walk", "slow movement walks")
	p.remove_ailment("chill")
	await _wait(10)
	await get_tree().process_frame
	assert_eq(v.loco_anim, "run", "full speed runs")
	p.ai_move(Vector3.ZERO)
