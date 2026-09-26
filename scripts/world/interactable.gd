class_name Interactable
extends Area3D
## Base for everything the player can hover with the mouse and click: ground loot (GroundItem),
## portals, the waypoint gate, NPCs, chests, the stash. OWNER: orchestrator.
##
## The player's CameraRig ray-casts the mouse against collision layers 4 (loot) and 5
## (interactables) with collide_with_areas = true. On click, the Player walks until it is within
## get_interact_range() of get_interact_position(), then calls interact(player).
## Every Interactable is in group "interactable".

const LAYER_LOOT := 1 << 3           # physics layer 4
const LAYER_INTERACTABLE := 1 << 4   # physics layer 5

@export var display_name: String = ""
## Disabled interactables are not hoverable or clickable (e.g. an opened chest).
var enabled: bool = true
var hovered: bool = false


func _init() -> void:
	collision_layer = LAYER_INTERACTABLE
	collision_mask = 0
	monitoring = false
	monitorable = true
	input_ray_pickable = true
	add_to_group("interactable")


## Convenience: add a pick shape (what the mouse ray hits).
func add_pick_shape(shape: Shape3D, offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	add_child(cs)
	return cs


func get_hover_name() -> String:
	return display_name


func get_hover_color() -> Color:
	return UIStyle.COLOR_TEXT


func set_hovered(on: bool) -> void:
	if hovered == on:
		return
	hovered = on
	_on_hover_changed(on)


## Override to highlight (outline, emission, label colour).
func _on_hover_changed(_on: bool) -> void:
	pass


func get_interact_position() -> Vector3:
	return global_position


func get_interact_range() -> float:
	return 2.5


func can_interact(_player: Node) -> bool:
	return enabled


## Override. Called by the Player once in range.
func interact(_player: Node) -> void:
	pass
