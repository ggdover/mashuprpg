extends Node3D
## World demo: builds the town and dungeons of each theme (depths 1, 4, 7) with a stand-in
## player capsule (+ the player's warm light) and a camera at the gameplay angle (§11.4: FOV 45,
## pitch 56°, distance 18, looking toward -Z). Saves windowed screenshots to
## docs/screenshots/world/: <area>_gameplay.png, <area>_overview.png, dungeons: _boss_room,
## _exit_portals, _town_portal, _chest (resting) / _chest_hover, _shrine, _lava; town: _merchant,
## _gate; and the wall cut-out check (<area>_cutout_on.png / _cutout_off.png: the capsule stands
## right behind a wall).
##
##   GTEST_WINDOWED=1 tools/gtest.sh world-demo res://tests/scenes/world_demo.tscn
##   ... -- --areas=town,d1 --seed=7        (subset / other seed)
## Headless runs only build the areas (smoke test) and skip the screenshots.

const PITCH := 56.0
const DISTANCE := 18.0

var cam: Camera3D
var world: World = null
var capsule: Node3D = null
var out_dir := ""
var shots := true
var areas: PackedStringArray = ["town", "d1", "d4", "d7"]
var seed_value := 20260925


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--areas="):
			areas = a.substr(8).split(",", false)
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	shots = DisplayServer.get_name() != "headless"
	out_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/world/"
	if shots:
		DirAccess.make_dir_recursive_absolute(out_dir)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 600.0
	add_child(cam)
	cam.make_current()
	_run.call_deferred()


func _run() -> void:
	for a in areas:
		await _show_area(a)
	print("[world_demo] done")
	get_tree().quit()


func _info(a: String) -> Dictionary:
	if a == "town":
		return {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
	if a == "arena":
		return {"id": "arena", "name": "Arena", "level": 1, "size": 16}
	var depth := int(a.substr(1))
	var theme := World.theme_for_depth(depth)
	return {"id": "dungeon", "depth": depth, "level": depth, "seed": seed_value + depth, "theme": theme,
		"name": "Depth %d — %s" % [depth, World.theme_display_name(theme)]}


func _show_area(a: String) -> void:
	if world != null:
		world.queue_free()
		await get_tree().process_frame
	world = World.new()
	add_child(world)
	GameState.world = world
	var info := _info(a)
	GameState.current_area = info
	world.build(info)
	print("[world_demo] %s built in %.1f ms: lights=%d collision_shapes=%d interactables=%d spawn_groups=%d" % [
		a, world.build_time_ms, world.get_light_count(), world.get_collision_shape_count(),
		world.get_interactables().size(), world.get_spawn_groups().size()])
	_make_capsule()
	var start := world.get_player_start()
	# Gameplay angle at the player start.
	_place_player(start)
	_aim(start, PITCH, DISTANCE)
	await _capture("%s_gameplay" % a)
	if world.area_info.get("id", "") == "arena":
		pass
	elif world.is_town():
		# Hover the merchant to show its label + highlight.
		for n in world.get_interactables():
			if n is WorldVendorNpc:
				(n as WorldVendorNpc).set_hovered(true)
				_place_player((n as Node3D).position + Vector3(2.5, 0, 1.0))
				_aim((n as Node3D).position + Vector3(2.0, 0, 0), PITCH, DISTANCE)
				await _capture("%s_merchant" % a)
				(n as WorldVendorNpc).set_hovered(false)
		for n in world.get_interactables():
			if n is WorldWaypointGate:
				var gp := (n as Node3D).position
				_place_player(gp + Vector3(1.0, 0, 3.5))
				_aim(gp + Vector3(0, 0, 4.0), PITCH, DISTANCE)
				(n as WorldWaypointGate).set_hovered(true)
				await _capture("%s_gate" % a)
				(n as WorldWaypointGate).set_hovered(false)
		# Cut-out through a house: the player stands right behind (north of) a southern house.
		var south: Dictionary = {}
		for h in world.layout["houses"]:
			if south.is_empty() or (h["pos"] as Vector3).z > (south["pos"] as Vector3).z:
				south = h
		var hp: Vector3 = south["pos"] + Vector3(0, 0, -3.7)
		_place_player(hp)
		_aim(hp, PITCH, DISTANCE)
		await _capture("%s_cutout_on" % a)
		RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(-1000, 0, -1000))
		await _capture("%s_cutout_off" % a)
	else:
		# A room with something in it: the boss room and a chest.
		var boss := world.get_boss_room_center()
		_place_player(boss + Vector3(0, 0, 3))
		_aim(boss, PITCH, DISTANCE)
		await _capture("%s_boss_room" % a)
		world.spawn_exit_portals(boss)
		await _capture("%s_exit_portals" % a)
		# A Town Portal cast in the south of the boss room (placed clear of the exit portals).
		var tp := world.spawn_town_portal(boss + Vector3(0, 0, 4.5))
		_place_player(boss + Vector3(0, 0, 4.5))
		_aim(tp.position, PITCH, DISTANCE)
		print("[world_demo] %s lights with exit + town portals: %d" % [a, world.get_light_count()])
		await _capture("%s_town_portal" % a)
		for n in world.get_interactables():
			if n is WorldChest:
				_place_player(world.get_nearest_walkable((n as Node3D).position + (n as Node3D).global_transform.basis.z * 2.2 + Vector3(0.8, 0, 0)))
				_aim((n as Node3D).position, PITCH, DISTANCE)
				await _capture("%s_chest" % a)
				(n as WorldChest).set_hovered(true)
				await _capture("%s_chest_hover" % a)
				(n as WorldChest).set_hovered(false)
				break
		for n in world.get_interactables():
			if n is WorldShrine:
				_place_player((n as Node3D).position + Vector3(1.5, 0, 2.5))
				_aim((n as Node3D).position, PITCH, DISTANCE)
				(n as WorldShrine).set_hovered(true)
				await _capture("%s_shrine" % a)
				(n as WorldShrine).set_hovered(false)
		var pools: Array = world.layout.get("lava", [])
		if not pools.is_empty():
			var r: Rect2i = pools[0]["rect"]
			var lc := world.grid.origin + Vector3((r.position.x + r.size.x * 0.5) * World.TILE_SIZE, 0, (r.position.y + r.size.y * 0.5) * World.TILE_SIZE)
			_place_player(world.get_nearest_walkable(lc + Vector3(0, 0, r.size.y + 1.5)))
			_aim(lc, PITCH, DISTANCE)
			await _capture("%s_lava" % a)
		await _cutout_shots(a)
	# Overview of the whole area.
	var env := world.world_environment.environment
	var fog_was := env.fog_enabled
	env.fog_enabled = false
	var extent := world.grid.size.x * World.TILE_SIZE
	var centre := world.grid.origin + Vector3(extent * 0.5, 0, extent * 0.5)
	_place_player(Vector3(-1000, 0, -1000))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 1.02
	_aim(centre, 72.0, extent * 1.5)
	await _capture("%s_overview" % a)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	env.fog_enabled = fog_was


## Capsule right behind (north of) a wall: the wall stands between camera and player.
func _cutout_shots(a: String) -> void:
	var g := world.grid
	var best := Vector2i(-1, -1)
	var sc := g.world_to_cell(world.get_player_start())
	var best_d := INF
	for j in range(1, g.size.y - 2):
		for i in range(1, g.size.x - 1):
			var c := Vector2i(i, j)
			if g.is_walkable_cell(c) and not g.is_floor(c + Vector2i(0, 1)) and not g.is_floor(c + Vector2i(0, 2)) and g.is_walkable_cell(c + Vector2i(-1, 0)) and g.is_walkable_cell(c + Vector2i(1, 0)):
				var d := Vector2(c - sc).length()
				if d < best_d:
					best_d = d
					best = c
	if best.x < 0:
		return
	var pos := g.cell_center(best) + Vector3(0, 0, 0.45)
	_place_player(pos)
	_aim(pos, PITCH, DISTANCE)
	await _capture("%s_cutout_on" % a)
	RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(-1000, 0, -1000))
	await _capture("%s_cutout_off" % a)
	_place_player(pos)


func _make_capsule() -> void:
	capsule = Node3D.new()
	capsule.name = "StandInPlayer"
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.2, 0.15)
	mi.material_override = m
	capsule.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 1.2
	light.omni_range = 10.0
	light.position = Vector3(0, 3.0, 0)
	capsule.add_child(light)
	world.add_dynamic(capsule)


func _place_player(pos: Vector3) -> void:
	capsule.position = pos
	RenderingServer.global_shader_parameter_set("player_world_pos", pos)
	world.mark_explored(pos, 14.0)


func _aim(target: Vector3, pitch_deg: float, dist: float) -> void:
	var p := deg_to_rad(pitch_deg)
	cam.position = target + Vector3(0, sin(p) * dist, cos(p) * dist)
	cam.rotation = Vector3(-p, 0, 0)


func _capture(shot_name: String) -> void:
	await get_tree().process_frame
	world.snap_light_pool()
	for i in 8:
		await RenderingServer.frame_post_draw
	if not shots:
		return
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + shot_name + ".png"
	img.save_png(path)
	print("[world_demo] saved ", path)
