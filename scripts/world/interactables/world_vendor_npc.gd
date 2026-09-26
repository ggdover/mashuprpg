class_name WorldVendorNpc
extends WorldInteractable
## The town Merchant (char_merchant, idle animation; "talk" on interaction if the model has
## it). Clicking opens the vendor panel: Events.panel_open_requested("vendor", {}). Turns to face
## the player while talking and back to its post when the player walks away. OWNER: world.

## Model id (a rigged character with an "idle" animation; "talk" optional).
var model_id := "char_merchant"
var anim: AnimationPlayer = null
## Facing (rotation.y) at its post.
var home_yaw := 0.0
var _talking := false
var _talk_time := 0.0
var _target_yaw := 0.0


func _init() -> void:
	super._init()
	display_name = "Merchant"
	marker_kind = "vendor"
	label_height = 2.35
	highlight_color = Color(1.0, 0.85, 0.5)


func get_hover_color() -> Color:
	return UIStyle.COLOR_GOLD


func get_interact_range() -> float:
	return 2.8


func _build() -> void:
	home_yaw = rotation.y
	_target_yaw = home_yaw
	model = Assets.model(model_id)
	model.name = "Model"
	add_child(model)
	anim = Assets.prepare_animations(model)
	_play("idle")
	var box := WorldInteractable.model_aabb(model)
	if box.size.y > 1.0:
		label_height = box.end.y + 0.45
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 2.0
	add_pick_shape(shape, Vector3(0, 1.0, 0))


func _play(anim_name: String) -> void:
	if anim != null and anim.has_animation(anim_name):
		anim.play(anim_name, 0.2)


func _physics_process(delta: float) -> void:
	if _talking:
		_talk_time += delta
		var p := GameState.player
		var gone := _talk_time > 1.5 if not is_instance_valid(p) else (p as Node3D).global_position.distance_to(global_position) > 6.0
		if gone:
			_talking = false
			_target_yaw = home_yaw
	rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 6.0, 0.0, 1.0))
	if anim != null and not anim.is_playing():
		_play("idle")


func interact(player: Node) -> void:
	if not enabled:
		return
	if player is Node3D and is_instance_valid(player):
		var d := (player as Node3D).global_position - global_position
		if Vector2(d.x, d.z).length() > 0.1:
			_target_yaw = atan2(d.x, d.z)
	_talking = true
	_talk_time = 0.0
	if anim != null and anim.has_animation("talk"):
		anim.play("talk", 0.15)
		anim.queue("idle")
	Events.panel_open_requested.emit("vendor", {})
