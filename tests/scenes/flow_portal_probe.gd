extends Node
## Probe (flow): are the boss exit portals reachable by the Player's click auto-walk? For many
## dungeon seeds: build the dungeon, spawn the exit portals where the boss stands, place the
## player a few metres away, ai_interact() each portal and report failures with positions.
##   GTEST_FULL=1 tools/gtest.sh flow-probe res://tests/scenes/flow_portal_probe.tscn -- --seeds=30
## OWNER: flow.

var fails := 0
var total := 0


func _ready() -> void:
	get_tree().create_timer(170).timeout.connect(get_tree().quit)
	_run.call_deferred()


func _run() -> void:
	var n := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			n = int(a.substr(8))
	GameState.new_character("Probe", "warrior")
	for s in n:
		var depth := 1 + (s % 12)
		await _probe(depth, 1000 + s)
	print("[portal_probe] %d / %d portal walks failed" % [fails, total])
	get_tree().quit(fails)


func _probe(depth: int, seed_value: int) -> void:
	var w := World.new()
	add_child(w)
	GameState.world = w
	var info := {"id": "dungeon", "depth": depth, "level": depth, "seed": seed_value, "theme": World.theme_for_depth(depth), "name": "probe"}
	GameState.current_area = info
	w.build(info)
	EnemyDB.populate_area(w)
	var boss_pos := w.get_boss_room_center()
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			boss_pos = e.global_position
		else:
			e.queue_free()
	w.spawn_exit_portals(boss_pos)
	for dest in ["town", "next"]:
		var portal: WorldPortal = null
		for it in w.get_interactables():
			if it is WorldPortal and (it as WorldPortal).destination == dest and CombatQuery.distance_xz((it as Node3D).position, boss_pos) < 12.0:
				portal = it
		if portal == null:
			continue
		total += 1
		var p := Player.new()
		p.setup(GameState.character)
		var start := w.random_walkable_near(boss_pos, 5.0)
		p.position = start
		GameState.player = p
		w.add_child(p)
		p.god_mode = true
		await get_tree().physics_frame
		var reached := [false]
		var cb := func(_id: String, _params: Dictionary) -> void: reached[0] = true
		Events.area_change_requested.connect(cb)
		p.ai_interact(portal)
		var t := 0.0
		var retries := 0
		while t < 10.0 and not reached[0]:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if not p.is_auto_walking() and not reached[0]:
				retries += 1
				p.ai_interact(portal)
		Events.area_change_requested.disconnect(cb)
		if not reached[0]:
			fails += 1
			var pp := portal.global_position
			print("[portal_probe] FAIL depth %d seed %d dest %s: player %s -> portal %s (dist %.1f, walkable %s, path %d pts, path dist %.1f, retries %d)" % [
				depth, seed_value, dest, _v(p.global_position), _v(pp), CombatQuery.distance_xz(p.global_position, pp),
				str(w.is_walkable(pp)), w.find_path(p.global_position, pp).size(), w.get_path_distance(p.global_position, pp), retries])
		GameState.player = null
		p.queue_free()
		await get_tree().physics_frame
	GameState.world = null
	w.queue_free()
	await get_tree().process_frame


static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]
