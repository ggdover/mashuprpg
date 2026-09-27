extends Node3D
## Gothic act sanity check: builds the act (one seamless World), checks that the start, every
## interactable and every spawn group are reachable, prints the build profile, prop instance /
## triangle counts per model id, collision shapes and lights, and (windowed) saves game-camera
## screenshots of chosen spots of the zones.
##   tools/gtest.sh acts-gothic res://tests/scenes/acts_gothic_check.tscn
##   GTEST_WINDOWED=1 tools/gtest.sh acts-gothic res://tests/scenes/acts_gothic_check.tscn -- --shots=all --out=DIR
## Options (after --): --shots=all|name,name... (see SPOTS), --out=DIR (default user://gothic_check),
## --dist=M (camera distance, default the game's), --monsters (spawn the packs near each spot),
## --fps (measure the frame rate for a second at each spot); --shots=packs shoots a pack per zone.
## Exit code = number of problems. OWNER: acts-gothic.

const FlowAreas := preload("res://scripts/main/flow_areas.gd")
## Named spots in the wilds layout's cell units (x, z).
const SPOTS := {
	"fountain": Vector2(200.0, 205.0), "market": Vector2(248.0, 206.0), "clock": Vector2(236.0, 156.0),
	"gallows": Vector2(151.0, 244.0), "chapel": Vector2(147.0, 152.0), "yard": Vector2(240.0, 248.0),
	"ward_street": Vector2(170.0, 170.0), "ward_edge": Vector2(128.0, 160.0),
	"canal_bridge": Vector2(71.0, 168.0), "canal_quay": Vector2(58.0, 158.0), "sluice": Vector2(50.0, 190.0),
	"canal_square": Vector2(64.0, 188.0),
	"cemetery_rows": Vector2(38.0, 70.0), "mausoleum": Vector2(56.0, 40.0), "crossing": Vector2(56.0, 66.0),
	"great_bridge": Vector2(236.0, 58.0), "bridge_head": Vector2(212.0, 58.0), "gorge_rim": Vector2(222.0, 36.0),
	"abbey_front": Vector2(345.0, 40.0), "cloister": Vector2(369.0, 24.0), "undercroft": Vector2(392.0, 57.0),
	"pilgrims_way": Vector2(310.0, 57.0), "abbey_graves": Vector2(362.0, 76.0),
	"gate_canals": Vector2(108.0, 198.0), "gate_bridge": Vector2(203.0, 114.0), "gate_cemetery": Vector2(57.0, 122.0),
	"gate_abbey": Vector2(291.0, 60.0),
}

var problems := 0
var cam: Camera3D = null


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	await _check(args)
	print("[gothic_check] done, %d problem(s)" % problems)
	get_tree().quit(problems)


func _check(args: Dictionary) -> void:
	var info := FlowAreas.act_info("gothic", "hub", 20, 1, true)
	var w := World.new()
	add_child(w)
	GameState.world = w
	GameState.current_area = info
	w.build(info)
	var lay: Dictionary = w.layout
	var start := w.get_player_start()
	print("[gothic_check] built in %.0f ms, walkable %d, connected %s" % [w.build_time_ms, w.grid.walkable_count(), w.grid.is_fully_connected()])
	print("[gothic_check] profile: %s" % str(w.build_profile))
	if not w.is_walkable(start):
		_fail("start not walkable")
	for it in w.get_interactables():
		var p: Vector3 = (it as Node3D).position
		if it.has_method("get_interact_position"):
			p = it.get_interact_position()
		var d := w.get_path_distance(start, w.get_nearest_walkable(p))
		var gap := w.get_nearest_walkable(p).distance_to(Vector3(p.x, 0, p.z))
		if d == INF or gap > 3.5:
			_fail("%s unreachable (%s)" % [(it as Node).name, p])
	for g in w.get_spawn_groups():
		var gp: Vector3 = g["position"]
		if w.get_path_distance(start, gp) == INF:
			_fail("spawn group %s at %s unreachable" % [g["kind"], gp])
	var per_region := {}
	for g2 in w.get_spawn_groups():
		var rid := w.region_at(g2["position"])
		per_region[rid] = int(per_region.get(rid, 0)) + 1
	print("[gothic_check] spawn groups per zone: %s" % str(per_region))
	var inter := {}
	for it2 in w.get_interactables():
		var key := "%s:%s" % [w.region_at((it2 as Node3D).position), (it2 as Node).get_class() if (it2 as Object).get_script() == null else String((it2 as Object).get_script().get_global_name())]
		inter[key] = int(inter.get(key, 0)) + 1
	print("[gothic_check] interactables per zone: %s" % str(inter))
	var body := w.find_child("WallCollision", true, false)
	print("[gothic_check] collision shapes in the world: %d" % (body.get_child_count() if body != null else -1))
	# Prop counts and triangles.
	var counts := {}
	for d2 in lay["props"]:
		counts[d2["id"]] = int(counts.get(d2["id"], 0)) + 1
	var tiles := 0
	for tg in lay["tiles"]:
		tiles += (tg["cells"] as Array).size()
	var total_tris := 0
	var house_tris := 0
	var ids: Array = counts.keys()
	ids.sort()
	var line := ""
	var tri_of := {}
	for id in ids:
		var tris := _tris(id)
		tri_of[id] = tris
		total_tris += tris * int(counts[id])
		if String(id).begins_with("gothic_house") or String(id).begins_with("gothic_terrace"):
			house_tris += tris * int(counts[id])
		line += "%s x%d (%dk)  " % [id, counts[id], tris * int(counts[id]) / 1000]
	var hub_house_tris := 0
	for d3 in lay["props"]:
		var hid := String(d3["id"])
		if (hid.begins_with("gothic_house") or hid.begins_with("gothic_terrace")) and w.region_at(d3["pos"]) == "hub":
			hub_house_tris += int(tri_of.get(hid, 0))
	print("[gothic_check] house triangles: %dk in the town, %dk in the zones" % [hub_house_tris / 1000, (house_tris - hub_house_tris) / 1000])
	var tile_tris := 0
	for tg2 in lay["tiles"]:
		var t_ids: Array = tg2["ids"]
		tile_tris += _tris(String(t_ids[0])) * (tg2["cells"] as Array).size()
	print("[gothic_check] props: %d (~%dk tris, houses ~%dk), tiles: %d (~%dk tris), shapes: %d, lights: %d, glows: %d" % [
		(lay["props"] as Array).size(), total_tris / 1000, house_tris / 1000, tiles, tile_tris / 1000, (lay["shapes"] as Array).size(),
		(lay["lights"] as Array).size(), (lay["glows"] as Array).size()])
	print("[gothic_check] ", line)
	if DisplayServer.get_name() != "headless" and args.has("shots"):
		await _shots(w, args)
	remove_child(w)
	w.queue_free()
	GameState.world = null
	await get_tree().process_frame


func _shots(w: World, args: Dictionary) -> void:
	var out := String(args.get("out", "user://gothic_check"))
	DirAccess.make_dir_recursive_absolute(out)
	var want := String(args["shots"])
	var names: Array = SPOTS.keys() if want == "all" or want == "1" else Array(want.split(",", false))
	# "packs": a spot at one monster group of every zone (world positions).
	var pack_spots := {}
	if want == "packs":
		names = []
		for g in w.get_spawn_groups():
			var rid := w.region_at(g["position"])
			if not pack_spots.has("pack_" + rid) and String(g["kind"]) != "boss":
				pack_spots["pack_" + rid] = g["position"]
				names.append("pack_" + rid)
	var dist := float(args.get("dist", str(CameraRig.DEFAULT_DISTANCE)))
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	var comp := w._act_gen as WorldActComposite
	var stand := Assets.model("char_player")
	w.add_child(stand)
	var ap := Assets.prepare_animations(stand)
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
	if args.has("monsters"):
		w.start_lazy_spawns()
	for n in names:
		var p: Vector3
		if pack_spots.has(n):
			p = w.get_nearest_walkable(pack_spots[n] + Vector3(3.0, 0.0, 4.0))
		elif SPOTS.has(n):
			var c: Vector2 = SPOTS[n]
			p = w.get_nearest_walkable(comp.to_world(comp.parts["wilds"], Vector3(c.x * World.TILE_SIZE, 0.0, c.y * World.TILE_SIZE)))
		else:
			continue
		stand.position = p
		var f := p + Vector3(0, 0.8, 0)
		cam.global_position = f + CameraRig.offset_for(dist, CameraRig.YAW_DEG, CameraRig.PITCH_DEG)
		cam.look_at(f, Vector3.UP)
		RenderingServer.global_shader_parameter_set("player_world_pos", p)
		w._apply_environment(w._region_themes.get(w.region_at(p), {}))
		if args.has("monsters"):
			var got := w.lazy_spawn_tick(true)
			print("[gothic_check]   %s: spawned %d, monsters %d, pending %d" % [n, got, EnemyDB.get_enemies(w).size(), w.pending_spawn_count()])
		EnemyDB.apply_sleep(p)
		w.snap_light_pool()
		for k in 24:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out.path_join("gothic_%s.png" % n)
		if img.save_png(path) == OK:
			print("[gothic_check] ", path)
		if args.has("fps"):
			var t0 := Time.get_ticks_usec()
			var frames := 0
			while Time.get_ticks_usec() - t0 < 1000000:
				await get_tree().process_frame
				frames += 1
			print("[gothic_check]   fps at %s: %d" % [n, frames])
	cam.queue_free()


func _tris(id: String) -> int:
	var n := 0
	var inst := Assets.model(id)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m != null:
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	inst.free()
	return n


func _fail(msg: String) -> void:
	problems += 1
	push_warning("gothic_check: " + msg)
	print("[gothic_check] PROBLEM: ", msg)
