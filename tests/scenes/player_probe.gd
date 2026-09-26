extends Node
## Prints the char_player model structure (parts, bones, animations) for the player module.
## tools/gtest.sh player res://tests/scenes/player_probe.tscn

func _ready() -> void:
	var m := Assets.model("char_player")
	add_child(m)
	_dump(m, 0)
	var ap := Assets.prepare_animations(m)
	if ap:
		for a in ap.get_animation_list():
			var an := ap.get_animation(a)
			print("anim %s len=%.3f loop=%d tracks=%d" % [a, an.length, an.loop_mode, an.get_track_count()])
	var sk := Assets.find_skeleton(m)
	if sk:
		for i in sk.get_bone_count():
			print("bone %d %s parent=%d rest=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), sk.get_bone_global_rest(i).origin])
	for id in ["weapon_sword", "offhand_shield", "armor_helmet_str"]:
		var w := Assets.model(id)
		add_child(w)
		_dump(w, 0)
	get_tree().quit()


func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var mats := []
		for i in mi.mesh.get_surface_count():
			var mm := mi.mesh.surface_get_material(i)
			mats.append(mm.resource_name if mm else "null")
		extra = " mats=%s aabb=%s" % [mats, mi.get_aabb()]
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
