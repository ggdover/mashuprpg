extends Node3D
## Forest act landmark shots (needs a window): builds the act and saves game-camera screenshots of
## the gateways, bridges, camps, the fort, the barrow and the downs' monuments. Spots are in the
## wilds' own coordinates (shifted by the composite's placement, found from the tarn arrival).
##   GTEST_WINDOWED=1 tools/gtest.sh acts-forest res://tests/scenes/acts_forest_shots.tscn -- --out=DIR [--only=a,b] [--monsters]
## OWNER: acts-forest.

const FlowAreas := preload("res://scripts/main/flow_areas.gd")
const TARN_ARRIVAL := Vector3(640, 0, 394)
const SPOTS := {
	"gate_tarn": Vector3(596, 0, 400), "stones_gap": Vector3(396, 0, 180), "stones_downs": Vector3(240, 0, 106),
	"cairns_hollows": Vector3(592, 0, 222), "bridge_brook": Vector3(401, 0, 356), "waterfall": Vector3(266, 0, 344),
	"camp": Vector3(438, 0, 488), "troll_stones": Vector3(496, 0, 458), "pond": Vector3(548, 0, 350),
	"fort_gate": Vector3(410, 0, 108), "fort_bridge": Vector3(376, 0, 72), "fort_east": Vector3(414, 0, 64),
	"gorge_south": Vector3(400, 0, 124), "jetty": Vector3(734, 0, 364), "causeway": Vector3(684, 0, 426),
	"island": Vector3(748, 0, 458), "witch": Vector3(700, 0, 520), "tarn_north": Vector3(720, 0, 300),
	"hollows_mid": Vector3(720, 0, 176), "hollows_deep": Vector3(742, 0, 124), "ship": Vector3(150, 0, 100),
	"king": Vector3(96, 0, 144), "downs_mid": Vector3(90, 0, 80),
}

var cam: Camera3D = null
var stand_in: Node3D = null
var out_dir := ""


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	out_dir = String(args.get("out", "user://forest_shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only: Array = String(args.get("only", "")).split(",", false)
	cam = Camera3D.new()
	cam.fov = CameraRig.FOV
	cam.far = 800.0
	add_child(cam)
	cam.current = true
	var info := FlowAreas.act_info("forest", "hub", 12, 1, args.has("monsters"))
	var w := World.new()
	add_child(w)
	GameState.world = w
	GameState.current_area = info
	w.build(info)
	if args.has("monsters"):
		EnemyDB.populate_area(w)
	stand_in = Assets.model("char_player")
	w.add_child(stand_in)
	var off := w.get_region_arrival("tarn") - TARN_ARRIVAL
	await _wait(1.0)
	var extra := {"dungeon": w.get_region_arrival("dungeon_exit"), "boss": (w.layout["boss_pos"] as Vector3) + Vector3(0, 0, 3)}
	for key in SPOTS.keys() + extra.keys():
		if not only.is_empty() and not key in only:
			continue
		var p: Vector3 = (SPOTS[key] as Vector3) + off if SPOTS.has(key) else extra[key]
		stand_in.position = w.get_nearest_walkable(p)
		var f := stand_in.position + Vector3(0, CameraRig.FOCUS_HEIGHT, 0)
		cam.global_position = f + CameraRig.offset_for(CameraRig.DEFAULT_DISTANCE, CameraRig.YAW_DEG, CameraRig.PITCH_DEG)
		cam.look_at(f, Vector3.UP)
		RenderingServer.global_shader_parameter_set("player_world_pos", stand_in.position)
		var themes: Dictionary = w.get("_region_themes")
		w.call("_apply_environment", themes.get(w.region_at(stand_in.position), {}))
		EnemyDB.apply_sleep(p)
		await _wait(0.5)
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("forest_%s.png" % key)
		get_viewport().get_texture().get_image().save_png(path)
		print("[shots] %s %s (%s)" % [path, str(stand_in.position), w.region_at(stand_in.position)])
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
