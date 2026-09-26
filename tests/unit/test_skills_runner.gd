extends "res://tests/unit/test_skills_util.gd"
## SkillRunner (§8.2): can_use codes, failure notifications, the use timeline (cost, cooldown,
## animation, hit frame, finish, chill), cancel on freeze / death / cancel(), channelling,
## movement multiplier, re-aiming and freed-caster safety. The runner is ticked by hand.

var started: Array = []
var effects: Array = []
var finished: Array = []
var fail_msgs: Array = []


func _manual(c: Caster) -> SkillRunner:
	var r := c.skill_runner
	r.set_physics_process(false)
	r.skill_started.connect(func(id: String, anim: String, d: float) -> void: started.append([id, anim, d]))
	r.skill_effect.connect(func(id: String) -> void: effects.append(id))
	r.skill_finished.connect(func(id: String) -> void: finished.append(id))
	return r


func _advance(r: SkillRunner, seconds: float, step: float = 0.01) -> void:
	var t := 0.0
	while t < seconds - 0.000001:
		var d := minf(step, seconds - t)
		r.tick(d)
		t += d


func test_can_use_codes() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 1)
	var r := _manual(c)
	assert_eq(r.can_use("nope")["code"], "unknown", "unknown")
	assert_eq(r.can_use("cleave")["code"], "ok", "ok")
	assert_true(bool(r.can_use("cleave")["ok"]), "ok flag")
	var lvl := r.can_use("meteor")
	assert_eq(lvl["code"], "level", "level")
	assert_true(String(lvl["reason"]).contains("14"), "level reason")
	var w := r.can_use("power_shot")
	assert_eq(w["code"], "weapon", "weapon")
	assert_eq(w["reason"], "Requires a Bow", "weapon reason")
	c.mana = 0.0
	var cost := r.can_use("cleave")
	assert_eq(cost["code"], "cost", "cost")
	assert_eq(cost["reason"], "Not enough mana", "cost reason")
	assert_eq(r.can_use("basic_attack")["code"], "ok", "free skill ok without mana")
	c.mana = c.max_mana
	c.level = 20
	assert_true(r.try_use("war_cry", Vector3(0, 0, 3)), "war cry")
	_advance(r, 2.0)
	assert_eq(r.can_use("war_cry")["code"], "cooldown", "cooldown")
	c.apply_ailment("freeze", {"duration": 3.0})
	assert_eq(r.can_use("cleave")["code"], "cannot_act", "frozen")
	# Enemies ignore level and cost.
	var e := make_caster(Actor.Team.ENEMY, Vector3(5, 0, 0), weapon("sword"), 1)
	var re := _manual(e)
	e.mana = 0.0
	assert_eq(re.can_use("meteor")["code"], "ok", "enemy ignores level")
	assert_eq(re.can_use("cleave")["code"], "ok", "enemy ignores cost")


func test_blood_magic_cost_reason() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 10, [StatBlock.mod("blood_magic", "flag", 1.0)])
	var r := _manual(c)
	c.life = 3.0
	var res := r.can_use("cleave")
	assert_eq(res["code"], "cost", "blood magic cost")
	assert_eq(res["reason"], "Not enough life", "life reason")


func test_timeline_cost_anim_hit_finish() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var t := target(Vector3(0, 0, 1.5))
	var r := _manual(c)
	var skill := SkillDB.get_resolved("heavy_strike", c)
	var cost := DamageCalc.get_cost(c, skill)
	var mana0 := c.mana
	assert_true(r.try_use("heavy_strike", t.global_position, t), "started")
	assert_true(r.is_busy(), "busy")
	assert_eq(r.get_current_skill(), "heavy_strike", "current")
	assert_near(c.mana, mana0 - cost, 0.001, "cost paid")
	var u := DamageCalc.get_use_time(c, skill)
	assert_near(u, 1.3, 0.001, "use time = attack_time_mult / aps")
	assert_eq(started.size(), 1, "skill_started")
	assert_eq(started[0][1], "attack_slam", "anim")
	assert_near(float(started[0][2]), u, 0.001, "duration")
	assert_eq(c.anims.size(), 1, "play_action_animation called")
	assert_near(float(c.anims[0][1]), u, 0.001, "anim duration")
	assert_false(r.try_use("heavy_strike", t.global_position, t), "busy rejects")
	var hit_t := u * float(skill["hit_frame"])
	assert_near(r.get_hit_time(), hit_t, 0.001, "hit time")
	_advance(r, hit_t - 0.02)
	assert_eq(effects.size(), 0, "no effect before the hit frame")
	assert_eq(lost(t), 0.0, "no damage before the hit frame")
	_advance(r, 0.04)
	assert_eq(effects.size(), 1, "effect at the hit frame")
	assert_near(lost(t), 19.0, 0.01, "10 phys x 1.9 effectiveness")
	_advance(r, u - hit_t - 0.05)
	assert_true(r.is_busy(), "still recovering")
	_advance(r, 0.06)
	assert_false(r.is_busy(), "finished")
	assert_eq(finished, ["heavy_strike"], "skill_finished")
	assert_eq(c.stops, 0, "no stop on a normal finish")


func test_fast_hit_frame_and_chill() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 10.0), 10)
	var t := target(Vector3(0, 0, 1.2))
	var r := _manual(c)
	assert_true(r.try_use("basic_attack", t.global_position, t), "fast attack")
	assert_near(r.get_duration(), 0.1, 0.0001, "0.1 s use")
	_advance(r, 0.04, 0.001)
	assert_eq(lost(t), 0.0, "before 45%")
	_advance(r, 0.006, 0.001)
	assert_true(lost(t) > 0.0, "hit at 45%")
	_advance(r, 0.06)
	assert_false(r.is_busy(), "done")
	# Chill slows the whole use by 1 / (1 - chill).
	c.weapon_override = weapon("sword", 10.0, 1.0)
	c.apply_ailment("chill", {"effect": 0.3, "duration": 10.0})
	assert_true(r.try_use("basic_attack", t.global_position, t), "chilled attack")
	assert_near(r.get_duration(), 1.0 / 0.7, 0.001, "chilled duration")


func test_cooldown_ratio() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 10)
	var r := _manual(c)
	assert_eq(r.get_cooldown_ratio("war_cry"), 0.0, "ready")
	assert_true(r.try_use("war_cry", Vector3(0, 0, 2)), "used")
	assert_near(r.get_cooldown_remaining("war_cry"), 10.0, 0.001, "starts on use")
	assert_near(r.get_cooldown_ratio("war_cry"), 1.0, 0.001, "just used")
	_advance(r, 5.0, 0.05)
	assert_near(r.get_cooldown_ratio("war_cry"), 0.5, 0.01, "half")
	_advance(r, 5.1, 0.05)
	assert_eq(r.get_cooldown_remaining("war_cry"), 0.0, "ready again")
	var fast := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 10, [StatBlock.mod("cooldown_recovery", "inc", 100.0)])
	var rf := _manual(fast)
	assert_true(rf.try_use("war_cry", Vector3(0, 0, 2)), "used")
	assert_near(rf.get_cooldown_remaining("war_cry"), 5.0, 0.001, "cooldown recovery")


func test_player_failure_notifications_throttled() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 10)
	c.add_to_group("player")
	var r := _manual(c)
	Events.skill_use_failed.connect(_on_failed)
	c.mana = 0.0
	for i in 4:
		assert_false(r.try_use("cleave", Vector3(0, 0, 2)), "no mana")
	assert_false(r.try_use("power_shot", Vector3(0, 0, 2)), "wrong weapon")
	Events.skill_use_failed.disconnect(_on_failed)
	assert_eq(fail_msgs, ["Not enough mana", "Requires a Bow"], "one message per reason within 1 s")
	# Cooldown: a fresh press says "not ready", a held key retrying every frame stays quiet.
	c.mana = c.max_mana
	Events.skill_use_failed.connect(_on_failed)
	fail_msgs.clear()
	assert_true(r.try_use("war_cry", Vector3(0, 0, 2)), "war cry")
	r.cancel()
	for i in 5:
		r.try_use("war_cry", Vector3(0, 0, 2))
	assert_eq(fail_msgs.size(), 0, "held retries are silent")
	await wait_time(0.35)
	r.try_use("war_cry", Vector3(0, 0, 2))
	Events.skill_use_failed.disconnect(_on_failed)
	assert_eq(fail_msgs.size(), 1, "fresh press notifies")
	# Non-player actors never notify.
	var d := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword"), 10)
	var rd := _manual(d)
	d.mana = 0.0
	fail_msgs.clear()
	Events.skill_use_failed.connect(_on_failed)
	rd.try_use("cleave", Vector3(0, 0, 2))
	Events.skill_use_failed.disconnect(_on_failed)
	assert_eq(fail_msgs.size(), 0, "silent for non-players")


func _on_failed(reason: String) -> void:
	fail_msgs.append(reason)


func test_freeze_and_death_cancel() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var t := target(Vector3(0, 0, 1.5))
	var r := _manual(c)
	assert_true(r.try_use("heavy_strike", t.global_position, t), "start")
	c.apply_ailment("freeze", {"duration": 1.0})
	assert_false(r.is_busy(), "freeze cancels")
	assert_eq(c.stops, 1, "stop_action_animation")
	assert_eq(finished, ["heavy_strike"], "finished on cancel")
	_advance(r, 2.0)
	assert_eq(lost(t), 0.0, "cancelled use never hits")
	c.remove_ailment("freeze")
	assert_true(r.try_use("heavy_strike", t.global_position, t), "start again")
	c.die(null)
	assert_false(r.is_busy(), "death cancels")
	assert_false(bool(r.can_use("heavy_strike")["ok"]), "dead can't act")


func test_cancel_windup_removes_telegraph() -> void:
	var w := await make_world()
	var e := make_caster(Actor.Team.ENEMY, Vector3.ZERO, weapon("monster", 10.0, 1.0), 5)
	var p := target(Vector3(0, 0, 2.0), 10000.0, Actor.Team.PLAYER)
	var r := _manual(e)
	assert_true(r.try_use("m_slam", p.global_position, p), "slam")
	var tele := _telegraphs(w)
	assert_eq(tele.size(), 1, "one cone telegraph")
	assert_true(r.get_hit_time() >= 0.9 - 0.001, "hit waits for the windup")
	_advance(r, 0.5)
	r.cancel()
	assert_false(r.is_busy(), "cancelled")
	await wait_time(0.35)
	assert_eq(_telegraphs(w).size(), 0, "telegraph removed")
	_advance(r, 2.0)
	assert_eq(lost(p), 0.0, "no damage after cancel")


func _telegraphs(w: World) -> Array:
	var out: Array = []
	for n in w.dynamic_root.get_children():
		if n is VfxEffect and not n.is_queued_for_deletion():
			for ch in n.get_children():
				if ch is MeshInstance3D and (ch as MeshInstance3D).material_override is ShaderMaterial:
					var sm := (ch as MeshInstance3D).material_override as ShaderMaterial
					if sm.shader != null and sm.shader.code.contains("uniform int shape"):
						out.append(n)
	return out


func test_windup_hits_after_telegraph() -> void:
	await make_world()
	var e := make_caster(Actor.Team.ENEMY, Vector3.ZERO, weapon("monster", 10.0, 1.0), 5)
	var p := target(Vector3(0, 0, 2.0), 10000.0, Actor.Team.PLAYER)
	var r := _manual(e)
	assert_true(r.try_use("m_slam", p.global_position, p), "slam")
	var ht := r.get_hit_time()
	assert_near(ht, 0.9, 0.001, "windup = time to impact")
	# Moving out of the committed cone during the windup avoids the hit.
	p.global_position = Vector3(0, 0, -3.0)
	_advance(r, ht + 0.05)
	assert_eq(lost(p), 0.0, "dodged the telegraph")
	_advance(r, r.get_duration())
	p.global_position = Vector3(0, 0, 2.0)
	r.reset_cooldowns()
	assert_true(r.try_use("m_slam", p.global_position, p), "again")
	_advance(r, ht - 0.05)
	assert_eq(lost(p), 0.0, "nothing before the telegraph fills")
	_advance(r, 0.1)
	assert_true(lost(p) > 0.0, "hit when full")


func test_channel_ticks_cost_release() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var t := target(Vector3(1.5, 0, 0))
	var hits := [0]
	t.damaged.connect(func(_a: float, _c: bool, _s: Node) -> void: hits[0] += 1)
	var r := _manual(c)
	var s := SkillDB.get_resolved("whirlwind", c)
	var interval := DamageCalc.get_use_time(c, s)
	assert_near(interval, 0.45, 0.001, "tick interval = attack_time_mult / aps")
	var per_tick := DamageCalc.scale_cost(c, float(s["params"]["cost_per_tick"]))
	var mana0 := c.mana
	assert_true(r.try_use("whirlwind", Vector3(0, 0, 3)), "channel")
	assert_true(r.is_channelling(), "channelling")
	assert_eq(c.anims[0][0], "channel", "channel anim")
	assert_eq(float(c.anims[0][1]), 0.0, "loops")
	assert_near(r.movement_multiplier(), 0.6, 0.001, "move while channelling")
	_advance(r, interval * 0.5 + interval * 2.0 + 0.01)
	assert_eq(hits[0], 3, "three ticks")
	assert_near(c.mana, mana0 - 3.0 * per_tick, 0.01, "cost per tick")
	assert_near(lost(t), 3.0 * 10.0 * 0.6, 0.05, "tick damage")
	r.release("whirlwind")
	assert_false(r.is_busy(), "released")
	assert_eq(c.stops, 1, "stop anim on release")
	# A tap still gives one tick.
	assert_true(r.try_use("whirlwind", Vector3(0, 0, 3)), "tap")
	r.release("whirlwind")
	assert_true(r.is_busy(), "waits for the first tick")
	_advance(r, interval)
	assert_eq(hits[0], 4, "one tick on tap")
	assert_false(r.is_busy(), "then ends")
	# Out of mana ends the channel.
	assert_true(r.try_use("whirlwind", Vector3(0, 0, 3)), "again")
	c.mana = per_tick * 1.5
	_advance(r, interval * 3.0)
	assert_false(r.is_busy(), "out of mana")
	assert_eq(hits[0], 5, "only the affordable tick")


func test_movement_multiplier_and_idle() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var r := _manual(c)
	assert_eq(r.movement_multiplier(), 1.0, "idle free")
	assert_false(r.is_busy(), "idle")
	assert_eq(r.get_current_skill(), "", "no skill")
	assert_true(r.try_use("heavy_strike", Vector3(0, 0, 2)), "start")
	assert_eq(r.movement_multiplier(), 0.0, "rooted")
	r.cancel()
	assert_eq(r.movement_multiplier(), 1.0, "free again")


func test_update_target_reaims_before_hit() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var east := target(Vector3(1.5, 0, 0))
	var north := target(Vector3(0, 0, -1.5))
	var r := _manual(c)
	assert_true(r.try_use("heavy_strike", east.global_position), "aim east")
	assert_near(c.rotation.y, PI * 0.5, 0.01, "faces east")
	r.update_target(north.global_position)
	assert_near(absf(c.rotation.y), PI, 0.01, "turned north")
	_advance(r, r.get_duration() + 0.01)
	assert_eq(lost(east), 0.0, "east not hit")
	assert_true(lost(north) > 0.0, "north hit")


func test_face_target_and_cost_for_projectiles() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	var r := _manual(c)
	assert_true(r.try_use("fireball", Vector3(-5, 0, 0)), "cast west")
	assert_near(c.rotation.y, -PI * 0.5, 0.01, "faces west")
	assert_eq(started[0][1], "cast", "cast anim")
	assert_near(float(started[0][2]), 0.75, 0.001, "cast time")


func test_freed_caster_safety() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 12.0, 1.4), 15)
	var t := target(Vector3(0, 0, 12))
	var t2 := target(Vector3(1.0, 0, 12.5))
	assert_true(c.skill_runner.try_use("venom_arrow", t.global_position, t), "venom arrow")
	await wait_until(func() -> bool: return c.skill_runner.last_use != null and count_nodes("SkillProjectile") > 0, 2.0)
	assert_true(count_nodes("SkillProjectile") > 0, "arrow in flight")
	c.free()
	await wait_until(func() -> bool: return lost(t) > 0.0, 2.0)
	assert_true(lost(t) > 0.0, "hit after the caster was freed")
	assert_true(t.has_ailment("poison"), "poisoned")
	await wait_time(1.0)
	assert_true(lost(t2) > 0.0, "cloud ticks without its caster")
	var e := make_caster(Actor.Team.ENEMY, Vector3(0, 0, 20), weapon("monster", 10.0, 1.0), 5)
	var p := target(Vector3(0, 0, 13.5), 10000.0, Actor.Team.PLAYER)
	assert_true(e.skill_runner.try_use("m_boss_meteors", p.global_position, p), "meteors")
	await wait_until(func() -> bool: return count_nodes("SkillImpact") > 0, 3.0)
	e.queue_free()
	await wait_until(func() -> bool: return lost(p) > 0.0, 3.0)
	assert_true(lost(p) > 0.0, "meteor lands after its caster is gone")
