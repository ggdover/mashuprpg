extends Node3D
## Ground loot demo: a plain floor + fixed game-like camera (no World / CameraRig) with ground items
## of every rarity and several slots, gold piles and a scattered boss drop. Checks the pick shapes
## with real physics rays (model + label) and saves screenshots when windowed:
##   GTEST_WINDOWED=1 GTEST_EXTRA="assets/models assets/icons" tools/gtest.sh items-demo res://tests/scenes/items_ground_demo.tscn
## Screenshots: docs/screenshots/items/items_ground_*.png. OWNER: items.

const TooltipDump := preload("res://tests/scenes/items_tooltip_dump.gd")
const CAM_PITCH := 56.0
const CAM_DISTANCE := 18.0

var cam: Camera3D
var _failures: Array[String] = []
var _shot_dir := ""


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	seed(12345)
	_build_scene()
	LootSystem.fallback_parent = self
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		_shot_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/items/"
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.33, 0.4)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -35, 0)
	sun.light_energy = 0.7
	sun.light_color = Color(0.8, 0.82, 1.0)
	sun.shadow_enabled = true
	add_child(sun)
	var torch := OmniLight3D.new()
	torch.position = Vector3(0, 3.5, 1.5)
	torch.omni_range = 14.0
	torch.light_energy = 1.6
	torch.light_color = Color(1.0, 0.75, 0.45)
	add_child(torch)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.2, 0.19)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	add_child(floor_mi)
	# Tile seams so the scale reads (2 m grid like the dungeon).
	for i in range(-7, 8):
		for axis in 2:
			var seam := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.01, 30) if axis == 0 else Vector3(30, 0.01, 0.04)
			seam.mesh = bm
			seam.position = Vector3(i * 2.0, 0.005, 0) if axis == 0 else Vector3(0, 0.005, i * 2.0)
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.12, 0.11, 0.1)
			seam.material_override = sm
			add_child(seam)
	cam = Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	_place_camera(Vector3(0, 0, 0), CAM_DISTANCE)


func _place_camera(target: Vector3, dist: float) -> void:
	var pitch := deg_to_rad(CAM_PITCH)
	cam.position = target + Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.rotation = Vector3(-pitch, 0, 0)


func _spawn_at(item: Item, pos: Vector3, gold: int = 0) -> GroundItem:
	var gi := GroundItem.new()
	if item != null:
		gi.setup_item(item)
	else:
		gi.setup_gold(gold)
	gi.position = pos
	gi.pop_from(pos + Vector3(0, 1.0, 0))
	add_child(gi)
	return gi


func _run() -> void:
	var layout: Array = [
		[ItemDB.create_item("sword_3"), Vector3(-6, 0, -3)],
		[ItemDB.create_item("body_str_2"), Vector3(-3.5, 0, -3)],
		[ItemDB.create_item("helmet_dex_2"), Vector3(-1, 0, -3)],
		[ItemDB.create_item("greataxe_4", Item.Rarity.MAGIC, 30), Vector3(1.5, 0, -3)],
		[ItemDB.create_item("boots_int_2", Item.Rarity.MAGIC, 12), Vector3(4, 0, -3)],
		[ItemDB.create_item("bow_3", Item.Rarity.MAGIC, 20), Vector3(6.5, 0, -3)],
		[ItemDB.create_item("shield_str_3", Item.Rarity.RARE, 24), Vector3(-6, 0, 0)],
		[ItemDB.create_item("ring_2", Item.Rarity.RARE, 20), Vector3(-3.5, 0, 0)],
		[ItemDB.create_item("gloves_str_dex_3", Item.Rarity.RARE, 24), Vector3(-1, 0, 0)],
		[ItemDB.create_unique("gorebinder"), Vector3(1.5, 0, 0)],
		[ItemDB.create_unique("stormcrown"), Vector3(4, 0, 0)],
		[ItemDB.create_item("quiver_2", Item.Rarity.NORMAL, 10), Vector3(6.5, 0, 0)],
		[ItemDB.create_item("amulet_3", Item.Rarity.MAGIC, 18), Vector3(-6, 0, 3)],
		[ItemDB.create_item("focus_2"), Vector3(-3.5, 0, 3)],
		[ItemDB.create_item("belt_2", Item.Rarity.NORMAL, 8), Vector3(-1, 0, 3)],
		[ItemDB.create_item("staff_2", Item.Rarity.RARE, 12), Vector3(1.5, 0, 3)],
	]
	var spawned: Array[GroundItem] = []
	for entry: Array in layout:
		spawned.append(_spawn_at(entry[0], entry[1]))
	# A few tooltips as text (wording check); the equipped comparison uses the normal sword.
	for i in [3, 9, 12]:
		TooltipDump.print_item(layout[i][0], {"strength": 40, "dexterity": 30, "intelligence": 20, "level": 22}, layout[0][0] if (layout[i][0] as Item).is_weapon() else null)
	spawned.append(_spawn_at(null, Vector3(4, 0, 3), 154))
	spawned.append(_spawn_at(null, Vector3(6.5, 0, 3), 23))
	await _wait(1.0)
	# ---- rules: normal labels hidden, magic+ and gold shown
	for gi in spawned:
		var always: bool = gi.item == null or gi.item.rarity >= Item.Rarity.MAGIC
		_check(gi.is_landed(), "%s landed" % gi.get_hover_name())
		_check(gi.is_label_visible() == always, "%s label visible=%s" % [gi.get_hover_name(), always])
	await _shot("items_ground_overview.png")
	# ---- pick rays: model and label of a rare, model of a normal item
	await get_tree().physics_frame
	_check_pick(spawned[6], false)
	_check_pick(spawned[6], true)
	_check_pick(spawned[0], false)
	# ---- hover a normal item: label appears, clicking its label then works
	spawned[1].set_hovered(true)
	await _wait(0.1)
	_check(spawned[1].is_label_visible(), "hovered normal item shows its label")
	await get_tree().physics_frame
	_check_pick(spawned[1], true)
	await _shot("items_ground_hover.png")
	spawned[1].set_hovered(false)
	# ---- Alt shows every label
	Input.action_press("highlight_items")
	await _wait(0.1)
	for gi in spawned:
		_check(gi.is_label_visible(), "%s label visible while Alt held" % gi.get_hover_name())
	await _shot("items_ground_alt.png")
	Input.action_release("highlight_items")
	await _wait(0.1)
	_check(not spawned[0].is_label_visible(), "normal label hidden again after Alt")
	# ---- close-up
	_place_camera(Vector3(-1, 0, 0), 8.0)
	await _shot("items_ground_closeup.png")
	# ---- boss drop scatter around a point
	for gi in spawned:
		gi.queue_free()
	_place_camera(Vector3(0, 0, 0), CAM_DISTANCE)
	var drops := LootSystem.roll_monster_drops(30, 3, 50.0, 0.0, 0.0)
	LootSystem.spawn_drops(drops, Vector3(0, 0, 0))
	var chest := LootSystem.roll_chest_drops(30, 2)
	LootSystem.spawn_drops(chest, Vector3(-6, 0, 2))
	await _wait(0.2)
	await _shot("items_ground_popping.png")
	await _wait(1.0)
	var loot := get_tree().get_nodes_in_group("loot")
	_check(loot.size() == drops.size() + chest.size(), "boss + chest drops spawned (%d loot nodes)" % loot.size())
	var positions: Array[Vector3] = []
	for n in loot:
		positions.append((n as Node3D).global_position)
	var min_gap := 99.0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			min_gap = minf(min_gap, positions[i].distance_to(positions[j]))
	print("[items_demo] %d loot nodes, min spacing %.2f m" % [loot.size(), min_gap])
	await _shot("items_ground_bossdrop.png")
	Input.action_press("highlight_items")
	await _wait(0.1)
	await _shot("items_ground_bossdrop_alt.png")
	Input.action_release("highlight_items")
	if _failures.is_empty():
		print("[items_demo] ALL CHECKS PASSED")
	else:
		for f in _failures:
			print("[items_demo] FAIL: ", f)
	get_tree().quit(_failures.size())


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


## Cast the hover ray (mask loot, areas) through the screen position of the item's model or label.
func _check_pick(gi: GroundItem, label: bool) -> void:
	var target: Vector3
	if label:
		target = gi.get_label_position()
	else:
		target = gi.global_position + Vector3(0, 0.1, 0)
	var screen := cam.unproject_position(target)
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 4 | 8 | 16)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ok: bool = not hit.is_empty() and hit["collider"] == gi
	print("[items_demo] pick %s of %s -> %s" % ["label" if label else "model", gi.get_hover_name(), "OK" if ok else "MISS %s" % [hit.get("collider")]])
	_check(ok, "pick ray hits %s of %s" % ["label" if label else "model", gi.get_hover_name()])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(file: String) -> void:
	if _shot_dir == "":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + file)
	print("[items_demo] saved ", _shot_dir + file)
