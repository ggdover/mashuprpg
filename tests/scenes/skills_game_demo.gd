extends Node3D
## Integration demo (needs the live Player / Enemy / EnemyDB: run with GTEST_FULL=1): a real
## Player of each class in a real dungeon, driven through the Player.ai_* API (the keyboard /
## mouse code paths), uses its skills on real monsters spawned by EnemyDB, with the real camera
## rig. Windowed runs save docs/screenshots/skills/game_<class>_<skill>.png just after each skill's
## effect; headless runs are an integration smoke test.
##
##   GTEST_FULL=1 GTEST_WINDOWED=1 GTEST_TIMEOUT=150 tools/gtest.sh skills-game res://tests/scenes/skills_game_demo.tscn -- --quit_after=130
##   ... -- --classes=warrior                     (subset)
## OWNER: skills.

## class -> [weapon base or "", [skill ids]]
const PLAN := {
	"warrior": ["", ["cleave", "ground_slam", "leap_slam", "whirlwind", "infernal_blow", "war_cry"]],
	"ranger": ["", ["split_arrow", "power_shot", "rain_of_arrows", "ice_shot", "venom_arrow"]],
	"crossbow": ["crossbow_2", ["explosive_bolt", "scatter_shot", "rapid_fire"]],
	"sorcerer": ["", ["fireball", "ice_spear", "chain_lightning", "frost_nova", "spark", "meteor"]],
}
const LEVEL := 20

var world: World = null
var player: Player = null
var rig: CameraRig = null
var shots := true
var out_dir := ""
var only: PackedStringArray = []
var count := 0


func _ready() -> void:
	get_tree().create_timer(_arg_float("--quit_after", 20.0)).timeout.connect(get_tree().quit)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--classes="):
			only = a.substr(10).split(",", false)
	shots = DisplayServer.get_name() != "headless"
	out_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/skills/"
	if shots:
		DirAccess.make_dir_recursive_absolute(out_dir)
		get_window().size = Vector2i(1280, 720)
	_run.call_deferred()


func _arg_float(key: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return float(a.substr(key.length() + 1))
	return def


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name_: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name_ + ".png")
	count += 1


func _run() -> void:
	for k in PLAN:
		if only.is_empty() or only.has(k):
			await _class_run(k)
	print("[skills_game_demo] done, %d screenshots" % count)
	get_tree().quit()


func _setup_area(class_key: String) -> void:
	if world != null:
		GameState.player = null
		GameState.world = null
		world.queue_free()
		await get_tree().process_frame
	world = World.new()
	add_child(world)
	GameState.world = world
	var info := {"id": "dungeon", "depth": 4, "level": LEVEL, "seed": 777, "theme": "crypt", "name": "Demo"}
	GameState.current_area = info
	world.build(info)
	var cls := class_key if class_key != "crossbow" else "ranger"
	var c := GameState.new_character("Demo", cls)
	c.level = LEVEL
	var wbase := String(PLAN[class_key][0])
	if wbase != "":
		c.equip(ItemDB.create_item(wbase, Item.Rarity.NORMAL, LEVEL), "main_hand")
		c.equip(ItemDB.create_item("quiver_1", Item.Rarity.NORMAL, LEVEL), "off_hand")
	player = Player.new()
	player.setup(c)
	player.position = world.get_player_start()
	world.add_child(player)
	GameState.player = player
	player.god_mode = true
	rig = CameraRig.new()
	rig.target = player
	world.add_child(rig)
	player.camera_rig = rig
	rig.snap_to_target()
	if world.has_method("snap_light_pool"):
		world.snap_light_pool()
	Events.player_spawned.emit(player)
	await _wait(0.4)


func _spawn_pack(center: Vector3, n: int) -> Array:
	var out: Array = []
	var ids := ["skeleton_warrior", "zombie", "skeleton_archer", "ghoul"]
	for i in n:
		var pos := world.random_walkable_near(center, 2.5)
		var e: Variant = EnemyDB.spawn_enemy(ids[i % ids.size()], pos, LEVEL, 0, [], world)
		if e != null:
			out.append(e)
			(e as Actor).base_move_speed *= 0.35
	return out


func _class_run(class_key: String) -> void:
	await _setup_area(class_key)
	if player.skill_runner == null or EnemyDB.get_def("skeleton_warrior").is_empty():
		push_warning("skills_game_demo: needs the live Player / EnemyDB (run with GTEST_FULL=1)")
		return
	var skills: Array = PLAN[class_key][1]
	var fwd := _open_direction()
	for id in skills:
		if not is_instance_valid(player):
			return
		player.character.set_skill_in_slot(1, id)
		player.refill_pools()
		for e in world.enemies_root.get_children():
			e.queue_free()
		await get_tree().process_frame
		var dist := 7.0 if not id in ["cleave", "whirlwind", "infernal_blow", "frost_nova", "scatter_shot", "war_cry"] else 3.0
		var center := player.global_position + fwd * dist
		var pack := _spawn_pack(center, 5)
		await _wait(0.3)
		var tgt: Actor = null
		for e in pack:
			if is_instance_valid(e) and not (e as Actor).dead:
				tgt = e
				break
		var aim := center if tgt == null else tgt.global_position
		if id == "leap_slam":
			aim = center
		player.ai_aim(aim, tgt)
		player.ai_hold_skill(1, true)
		var r := player.skill_runner
		var t := 0.0
		var hit_after := 0.0
		while t < 2.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if r.is_busy() and hit_after == 0.0:
				hit_after = t + r.get_hit_time()
			if hit_after > 0.0 and t >= hit_after + _extra(id):
				break
		if id != "whirlwind":
			player.ai_hold_skill(1, false)
		await _shot("game_%s_%s" % [class_key, id])
		player.ai_release_all()
		await _wait(0.6)
		if not id in ["leap_slam"]:
			continue
		# After a leap, walk back so the next skill starts from the room.
		player.global_position = world.get_player_start()


func _extra(id: String) -> float:
	match id:
		"fireball", "explosive_bolt", "ice_spear", "power_shot", "split_arrow", "ice_shot":
			return 0.2
		"venom_arrow":
			return 0.7
		"meteor":
			return 1.05
		"rain_of_arrows":
			return 0.55
		"leap_slam":
			return 0.55
		"whirlwind":
			return 0.8
		"spark":
			return 0.35
		"rapid_fire":
			return 0.45
		"war_cry":
			return 0.2
	return 0.06


## The direction from the player start with the most open floor.
func _open_direction() -> Vector3:
	var start := world.get_player_start()
	var best := Vector3.FORWARD
	var best_n := -1
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector3(sin(a), 0, cos(a))
		var n := 0
		for k in range(1, 6):
			if world.is_walkable(start + d * 2.0 * k):
				n += 1
			else:
				break
		# Prefer "up the screen" (-Z) on ties so the action stays in view.
		if n > best_n or (n == best_n and d.z < best.z):
			best_n = n
			best = d
	return best
