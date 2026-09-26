class_name WorldWaypointGate
extends WorldInteractable
## The Dungeon Gate in town (env_waypoint): opens the waypoint panel with
## Events.panel_open_requested("waypoint", {"max_depth": character.max_depth}). Its runes pulse
## (a glowing ground circle + light). OWNER: world.

var rune_material: StandardMaterial3D = null
var _time := 0.0


func _init() -> void:
	super._init()
	display_name = "Dungeon Gate"
	marker_kind = "waypoint"
	label_height = 4.4
	highlight_color = Color(0.6, 0.85, 1.0)


func get_hover_color() -> Color:
	return Color(0.62, 0.86, 1.0)


func get_interact_range() -> float:
	return 3.0


## A walkable spot in front of the gate (the gate itself stands on solid cells).
func get_interact_position() -> Vector3:
	return global_position + global_transform.basis.z * 3.0


func _build() -> void:
	model = Assets.model("env_waypoint")
	model.name = "Model"
	var width := 3.6
	var height := 4.0
	var depth := 1.6
	if WorldInteractable.is_placeholder(model):
		model.free()
		model = _fallback_model()
	else:
		var box := WorldInteractable.model_aabb(model)
		if box.size.x > 0.5:
			width = box.size.x
			height = box.size.y
			depth = maxf(box.size.z, 1.0)
			label_height = box.end.y + 0.5
	add_child(model)
	add_light(Color(0.4, 0.75, 1.0), 1.6, 7.0, Vector3(0, 2.0, 1.4))
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(width, 2.0), maxf(height, 2.5), depth)
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))
	if model.has_meta("fallback"):
		_add_rune_circle()


## Glowing rune circle in front of the code-built fallback gate (the real model has its own).
func _add_rune_circle() -> void:
	rune_material = StandardMaterial3D.new()
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.albedo_color = Color(0.35, 0.75, 1.0)
	rune_material.emission_enabled = false
	var ring := TorusMesh.new()
	ring.inner_radius = 1.05
	ring.outer_radius = 1.2
	ring.rings = 32
	ring.ring_segments = 4
	var rune := WorldInteractable.mesh_node(ring, rune_material, Vector3(0, 0.03, 1.9))
	rune.scale = Vector3(1, 0.05, 1)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rune.name = "Runes"
	add_child(rune)


func _fallback_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.set_meta("fallback", true)
	var stone := WorldInteractable.stone_material(Color(0.45, 0.45, 0.5))
	var glow := WorldInteractable.stone_material(Color(0.2, 0.4, 0.6), Color(0.35, 0.75, 1.0), 2.5)
	var post := BoxMesh.new()
	post.size = Vector3(0.7, 3.4, 0.7)
	root.add_child(WorldInteractable.mesh_node(post, stone, Vector3(-1.45, 1.7, 0)))
	root.add_child(WorldInteractable.mesh_node(post, stone, Vector3(1.45, 1.7, 0)))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(3.9, 0.6, 0.85)
	root.add_child(WorldInteractable.mesh_node(lintel, stone, Vector3(0, 3.7, 0)))
	var rune := BoxMesh.new()
	rune.size = Vector3(0.18, 1.6, 0.05)
	root.add_child(WorldInteractable.mesh_node(rune, glow, Vector3(-1.45, 1.8, 0.36)))
	root.add_child(WorldInteractable.mesh_node(rune, glow, Vector3(1.45, 1.8, 0.36)))
	var gate_glow := QuadMesh.new()
	gate_glow.size = Vector2(2.2, 3.0)
	var veil := StandardMaterial3D.new()
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	veil.albedo_color = Color(0.15, 0.3, 0.5, 0.6)
	root.add_child(WorldInteractable.mesh_node(gate_glow, veil, Vector3(0, 1.7, 0)))
	return root


func _process(delta: float) -> void:
	_time += delta
	var k := 0.75 + 0.25 * sin(_time * 2.0)
	if rune_material != null:
		var c := Color(0.35, 0.75, 1.0) * (1.4 * k + (0.8 if hovered else 0.0))
		rune_material.albedo_color = Color(c.r, c.g, c.b, 1.0)
	if light != null:
		light.light_energy = 1.3 + 0.5 * k + (0.6 if hovered else 0.0)


func interact(_player: Node) -> void:
	if not enabled:
		return
	var max_depth := 1
	if GameState.character != null:
		max_depth = GameState.character.max_depth
	Events.panel_open_requested.emit("waypoint", {"max_depth": max_depth})
