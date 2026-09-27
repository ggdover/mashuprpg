extends Node3D
## Desert act shots (dev tool): builds the act World and saves game-camera screenshots at given
## spots, for checking landmarks the region shots of act_preview miss. Needs a window.
##   GTEST_WINDOWED=1 tools/gtest.sh acts-desert res://tests/scenes/acts_desert_shots.tscn -- \
##     --out=DIR --at=bridge:340:290,temple:631:176:20:40:30
## Each spot: name:x:z[:yaw_deg[:pitch_deg[:distance]]] (world metres; defaults = the game camera).
## --packs: also spawn one monster pack per zone and shoot it (pack_<zone>).
## OWNER: acts-desert.

const FlowAreas := preload("res://scripts/main/flow_areas.gd")

var cam: Camera3D = null
var _stand_in: Node3D = null


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		push_warning("acts_desert_shots: needs a window (GTEST_WINDOWED=1)")
		get_tree().quit(0)
		return
	var out := String(args.get("out", "user://desert_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	var info := FlowAreas.act_info("desert", "hub", 10, int(args.get("seed", "1")), false)
	var w := World.new()
	w.name = "World"
	add_child(w)
	GameState.world = w
	GameState.current_area = info
	w.build(info)
	print("[desert_shots] built in %.0f ms" % w.build_time_ms)
	_stand_in = Assets.model("char_player")
	w.add_child(_stand_in)
	await _wait(1.0)
	var specs: Array = Array(String(args.get("at", "")).split(",", false))
	if args.has("packs"):
		# One monster pack per zone (its own pool and level), shot where it stands.
		var done := {}
		var pid := 0
		for g in w.get_spawn_groups():
			var rid := w.region_at(g["position"])
			if done.has(rid) or String(g.get("kind", "")) == "boss":
				continue
			done[rid] = true
			var gp: Vector3 = g["position"]
			EnemyDB.spawn_group(w, g, pid)
			pid += 1
			specs.append("pack_%s:%.1f:%.1f:37.5:52:15" % [rid, gp.x, gp.z + 3.0])
	for spec: String in specs:
		var p := spec.split(":")
		if p.size() < 3:
			continue
		var focus := Vector3(float(p[1]), 0.0, float(p[2]))
		var yaw := float(p[3]) if p.size() > 3 else CameraRig.YAW_DEG
		var pitch := float(p[4]) if p.size() > 4 else CameraRig.PITCH_DEG
		var dist := float(p[5]) if p.size() > 5 else CameraRig.DEFAULT_DISTANCE
		_stand_in.position = w.get_nearest_walkable(focus)
		var f := _stand_in.position + Vector3(0, 0.8, 0)
		cam.global_position = f + CameraRig.offset_for(dist, yaw, pitch)
		cam.look_at(f, Vector3.UP)
		RenderingServer.global_shader_parameter_set("player_world_pos", _stand_in.position)
		EnemyDB.apply_sleep(focus)
		w.snap_light_pool()
		await _wait(0.5)
		await RenderingServer.frame_post_draw
		var path := out.path_join("desert_%s.png" % p[0])
		get_viewport().get_texture().get_image().save_png(path)
		print("[desert_shots] ", path)
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
