extends TestCase
## Dodge roll: distance and duration, i-frames, cooldown, skill / portal cancel, animation,
## passing through monsters but not walls, direction fallbacks, WASD steering during the roll, no
## dodge while frozen or dead.

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


func test_dodge_distance_iframes_cooldown_and_cancel() -> void:
	await make_world()
	make_character()
	var p := _spawn_with_runner(Vector3(-8, 0, 0))
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 1.0
	await _wait(2)
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_true(r.is_busy(), "busy with a skill")
	assert_true(p.can_dodge(), "dodge ready")
	var start := p.global_position
	p.ai_dodge(Vector3(1, 0, 0))
	assert_true(p.dodging, "dodging")
	assert_true(r.fk_cancels >= 1, "dodge cancels the skill")
	assert_false(r.is_busy(), "no longer busy")
	assert_true(p.invulnerable_time > 0.25, "i-frames")
	assert_eq(p.collision_mask, Player.DODGE_COLLISION_MASK, "rolls through monsters")
	assert_eq(p.visuals.action_anim, "dodge", "dodge animation")
	assert_near(p.get_dodge_cooldown_ratio(), 1.0, 0.001, "cooldown started")
	assert_false(p.can_dodge(), "no double dodge")
	# Hits are ignored during the i-frames.
	var src := spawn_dummy(Actor.Team.ENEMY, Vector3(-8, 0, 6), 100.0)
	var hit := HitData.create({"physical": 30.0}, src, PackedStringArray(["attack"]))
	var life_before := p.life
	assert_eq(p.take_hit(hit), 0.0, "take_hit ignored while invulnerable")
	assert_eq(p.take_damage(20.0, "fire"), 0.0, "direct damage ignored while invulnerable")
	assert_eq(p.life, life_before, "no life lost")
	var f0 := int(Player.DODGE_TIME * 0.4 * 60.0)
	await _wait(f0)
	var early := p.global_position.distance_to(start)
	assert_true(early > Player.DODGE_DISTANCE * 0.65, "fast start: %.2f m after 40%% of the roll" % early)
	await _wait(40 - f0)   # 0.55 s roll + margin
	assert_false(p.dodging, "roll over")
	var dist := p.global_position.distance_to(start)
	assert_between(dist, Player.DODGE_DISTANCE - 0.3, Player.DODGE_DISTANCE + 0.3, "rolled ~%.0f m (%.2f)" % [Player.DODGE_DISTANCE, dist])
	assert_near(p.global_position.z, start.z, 0.02, "straight")
	assert_eq(p.collision_mask, Player.COLLISION_MASK, "mask restored")
	await get_tree().process_frame
	assert_ne(p.visuals.action_anim, "dodge", "dodge animation over")
	assert_false(p.can_dodge(), "still on cooldown")
	assert_between(p.get_dodge_cooldown_ratio(), 0.3, 0.8, "cooldown ratio counts down")
	await _wait(50)
	assert_true(p.can_dodge(), "ready after 1.2 s")
	assert_near(p.get_dodge_cooldown_ratio(), 0.0, 0.001, "ratio back to 0")


func test_dodge_passes_monsters_but_not_walls() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3(-8, 0, 0))
	spawn_dummy(Actor.Team.ENEMY, Vector3(-5, 0, 0), 100.0)
	await _wait(3)
	# Walking into the monster is blocked...
	p.ai_move(Vector3(1, 0, 0))
	await _wait(40)
	assert_true(p.global_position.x < -5.5, "walking is blocked by the monster (x=%.2f)" % p.global_position.x)
	p.ai_move(Vector3.ZERO)
	await _wait(2)
	# ...rolling is not.
	var start := p.global_position
	p.ai_dodge(Vector3(1, 0, 0))
	await _wait(40)
	assert_true(p.global_position.x > -4.5, "rolled through the monster (x=%.2f)" % p.global_position.x)
	assert_between(p.global_position.distance_to(start), Player.DODGE_DISTANCE - 0.5, Player.DODGE_DISTANCE + 0.3, "full distance")
	# Walls stop a roll.
	await _wait(80)
	p.global_position = Vector3(13, 0, 4)
	await _wait(2)
	p.ai_dodge(Vector3(1, 0, 0))
	await _wait(40)
	assert_between(p.global_position.x, 15.0, 15.7, "stopped at the wall")


func test_dodge_direction_fallbacks() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	# No move direction: toward the aim point.
	p.ai_aim(Vector3(0, 0, -10))
	await _wait(2)
	p.ai_dodge(Vector3.ZERO)
	await _wait(40)
	assert_true(p.global_position.z < -Player.DODGE_DISTANCE + 0.5, "rolled toward the aim (z=%.2f)" % p.global_position.z)
	assert_near(p.global_position.x, 0.0, 0.05, "straight toward the aim")
	assert_near(p.get_forward().z, -1.0, 0.02, "faces the roll direction")
	# The move direction wins over the aim.
	await _wait(80)
	var start := p.global_position
	p.ai_move(Vector3(1, 0, 0))
	await _wait(2)
	p.ai_dodge(Vector3(1, 0, 0))
	await _wait(36)
	p.ai_move(Vector3.ZERO)
	assert_true(p.global_position.x - start.x > Player.DODGE_DISTANCE - 0.5, "rolled along the move direction")


func test_dodge_is_steered_by_wasd() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3(-6, 0, 6))
	await _wait(2)
	var start := p.global_position
	# Roll east, then hold "up" (north, -Z) for the rest of the roll: it curves north.
	p.ai_dodge(Vector3(1, 0, 0))
	await _wait(3)
	p.ai_move(Vector3(0, 0, -1))
	await _wait(40)
	p.ai_move(Vector3.ZERO)
	assert_false(p.dodging, "roll over")
	var d := p.global_position - start
	assert_true(d.x > 1.0, "started east (dx=%.2f)" % d.x)
	assert_true(d.z < -1.5, "steered north during the roll (dz=%.2f)" % d.z)
	assert_true(Vector2(d.x, d.z).length() < Player.DODGE_DISTANCE + 0.2, "no longer than a straight roll")
	# Fast first, then slowing down: most of the distance early, the rise at the end slow.
	assert_true(Player.dodge_progress(0.4) > 0.75, "~80% of the roll in the first 40% of its time")
	assert_true(Player.dodge_progress(0.7) - Player.dodge_progress(0.4) < 0.2, "the rest is slow")
	assert_near(Player.dodge_progress(1.0), 1.0, 0.0001, "whole distance at the end")


func test_no_dodge_while_frozen_or_dead() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	p.apply_ailment("freeze", {"duration": 0.5})
	p.ai_dodge(Vector3(1, 0, 0))
	assert_false(p.dodging, "frozen: no dodge")
	await _wait(40)
	assert_false(p.is_frozen(), "thawed")
	p.die(null)
	p.ai_dodge(Vector3(1, 0, 0))
	assert_false(p.dodging, "dead: no dodge")
	assert_false(p.can_dodge(), "can_dodge false when dead")
