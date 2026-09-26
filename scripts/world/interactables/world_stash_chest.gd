class_name WorldStashChest
extends WorldInteractable
## The town Stash (town_stash, an iron-bound chest). Clicking opens the stash panel:
## Events.panel_open_requested("stash", {}). The lid (if the model has a "Lid") opens and closes
## again once the player walks away. OWNER: world.

## Lid angle when open (§13: lid.rotation.x = -deg_to_rad(110)).
const LID_OPEN := -deg_to_rad(110.0)

var lid: Node3D = null
var _open := false
var _open_time := 0.0


func _init() -> void:
	super._init()
	display_name = "Stash"
	marker_kind = "stash"
	label_height = 1.7
	highlight_color = Color(1.0, 0.85, 0.55)


func get_hover_color() -> Color:
	return UIStyle.COLOR_TITLE


func _build() -> void:
	model = Assets.model("town_stash")
	model.name = "Model"
	if WorldInteractable.is_placeholder(model):
		model.free()
		model = WorldChest.fallback_chest_model(Color(0.36, 0.24, 0.14), Color(0.35, 0.36, 0.4), 1.25)
	add_child(model)
	lid = model.find_child("Lid", true, false) as Node3D
	var box := WorldInteractable.model_aabb(model)
	if box.size.y > 0.3:
		label_height = box.end.y + 0.7
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 1.2), maxf(box.size.y, 1.0), maxf(box.size.z, 0.9))
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))


func _set_open(on: bool) -> void:
	if _open == on:
		return
	_open = on
	_open_time = 0.0
	if lid != null:
		var tw := create_tween()
		tw.tween_property(lid, "rotation:x", LID_OPEN if on else 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("chest_open", global_position)


func _physics_process(delta: float) -> void:
	if _open:
		_open_time += delta
		var p := GameState.player
		var gone := _open_time > 1.5 if not is_instance_valid(p) else (p as Node3D).global_position.distance_to(global_position) > 5.0
		if gone:
			_set_open(false)


func interact(_player: Node) -> void:
	if not enabled:
		return
	_set_open(true)
	Events.panel_open_requested.emit("stash", {})
