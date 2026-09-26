extends Node
## Prints the AABB (model space) and material names of every environment / town model the World
## uses, so placement assumptions (§14.1 origins and sizes) can be checked against real assets.
##   GTEST_EXTRA="assets/models" tools/gtest.sh world-probe res://tests/scenes/world_asset_probe.tscn

const IDS := ["env_floor_a", "env_floor_b", "env_floor_c", "env_wall_a", "env_wall_b", "env_pillar",
	"env_torch", "env_brazier", "env_crate", "env_barrel", "env_bones", "env_rubble", "env_rock_a",
	"env_rock_b", "env_crystal", "env_chest", "env_portal", "env_waypoint", "town_house_a",
	"town_house_b", "town_house_c", "town_well", "town_tree_a", "town_tree_b", "town_fence",
	"town_lamp", "town_stall", "town_stash", "town_cart", "town_bush", "town_rock", "char_merchant"]


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	var kit := WorldKit.new({})
	for id in IDS:
		var real := Assets.has_model(id)
		var box := kit.model_aabb(id)
		var mats: Array = []
		var parts := kit.parts(id)
		for p in parts:
			for m in p["mats"]:
				if m != null:
					mats.append((m as Material).resource_name)
		var inst := Assets.model(id)
		var lid := inst.find_child("Lid", true, false)
		var extra := ""
		if lid != null:
			extra = " Lid@%s" % [(lid as Node3D).position]
		inst.free()
		print("%-14s %s parts=%d pos=%s size=%s%s mats=%s" % [id, "REAL" if real else "fallback", parts.size(),
			_v(box.position), _v(box.size), extra, mats])
	get_tree().quit()


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
