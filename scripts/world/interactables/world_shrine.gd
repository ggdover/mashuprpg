class_name WorldShrine
extends WorldInteractable
## A dungeon shrine: a pedestal with a floating crystal. Touching it grants a 30 s buff
## (Actor.add_buff) and it goes dark. Kinds: fury (damage), swiftness (speed), fortitude
## (armour + regen), arcana (spell damage + mana regen). OWNER: world.

const DURATION := 30.0
const KINDS := {
	"fury": {"name": "Shrine of Fury", "color": Color(1.0, 0.35, 0.2), "icon": "war_cry",
		"text": "+40% increased Damage",
		"mods": [["damage", "inc", 40.0]]},
	"swiftness": {"name": "Shrine of Swiftness", "color": Color(0.4, 1.0, 0.55), "icon": "teleport",
		"text": "+25% Movement Speed, +15% Attack and Cast Speed",
		"mods": [["movement_speed", "inc", 25.0], ["attack_speed", "inc", 15.0], ["cast_speed", "inc", 15.0]]},
	"fortitude": {"name": "Shrine of Fortitude", "color": Color(1.0, 0.8, 0.35), "icon": "heavy_strike",
		"text": "+60% increased Armour, regenerate 2% Life per second",
		"mods": [["armour", "inc", 60.0], ["life_regen_percent", "flat", 2.0]]},
	"arcana": {"name": "Shrine of Arcana", "color": Color(0.55, 0.5, 1.0), "icon": "fireball",
		"text": "+40% increased Spell Damage, +100% Mana Regeneration",
		"mods": [["spell_damage", "inc", 40.0], ["mana_regen", "inc", 100.0]]},
}

var kind := "fury"
var used := false
var crystal: Node3D = null
var glow_material: StandardMaterial3D = null
var _time := 0.0


func _init() -> void:
	super._init()
	label_height = 2.6


func setup(p_kind: String) -> WorldShrine:
	kind = p_kind if KINDS.has(p_kind) else "fury"
	display_name = KINDS[kind]["name"]
	return self


func get_hover_color() -> Color:
	return (KINDS[kind]["color"] as Color).lerp(Color.WHITE, 0.35)


## The buff this shrine grants (Actor.add_buff data).
func get_buff_data() -> Dictionary:
	var def: Dictionary = KINDS[kind]
	var mods: Array = []
	for m in def["mods"]:
		mods.append(StatBlock.mod(m[0], m[1], m[2]))
	return {"name": def["name"], "mods": mods, "duration": DURATION, "icon": def["icon"]}


func _build() -> void:
	if display_name == "":
		setup(kind)
	var col: Color = KINDS[kind]["color"]
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var stone := WorldInteractable.stone_material(Color(0.42, 0.4, 0.42))
	var base := CylinderMesh.new()
	base.top_radius = 0.45
	base.bottom_radius = 0.6
	base.height = 0.9
	base.radial_segments = 8
	model.add_child(WorldInteractable.mesh_node(base, stone, Vector3(0, 0.45, 0)))
	var top := CylinderMesh.new()
	top.top_radius = 0.55
	top.bottom_radius = 0.5
	top.height = 0.15
	top.radial_segments = 8
	model.add_child(WorldInteractable.mesh_node(top, stone, Vector3(0, 0.97, 0)))
	glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = col
	glow_material.emission_enabled = true
	glow_material.emission = col
	glow_material.emission_energy_multiplier = 3.0
	crystal = Node3D.new()
	crystal.name = "Crystal"
	crystal.position = Vector3(0, 1.55, 0)
	var gem := PrismMesh.new()
	gem.size = Vector3(0.35, 0.5, 0.35)
	var up := WorldInteractable.mesh_node(gem, glow_material, Vector3(0, 0.25, 0))
	var down := WorldInteractable.mesh_node(gem, glow_material, Vector3(0, -0.25, 0), Vector3(PI, 0, 0))
	crystal.add_child(up)
	crystal.add_child(down)
	model.add_child(crystal)
	add_light(col, 1.8, 7.0, Vector3(0, 1.6, 0))
	var shape := CylinderShape3D.new()
	shape.radius = 0.7
	shape.height = 2.2
	add_pick_shape(shape, Vector3(0, 1.1, 0))


func _process(delta: float) -> void:
	_time += delta
	if crystal != null and not used:
		crystal.rotation.y += delta * 1.2
		crystal.position.y = 1.55 + sin(_time * 1.8) * 0.08


func interact(player: Node) -> void:
	if used or not enabled:
		return
	used = true
	disable_interaction()
	if is_instance_valid(player) and player.has_method("add_buff"):
		player.call("add_buff", "shrine_" + kind, get_buff_data())
	Events.notify.emit("%s: %s" % [KINDS[kind]["name"], KINDS[kind]["text"]], KINDS[kind]["color"])
	Sfx.play("potion", global_position)
	if glow_material != null:
		glow_material.emission_energy_multiplier = 0.15
		glow_material.albedo_color = Color(0.25, 0.25, 0.28)
	if light != null:
		var tw := create_tween()
		tw.tween_property(light, "light_energy", 0.0, 0.8)
	if crystal != null:
		crystal.position.y = 1.2
