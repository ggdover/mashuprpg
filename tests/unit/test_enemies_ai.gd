extends TestCase
## Enemy AI (§12): aggro by radius + line of sight or when hit (DoTs too), pack aggro, chasing
## (paths around walls), ranged kiting / preferred range, skill choice + pauses, hit stagger
## (§6.7), sleeping, leaving combat, bosses (roar + boss_spawned, rotation, reset).
## Uses a scripted SkillRunner (FakeRunner) where skill use matters. OWNER: enemies.


## Records skill uses; every use keeps the runner busy for `busy_len` seconds.
class FakeRunner extends SkillRunner:
	var uses: Array = []
	var busy_len := 0.5
	var cancels := 0
	var fk_clock := 0.0
	var _fk_busy := 0.0
	var _fk_current := ""

	func can_use(skill_id: String) -> Dictionary:
		if actor == null or not actor.can_act():
			return {"ok": false, "reason": "Cannot act", "code": "cannot_act"}
		if skill_id == "":
			return {"ok": false, "reason": "Unknown", "code": "unknown"}
		return {"ok": true, "reason": "", "code": "ok"}

	func try_use(skill_id: String, target_pos: Vector3, _target: Actor = null) -> bool:
		if _fk_busy > 0.0 or not bool(can_use(skill_id)["ok"]):
			return false
		uses.append({"id": skill_id, "t": fk_clock, "pos": target_pos,
			"dist": CombatQuery.distance_to_actor(actor.global_position, _target) if _target != null else -1.0})
		_fk_busy = busy_len
		_fk_current = skill_id
		actor.face_towards(target_pos)
		skill_started.emit(skill_id, "attack_slash", busy_len)
		actor.play_action_animation("attack_slash", busy_len)
		return true

	func is_busy() -> bool:
		return _fk_busy > 0.0

	func get_current_skill() -> String:
		return _fk_current if _fk_busy > 0.0 else ""

	func movement_multiplier() -> float:
		return 0.0 if _fk_busy > 0.0 else 1.0

	func cancel() -> void:
		cancels += 1
		if _fk_busy > 0.0:
			_fk_busy = 0.0
			actor.stop_action_animation()

	func _physics_process(delta: float) -> void:
		fk_clock += delta
		if _fk_busy > 0.0:
			_fk_busy -= delta
			if _fk_busy <= 0.0:
				skill_finished.emit(_fk_current)


func _spawn(id: String, pos: Vector3, runner: SkillRunner = null, rarity: int = 0, level: int = 5) -> Enemy:
	var e := Enemy.new()
	e.setup(EnemyDB.get_def(id), level, rarity, [])
	e.position = pos
	if runner != null:
		e.skill_runner = runner
	GameState.world.add_enemy(e)
	return e


func _wait(seconds: float) -> void:
	var n := int(ceil(seconds * 60.0))
	for i in n:
		await get_tree().physics_frame


## Grid-only wall (walkability + LOS) along x = wx for z in [z0, z1] (world metres).
func _grid_wall(w: World, wx: float, z0: float, z1: float) -> void:
	var z := z0
	while z <= z1:
		var c := w.world_to_cell(Vector3(wx, 0, z))
		w.grid.set_walkable(c, false)
		w.grid.set_opaque(c, true)
		w.grid.update_astar_cell(c)
		z += 1.0


func test_aggro_by_radius() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 5000.0)
	var e := _spawn("skeleton_warrior", Vector3(-4, 0, 0))
	var far := _spawn("zombie", Vector3(-10, 0, 12))   # 18 m away, aggro radius 9
	assert_eq(e.state, Enemy.State.IDLE, "starts idle")
	await _wait(0.5)
	assert_eq(e.state, Enemy.State.COMBAT, "aggro within radius")
	assert_eq(e.get_target(), d, "targets the player-team actor")
	assert_eq(far.state, Enemy.State.IDLE, "out of radius stays idle")
	assert_true(far.get_target() == null, "no target")


func test_no_aggro_without_line_of_sight() -> void:
	var w := await make_world()
	_grid_wall(w, 0.5, -15.0, 15.0)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 5000.0)
	var e := _spawn("skeleton_warrior", Vector3(-4, 0, 0))
	await _wait(0.5)
	assert_eq(e.state, Enemy.State.IDLE, "wall blocks sight")
	# Open the wall: now it sees the target.
	for z in range(-15, 16):
		var c := w.world_to_cell(Vector3(0.5, 0, z))
		w.grid.set_opaque(c, false)
	await _wait(0.4)
	assert_eq(e.state, Enemy.State.COMBAT, "aggro once visible")
	assert_eq(e.get_target(), d, "target")


func test_aggro_when_hit() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-14, 0, 12), 5000.0)
	var e := _spawn("zombie", Vector3(4, 0, 0))
	await _wait(0.3)
	assert_eq(e.state, Enemy.State.IDLE, "too far to notice")
	var h := HitData.create({"physical": 3.0}, d, PackedStringArray(["attack", "projectile"]))
	h.can_evade = false
	h.can_block = false
	assert_true(e.take_hit(h) > 0.0, "hit landed")
	assert_eq(e.state, Enemy.State.COMBAT, "aggro on hit")
	assert_eq(e.get_target(), d, "targets the attacker")
	await _wait(0.5)
	assert_eq(e.get_target(), d, "keeps the target beyond its aggro radius")


func test_dot_damage_wakes_up() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-14, 0, 12), 5000.0)
	var e := _spawn("zombie", Vector3(4, 0, 0))
	await _wait(0.2)
	assert_false(e.visuals.is_bar_visible(), "no life bar before damage")
	e.apply_ailment("poison", {"dps": 2.0, "duration": 2.0, "source": d})
	await _wait(0.5)
	assert_eq(e.state, Enemy.State.COMBAT, "damage over time aggroes")
	assert_eq(e.get_target(), d, "nearest hostile")
	assert_true(e.visuals.is_bar_visible(), "DoT damage shows the life bar")
	# Already fighting (never hit directly): a DoT alone still shows the bar (§12).
	var f := _spawn("zombie", Vector3(-4, 0, -6))
	f.aggro(d, false)
	await _wait(0.3)
	assert_false(f.visuals.is_bar_visible(), "undamaged fighter: no bar")
	f.apply_ailment("ignite", {"dps": 3.0, "duration": 2.0, "source": d})
	await _wait(0.5)
	assert_true(f.visuals.is_bar_visible(), "ignite shows the bar of a fighting monster")


func test_pack_aggro() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-14, 0, 14), 5000.0)
	var a := _spawn("zombie", Vector3(-8, 0, -8))
	var b := _spawn("zombie", Vector3(8, 0, 8))        # same pack, far away
	var c := _spawn("zombie", Vector3(-8, 0, -3))      # other pack, 5 m from a
	var other := _spawn("zombie", Vector3(8, 0, -8))   # other pack, 16 m away
	a.pack_id = 1
	b.pack_id = 1
	c.pack_id = 2
	other.pack_id = 3
	await _wait(0.3)
	assert_eq(a.state, Enemy.State.IDLE, "idle before")
	a.aggro(d)
	assert_eq(a.state, Enemy.State.COMBAT, "a aggroed")
	assert_eq(b.state, Enemy.State.COMBAT, "same pack aggroes together")
	assert_eq(c.state, Enemy.State.COMBAT, "within 8 m aggroes")
	assert_eq(other.state, Enemy.State.IDLE, "unrelated far enemy stays idle")
	await _wait(0.3)
	assert_eq(other.state, Enemy.State.IDLE, "still idle")
	assert_eq(c.get_target(), d, "pack member targets the player")


func test_chase_and_run_animation() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(12, 0, 0), 5000.0)
	var e := _spawn("skeleton_warrior", Vector3(-10, 0, 0))
	e.aggro(d)
	var start := CombatQuery.distance_xz(e.global_position, d.global_position)
	await _wait(0.8)
	var ap := e.visuals.anim
	assert_not_null(ap, "animation player")
	if ap != null:
		assert_eq(String(ap.current_animation), "run", "run cycle while chasing")
		var want := e.get_move_speed() / EnemyDB.get_model_run_speed("char_skeleton")
		assert_near(ap.speed_scale, want, 0.05, "run speed_scale = move speed / reference")
	await _wait(0.8)
	var now := CombatQuery.distance_xz(e.global_position, d.global_position)
	assert_true(start - now > 3.0, "closed in (%.1f -> %.1f)" % [start, now])
	assert_true(absf(e.global_position.y) < 0.01, "stays on the floor")


func test_melee_stops_in_reach() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(5, 0, 0), 5000.0)
	var e := _spawn("zombie", Vector3(-1, 0, 0))
	await _wait(3.0)
	var dist := CombatQuery.distance_to_actor(e.global_position, d)
	var reach: Vector2 = e._skill_ranges["m_melee"]
	assert_true(dist <= reach.y + 0.05, "in melee reach (%.2f <= %.2f)" % [dist, reach.y])
	assert_true(CombatQuery.distance_xz(e.global_position, d.global_position) > 0.6, "does not walk into the target")
	var ap := e.visuals.anim
	if ap != null and not bool(e.skill_runner.can_use("m_melee")["ok"]):
		assert_eq(String(ap.current_animation), "idle", "idles in reach when it cannot attack")


func test_chase_paths_around_walls() -> void:
	var w := await make_world()
	_grid_wall(w, 0.5, -15.0, 6.0)   # gap at z > 6
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(6, 0, -6), 5000.0)
	var e := _spawn("ghoul", Vector3(-6, 0, -6))
	e.aggro(d)
	var max_z := -INF
	var crossed := false
	for i in 30:
		await _wait(0.15)
		max_z = maxf(max_z, e.global_position.z)
		if e.global_position.x > 1.5:
			crossed = true
			break
	assert_true(crossed, "reached the far side (x %.1f)" % e.global_position.x)
	assert_true(max_z > 5.0, "went around through the gap (max z %.1f)" % max_z)


func test_ranged_kites_when_close() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(1.5, 0, 0), 5000.0)
	var e := _spawn("skeleton_archer", Vector3(-1, 0, 0))
	e.aggro(d)
	var start := CombatQuery.distance_xz(e.global_position, d.global_position)
	await _wait(1.2)
	var now := CombatQuery.distance_xz(e.global_position, d.global_position)
	assert_true(now > start + 2.0, "stepped back (%.1f -> %.1f)" % [start, now])


func test_ranged_keeps_preferred_range() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(8, 0, 0), 5000.0)
	var e := _spawn("skeleton_archer", Vector3(-12, 0, 0))
	e.aggro(d)
	await _wait(4.0)
	var dist := CombatQuery.distance_to_actor(e.global_position, d)
	var pref := float(e.def["preferred_range"])
	var reach := float(e.def["skills"][0]["range"])
	assert_between(dist, pref * 0.6, reach + 0.6, "approaches to its range, not into melee (%.1f)" % dist)
	if not bool(e.skill_runner.can_use("m_arrow")["ok"]):
		assert_between(dist, pref * 0.6, pref + 1.6, "holds its preferred range (%.1f)" % dist)


func test_skill_use_and_pause() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(1.4, 0, 0), 50000.0)
	var fr := FakeRunner.new()
	fr.busy_len = 0.5
	var e := _spawn("skeleton_warrior", Vector3(0, 0, 0), fr)
	assert_eq(e.skill_runner, fr, "injected runner kept")
	await _wait(3.2)
	assert_true(fr.uses.size() >= 2, "attacks repeatedly (%d)" % fr.uses.size())
	for u in fr.uses:
		assert_eq(String(u["id"]), "m_melee", "uses its skill")
		assert_true(float(u["pos"].distance_to(d.global_position)) < 0.01, "aimed at the target")
	# The pause starts when the skill ends and the next use follows as soon as it runs out
	# (not on the next 0.2 s think tick): gap = busy + 0.3-0.8 s, give or take a frame.
	for i in range(1, fr.uses.size()):
		var gap := float(fr.uses[i]["t"]) - float(fr.uses[i - 1]["t"])
		assert_between(gap, 0.5 + Enemy.SKILL_PAUSE_MIN - 0.035, 0.5 + Enemy.SKILL_PAUSE_MAX + 0.035,
			"use + 0.3-0.8 s pause (%.3f)" % gap)


func test_skill_choice_by_range() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(6, 0, 0), 50000.0)
	var fr := FakeRunner.new()
	fr.busy_len = 0.4
	var e := _spawn("ghoul", Vector3(0, 0, 0), fr)
	await get_tree().physics_frame
	e.aggro(d)
	# Think right away (no reaction pause) so the distance is exactly known.
	e._pause = 0.0
	e._think()
	assert_eq(fr.uses.size(), 1, "used a skill at range")
	if fr.uses.size() >= 1:
		assert_eq(String(fr.uses[0]["id"]), "m_leap", "leap from 6 m")
	# Up close it bites (the leap has a minimum range and an AI cooldown).
	d.global_position = e.global_position + Vector3(1.2, 0, 0)
	fr.uses.clear()
	await _wait(1.5)
	assert_true(fr.uses.size() >= 1, "used a skill up close")
	for u in fr.uses:
		assert_eq(String(u["id"]), "m_bite", "bites up close")


func test_caster_needs_line_of_sight() -> void:
	var w := await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(6, 0, 0), 50000.0)
	var fr := FakeRunner.new()
	var e := _spawn("cultist", Vector3(-6, 0, 0), fr)
	e.aggro(d)
	_grid_wall(w, 0.5, -15.0, 6.0)
	await _wait(0.8)
	assert_eq(fr.uses.size(), 0, "no firebolt through a wall")
	assert_eq(e._move_mode, Enemy.Move.CHASE, "moves to get a clear shot")


func test_stagger() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(1.4, 0, 0), 50000.0)
	var fr := FakeRunner.new()
	fr.busy_len = 1.0
	var e := _spawn("zombie", Vector3(0, 0, 0), fr)
	await _wait(0.8)
	assert_true(fr.is_busy(), "mid-attack")
	var small := e.take_damage_from(d, e.max_life * 0.08, "physical")
	assert_true(small > 0.0, "small hit")
	assert_eq(fr.cancels, 0, "small hits don't stagger")
	e.take_damage_from(d, e.max_life * 0.25, "physical")
	assert_eq(fr.cancels, 1, "a 25% hit cancels the attack")
	assert_false(fr.is_busy(), "windup cancelled")
	assert_eq(e.visuals.get_action(), "hit", "plays hit")
	e.take_damage_from(d, e.max_life * 0.22, "physical")
	assert_eq(fr.cancels, 1, "1.5 s stagger immunity")
	# Bosses never flinch.
	var fr2 := FakeRunner.new()
	var b := _spawn("boss_gravebreaker", Vector3(-6, 0, 6), fr2)
	b.aggro(d)
	await _wait(1.4)
	var c0 := fr2.cancels
	b.take_damage_from(d, b.max_life * 0.3, "physical")
	assert_eq(fr2.cancels, c0, "boss never flinches")
	assert_ne(b.visuals.get_action(), "hit", "no hit anim on bosses")


func test_frozen_enemy_stands_still() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(10, 0, 0), 5000.0)
	var e := _spawn("skeleton_warrior", Vector3(-6, 0, 0))
	e.aggro(d)
	e.apply_ailment("freeze", {"duration": 0.8})
	var p := e.global_position
	await _wait(0.5)
	assert_true(CombatQuery.distance_xz(p, e.global_position) < 0.05, "frozen: no movement")
	await _wait(0.8)
	assert_true(CombatQuery.distance_xz(p, e.global_position) > 0.5, "moves again after the freeze")


func test_sleep_far_from_focus() -> void:
	await make_world()
	var near := _spawn("zombie", Vector3(14, 0, 0))
	var far := _spawn("zombie", Vector3(-12, 0, 0))
	EnemyDB.apply_sleep(Vector3(50, 0, 0))
	assert_false(near.sleeping, "36 m: awake")
	assert_true(far.sleeping, "62 m: asleep")
	assert_false(far.visible, "hidden")
	assert_false(far.is_physics_processing(), "physics off")
	assert_true(near.is_physics_processing(), "near keeps processing")
	var p := far.global_position
	await _wait(0.2)
	assert_eq(far.global_position, p, "sleeping enemies don't move")
	EnemyDB.apply_sleep(Vector3(0, 0, 0))
	assert_false(far.sleeping, "wakes when the focus comes close")
	assert_true(far.visible and far.is_physics_processing(), "visible + processing again")
	# Hysteresis: just past the wake distance it stays asleep until clearly inside.
	EnemyDB.apply_sleep(Vector3(29, 0, 0))   # far at 41 m
	assert_true(far.sleeping, "sleeps beyond 40 m")
	EnemyDB.apply_sleep(Vector3(27, 0, 0))   # 39 m: inside the 2 m margin
	assert_true(far.sleeping, "hysteresis")
	EnemyDB.apply_sleep(Vector3(25, 0, 0))   # 37 m
	assert_false(far.sleeping, "wakes inside 38 m")
	# Aggro wakes a sleeping enemy at once.
	EnemyDB.apply_sleep(Vector3(60, 0, 0))
	assert_true(far.sleeping, "asleep again")
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-8, 0, 0), 5000.0)
	far.aggro(d)
	assert_false(far.sleeping, "aggro wakes up")


func test_leave_combat_returns_home_and_heals() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(14, 0, 14), 5000.0)
	var e := _spawn("zombie", Vector3(0, 0, 0))
	e.aggro(d)
	await _wait(1.0)
	var moved := CombatQuery.distance_xz(e.global_position, e.home_position)
	assert_true(moved > 1.0, "chased away from home (%.1f)" % moved)
	e.take_damage(e.max_life * 0.3, "physical")
	e.leave_combat()
	assert_eq(e.state, Enemy.State.RETURN, "returning")
	assert_true(e.get_target() == null, "dropped the target")
	await _wait(2.5)
	assert_eq(e.state, Enemy.State.IDLE, "home and idle")
	assert_true(CombatQuery.distance_xz(e.global_position, e.home_position) <= Enemy.HOME_REACHED + 0.1, "at home")
	assert_near(e.life, e.max_life, 0.01, "healed on arrival")


func test_player_death_ends_fights() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 5000.0)
	var e := _spawn("zombie", Vector3(-2, 0, 0))
	await _wait(0.4)
	assert_eq(e.state, Enemy.State.COMBAT, "fighting")
	d.die(null)
	Events.player_died.emit()
	assert_eq(e.state, Enemy.State.RETURN, "walks home after the player died")


func test_target_death_leashes() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 5000.0)
	var e := _spawn("zombie", Vector3(-2, 0, 0))
	await _wait(0.4)
	d.die(null)
	await _wait(Enemy.LEASH_TIMEOUT + 0.6)
	assert_ne(e.state, Enemy.State.COMBAT, "gives up without targets")


func test_boss_spawned_on_first_aggro_and_reset() -> void:
	await make_world()
	var seen: Array = []
	var cb := func(b: Node) -> void: seen.append(b)
	Events.boss_spawned.connect(cb)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-14, 0, -14), 50000.0)
	var boss := _spawn("boss_gravebreaker", Vector3(6, 0, 6))
	var minion := _spawn("zombie", Vector3(-6, 0, 6))
	await _wait(0.3)
	assert_eq(seen.size(), 0, "not at spawn")
	minion.aggro(d)
	assert_eq(seen.size(), 0, "normal monsters don't announce")
	boss.aggro(d)
	assert_eq(seen.size(), 1, "boss_spawned on first aggro")
	assert_eq(seen[0], boss, "emits itself")
	assert_eq(boss.visuals.get_action(), "roar", "roars")
	boss.aggro(d)
	await _wait(0.5)
	assert_eq(seen.size(), 1, "only once")
	var home := boss.home_position
	boss.take_damage(boss.max_life * 0.6, "physical")
	await _wait(1.5)
	assert_true(boss.enraged, "enrages below half life")
	assert_true(boss.has_buff("boss_enrage"), "enrage buff")
	boss.reset_boss()
	assert_eq(boss.state, Enemy.State.IDLE, "reset: idle")
	assert_near(boss.life, boss.max_life, 0.01, "reset: full life")
	assert_false(boss.enraged or boss.has_buff("boss_enrage"), "reset: calm")
	assert_true(CombatQuery.distance_xz(boss.global_position, home) < 0.01, "reset: back home")
	boss.aggro(d)
	assert_eq(seen.size(), 2, "announces again after a reset")
	Events.boss_spawned.disconnect(cb)


func test_respawn_resets_bosses() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-10, 0, -10), 50000.0)
	var boss := _spawn("boss_lich", Vector3(6, 0, 6))
	boss.aggro(d)
	boss.take_damage(boss.max_life * 0.3, "fire")
	await _wait(0.2)
	Events.respawn_requested.emit()
	assert_eq(boss.state, Enemy.State.IDLE, "respawn: boss leaves combat")
	assert_near(boss.life, boss.max_life, 0.01, "respawn: boss at full life")


func test_boss_ability_rotation() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(3.2, 0, 0), 500000.0)
	var fr := FakeRunner.new()
	fr.busy_len = 0.3
	var boss := _spawn("boss_gravebreaker", Vector3(0, 0, 0), fr)
	boss.aggro(d)
	await _wait(5.0)
	var specials: Array = []
	for u in fr.uses:
		if String(u["id"]) != "m_melee":
			specials.append(String(u["id"]))
		if String(u["id"]) == "m_boss_charge":
			assert_true(float(u["dist"]) >= 4.9, "charge only from range")
	assert_true(fr.uses.size() >= 3, "keeps fighting (%d uses)" % fr.uses.size())
	assert_true(specials.size() >= 2, "uses its abilities (%s)" % str(specials))
	if specials.size() >= 2:
		assert_ne(specials[0], specials[1], "rotates abilities")
	assert_true(fr.uses.size() >= 1 and String(fr.uses[0]["id"]) != "m_melee", "opens with an ability")


func test_summoner_minions() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-12, 0, 0), 50000.0)
	var fr := FakeRunner.new()
	var necro := _spawn("necromancer", Vector3(0, 0, 0), fr)
	necro.aggro(d)
	await _wait(0.8)
	assert_true(fr.uses.size() >= 1, "casts")
	# The skills module spawns summons through EnemyDB while the cast is running.
	fr.skill_started.emit("m_summon", "cast_area", 1.0)
	var s := EnemyDB.spawn_enemy("skeleton_warrior", necro.global_position + Vector3(1.5, 0, 0), necro.level)
	assert_true(s.is_summon, "claimed as a minion")
	assert_eq(s.summoner_id, necro.get_instance_id(), "summoner id")
	assert_eq(s.pack_id, necro.pack_id, "joins the pack")
	assert_eq(s.state, Enemy.State.COMBAT, "enters the fight at once")
	assert_true(s.visuals.is_rising(), "climbs out of the ground")
	assert_eq(necro.get_minion_count(), 1, "minion count")
	var free := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(12, 0, 12), necro.level)
	assert_false(free.is_summon, "far away spawns are not minions")


func test_hover_highlight() -> void:
	await make_world()
	var e := _spawn("zombie", Vector3(0, 0, 0))
	await _wait(0.1)
	assert_false(e.visuals.has_overlay(), "normal: no overlay")
	Events.hovered_target_changed.emit(e)
	assert_true(e.visuals.has_overlay(), "hovered: highlight")
	Events.hovered_target_changed.emit(null)
	assert_false(e.visuals.has_overlay(), "unhovered")


func test_separation() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 50000.0)
	var pack: Array[Enemy] = []
	for i in 4:
		pack.append(_spawn("skeleton_warrior", Vector3(-6 + i * 0.1, 0, i * 0.1)))
	await _wait(2.5)
	for i in pack.size():
		for j in range(i + 1, pack.size()):
			var dd := CombatQuery.distance_xz(pack[i].global_position, pack[j].global_position)
			assert_true(dd > 0.6, "members spread out (%.2f)" % dd)


func test_leashed_boss_calms_down() -> void:
	await make_world()
	var seen: Array = []
	var cb := func(b: Node) -> void: seen.append(b)
	Events.boss_spawned.connect(cb)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(3.2, 0, 0), 500000.0)
	var fr := FakeRunner.new()
	fr.busy_len = 0.3
	var boss := _spawn("boss_gravebreaker", Vector3(0, 0, 0), fr)
	boss.aggro(d)
	boss.take_damage(boss.max_life * 0.6, "physical")
	await _wait(1.6)
	assert_true(boss.enraged and boss.has_buff("boss_enrage"), "enraged below half life")
	assert_true(boss.visuals.is_enraged_look(), "enrage look")
	var fast := boss.get_move_speed()
	# The player gets away: the boss walks home, heals up and calms down.
	d.die(null)
	boss.leave_combat()
	for i in 40:
		await _wait(0.1)
		if boss.state == Enemy.State.IDLE:
			break
	assert_eq(boss.state, Enemy.State.IDLE, "home")
	assert_near(boss.life, boss.max_life, 0.01, "healed")
	assert_false(boss.enraged, "no longer enraged")
	assert_false(boss.has_buff("boss_enrage"), "enrage buff gone")
	assert_true(boss.get_move_speed() < fast - 0.01, "enrage speed gone")
	assert_false(boss.visuals.is_enraged_look(), "enrage look gone")
	assert_true(boss.visuals.get_rim().is_equal_approx(boss.visuals.BOSS_RIM), "boss rim back")
	# The next fight starts fresh: roar + announce, and it enrages again at half life.
	var d2 := spawn_dummy(Actor.Team.PLAYER, Vector3(3.2, 0, 0), 500000.0)
	boss.aggro(d2)
	assert_eq(seen.size(), 2, "announces again")
	assert_eq(boss.visuals.get_action(), "roar", "roars again")
	boss.take_damage(boss.max_life * 0.6, "physical")
	await _wait(1.6)
	assert_true(boss.enraged and boss.has_buff("boss_enrage"), "can enrage again")
	assert_true(boss.visuals.is_enraged_look(), "enrage look again")
	Events.boss_spawned.disconnect(cb)


func test_boss_reannounces_after_town_portal() -> void:
	var w := await make_world()
	var seen: Array = []
	var cb := func(b: Node) -> void: seen.append(b)
	Events.boss_spawned.connect(cb)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(4, 0, 0), 500000.0)
	var fr := FakeRunner.new()
	var boss := _spawn("boss_lich", Vector3(-2, 0, 0), fr)
	boss.aggro(d)
	assert_eq(seen.size(), 1, "announced on aggro")
	await _wait(1.5)
	# Town portal round trip: the flow detaches the kept dungeon and later re-attaches it (the
	# HUD hides the boss bar on area_entered).
	remove_child(w)
	await _wait(0.2)
	add_child(w)
	await _wait(0.5)
	assert_eq(boss.state, Enemy.State.COMBAT, "still fighting")
	assert_eq(seen.size(), 2, "announces again so the HUD shows the boss bar")
	if seen.size() >= 2:
		assert_eq(seen[1], boss, "emits itself")
	assert_true(boss._roar <= 0.0, "no second roar")
	await _wait(0.6)
	assert_eq(seen.size(), 2, "once per re-attach")
	Events.boss_spawned.disconnect(cb)
