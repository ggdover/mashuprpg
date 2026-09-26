class_name TestDummy
extends Actor
## A configurable Actor for tests and demos: a capsule body with base life and optional extra mods.
## OWNER: orchestrator.
##
##   var d := TestDummy.new(); d.team = Actor.Team.ENEMY; d.base_life = 500; add_child(d)

var base_life: float = 1000.0
var base_mana: float = 100.0
## Extra mods added to the base (e.g. resistances, armour).
var extra_mods: Array = []
## Optional weapon override for attack tests (DamageCalc weapon dict).
var weapon_override: Dictionary = {}


func _init() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)


func _ready() -> void:
	collision_layer = 1 << 1 if team == Team.PLAYER else 1 << 2
	collision_mask = 1
	super._ready()
	recalculate_stats()
	life = max_life
	mana = max_mana
	es = max_es


func get_base_mods() -> Array:
	var mods: Array = [
		StatBlock.mod("max_life", "flat", base_life),
		StatBlock.mod("max_mana", "flat", base_mana),
	]
	mods.append_array(extra_mods)
	return mods


func get_weapon() -> Dictionary:
	if not weapon_override.is_empty():
		return weapon_override
	return super.get_weapon()
