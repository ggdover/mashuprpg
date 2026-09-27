extends TestCase
## Parry (hold Shift): while the guard is up a hostile hit is caught (no damage), stuns and knocks
## back the monsters in the cone in front and gives a parry charge (buff) that the next damaging
## skill uses up (SkillEmpower: more damage, projectiles, chains, area, attack echo); the guard drops
## and a 3 s cooldown starts (none without a parry), and comes back by itself while still held.
## What the guard cancels and blocks, the stun ailment. Also moving while using a skill (slowed, not
## rooted) and cutting the recovery short by moving off after the hit.

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


## A hit from `src` that cannot be evaded or blocked (so only the parry decides).
func _hit_from(src: Actor, amount: float = 40.0) -> HitData:
	var h := HitData.create({"physical": amount}, src, PackedStringArray(["attack"]))
	h.can_evade = false
	h.can_block = false
	return h


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_parry_catches_a_hit_and_counters() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var front := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -2.0), 500.0)
	var side := spawn_dummy(Actor.Team.ENEMY, Vector3(3.0, 0, -1.5), 500.0)
	var behind := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, 3.0), 500.0)
	var far := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -9.0), 500.0)
	await _wait(2)
	p.ai_aim(Vector3(0, 0, -5))
	await _wait(1)
	assert_true(p.can_parry(), "parry ready")
	assert_true(p.ai_parry(), "guard up (key held)")
	await _wait(90)
	assert_true(p.is_parrying(), "the guard stays up as long as the key is held")
	await get_tree().process_frame
	assert_eq(p.visuals.action_anim, "parry_hold", "held guard animation")
	var life := p.life
	assert_eq(p.take_hit(_hit_from(front)), 0.0, "the blow is caught")
	assert_eq(p.life, life, "no damage")
	assert_true(front.is_stunned(), "the attacker is stunned")
	assert_false(front.can_act(), "stunned monsters cannot act")
	assert_true(front.knockback_velocity.z < -5.0, "knocked back away from the player")
	assert_true(side.is_stunned(), "a monster beside, in front, is stunned too")
	assert_false(behind.is_stunned(), "the one behind is not")
	assert_eq(behind.knockback_velocity, Vector3.ZERO, "nor knocked back")
	assert_false(far.is_stunned(), "out of reach: not stunned")
	assert_eq(p.get_parry_charges(), 1, "a parry charge")
	assert_true(p.has_buff(Player.PARRY_BUFF), "shown as a buff")
	assert_false(p.is_parrying(), "a parry drops the guard")
	assert_near(p.get_parry_cooldown_ratio(), 1.0, 0.02, "and starts the cooldown")
	assert_false(p.can_parry(), "on cooldown")
	# The rest of a combo right after it does not land (short invulnerability), no second charge.
	assert_eq(p.take_hit(_hit_from(side)), 0.0, "the next blow right after is avoided")
	assert_eq(p.get_parry_charges(), 1, "at most one charge")
	# The stun wears off; still holding the key, the guard comes back up after the cooldown.
	await _wait(int(Player.PARRY_STUN * 60.0) + 10)
	assert_false(front.is_stunned(), "stun over")
	assert_true(front.can_act(), "acts again")
	assert_false(p.is_parrying(), "still cooling down (%.2f)" % p.get_parry_cooldown_ratio())
	await _wait(int((Player.PARRY_COOLDOWN - Player.PARRY_STUN) * 60.0) + 10)
	assert_true(p.is_parrying(), "guard back up by itself (key still held) after %.0f s" % Player.PARRY_COOLDOWN)
	assert_eq(p.get_parry_charges(), 1, "the charge is kept until a skill uses it")
	p.ai_release_parry()
	assert_false(p.is_parrying(), "released")


func test_parry_hold_release_and_dodge() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var src := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -2.0), 500.0)
	await _wait(2)
	assert_true(p.ai_parry(), "guard up")
	await _wait(30)
	p.ai_release_parry()
	assert_false(p.is_parrying(), "releasing the key lowers the guard")
	await get_tree().process_frame
	assert_ne(p.visuals.action_anim, "parry_hold", "guard animation over")
	assert_true(p.take_hit(_hit_from(src)) > 0.0, "hits land again when the guard is down")
	assert_eq(p.get_parry_charges(), 0, "no parry, no charge")
	assert_false(src.is_stunned(), "and nothing stunned")
	assert_near(p.get_parry_cooldown_ratio(), 0.0, 0.001, "lowering the guard costs no cooldown")
	assert_true(p.can_parry(), "raise it again right away")
	# A dodge roll drops the guard; still holding the key, it comes back after the roll.
	assert_true(p.ai_parry(), "guard up again")
	p.ai_dodge(Vector3(1, 0, 0))
	assert_true(p.dodging, "rolling")
	assert_false(p.is_parrying(), "the roll dropped the guard")
	await _wait(int(Player.DODGE_TIME * 60.0) + 5)
	assert_false(p.dodging, "roll over")
	assert_true(p.is_parrying(), "guard back up (key still held)")
	# Stunned: the guard drops and comes back when the stun ends.
	p.apply_ailment("stun", {"duration": 0.3})
	assert_false(p.can_act(), "stunned player cannot act")
	assert_false(p.is_parrying(), "no guard while stunned")
	await _wait(25)
	assert_true(p.is_parrying(), "guard back after the stun")
	p.ai_release_parry()


func test_parry_cancels_and_holds_back_skills() -> void:
	await make_world()
	make_character()
	var p := _spawn_with_runner(Vector3.ZERO)
	var r: FakeRunner = p.skill_runner
	r.fk_use_time = 1.0
	await _wait(2)
	p.ai_hold_skill(0, true)
	await _wait(2)
	assert_true(r.is_busy(), "attacking")
	assert_eq(r.fk_use_count(p.get_skill_in_slot(0)), 1, "one use")
	assert_true(p.ai_parry(), "the guard interrupts the attack")
	assert_true(r.fk_cancels >= 1, "skill cancelled")
	assert_false(r.is_busy(), "no longer busy")
	await _wait(30)
	assert_eq(r.fk_use_count(p.get_skill_in_slot(0)), 1, "no skill while guarding (key still held)")
	p.ai_release_parry()
	await _wait(3)
	assert_false(p.is_parrying(), "guard lowered")
	assert_eq(r.fk_use_count(p.get_skill_in_slot(0)), 2, "the held skill goes on after the guard")
	p.ai_hold_skill(0, false)


func test_empowered_attack_strikes_twice() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -1.6), 100000.0)
	await _wait(2)
	assert_eq(p.get_skill_in_slot(0), "basic_attack", "warrior slot 1 = attack")
	var hits: Array = []
	d.damaged.connect(func(amount: float, _crit: bool, _src: Node) -> void: hits.append(amount))
	p.grant_parry_charge()
	assert_eq(p.get_parry_charges(), 1, "charge granted")
	p.ai_aim(d.global_position, d)
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	var use: SkillUse = p.skill_runner.last_use
	assert_not_null(use, "attack started")
	if use == null:
		return
	assert_true(use.empowered, "the attack used the charge")
	assert_true(use.echo, "attacks echo")
	assert_near(use.more_damage, SkillEmpower.MORE_DAMAGE, 0.001, "more damage")
	assert_eq(p.get_parry_charges(), 0, "charge used")
	assert_false(p.has_buff(Player.PARRY_BUFF), "buff gone")
	await _wait(100)
	assert_eq(hits.size(), 2, "struck twice: the swing and its echo")
	# The next attack is a normal one.
	hits.clear()
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_false((p.skill_runner.last_use as SkillUse).empowered, "no charge left: normal attack")
	await _wait(100)
	assert_eq(hits.size(), 1, "struck once")


func test_empower_effects_by_skill() -> void:
	await make_world()
	make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	var dummy := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -4.0), 5000.0)
	await _wait(2)
	# Projectiles: two more, in a wider fan.
	var split := SkillDB.get_resolved("split_arrow", p)
	var u := SkillUse.create(p, split, Vector3(0, 0, -8))
	var n0 := SkillDeliveries.fire_projectiles(u, p).size()
	var ue := SkillUse.create(p, split, Vector3(0, 0, -8))
	SkillEmpower.apply(ue)
	assert_eq(ue.extra_projectiles, SkillEmpower.EXTRA_PROJECTILES, "extra projectiles")
	assert_eq(SkillDeliveries.fire_projectiles(ue, p).size(), n0 + SkillEmpower.EXTRA_PROJECTILES, "fires them")
	assert_true(ue.echo, "a bow attack echoes")
	# Areas: a bigger nova; spells do not echo.
	var nova := SkillDB.get_resolved("frost_nova", p)
	var un := SkillUse.create(p, nova, Vector3.ZERO)
	var a0 := un.area_mult
	SkillEmpower.apply(un)
	assert_near(un.area_mult, a0 * SkillEmpower.AREA_MULT, 0.001, "bigger area")
	assert_false(un.echo, "spells do not echo")
	# Chains.
	var uc := SkillUse.create(p, SkillDB.get_resolved("chain_lightning", p), Vector3(0, 0, -6))
	SkillEmpower.apply(uc)
	assert_eq(uc.extra_chains, SkillEmpower.EXTRA_CHAINS, "extra chains")
	# More damage on every hit (same rolls with the same seed).
	var fb := SkillDB.get_resolved("fireball", p)
	var plain := SkillUse.create(p, fb, dummy.global_position, dummy)
	var strong := SkillUse.create(p, fb, dummy.global_position, dummy)
	SkillEmpower.apply(strong)
	seed(42)
	var h0 := plain.build_hit(dummy)
	seed(42)
	var h1 := strong.build_hit(dummy)
	assert_near(h1.total() / maxf(0.001, h0.total()), 1.0 + SkillEmpower.MORE_DAMAGE / 100.0, 0.01, "50% more damage")
	# Buffs, teleports and summons keep the charge.
	assert_false(SkillEmpower.can_empower(SkillDB.get_resolved("war_cry", p)), "war cry does not use it")
	assert_false(SkillEmpower.can_empower(SkillDB.get_resolved("teleport", p)), "teleport does not use it")
	assert_true(SkillEmpower.can_empower(fb), "fireball uses it")


func test_move_while_using_a_skill() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var r := p.skill_runner
	p.ai_aim(Vector3(0, 0, -5))
	# Holding the attack: the player keeps moving, heavily slowed.
	p.ai_hold_skill(0, true)
	await _wait(2)
	assert_true(r.is_busy(), "attacking")
	p.ai_move(Vector3(1, 0, 0))
	await _wait(3)
	assert_near(_xz(p.velocity).length(), p.get_move_speed() * SkillRunner.PLAYER_SKILL_MOVE_MULT, 0.1, "slowed, not rooted")
	await _wait(60)
	assert_true(r.is_busy(), "still attacking while the key is held")
	p.ai_hold_skill(0, false)
	p.ai_move(Vector3.ZERO)
	await _wait(90)
	assert_false(r.is_busy(), "done")
	# A single attack standing still plays out its whole recovery...
	var frames := {}
	r.skill_effect.connect(func(_id: String) -> void: frames["effect"] = Engine.get_physics_frames())
	r.skill_finished.connect(func(_id: String) -> void: frames["finish"] = Engine.get_physics_frames())
	var f0 := Engine.get_physics_frames()
	p.ai_hold_skill(0, true)
	await _wait(1)
	p.ai_hold_skill(0, false)
	var dur := int(r.get_duration() * 60.0)
	await _wait(dur + 10)
	var still_len := int(frames.get("finish", 0)) - f0
	assert_true(still_len >= dur - 2, "standing still: the full use (%d of %d frames)" % [still_len, dur])
	# ...moving off after the hit ends it at once, back to full speed.
	frames.clear()
	p.ai_move(Vector3(0, 0, 1))
	f0 = Engine.get_physics_frames()
	p.ai_hold_skill(0, true)
	await _wait(1)
	p.ai_hold_skill(0, false)
	await _wait(dur + 10)
	assert_true(frames.has("effect") and frames.has("finish"), "hit and finished")
	var cut := int(frames.get("finish", 0)) - int(frames.get("effect", 0))
	assert_true(cut <= 2, "recovery cut right after the hit (%d frames)" % cut)
	assert_true(int(frames.get("finish", 0)) - f0 < dur - 3, "shorter than the full use")
	assert_near(_xz(p.velocity).length(), p.get_move_speed(), 0.1, "full speed again")
	p.ai_move(Vector3.ZERO)
