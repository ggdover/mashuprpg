extends TestCase
## Integration with the real SkillRunner / SkillDB (skills module). In the isolated wave baseline
## the runner is a stub: every test detects that and passes with a warning. Run with
##   GTEST_EXTRA="scripts/skills scripts/vfx scripts/autoload/skill_db.gd" tools/gtest.sh player-int \
##       res://tests/test_runner.tscn -- --filter=test_player_real
## to exercise: attacks damaging a monster through ai_hold_skill, the action animation chosen by
## the runner, mana costs, dodge / freeze cancelling a use, channelling while held, and
## movement_multiplier rooting the player, and a fight against a real Enemy (potion charges, XP).


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## True when the live skills module is present (not the wave-0 stub).
func _real_skills(p: Player, skill_id: String) -> bool:
	if SkillDB.get_skill(skill_id).is_empty():
		push_warning("test_player_real_skills: SkillDB has no '%s' (stub) - skipped" % skill_id)
		return false
	var check: Dictionary = p.skill_runner.can_use(skill_id)
	if String(check.get("reason", "")) == "Skills not implemented":
		push_warning("test_player_real_skills: SkillRunner is the stub - skipped")
		return false
	if not bool(check.get("ok", false)):
		push_warning("test_player_real_skills: %s can't be used (%s) - skipped" % [skill_id, check.get("reason", "")])
		return false
	return true


func test_melee_attack_damages_and_animates() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -1.6), 5000.0)
	await _wait(2)
	var id := p.get_skill_in_slot(0)
	if not _real_skills(p, id):
		return
	var started: Array = []
	p.skill_runner.skill_started.connect(func(sid: String, anim: String, dur: float) -> void: started.append([sid, anim, dur]))
	p.ai_aim(d.global_position, d)
	p.ai_hold_skill(0, true)
	await _wait(2)
	assert_true(p.skill_runner.is_busy(), "attacking")
	assert_true(started.size() >= 1, "skill_started")
	if started.size() >= 1:
		assert_eq(p.visuals.action_anim, String(started[0][1]), "the runner's animation plays on the model")
		assert_true(float(started[0][2]) > 0.1, "timed one-shot")
	assert_near(p.get_forward().z, -1.0, 0.05, "faces the target")
	var start := p.global_position
	p.ai_move(Vector3(1, 0, 0))
	await _wait(5)
	var mm: float = p.skill_runner.movement_multiplier()
	if mm <= 0.001:
		assert_true(p.global_position.distance_to(start) < 0.01, "rooted by the attack (move_mult 0)")
	p.ai_move(Vector3.ZERO)
	await _wait(70)
	p.ai_hold_skill(0, false)
	assert_true(d.life < d.max_life, "the monster took damage (%.0f / %.0f)" % [d.life, d.max_life])
	assert_true(started.size() >= 2, "held = repeated attacks (%d)" % started.size())
	await _wait(60)
	assert_false(p.skill_runner.is_busy(), "idle after release")
	assert_eq(p.visuals.action_anim, "", "locomotion after the last attack")


func test_spell_cost_and_projectile() -> void:
	await make_world()
	make_character("sorcerer")
	var p := spawn_player(Vector3.ZERO)
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -8), 5000.0)
	await _wait(2)
	var id := p.get_skill_in_slot(0)
	if not _real_skills(p, id):
		return
	var mana0 := p.mana
	p.mana_regen = 0.0
	p.ai_aim(d.global_position, d)
	p.ai_hold_skill(0, true)
	await _wait(3)
	p.ai_hold_skill(0, false)
	assert_true(p.mana < mana0, "the spell cost mana (%.1f -> %.1f)" % [mana0, p.mana])
	await _wait(90)
	assert_true(d.life < d.max_life, "the projectile hit the monster 8 m away")


func test_dodge_and_freeze_cancel_a_use() -> void:
	await make_world()
	var c := make_character("warrior")
	c.set_skill_in_slot(2, "heavy_strike")
	var p := spawn_player(Vector3.ZERO)
	spawn_dummy(Actor.Team.ENEMY, Vector3(0, 0, -1.6), 5000.0)
	await _wait(2)
	if not _real_skills(p, "heavy_strike"):
		return
	p.ai_aim(Vector3(0, 0, -1.6))
	p.ai_hold_skill(2, true)
	p.ai_hold_skill(2, false)
	await _wait(2)
	assert_true(p.skill_runner.is_busy(), "heavy strike started")
	p.ai_dodge(Vector3(1, 0, 0))
	assert_false(p.skill_runner.is_busy(), "dodge cancels the skill")
	assert_eq(p.visuals.action_anim, "dodge", "dodge animation replaces the attack")
	await _wait(40)
	p.ai_hold_skill(2, true)
	p.ai_hold_skill(2, false)
	await _wait(2)
	assert_true(p.skill_runner.is_busy(), "second heavy strike")
	p.apply_ailment("freeze", {"duration": 0.3})
	await _wait(1)
	assert_false(p.skill_runner.is_busy(), "freeze cancels the skill")


func test_whirlwind_channels_while_held() -> void:
	await make_world()
	var c := make_character("warrior")
	c.level = 12
	c.set_skill_in_slot(3, "whirlwind")
	var p := spawn_player(Vector3.ZERO)
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(1.2, 0, 0), 5000.0)
	await _wait(2)
	if not _real_skills(p, "whirlwind"):
		return
	p.ai_aim(d.global_position, d)
	p.ai_hold_skill(3, true)
	await _wait(50)
	assert_true(p.skill_runner.is_busy(), "still channelling while held")
	assert_eq(p.visuals.action_anim, "channel", "channel loop")
	var mm: float = p.skill_runner.movement_multiplier()
	assert_true(mm > 0.0 and mm < 1.0, "slowed, not rooted, while spinning (%.2f)" % mm)
	assert_true(d.life < d.max_life, "whirlwind hits")
	p.ai_hold_skill(3, false)
	await _wait(40)
	assert_false(p.skill_runner.is_busy(), "released")
	assert_ne(p.visuals.action_anim, "channel", "channel animation stopped")
	assert_near(p.model.rotation.y, 0.0, 0.0001, "model spin reset")


func test_real_enemy_fight_and_potion_charges() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	if EnemyDB.get_def("skeleton_warrior").is_empty() or not _real_skills(p, p.get_skill_in_slot(0)):
		push_warning("test_player_real_skills: EnemyDB / skills stub - skipped")
		return
	var e: Actor = EnemyDB.spawn_enemy("skeleton_warrior", Vector3(0, 0, -1.8), 1, 1, [], GameState.world)
	assert_not_null(e, "spawned a magic skeleton")
	if e == null:
		return
	c.life_potion_charges = 0.0
	c.mana_potion_charges = 0.0
	var hurt := [0]
	p.damaged.connect(func(_a: float, _c: bool, _s: Node) -> void: hurt[0] += 1)
	p.ai_aim(e.global_position, e)
	p.ai_hold_skill(0, true)
	for i in 600:
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.dead:
			break
		p.ai_aim(e.global_position, e)
	p.ai_hold_skill(0, false)
	assert_true(not is_instance_valid(e) or e.dead, "the skeleton died")
	assert_near(c.get_potion_charges("life"), Player.POTION_CHARGES_PER_KILL[1], 0.0001, "magic kill: +0.5 potion charges")
	assert_true(c.xp > 0, "xp awarded")
	assert_false(p.dead, "survived")
