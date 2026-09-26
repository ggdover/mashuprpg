extends Node3D
## Skills demo: an arena with a caster (char_player with animations and the skill's weapon) using
## every player skill on rows of skeleton dummies, then monster casters (skeleton / cultist /
## brute / ghoul / lich / gravebreaker models) using every monster skill on player dummies, plus
## an ailment line-up for StatusVisuals. Windowed runs save screenshots mid-effect to
## docs/screenshots/skills/<id>[_n].png; headless runs are a smoke test.
##
##   GTEST_WINDOWED=1 GTEST_TIMEOUT=200 tools/gtest.sh skills-demo res://tests/scenes/skills_demo.tscn -- --quit_after=180
##   ... -- --skills=fireball,meteor,status          (subset; "status" = ailment line-up)
##   ... -- --dark=0                                  (keep the bright arena lighting)
## OWNER: skills.

const PITCH := 56.0
const DISTANCE := 15.5

## id -> [layout, weapon model, capture offsets after the hit time (s), caster model]
const PLAYER_PLAN := {
	"basic_attack": ["melee", "sword", [0.06]],
	"heavy_strike": ["melee", "greataxe", [0.05, 0.25]],
	"cleave": ["melee", "sword", [0.07]],
	"ground_slam": ["cone", "maul", [0.12, 0.3]],
	"leap_slam": ["far_cluster", "greatsword", [0.25, 0.62]],
	"whirlwind": ["around", "greatsword", [0.5]],
	"infernal_blow": ["melee", "axe", [0.07, 0.22]],
	"war_cry": ["allies", "mace", [0.18, 0.9]],
	"power_shot": ["line", "bow", [0.12, 0.3]],
	"split_arrow": ["fan", "bow", [0.1, 0.25]],
	"rain_of_arrows": ["cluster", "bow", [0.35, 0.6]],
	"explosive_bolt": ["cluster", "crossbow", [0.2, 0.3]],
	"scatter_shot": ["near_fan", "crossbow", [0.05, 0.12]],
	"rapid_fire": ["line", "crossbow", [0.35, 0.8]],
	"ice_shot": ["line", "bow", [0.15, 0.32]],
	"venom_arrow": ["cluster", "bow", [0.4, 1.4]],
	"fireball": ["cluster", "wand", [0.25, 0.48]],
	"ice_spear": ["line", "wand", [0.12, 0.3]],
	"frost_nova": ["around", "staff", [0.12, 0.3]],
	"chain_lightning": ["chain", "wand", [0.04, 0.14]],
	"teleport": ["none", "staff", [0.03, 0.2]],
	"spark": ["fan", "staff", [0.3, 0.7]],
	"meteor": ["cluster", "staff", [0.6, 1.02, 1.2]],
	"blood_rite": ["none", "wand", [0.15, 0.9]],
}
## id -> [layout, caster model, capture offsets RELATIVE TO THE USE START (s; negative = before
## the hit, as a fraction of the hit time when < 0 and > -1)]
const MONSTER_PLAN := {
	"m_melee": ["m_melee", "char_skeleton", [0.06]],
	"m_bite": ["m_melee", "char_ghoul", [0.05]],
	"m_arrow": ["m_line", "char_skeleton", [0.15]],
	"m_firebolt": ["m_line", "char_cultist", [0.2, 0.55]],
	"m_frostbolt": ["m_line", "char_cultist", [0.25]],
	"m_slam": ["m_cone", "char_brute", [-0.6, 0.15]],
	"m_summon": ["m_line", "char_cultist", [0.1, 0.6]],
	"m_leap": ["m_far", "char_ghoul", [-0.5, 0.25, 0.5]],
	"m_boss_nova": ["m_around", "char_lich", [-0.6, 0.35]],
	"m_boss_volley": ["m_fan", "char_lich", [0.3]],
	"m_boss_charge": ["m_far", "char_gravebreaker", [-0.6, 0.35, 0.8]],
	"m_boss_meteors": ["m_line", "char_lich", [0.7, 1.33, 1.6]],
	"m_boss_slam": ["m_cone", "char_gravebreaker", [-0.6, 0.15]],
	"m_boss_spikes": ["m_line", "char_gravebreaker", [-0.5, 0.15, 0.45]],
}
const WEAPON_TYPES := {
	"sword": ["sword", 1.45, 2.2, false], "greatsword": ["sword", 1.2, 2.7, true], "axe": ["axe", 1.3, 2.2, false],
	"greataxe": ["axe", 1.1, 2.7, true], "mace": ["mace", 1.25, 2.2, false], "maul": ["mace", 1.0, 2.7, true],
	"bow": ["bow", 1.4, 20.0, true], "crossbow": ["crossbow", 1.0, 20.0, true], "wand": ["wand", 1.4, 2.2, false],
	"staff": ["staff", 1.15, 2.6, true],
}


class DemoActor extends TestDummy:
	var model_id := "char_player"
	var model: Node3D = null
	var ap: AnimationPlayer = null
	var action := ""
	var spin := false
	var weapon_node: Node3D = null
	var offhand_node: Node3D = null
	var flash := 0.0

	func _ready() -> void:
		model = Assets.model(model_id)
		model.name = "Model"
		add_child(model)
		ap = Assets.prepare_animations(model)
		super._ready()
		_idle()
		StatusVisuals.attach(self)
		damaged.connect(func(_a: float, _c: bool, _s: Node) -> void: flash = 0.12)

	func play_action_animation(anim: String, duration: float) -> void:
		if ap == null or not ap.has_animation(anim):
			return
		action = anim
		spin = anim == "channel"
		ap.play(anim, 0.06)
		ap.speed_scale = ap.get_animation(anim).length / duration if duration > 0.0 else 1.0

	func stop_action_animation() -> void:
		action = ""
		spin = false
		_idle()

	func _actor_physics(delta: float) -> void:
		if spin:
			model.rotation.y += delta * TAU * 2.0
		elif action == "":
			model.rotation.y = 0.0
		if action != "" and not spin and ap != null and not ap.is_playing():
			action = ""
			_idle()
		if flash > 0.0:
			flash -= delta
			Assets.set_flash(model, 0.55 if flash > 0.0 else 0.0, Color(1, 0.9, 0.8))

	func _idle() -> void:
		if ap != null and ap.has_animation("idle"):
			ap.speed_scale = 1.0
			ap.play("idle", 0.15)

	func set_weapon(wid: String) -> void:
		if weapon_node != null and is_instance_valid(weapon_node):
			weapon_node.queue_free()
		if offhand_node != null and is_instance_valid(offhand_node):
			offhand_node.queue_free()
		weapon_node = null
		offhand_node = null
		if wid == "":
			return
		weapon_node = Assets.model("weapon_" + wid)
		Assets.attach_to_bone(model, "grip_r", weapon_node)
		if wid in ["bow", "crossbow"]:
			offhand_node = Assets.model("offhand_quiver")
			Assets.attach_to_bone(model, "chest", offhand_node)
		elif wid == "wand":
			offhand_node = Assets.model("offhand_focus")
			Assets.attach_to_bone(model, "grip_l", offhand_node)


var cam: Camera3D
var world: World
var out_dir := ""
var shots := true
var caster: DemoActor = null
var dummies: Array = []
var only: PackedStringArray = []
var dark := true
var shot_count := 0


func _ready() -> void:
	get_tree().create_timer(_arg_float("--quit_after", 20.0)).timeout.connect(get_tree().quit)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skills="):
			only = a.substr(9).split(",", false)
		elif a.begins_with("--dark="):
			dark = a.substr(7) != "0"
	shots = DisplayServer.get_name() != "headless"
	out_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/skills/"
	if shots:
		DirAccess.make_dir_recursive_absolute(out_dir)
		get_window().size = Vector2i(1280, 720)
	world = World.new()
	add_child(world)
	GameState.world = world
	world.build({"id": "arena", "name": "Arena", "level": 20, "size": 14})
	if dark:
		_darken()
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()
	_look_at(Vector3(0, 0, -1.5))
	_run.call_deferred()


func _arg_float(key: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return float(a.substr(key.length() + 1))
	return def


func _darken() -> void:
	var we := world.world_environment
	if we != null and we.environment != null:
		var env := we.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.012, 0.014, 0.025)
		env.ambient_light_color = Color(0.45, 0.5, 0.62)
		env.ambient_light_energy = 0.35
		env.glow_enabled = true
		env.glow_intensity = 0.8
		env.glow_bloom = 0.1
	if world.sun != null:
		world.sun.light_energy = 0.35
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.45)
	l.light_energy = 2.2
	l.omni_range = 13.0
	l.position = Vector3(0, 4.5, 2.0)
	l.shadow_enabled = false
	world.add_child(l)


func _look_at(focus: Vector3) -> void:
	var p := deg_to_rad(PITCH)
	cam.position = focus + Vector3(0, sin(p), cos(p)) * DISTANCE
	cam.rotation = Vector3(-p, 0, 0)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name_: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + name_ + ".png")
	shot_count += 1


func _run() -> void:
	await _wait(0.5)
	for id in PLAYER_PLAN:
		if only.is_empty() or only.has(id):
			await _player_skill(id)
	for id in MONSTER_PLAN:
		if only.is_empty() or only.has(id):
			await _monster_skill(id)
	if only.is_empty() or only.has("status"):
		await _status_lineup()
	if only.has("gallery"):
		await _gallery()
	if only.has("stress"):
		await _stress()
	print("[skills_demo] done, %d screenshots" % shot_count)
	get_tree().quit()


func _clear() -> void:
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	if caster != null and is_instance_valid(caster):
		caster.queue_free()
	caster = null
	for c in world.dynamic_root.get_children():
		c.queue_free()
	for c in world.enemies_root.get_children():
		c.queue_free()


func _spawn_actor(model_id: String, team: int, pos: Vector3, lvl: int = 20) -> DemoActor:
	var a := DemoActor.new()
	a.model_id = model_id
	a.team = team
	a.level = lvl
	a.base_life = 1000000.0
	a.base_mana = 1000.0
	a.position = pos
	world.add_child(a)
	return a


func _layout(kind: String, team: int) -> Array:
	var pts: Array = []
	match kind:
		"melee", "m_melee":
			pts = [Vector3(0, 0, 0.3), Vector3(-1.4, 0, 0.9), Vector3(1.4, 0, 0.9), Vector3(0.0, 0, -1.6)]
		"cone", "m_cone":
			pts = [Vector3(0, 0, 0.5), Vector3(-1.2, 0, -1.5), Vector3(1.0, 0, -2.6), Vector3(0, 0, -3.8), Vector3(-2.2, 0, 0.8)]
		"far_cluster", "m_far":
			pts = [Vector3(0, 0, -5.0), Vector3(-1.2, 0, -5.8), Vector3(1.1, 0, -5.6), Vector3(0.3, 0, -6.8)]
		"around", "m_around":
			for i in 6:
				var ang := TAU * i / 6.0 + 0.3
				pts.append(Vector3(sin(ang) * 2.6, 0, 2.5 + cos(ang) * 2.6))
		"allies":
			pts = [Vector3(-2.0, 0, 2.5), Vector3(2.0, 0, 2.5), Vector3(0, 0, -3.5)]
		"line", "m_line":
			pts = [Vector3(0, 0, -1.0), Vector3(0.3, 0, -3.5), Vector3(-0.3, 0, -6.0), Vector3(0.2, 0, -8.5)]
		"fan", "m_fan":
			for i in 5:
				var ang2 := deg_to_rad(-40.0 + 20.0 * i)
				pts.append(Vector3(sin(ang2) * 7.5, 0, 3.0 - cos(ang2) * 7.5))
		"near_fan":
			pts = [Vector3(0, 0, 0.0), Vector3(-1.2, 0, -0.6), Vector3(1.2, 0, -0.6), Vector3(0, 0, -3.0)]
		"cluster":
			pts = [Vector3(0, 0, -5.0), Vector3(-1.3, 0, -5.6), Vector3(1.2, 0, -5.4), Vector3(0.2, 0, -6.6), Vector3(-0.4, 0, -4.0)]
		"chain":
			pts = [Vector3(0, 0, -2.5), Vector3(-2.5, 0, -4.5), Vector3(1.0, 0, -6.5), Vector3(3.5, 0, -5.0), Vector3(-1.5, 0, -8.0)]
	var out: Array = []
	var model := "char_skeleton" if team == Actor.Team.ENEMY else "char_player"
	for p in pts:
		var d := _spawn_actor(model, team, p)
		d.rotation.y = PI if team == Actor.Team.ENEMY else 0.0
		out.append(d)
	return out


func _player_skill(id: String) -> void:
	_clear()
	await get_tree().process_frame
	var plan: Array = PLAYER_PLAN[id]
	var layout := String(plan[0])
	var wid := String(plan[1])
	caster = _spawn_actor("char_player", Actor.Team.PLAYER, Vector3(0, 0, 2.5), 20)
	var wt: Array = WEAPON_TYPES[wid]
	caster.weapon_override = {"weapon_type": wt[0], "phys_min": 20.0, "phys_max": 34.0, "added": {}, "attack_speed": wt[1],
		"crit_chance": 5.0, "range": wt[2], "two_handed": wt[3]}
	var r := SkillRunner.new()
	r.name = "SkillRunner"
	r.setup(caster)
	caster.skill_runner = r
	caster.add_child(r)
	if layout == "allies":
		dummies = _layout(layout, Actor.Team.PLAYER)
	elif layout != "none":
		dummies = _layout(layout, Actor.Team.ENEMY)
	await get_tree().process_frame
	caster.set_weapon(wid)
	caster.rotation.y = PI
	var aim := Vector3(0, 0, -4.0)
	var tgt: Actor = null
	if not dummies.is_empty() and layout != "allies":
		tgt = dummies[2] if layout == "fan" else dummies[0]
		aim = tgt.global_position
	if layout == "none":
		aim = Vector3(-4.0, 0, -3.0)
	if layout == "around":
		aim = Vector3(0, 0, 0)
		tgt = null
	var focus := Vector3(0, 0, -1.5)
	if layout in ["melee", "around", "near_fan", "allies", "none"]:
		focus = Vector3(0, 0, 1.2)
	elif layout == "cone":
		focus = Vector3(0, 0, 0.3)
	_look_at(focus)
	await _wait(0.35)
	var ok := r.try_use(id, aim, tgt)
	if not ok:
		push_warning("skills_demo: %s could not start: %s" % [id, r.can_use(id)])
		return
	var hit := r.get_hit_time()
	var t0 := Time.get_ticks_msec()
	var offsets: Array = plan[2]
	for i in offsets.size():
		var at := hit + float(offsets[i])
		await _wait_until_ms(t0, at)
		await _shot(id if i == 0 else "%s_%d" % [id, i + 1])
	if id == "whirlwind":
		await _wait(0.3)
		r.release(id)
	await _wait(0.6)


func _wait_until_ms(t0: int, at: float) -> void:
	while (Time.get_ticks_msec() - t0) / 1000.0 < at:
		await get_tree().process_frame


func _monster_skill(id: String) -> void:
	_clear()
	await get_tree().process_frame
	var plan: Array = MONSTER_PLAN[id]
	var layout := String(plan[0])
	var start := Vector3(0, 0, 2.5)
	caster = _spawn_actor(String(plan[1]), Actor.Team.ENEMY, start, 12)
	caster.weapon_override = {"weapon_type": "monster", "phys_min": 16.0, "phys_max": 24.0, "added": {}, "attack_speed": 0.9,
		"crit_chance": 5.0, "range": 2.4 if plan[1] in ["char_brute", "char_gravebreaker"] else 1.8, "two_handed": false}
	if plan[1] == "char_skeleton" and id == "m_arrow":
		pass
	var r := SkillRunner.new()
	r.name = "SkillRunner"
	r.setup(caster)
	caster.skill_runner = r
	caster.add_child(r)
	if plan[1] == "char_skeleton":
		await get_tree().process_frame
		caster.set_weapon("bow" if id == "m_arrow" else "sword")
	dummies = _layout(layout, Actor.Team.PLAYER)
	await get_tree().process_frame
	caster.rotation.y = PI
	var tgt: Actor = null
	if not dummies.is_empty():
		tgt = dummies[2] if layout == "m_fan" else dummies[0]
	var aim := tgt.global_position if tgt != null else Vector3(0, 0, -4)
	if layout == "m_around":
		tgt = null
		aim = Vector3(0, 0, 0)
	_look_at(Vector3(0, 0, -1.5) if not layout in ["m_melee", "m_around"] else Vector3(0, 0, 1.2))
	await _wait(0.35)
	if not r.try_use(id, aim, tgt):
		push_warning("skills_demo: %s could not start: %s" % [id, r.can_use(id)])
		return
	var hit := r.get_hit_time()
	var t0 := Time.get_ticks_msec()
	var offsets: Array = plan[2]
	for i in offsets.size():
		var off := float(offsets[i])
		var at := hit * (1.0 + off) if off < 0.0 else hit + off
		await _wait_until_ms(t0, at)
		await _shot(id if i == 0 else "%s_%d" % [id, i + 1])
	await _wait(0.8)


func _status_lineup() -> void:
	_clear()
	await get_tree().process_frame
	var kinds := ["ignite", "chill", "freeze", "shock", "poison", "bleed"]
	for i in kinds.size():
		var d := _spawn_actor("char_skeleton", Actor.Team.ENEMY, Vector3(-5.0 + 2.0 * i, 0, 0))
		dummies.append(d)
	await get_tree().process_frame
	for i in kinds.size():
		var d: DemoActor = dummies[i]
		var k: String = kinds[i]
		match k:
			"ignite", "bleed", "poison":
				d.apply_ailment(k, {"dps": 1.0, "duration": 30.0})
			"chill", "shock":
				d.apply_ailment(k, {"effect": 0.3, "duration": 30.0})
			"freeze":
				d.apply_ailment(k, {"duration": 30.0})
	_look_at(Vector3(0, 0, 0))
	await _wait(0.8)
	await _shot("status_visuals")
	var p := deg_to_rad(PITCH)
	cam.position = Vector3(0, 0, 0) + Vector3(0, sin(p), cos(p)) * 7.0
	await _wait(0.1)
	await _shot("status_visuals_close")
	_look_at(Vector3(0, 0, 0))
	(dummies[2] as Actor).remove_ailment("freeze")
	await _wait(0.12)
	await _shot("status_freeze_shatter")


## Static line-up of projectile visuals (debugging the missile look).
func _gallery() -> void:
	_clear()
	await get_tree().process_frame
	var entries := [
		[{"color": SkillDB.C_FIRE, "orb": true, "scale": 1.0, "light": true}, ""],
		[{"color": SkillDB.C_LIGHT, "orb": true, "scale": 0.55}, ""],
		[{"color": SkillDB.C_ARCANE, "orb": true, "scale": 0.8}, ""],
		[{"color": SkillDB.C_PHYS, "trail": true}, "proj_arrow"],
		[{"color": SkillDB.C_WAR, "trail": true, "scale": 1.25}, "proj_arrow"],
		[{"color": SkillDB.C_PHYS, "trail": true}, "proj_bolt"],
		[{"color": SkillDB.C_COLD, "trail": true, "glow": true}, "proj_ice_spear"],
		[{"color": SkillDB.C_POISON, "trail": true, "glow": true}, "proj_arrow"],
	]
	for i in entries.size():
		var holder := Node3D.new()
		world.add_dynamic(holder)
		holder.global_position = Vector3(-6.0 + 1.7 * i, 1.1, -1.0)
		var m := VfxMissile.build(entries[i][0], entries[i][1])
		holder.add_child(m)
		m.face(Vector3(0, 0, -1))
	_look_at(Vector3(0, 0, -1.0))
	await _wait(0.6)
	await _shot("gallery_missiles")


## Stress: 16 casters firing volleys / fireballs / meteors for a few seconds; prints fps.
func _stress() -> void:
	_clear()
	await get_tree().process_frame
	var casters: Array = []
	for i in 16:
		var c := _spawn_actor("char_cultist", Actor.Team.ENEMY, Vector3(-8 + i, 0, 6), 10)
		c.weapon_override = {"weapon_type": "monster", "phys_min": 10.0, "phys_max": 12.0, "added": {}, "attack_speed": 1.0, "crit_chance": 5.0, "range": 1.8, "two_handed": false}
		var r := SkillRunner.new()
		r.setup(c)
		c.skill_runner = r
		c.add_child(r)
		casters.append(c)
	for i in 10:
		dummies.append(_spawn_actor("char_player", Actor.Team.PLAYER, Vector3(-9 + 2 * i, 0, -8), 10))
	_look_at(Vector3(0, 0, -1))
	var ids := ["m_boss_volley", "m_firebolt", "m_boss_meteors", "m_boss_nova", "m_frostbolt"]
	var t := 0.0
	var frames := 0
	var worst := 0.0
	var shot_done := false
	while t < 6.0:
		for c in casters:
			var cr: SkillRunner = (c as DemoActor).skill_runner
			if not cr.is_busy():
				cr.reset_cooldowns()
				cr.try_use(ids[randi() % ids.size()], Vector3(randf_range(-8, 8), 0, -8))
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if t > 1.0:
			frames += 1
			worst = maxf(worst, dt)
		if t > 3.0 and not shot_done:
			shot_done = true
			await _shot("stress")
	print("[skills_demo] stress: avg fps %.1f, worst frame %.1f ms, particles %d, lights %d, projectiles %d" % [
		frames / maxf(0.01, t - 1.0), worst * 1000.0, VfxUtil.particle_count(), VfxUtil.light_count(),
		world.dynamic_root.get_child_count()])
