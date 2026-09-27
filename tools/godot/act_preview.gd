extends Node3D
## Act preview: builds an act (ONE seamless world: hub + wilds + the road between them) and saves
## screenshots from the game camera (CameraRig defaults) and from above, for judging the look
## against the reference art. Needs a real window (not --headless).
##   GTEST_WINDOWED=1 tools/gtest.sh acts-desert res://tools/godot/act_preview.tscn -- --act=desert
## Options (after --):
##   --act=desert|forest|gothic   (default desert)
##   --zone=hub|wilds             where the stand-in arrives (default hub; the whole act is built)
##   --out=DIR                    (default $GTEST_REPO/docs/screenshots/acts/<act>, else user://act_preview)
##   --seed=N  --level=N          layout seed (default 1) and monster level
##   --monsters                   populate the wilds (idle monsters, for scale and colour)
##   --only=overview,regions,...  shot names to take (default all): overview, regions (every
##                                region: arrival, 2 far spots, from above) or a region id,
##                                road, seam (the road from both sides), low, interactables
##                                (i0..), spots (p0..), boss, dungeon
##   --hold=SECONDS               keep the window open after the shots (look around: WASD/arrows
##                                move, mouse wheel zooms, Q/E pitch) — handy for manual checks
## Prints the build time, layout stats and every saved file. Exit code = number of errors.
## OWNER: acts framework.

const FlowAreas := preload("res://scripts/main/flow_areas.gd")

var out_dir := ""
var cam: Camera3D = null
var errors := 0
var _hold := 0.0
var _focus := Vector3.ZERO
var _pitch := CameraRig.PITCH_DEG
var _yaw := CameraRig.YAW_DEG
var _dist := CameraRig.DEFAULT_DISTANCE
var _stand_in: Node3D = null


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		push_warning("act_preview: needs a window (run with GTEST_WINDOWED=1); nothing to do")
		get_tree().quit(0)
		return
	var act := String(args.get("act", "desert"))
	var zones: Array = [String(args.get("zone", "hub")).replace("both", "hub")]
	var repo := OS.get_environment("GTEST_REPO")
	out_dir = String(args.get("out", (repo + "/docs/screenshots/acts/" + act) if repo != "" else "user://act_preview/" + act))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_hold = float(args.get("hold", "0"))
	var only: Array = String(args.get("only", "")).split(",", false)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	for k in zones.size():
		var keep := _hold > 0.0 and k == zones.size() - 1
		await _preview_zone(act, zones[k], int(args.get("seed", "1")), int(args.get("level", "0")), args.has("monsters"), only, keep)
	print("[act_preview] done, %d error(s)" % errors)
	if _hold > 0.0:
		print("[act_preview] holding %.0f s: WASD/arrows move, wheel zooms, Q/E pitch" % _hold)
		while _hold > 0.0:
			await get_tree().process_frame
			_hold -= get_process_delta_time()
	get_tree().quit(errors)


func _preview_zone(act: String, zone: String, seed_value: int, level: int, monsters: bool, only: Array, keep: bool) -> void:
	var info := FlowAreas.act_info(act, zone, level, seed_value, monsters)
	var w := World.new()
	w.name = "World"
	add_child(w)
	GameState.world = w
	GameState.current_area = info
	w.build(info)
	var lay: Dictionary = w.layout
	print("[act_preview] %s built in %.0f ms: grid %s, walkable %d, props %d, shapes %d, lights %d, interactables %d, spawn groups %d" % [
		act, w.build_time_ms, w.grid.size, w.grid.walkable_count(), (lay["props"] as Array).size(),
		(lay["shapes"] as Array).size(), (lay["lights"] as Array).size(), (lay["interactables"] as Array).size(),
		w.get_spawn_groups().size()])
	print("[act_preview] build profile (ms): %s" % str(w.build_profile))
	print("[act_preview] nodes under the world: %d" % w.get_child_count(true) if false else "[act_preview] geometry nodes: %d" % w.level_root.find_children("*", "", true, false).size())
	if not w.grid.is_fully_connected():
		print("[act_preview] WARNING: walkable area is not fully connected")
	if monsters and zone == "wilds":
		EnemyDB.populate_area(w)
		print("[act_preview] monsters: %d" % EnemyDB.get_enemies(w).size())
	_stand_in = Assets.model("char_player")
	w.add_child(_stand_in)
	var ap := Assets.prepare_animations(_stand_in)
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
	await _wait(1.2)
	var prefix := "%s_" % act
	var dp := CameraRig.PITCH_DEG
	var dd := CameraRig.DEFAULT_DISTANCE
	# Overview from high above, framing the whole grid.
	var gsize := Vector2(w.grid.size) * World.TILE_SIZE
	var centre := Vector3(gsize.x * 0.5, 0, gsize.y * 0.5)
	if _want(only, "overview"):
		# No fog from that far up (it would wash the whole map out).
		var env := w.world_environment.environment if w.world_environment != null else null
		var fog_was := env.fog_enabled if env != null else false
		var vfog_was := env.volumetric_fog_enabled if env != null else false
		if env != null:
			env.fog_enabled = false
			env.volumetric_fog_enabled = false
		await _shot_at(w, centre, 64.0, maxf(gsize.x, gsize.y) * 1.2, prefix + "overview", false, 0.0)
		if env != null:
			env.fog_enabled = fog_was
			env.volumetric_fog_enabled = vfog_was
	# Every region: where the player arrives, its most open spot, and a spot far from both.
	for r in w.get_regions():
		var rid := String(r["id"])
		if not (_want(only, rid) or _want(only, "regions")):
			continue
		await _shot_at(w, w.get_region_arrival(rid), dp, dd, prefix + "%s_arrival" % rid, true)
		if rid == "hub":
			continue
		var spots := _region_spots(w, rid, 2)
		for k in spots.size():
			await _shot_at(w, spots[k], dp, dd, prefix + "%s_%d" % [rid, k], true)
		# The region from high above (no fog).
		var rb := _region_bounds(w, rid)
		var env2 := w.world_environment.environment if w.world_environment != null else null
		var fog2 := [env2.fog_enabled, env2.volumetric_fog_enabled] if env2 != null else []
		if env2 != null:
			env2.fog_enabled = false
			env2.volumetric_fog_enabled = false
		await _shot_at(w, Vector3(rb.get_center().x, 0, rb.get_center().y), 62.0, maxf(rb.size.x, rb.size.y) * 1.15, prefix + "%s_top" % rid, false, 0.0)
		if env2 != null:
			env2.fog_enabled = fog2[0]
			env2.volumetric_fog_enabled = fog2[1]
	var road: Dictionary = lay.get("road", {})
	if not road.is_empty():
		var rm: Vector3 = ((road["from"] as Vector3) + (road["to"] as Vector3)) * 0.5
		if _want(only, "road"):
			await _shot_at(w, rm, dp, dd, prefix + "road", true)
		if _want(only, "seam"):
			await _shot_at(w, road["from"], 40.0, 22.0, prefix + "seam_from_hub", true, 180.0 + rad_to_deg(atan2((road["to"] as Vector3).x - (road["from"] as Vector3).x, (road["to"] as Vector3).z - (road["from"] as Vector3).z)))
			await _shot_at(w, road["to"], 40.0, 22.0, prefix + "seam_from_wilds", true, 180.0 + rad_to_deg(atan2((road["from"] as Vector3).x - (road["to"] as Vector3).x, (road["from"] as Vector3).z - (road["to"] as Vector3).z)))
	var start := w.get_player_start()
	if _want(only, "low"):
		await _shot_at(w, start, 30.0, 15.0, prefix + "low", true)
	var de := w.get_dungeon_entrance()
	if not de.is_empty() and _want(only, "dungeon"):
		await _shot_at(w, w.get_region_arrival("dungeon_exit"), dp, dd, prefix + "dungeon", true)
	var n := 0
	for it in w.get_interactables():
		if n >= 8:
			break
		var nm := "i%d_%s" % [n, String((it as Node).name).to_lower()]
		if _want(only, "i%d" % n) or _want(only, "interactables"):
			await _shot_at(w, (it as Node3D).position + Vector3(0, 0, 2.5), dp, dd - 2.0, prefix + nm, true)
		n += 1
	# Spots spread over the walkable area (farthest-point sampling from the start).
	var spots := _spread_spots(w, start, 5)
	for k in spots.size():
		if _want(only, "p%d" % k) or _want(only, "spots"):
			await _shot_at(w, spots[k], dp, dd, prefix + "p%d" % k, true)
	if _want(only, "boss"):
		var bp: Vector3 = lay.get("boss_pos", start)
		await _shot_at(w, bp + Vector3(0, 0, 4.0), dp, dd + 2.0, prefix + "boss", true)
	if keep:
		_focus = start
		_place_camera(start, _pitch, _dist, _yaw)
		return
	EnemyDB.leave_combat_all(w)
	for e in EnemyDB.get_enemies(w):
		e.queue_free()
	remove_child(w)
	w.queue_free()
	GameState.world = null
	await get_tree().process_frame


## Farthest-point spots inside a region (from its arrival).
func _region_spots(w: World, rid: String, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cells: Array[Vector3] = []
	for j in range(0, w.grid.size.y, 3):
		for i in range(0, w.grid.size.x, 3):
			var c := Vector2i(i, j)
			if w.grid.is_walkable_cell(c):
				var p := w.grid.cell_center(c)
				if w.region_at(p) == rid:
					cells.append(p)
	var taken: Array[Vector3] = [w.get_region_arrival(rid)]
	for k in count:
		var best := Vector3.ZERO
		var best_d := -1.0
		for c in cells:
			var d := INF
			for t in taken:
				d = minf(d, c.distance_to(t))
			if d > best_d:
				best_d = d
				best = c
		if best_d <= 0.0:
			break
		taken.append(best)
		out.append(best)
	return out


func _region_bounds(w: World, rid: String) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in range(0, w.grid.size.y, 2):
		for i in range(0, w.grid.size.x, 2):
			var p := w.grid.cell_center(Vector2i(i, j))
			if w.region_at(p) == rid and w.grid.is_floor(Vector2i(i, j)):
				lo = lo.min(Vector2(p.x, p.z))
				hi = hi.max(Vector2(p.x, p.z))
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


func _want(only: Array, shot: String) -> bool:
	return only.is_empty() or shot in only


func _spread_spots(w: World, start: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cells: Array[Vector3] = []
	for j in range(0, w.grid.size.y, 2):
		for i in range(0, w.grid.size.x, 2):
			if w.grid.is_walkable_cell(Vector2i(i, j)):
				cells.append(w.grid.cell_center(Vector2i(i, j)))
	var taken: Array[Vector3] = [start]
	for k in count:
		var best := Vector3.ZERO
		var best_d := -1.0
		for c in cells:
			var d := INF
			for t in taken:
				d = minf(d, c.distance_to(t))
			if d > best_d:
				best_d = d
				best = c
		if best_d <= 0.0:
			break
		taken.append(best)
		out.append(best)
	return out


func _place_camera(focus: Vector3, pitch_deg: float, dist: float, yaw_deg: float = CameraRig.YAW_DEG) -> void:
	var f := focus + Vector3(0, 0.8, 0)
	cam.global_position = f + CameraRig.offset_for(dist, yaw_deg, pitch_deg)
	cam.look_at(f, Vector3.UP)
	RenderingServer.global_shader_parameter_set("player_world_pos", focus)


func _shot_at(w: World, focus: Vector3, pitch_deg: float, dist: float, shot_name: String, stand_in: bool, yaw_deg: float = CameraRig.YAW_DEG) -> void:
	_stand_in.visible = stand_in
	_stand_in.position = w.get_nearest_walkable(focus)
	_place_camera(_stand_in.position if stand_in else focus, pitch_deg, dist, yaw_deg)
	EnemyDB.apply_sleep(focus)
	w.snap_light_pool()
	await _wait(0.45)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	if err == OK:
		print("[act_preview] ", path)
	else:
		errors += 1
		push_warning("act_preview: can't save %s (%s)" % [path, error_string(err)])


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _process(delta: float) -> void:
	if _hold <= 0.0 or cam == null:
		return
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_Q):
		_pitch = clampf(_pitch - 30.0 * delta, 15.0, 85.0)
	if Input.is_key_pressed(KEY_E):
		_pitch = clampf(_pitch + 30.0 * delta, 15.0, 85.0)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		pass
	_focus += mv.rotated(Vector3.UP, deg_to_rad(_yaw)) * delta * 14.0
	_place_camera(_focus, _pitch, _dist, _yaw)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_yaw -= event.relative.x * 0.25
		_pitch = clampf(_pitch + event.relative.y * 0.25, 5.0, 89.0)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(6.0, _dist - 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(120.0, _dist + 1.5)
