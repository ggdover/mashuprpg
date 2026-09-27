extends "res://scripts/debug/debug_shot_tour.gd"
## Acts screenshot tour: `-- --acts-tour=DIR` (needs a real window). Plays the real flow: title
## screen, the Act Explorer and the debug menu, then for every act (one seamless World): its town
## (arrival with the title card, the merchant), the road out, the outskirts (the zone's name fades
## in; a far view shows its size), a fight, every further zone's banner, the act's dungeon (door,
## inside), the act boss and the portals after it falls. Saves PNGs into DIR (relative to $GTEST_REPO, else the
## project) and quits. OWNER: acts framework.
##
##   GTEST_FULL=1 GTEST_WINDOWED=1 GTEST_TIMEOUT=400 tools/gtest.sh acts-tour res://scenes/main.tscn -- --acts-tour=docs/screenshots/acts/tour

const TOUR_LEVEL := 18


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("Acts tour needs a window (GTEST_WINDOWED=1); skipping")
		get_tree().quit.call_deferred(0)
		return
	get_tree().create_timer(600.0, true).timeout.connect(get_tree().quit)
	out_dir = _resolve_dir(String(config.get("acts-tour", "docs/screenshots/acts/tour")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.save_dir = SAVE_DIR
	_run.call_deferred()


func _run() -> void:
	print("[acts-tour] saving screenshots to ", out_dir)
	_clear_saves()
	main.call("show_main_menu")
	await _wait(1.6)
	await _shot("00_main_menu")
	# Into the game the way "Explore the Acts" does it, with a boosted sorcerer.
	GameState.act_options = {"level_mode": "custom", "level": TOUR_LEVEL, "monsters": true, "open_on_enter": true, "god_mode": true}
	Events.new_game_requested.emit("Act Explorer", CLASS_ID)
	_boost()
	await _await_area()
	await _wait(1.0)
	await _shot("01_act_explorer")
	UI.close_all_panels()
	UI.open_panel("debug", {})
	(UI.get_panel("debug") as DebugPanel).show_tab("zones")
	await _wait(0.6)
	await _shot("01b_debug_menu_zones")
	(UI.get_panel("debug") as DebugPanel).show_tab("cheats")
	await _wait(0.3)
	await _shot("01c_debug_menu_cheats")
	UI.close_all_panels()
	var n := 2
	for act in ActDefs.ACT_ORDER:
		n = await _tour_act(act, n)
	print("[acts-tour] %d screenshots" % count)
	get_tree().quit(0)


func _tour_act(act: String, n: int) -> int:
	UI.close_all_panels()
	main.call("request_area_change", "act", {"act": act, "zone": "hub", "seed": 7})
	await _await_area()
	await _wait(0.4)
	await _shot("%02d_%s_town_arrival" % [n, act])
	n += 1
	await _wait(3.0)
	var w := GameState.world
	if act == ActDefs.ACT_ORDER[0]:
		var rig := _player().camera_rig
		rig.set_camera_info_visible(true)
		rig.orbit_by(Vector2(-140, -90))
		await _wait(0.5)
		await _shot("%02d_%s_camera_orbit" % [n, act])
		n += 1
		rig.set_camera_info_visible(false)
		rig.reset_view()
		await _wait(0.3)
	var merchant := _find(w, "WorldVendorNpc")
	if merchant != null:
		_teleport(w.get_nearest_walkable(merchant.get_interact_position() + Vector3(0, 0, 3.0)))
		await _wait(0.8)
		await _shot("%02d_%s_town_merchant" % [n, act])
		n += 1
	# The road out of town.
	var road: Dictionary = w.layout.get("road", {})
	if not road.is_empty():
		_teleport(w.get_nearest_walkable(((road["from"] as Vector3) + (road["to"] as Vector3)) * 0.5))
		await _wait(0.8)
		await _shot("%02d_%s_road" % [n, act])
		n += 1
	# Out into the outskirts: the zone's name fades in; a far view shows how big it is.
	var p := _player()
	if p != null:
		p.god_mode = true
	_teleport(w.get_region_arrival("outskirts"))
	await _wait(1.1)
	await _shot("%02d_%s_outskirts_banner" % [n, act])
	n += 1
	await _wait(2.5)
	p = _player()
	if p != null and p.camera_rig != null:
		p.camera_rig.set_camera_info_visible(true)
		p.camera_rig.zoom_target = 60.0
		p.camera_rig.snap_to_target()
		await _wait(0.6)
		await _shot("%02d_%s_outskirts_far" % [n, act])
		n += 1
		p.camera_rig.set_camera_info_visible(false)
		p.camera_rig.reset_view()
		p.camera_rig.snap_to_target()
	n = await _act_fight(act, n)
	# Every further zone: its banner (name + monster level).
	for r in w.get_regions():
		var rid := String(r["id"])
		if rid == "hub" or rid == "outskirts":
			continue
		_teleport(w.get_region_arrival(rid))
		await _wait(1.1)
		await _shot("%02d_%s_%s_banner" % [n, act, rid])
		n += 1
		await _wait(2.6)
	# The act's dungeon: its door, inside, the act boss, the portals after it falls.
	var door := _find(w, "WorldDungeonEntrance")
	if door != null:
		_teleport(w.get_nearest_walkable(door.get_interact_position() + Vector3(0, 0, 1.5)))
		await _wait(0.8)
		await _shot("%02d_%s_dungeon_door" % [n, act])
		n += 1
		door.interact(_player())
		await _await_area()
		p = _player()
		if p != null:
			p.god_mode = true
		await _wait(0.6)
		await _shot("%02d_%s_dungeon_inside" % [n, act])
		n += 1
		var dw := GameState.world
		var boss: Enemy = null
		for e in EnemyDB.get_enemies(dw):
			if e.is_boss:
				boss = e
		if boss != null:
			_teleport(_stand_spot(dw, boss.global_position, 8.0))
			await _wait(0.6)
			boss.aggro(_player(), false)
			await _wait(1.6)
			await _shot("%02d_%s_act_boss" % [n, act])
			n += 1
			boss.die(_player())
			await _wait(2.5)
			await _shot("%02d_%s_act_cleared" % [n, act])
			n += 1
	return n


## Teleport next to a pack, pull it and cast a few spells.
func _act_fight(act: String, n: int) -> int:
	var w := GameState.world
	var p := _player()
	if w == null or p == null:
		return n
	var start := p.global_position
	# Big acts spawn packs near the player: walk (teleport) to the nearest pending pack first.
	if w.is_act():
		var goal := Vector3.INF
		var gd := INF
		for g in w.pending_groups():
			if String(g.get("kind", "")) == "boss":
				continue
			var d0 := CombatQuery.distance_xz(start, g["position"])
			if d0 < gd:
				gd = d0
				goal = g["position"]
		if goal != Vector3.INF:
			_teleport(w.get_nearest_walkable(goal + Vector3(0, 0, 14.0)))
			w.lazy_spawn_tick(true)
			await _wait(0.5)
			start = _player().global_position
	var best: Enemy = null
	var best_score := -INF
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			continue
		var near := 0
		for o in EnemyDB.get_enemies(w):
			if CombatQuery.distance_xz(o.global_position, e.global_position) < 5.0:
				near += 1
		var s := float(near) * 10.0 - CombatQuery.distance_xz(start, e.global_position) * 0.3
		if s > best_score:
			best_score = s
			best = e
	if best == null:
		return n
	var center := best.global_position
	_teleport(_stand_spot(w, center, 7.5))
	await _wait(0.5)
	for e in EnemyDB.get_enemies(w):
		if CombatQuery.distance_xz(e.global_position, center) < 9.0:
			e.aggro(_player(), false)
	await _wait(0.9)
	var bar := GameState.character.skill_bar
	var shot_taken := false
	for sid in ["fireball", "chain_lightning", "frost_nova", "meteor"]:
		var slot := bar.find(sid)
		p = _player()
		if slot < 0 or p == null:
			continue
		var tgt := _nearest_enemy(p)
		if tgt == null:
			break
		p.refill_pools()
		p.ai_aim(tgt.global_position, tgt)
		p.ai_hold_skill(slot, true)
		await _wait(0.5)
		p.ai_hold_skill(slot, false)
		if not shot_taken:
			await _shot("%02d_%s_wilds_fight" % [n, act])
			n += 1
			shot_taken = true
		await _wait(0.3)
	if p != null:
		p.ai_release_all()
	return n


## Every shot also logs the frame rate (the acts are dense outdoor scenes).
func _shot(shot_name: String) -> void:
	print("[acts-tour] %s  fps=%d  draw_calls=%d  primitives=%dk" % [shot_name, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	await super._shot(shot_name)
