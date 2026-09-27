class_name WorldActWaystone
extends WorldWaypointGate
## The waystone of an act hub: opens the Act Explorer panel (Events.panel_open_requested("acts",
## {"act": act})) to travel between acts and zones. Looks like the Dungeon Gate unless the act
## gives it its own model (an obelisk, a rune stone...). OWNER: acts framework.

var act := ""
var model_id := ""


func _init() -> void:
	super._init()
	display_name = "Waystone"


## act: the act this hub belongs to; p_model: a prop id for its look ("" = env_waypoint).
func setup(p_act: String, p_model: String = "") -> WorldActWaystone:
	act = p_act
	model_id = p_model
	if ActDefs.has_act(act):
		highlight_color = ActDefs.accent(act)
	return self


func get_hover_color() -> Color:
	return ActDefs.accent(act).lerp(Color.WHITE, 0.3) if ActDefs.has_act(act) else super.get_hover_color()


func get_interact_position() -> Vector3:
	if model_id == "":
		return super.get_interact_position()
	var box := WorldInteractable.model_aabb(model) if model != null else AABB()
	return global_position + global_transform.basis.z * maxf(box.size.z * 0.5 + 1.4, 2.0)


func _build() -> void:
	if model_id == "" or not Assets.has_model(model_id):
		super._build()
		return
	model = Assets.model(model_id)
	model.name = "Model"
	add_child(model)
	var box := WorldInteractable.model_aabb(model)
	label_height = box.end.y + 0.5
	var glow := ActDefs.accent(act) if ActDefs.has_act(act) else Color(0.4, 0.75, 1.0)
	add_light(glow, 1.4, 7.0, Vector3(0, minf(box.size.y * 0.5, 2.5), maxf(box.size.z * 0.5, 0.6) + 0.6))
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 1.2), maxf(box.size.y, 2.0), maxf(box.size.z, 1.0))
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))


func interact(_player: Node) -> void:
	if not enabled:
		return
	Events.panel_open_requested.emit("acts", {"act": act})
