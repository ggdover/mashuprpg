class_name WorldDungeonEntrance
extends WorldInteractable
## The entrance of an act's dungeon (a tomb, a barrow, a crypt door...): a solid prop model the
## player clicks to go down (screen fade): Events.area_change_requested("act_dungeon", {"act"}).
## The dungeon's name comes from ActDefs; the player comes back out in front of it. OWNER: acts.

var act := ""
var model_id := ""
var size := Vector2(4, 4)
## The World's geometry kit (set before the entrance enters the tree): the model is then drawn with
## the world's cut-out materials, dithered away between the camera and the player like the act's
## tall props, so the player stays visible behind it.
var kit: WorldKit = null
var _time := 0.0
var _glow: OmniLight3D = null


func _init() -> void:
	super._init()
	marker_kind = "waypoint"
	label_height = 3.4
	highlight_color = Color(1.0, 0.75, 0.4)


func setup(p_act: String, p_model: String, p_size: Vector2 = Vector2(4, 4)) -> WorldDungeonEntrance:
	act = p_act
	model_id = p_model
	size = p_size
	var de: Dictionary = ActDefs.get_act(act).get("dungeon", {})
	display_name = "Enter %s" % String(de.get("name", "the Dungeon"))
	return self


func get_hover_color() -> Color:
	return Color(1.0, 0.78, 0.45)


func get_interact_range() -> float:
	return maxf(size.x, size.y) * 0.5 + 1.8


## A walkable spot in front of the entrance.
func get_interact_position() -> Vector3:
	return global_position + global_transform.basis.z * (size.y * 0.5 + 1.6)


func _build() -> void:
	if model_id != "" and Assets.has_model(model_id) and kit != null:
		model = _cutout_model()
	elif model_id != "" and Assets.has_model(model_id):
		model = Assets.model(model_id)
	else:
		model = Assets.model("env_waypoint")
	model.name = "Model"
	add_child(model)
	var box := WorldInteractable.model_aabb(model)
	if box.size.y > 0.5:
		label_height = box.end.y + 0.5
	# A faint warm light at the doorway draws the eye.
	_glow = add_light(Color(1.0, 0.62, 0.3), 1.2, 6.0, Vector3(0, 1.2, size.y * 0.5 + 0.8))
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 1.5), maxf(box.size.y, 2.0), maxf(box.size.z, 1.5))
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))


## The model as plain MeshInstance3Ds with the kit's cut-out world materials.
func _cutout_model() -> Node3D:
	var root := Node3D.new()
	var parts := kit.parts(model_id)
	for i in parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = kit.prepared_mesh(model_id, i, Color.WHITE, true, false)
		mi.transform = parts[i]["xform"]
		root.add_child(mi)
	return root


func _process(delta: float) -> void:
	_time += delta
	if _glow != null and is_instance_valid(_glow):
		_glow.light_energy = 1.1 + 0.25 * sin(_time * 2.1)


func interact(_player: Node) -> void:
	if not enabled:
		return
	Sfx.play("portal", global_position)
	Events.area_change_requested.emit("act_dungeon", {"act": act})
