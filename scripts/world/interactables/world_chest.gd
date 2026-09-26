class_name WorldChest
extends WorldInteractable
## A dungeon loot chest (env_chest with a hinged "Lid"). Clicking opens the lid
## (lid.rotation.x = -deg_to_rad(110); a missing Lid is tolerated), then drops
## LootSystem.roll_chest_drops(area_level, tier) in front of it. Opened chests are no longer
## hoverable and drop off the minimap. Tier 0 = chest, 1 = ornate chest (bigger, gilded).
## OWNER: world.

const LID_OPEN_ANGLE := 110.0

var tier := 0
var area_level := 1
var opened := false
var lid: Node3D = null
var _drop_timer := -1.0


func _init() -> void:
	super._init()
	marker_kind = "chest"
	label_height = 1.5
	display_name = "Chest"


func setup(p_tier: int, p_area_level: int) -> WorldChest:
	tier = clampi(p_tier, 0, 2)
	area_level = maxi(p_area_level, 1)
	display_name = ["Chest", "Ornate Chest", "Treasure Hoard"][tier]
	return self


func get_hover_color() -> Color:
	if tier >= 1:
		return UIStyle.rarity_color(2 if tier == 1 else 3)
	return UIStyle.COLOR_TEXT


func get_minimap_kind() -> String:
	return "" if opened else marker_kind


func get_interact_range() -> float:
	return 2.2


func _build() -> void:
	model = Assets.model("env_chest")
	model.name = "Model"
	if WorldInteractable.is_placeholder(model):
		model.free()
		model = fallback_chest_model(Color(0.5, 0.32, 0.16), Color(0.55, 0.5, 0.35), 1.0)
	add_child(model)
	if tier >= 1:
		model.scale = Vector3.ONE * (1.15 if tier == 1 else 1.3)
		Assets.tint(model, Color(1.15, 0.95, 0.6))
	lid = model.find_child("Lid", true, false) as Node3D
	var box := WorldInteractable.model_aabb(model)
	box = Transform3D(Basis.from_scale(model.scale), Vector3.ZERO) * box
	if box.size.y > 0.2:
		label_height = box.end.y + 0.6
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 1.0), maxf(box.size.y, 0.8), maxf(box.size.z, 0.8))
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))


## Code-built chest (placeholder until env_chest exists): base + a "Lid" hinged at the back.
static func fallback_chest_model(wood: Color, metal: Color, s: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var wood_mat := WorldInteractable.stone_material(wood)
	var metal_mat := WorldInteractable.stone_material(metal)
	metal_mat.metallic = 0.6
	metal_mat.roughness = 0.45
	var base := BoxMesh.new()
	base.size = Vector3(1.0, 0.55, 0.62) * s
	root.add_child(WorldInteractable.mesh_node(base, wood_mat, Vector3(0, 0.275, 0) * s))
	var band := BoxMesh.new()
	band.size = Vector3(1.04, 0.08, 0.66) * s
	root.add_child(WorldInteractable.mesh_node(band, metal_mat, Vector3(0, 0.45, 0) * s))
	var lid_pivot := Node3D.new()
	lid_pivot.name = "Lid"
	lid_pivot.position = Vector3(0, 0.55, -0.31) * s
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.0, 0.22, 0.62) * s
	lid_pivot.add_child(WorldInteractable.mesh_node(lid_mesh, wood_mat, Vector3(0, 0.11, 0.31) * s))
	var lock := BoxMesh.new()
	lock.size = Vector3(0.14, 0.16, 0.05) * s
	lid_pivot.add_child(WorldInteractable.mesh_node(lock, metal_mat, Vector3(0, 0.02, 0.63) * s))
	root.add_child(lid_pivot)
	return root


func interact(_player: Node) -> void:
	if opened or not enabled:
		return
	opened = true
	disable_interaction()
	Sfx.play("chest_open", global_position)
	if lid != null:
		var tw := create_tween()
		tw.tween_property(lid, "rotation:x", -deg_to_rad(LID_OPEN_ANGLE), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Drops come out once the lid is up (counted in physics frames: never a SceneTree timer).
	_drop_timer = 0.3


func _physics_process(delta: float) -> void:
	if _drop_timer < 0.0:
		return
	_drop_timer -= delta
	if _drop_timer < 0.0:
		_spawn_drops()


func _spawn_drops() -> void:
	var drops := LootSystem.roll_chest_drops(area_level, tier)
	var front := global_position + global_transform.basis.z.normalized() * 1.1
	var w := get_parent()
	while w != null and not (w is World):
		w = w.get_parent()
	if w is World:
		front = (w as World).get_nearest_walkable(front)
	LootSystem.spawn_drops(drops, front)
