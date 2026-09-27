extends "res://scripts/debug/debug_shot_tour.gd"
## Combat screenshot tour: `-- --combat-tour=DIR` (needs a real window). A boosted warrior (sword
## and shield) in Act I's outskirts next to a monster pack: attacking while walking, the parry
## guard, a caught blow (counter shockwave, stunned monsters, "Parry!"), the parry charge on the
## HUD, the empowered attack and its echo, and a dodge roll (the tumble, then the slower rise)
## steered with WASD. Saves PNGs into DIR
## and quits. God mode keeps the warrior alive. OWNER: orchestrator.
##
##   GTEST_FULL=1 GTEST_WINDOWED=1 GTEST_TIMEOUT=300 tools/gtest.sh combat-tour res://scenes/main.tscn -- --combat-tour=DIR

const TOUR_CLASS := "warrior"
const TOUR_LEVEL := 12


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("Combat tour needs a window (GTEST_WINDOWED=1); skipping")
		get_tree().quit.call_deferred(0)
		return
	get_tree().create_timer(160.0, true).timeout.connect(get_tree().quit)
	out_dir = _resolve_dir(String(config.get("combat-tour", "docs/screenshots/combat")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.save_dir = SAVE_DIR
	_run.call_deferred()


func _run() -> void:
	print("[combat-tour] saving screenshots to ", out_dir)
	_clear_saves()
	GameState.act_options = {"level_mode": "custom", "level": TOUR_LEVEL, "monsters": true, "god_mode": true}
	Events.new_game_requested.emit("Parry Tester", TOUR_CLASS)
	await _await_area()
	UI.close_all_panels()
	main.call("request_area_change", "act", {"act": "forest", "zone": "outskirts", "seed": 7})
	await _await_area()
	UI.close_all_panels()
	var p := _player()
	var w := GameState.world
	if p == null or w == null:
		get_tree().quit(1)
		return
	p.god_mode = true
	# Walking through a grass patch: the blades bend away and spring back after.
	var grass: Array = w.layout.get("grass", [])
	if not grass.is_empty():
		var counts := {}
		var best := Vector2i.ZERO
		var most := 0
		for g in grass:
			var key := Vector2i(floori(float(g[0]) / 5.0), floori(float(g[1]) / 5.0))
			if Vector2(key).distance_to(Vector2(p.global_position.x, p.global_position.z) / 5.0) > 30.0:
				continue
			var c := int(counts.get(key, 0)) + 1
			counts[key] = c
			if c > most:
				most = c
				best = key
		if most > 0:
			var centre := Vector3((best.x + 0.5) * 5.0, 0, (best.y + 0.5) * 5.0)
			_teleport(w.get_nearest_walkable(centre - Vector3(3.0, 0, 0)))
			var rig0 := p.camera_rig
			if rig0 != null:
				rig0.zoom_target = 8.0
				rig0.snap_to_target()
			await _wait(0.5)
			p.ai_move(Vector3(1, 0, 0))
			await _wait(0.55)
			await _shot("00_grass_walk")
			p.ai_move(Vector3.ZERO)
			await _wait(0.25)
			await _shot("00b_grass_behind")
			await _wait(1.2)
			await _shot("00c_grass_sprung_back")
			if rig0 != null:
				rig0.zoom_target = CameraRig.DEFAULT_DISTANCE
				rig0.snap_to_target()
			var fx := w.ground_fx
			print("[combat-tour] grass pushers: %d" % (fx.last_pushers.size() if fx != null else -1))
	# The nearest monster pack: spawn it and stand a few metres from it.
	var goal := Vector3.INF
	var gd := INF
	for g in w.pending_groups():
		if String(g.get("kind", "")) == "boss":
			continue
		var d0 := CombatQuery.distance_xz(p.global_position, g["position"])
		if d0 < gd:
			gd = d0
			goal = g["position"]
	if goal == Vector3.INF:
		print("[combat-tour] no monster pack found")
		get_tree().quit(1)
		return
	_teleport(w.get_nearest_walkable(goal + Vector3(0, 0, 9.0)))
	w.lazy_spawn_tick(true)
	await _wait(0.6)
	var tgt := _nearest_enemy(p)
	if tgt == null:
		get_tree().quit(1)
		return
	for e in EnemyDB.get_enemies(w):
		if CombatQuery.distance_xz(e.global_position, tgt.global_position) < 10.0:
			e.aggro(p, false)
	# 1. Attacking while walking (slowed, still moving).
	p.ai_aim(tgt.global_position, tgt)
	p.ai_move(Vector3(1, 0, 0))
	p.ai_hold_skill(0, true)
	await _wait(0.35)
	await _shot("01_attack_while_moving")
	# Close up: the walking legs under the attack (two moments of the stride).
	var rig := p.camera_rig
	if rig != null:
		rig.zoom_target = 7.0
		rig.snap_to_target()
		await _wait(0.2)
		await _shot("01b_walking_legs_close_a")
		await _wait(0.27)
		await _shot("01c_walking_legs_close_b")
		rig.zoom_target = CameraRig.DEFAULT_DISTANCE
		rig.snap_to_target()
	p.ai_hold_skill(0, false)
	p.ai_move(Vector3.ZERO)
	# Let the monsters close in.
	var t := 0.0
	while t < 4.0:
		tgt = _nearest_enemy(p)
		if tgt != null and CombatQuery.distance_xz(tgt.global_position, p.global_position) < 2.6:
			break
		await _wait(0.1)
		t += 0.1
	tgt = _nearest_enemy(p)
	if tgt == null:
		get_tree().quit(1)
		return
	p.ai_aim(tgt.global_position, tgt)
	await _wait(0.1)
	# 2. The guard (held).
	p.ai_parry()
	await _wait(0.12)
	await _shot("02_parry_guard")
	# 3. A blow caught in it (the nearest monster's hit), the counter.
	var hit := HitData.create({"physical": 30.0}, tgt, PackedStringArray(["attack"]))
	hit.origin = tgt.global_position
	p.take_hit(hit)
	p.ai_release_parry()
	await _wait(0.12)
	await _shot("03_parry_counter")
	await _wait(0.45)
	await _shot("04_stunned_and_charged")
	# 4. The empowered attack and its echo.
	tgt = _nearest_enemy(p)
	if tgt != null:
		p.ai_aim(tgt.global_position, tgt)
	await _wait(0.3)
	p.ai_hold_skill(0, true)
	await _wait(0.05)
	p.ai_hold_skill(0, false)
	var use := p.skill_runner.get_current_use()
	var hf := p.skill_runner.get_hit_time()
	await _wait(hf + 0.05)
	await _shot("05_empowered_attack")
	await _wait(SkillEmpower.ECHO_DELAY)
	await _shot("06_attack_echo")
	print("[combat-tour] empowered=%s echo=%s" % [use.empowered if use != null else false, use.echo if use != null else false])
	# 5. A dodge roll steered with WASD: east, then curving north. The fast tumble, then the rise.
	await _wait(0.6)
	p.ai_dodge(Vector3(1, 0, 0))
	await _wait(0.08)
	await _shot("07_dodge_tumble")
	p.ai_move(Vector3(0, 0, -1))
	await _wait(0.22)
	await _shot("08_dodge_rise_steered")
	await _wait(0.4)
	p.ai_move(Vector3.ZERO)
	print("[combat-tour] %d screenshots" % count)
	get_tree().quit(0)
