extends Node
## Validation probe for the assets-characters module (docs/ARCHITECTURE.md §14.5).
## Loads every character / item model and icon and asserts the import contract:
##   * characters: exactly one Skeleton3D and one AnimationPlayer, every §14.3 animation present
##     (exact names, no "_001"), all §14.2 bones, rough AABB height / feet on y = 0, grip_r / grip_l /
##     head / chest attachment axes, animation lengths; the player models (char_player_f / _m1 / _m2 and
##     the char_player alias) also have the player animations, the base parts (Head, HairTop, Body,
##     Hands, Outfit_*) and every gear piece of data/player_gear.json with a tint* material;
##   * items: loads, has a tint* material, rough AABB size and origin conventions;
##   * icons: assets/icons/items/<id>.png exists, 128x128;
##   * motion (CPU skinning of the posed rig, sampled at 60 Hz like the review did):
##       - run: planted-foot speed of every walking character = RUN_REF_SPEED +- RUN_SPEED_TOL, so
##         consumers use speed_scale = move_speed / 5.2 for all of them (ankle within 2 cm of its
##         lowest height over the cycle, mean backward speed);
##       - feet on the floor: lowest foot vertex within +-2 cm of y = 0 in every animation except
##         die / dodge (the lich hovers: skipped);
##       - corpses (die end): torso/head on or above the floor, nothing below it, built-in weapons
##         lying flat (the lich's staff, the gravebreaker's maul);
##       - attack_slam hit frame: char_gravebreaker's maul head, and a weapon_maul held by char_player,
##         rest on the floor;
##   * draw calls: monsters and the merchant are ONE skinned mesh "Body" (+ "Weapon" on bosses) with
##     one surface per material.
## Run: tools/gtest.sh assets-characters res://tools/godot/probe_characters.tscn
## Prints a report; every failed assertion is a push_error (so gtest counts it) and the exit code
## is the number of failures.

const PlayerGear := preload("res://scripts/entities/player/player_gear.gd")

const MODEL_DIR := "res://assets/models/"
const ICON_DIR := "res://assets/icons/items/"

const HUMANOID_ANIMS: Array[String] = ["idle", "run", "attack_slash", "attack_slam", "attack_stab",
	"shoot_bow", "shoot_crossbow", "cast", "cast_area", "channel", "hit", "die", "dodge"]
const ANIM_LENGTH := {"idle": 2.0, "run": 0.6, "attack_slash": 0.6, "attack_slam": 0.8, "attack_stab": 0.5,
	"shoot_bow": 0.7, "shoot_crossbow": 0.6, "cast": 0.6, "cast_area": 0.7, "channel": 1.0, "hit": 0.3,
	"die": 1.0, "dodge": 0.4, "roar": 1.2, "parry": 0.55, "parry_hold": 1.0}
## Player models: lengths that differ from the monsters'.
const PLAYER_ANIM_LENGTH := {"dodge": 0.55}
## Gear pieces on a corpse (die end): helmet ornaments may dip this far into the floor, nothing
## higher than GEAR_CORPSE_MAX.
const GEAR_CORPSE_MIN := -0.15
const GEAR_CORPSE_MAX := 0.75
const BONES: Array[String] = ["root", "hips", "spine", "chest", "neck", "head", "upper_arm_l", "upper_arm_r",
	"lower_arm_l", "lower_arm_r", "hand_l", "hand_r", "grip_l", "grip_r", "upper_leg_l", "upper_leg_r",
	"lower_leg_l", "lower_leg_r", "foot_l", "foot_r"]
const PLAYER_PARTS: Array[String] = ["Head", "HairTop", "Body", "Hands", "Outfit_Top", "Outfit_Legs", "Outfit_Feet"]
const PLAYER_IDS: Array[String] = ["char_player", "char_player_f", "char_player_m1", "char_player_m2"]
const PLAYER_ANIMS: Array[String] = ["parry", "parry_hold", "walk", "walk_back", "walk_left", "walk_right"]
## Bones simulated at runtime (spring bones): left out of the corpse check.
const SIM_BONES: Array[String] = ["hair_1", "hair_2", "cape_1", "cape_2", "cape_3"]

## id -> [min height, max height]
const CHARACTERS := {
	"char_player": [1.7, 2.0],
	"char_player_f": [1.6, 1.95],
	"char_player_m1": [1.7, 2.0],
	"char_player_m2": [1.7, 2.05],
	"char_skeleton": [1.6, 2.0],
	"char_zombie": [1.45, 1.95],
	"char_ghoul": [1.2, 1.9],
	"char_cultist": [1.65, 2.1],
	"char_brute": [2.2, 2.75],
	"char_lich": [2.7, 3.5],
	"char_gravebreaker": [2.7, 3.5],
	"char_merchant": [1.55, 2.0],
}
const BOSSES: Array[String] = ["char_lich", "char_gravebreaker"]

## Run cycles: every walking character's planted foot moves at this speed (m/s).
const RUN_REF_SPEED := 5.2
const RUN_SPEED_TOL := 0.3
## Characters that hover (no foot contact) or have no run.
const NO_RUN: Array[String] = ["char_lich", "char_merchant"]
const HOVERING: Array[String] = ["char_lich"]
## Ground contact tolerance (m) for the lowest foot vertex.
const CONTACT_TOL := 0.02
## Animations exempt from the foot-contact check (they handle the floor themselves).
const NO_CONTACT: Array[String] = ["die", "dodge"]
const CORE_BONES: Array[String] = ["hips", "spine", "chest", "neck", "head"]
const HIT_FRAME := {"attack_slam": 0.55}
const SAMPLE_RATE := 60.0

## id -> [min longest side, max longest side] (metres)
const ITEMS := {
	"weapon_sword": [0.8, 1.1], "weapon_greatsword": [1.3, 1.8], "weapon_axe": [0.65, 1.0],
	"weapon_greataxe": [1.2, 1.7], "weapon_mace": [0.6, 1.0], "weapon_maul": [1.1, 1.6],
	"weapon_dagger": [0.35, 0.6], "weapon_wand": [0.35, 0.6], "weapon_staff": [1.5, 2.1],
	"weapon_bow": [1.1, 1.5], "weapon_crossbow": [0.7, 1.1],
	"offhand_shield": [0.6, 0.9], "offhand_focus": [0.2, 0.45], "offhand_quiver": [0.5, 0.9],
	"armor_helmet_str": [0.25, 0.45], "armor_helmet_dex": [0.25, 0.5], "armor_helmet_int": [0.2, 0.4],
	"armor_body": [0.4, 0.7], "armor_gloves": [0.2, 0.45], "armor_boots": [0.2, 0.45],
	"jewel_ring": [0.08, 0.2], "jewel_amulet": [0.15, 0.4], "jewel_belt": [0.25, 0.5],
	"loot_gold": [0.2, 0.45], "loot_potion_life": [0.15, 0.35], "loot_potion_mana": [0.15, 0.35],
}

var failures := 0
var checks := 0
## id -> summary strings for the final report
var motion_report: Array[String] = []


func _ready() -> void:
	print("[probe] assets-characters probe")
	for id in CHARACTERS:
		_probe_character(id)
	for id in CHARACTERS:
		_probe_motion(id)
	for id in ITEMS:
		_probe_item(id)
		_probe_icon(id)
	for l in motion_report:
		print(l)
	print("[probe] %d checks, %d failures" % [checks, failures])
	get_tree().quit(failures)


func _check(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		failures += 1
		push_error("[probe] FAIL %s (res://tools/godot/probe_characters.gd)" % what)
	return cond


func _load(id: String) -> Node3D:
	var path := MODEL_DIR + id + ".glb"
	if not _check(ResourceLoader.exists(path), "%s: %s missing" % [id, path]):
		return null
	var ps := load(path) as PackedScene
	if not _check(ps != null, "%s: not a PackedScene" % id):
		return null
	var n := ps.instantiate() as Node3D
	_check(n != null, "%s: root is not a Node3D" % id)
	return n


## Merged AABB of every MeshInstance3D (rest pose), in the model root's space.
func _aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := root.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else _rel_xform(root, m)
		var bb := xf * m.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _has_tint(root: Node) -> bool:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat != null and mat.resource_name.begins_with("tint"):
				return true
	return false


func _probe_character(id: String) -> void:
	var root := _load(id)
	if root == null:
		return
	var skels := root.find_children("*", "Skeleton3D", true, false)
	var aps := root.find_children("*", "AnimationPlayer", true, false)
	_check(skels.size() == 1, "%s: %d Skeleton3D (want 1)" % [id, skels.size()])
	_check(aps.size() == 1, "%s: %d AnimationPlayer (want 1)" % [id, aps.size()])
	_check(root.get_node_or_null("Armature/Skeleton3D") != null, "%s: no Armature/Skeleton3D" % id)
	var sk: Skeleton3D = skels[0] if skels.size() > 0 else null
	var ap: AnimationPlayer = aps[0] if aps.size() > 0 else null
	if sk != null:
		for b in BONES:
			_check(sk.find_bone(b) >= 0, "%s: missing bone %s" % [id, b])
		_check_axes(id, sk)
	var want: Array[String] = []
	if id == "char_merchant":
		want = ["idle"]
	else:
		want = HUMANOID_ANIMS.duplicate()
		if id in BOSSES:
			want.append("roar")
		if id in PLAYER_IDS:
			want.append_array(PLAYER_ANIMS)
	if ap != null:
		var names := ap.get_animation_list()
		for a in want:
			if _check(ap.has_animation(a), "%s: missing animation %s (has %s)" % [id, a, names]):
				var anim := ap.get_animation(a)
				if a == "run":
					# Run loops are tuned per character (cadence at its real speed); whole 30 fps frames.
					var frames := anim.length * 30.0
					_check(anim.length >= 0.3 and anim.length <= 0.7 and absf(frames - roundf(frames)) < 0.02,
						"%s: run length %.3f (want 0.3..0.7 s, whole frames)" % [id, anim.length])
				elif ANIM_LENGTH.has(a):
					var want_len: float = PLAYER_ANIM_LENGTH.get(a, ANIM_LENGTH[a]) if id in PLAYER_IDS else ANIM_LENGTH[a]
					_check(absf(anim.length - want_len) < 0.04, "%s: %s length %.3f (want %.2f)" % [id, a, anim.length, want_len])
				_check(anim.get_track_count() > 0, "%s: %s has no tracks" % [id, a])
		for n in names:
			_check(not String(n).contains("_001") and not String(n).contains(".001"), "%s: suffixed animation %s" % [id, n])
	if id in PLAYER_IDS:
		for p in PLAYER_PARTS:
			_check(root.find_child(p, true, false) is MeshInstance3D, "%s: missing part %s" % [id, p])
		var pieces := PlayerGear.pieces()
		_check(pieces.size() == 36, "%s: data/player_gear.json lists %d pieces (want 36)" % [id, pieces.size()])
		for p in pieces:
			var mi := root.find_child(String(p), true, false) as MeshInstance3D
			if _check(mi != null, "%s: missing gear piece %s" % [id, p]):
				var ok := false
				for i in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(i)
					ok = ok or (mat != null and mat.resource_name.begins_with("tint"))
				_check(ok, "%s: gear piece %s has no tint material" % [id, p])
	else:
		# Draw calls: one skinned "Body" (+ "Weapon" on bosses), one surface per material.
		var want_parts: Array[String] = ["Body"]
		if id in BOSSES:
			want_parts.append("Weapon")
		var mis := root.find_children("*", "MeshInstance3D", true, false)
		var names: Array[String] = []
		for n in mis:
			names.append(String(n.name))
		names.sort()
		want_parts.sort()
		_check(names == want_parts, "%s: mesh parts %s (want %s)" % [id, names, want_parts])
		for n in mis:
			var m := (n as MeshInstance3D).mesh
			var mats := {}
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				mats[mat.resource_name if mat != null else "<none>"] = true
			_check(m.get_surface_count() == mats.size(), "%s: part %s has %d surfaces for %d materials" % [id, n.name, m.get_surface_count(), mats.size()])
	var bb := _aabb(root)
	var h: Array = CHARACTERS[id]
	_check(bb.size.y >= h[0] and bb.size.y <= h[1], "%s: height %.2f not in [%.2f, %.2f]" % [id, bb.size.y, h[0], h[1]])
	_check(absf(bb.position.y) < 0.06, "%s: feet at y=%.3f (want ~0)" % [id, bb.position.y])  # rest pose (bosses hover only when animated)
	_check(absf(bb.get_center().x) < 0.15, "%s: not centred on x (%.2f)" % [id, bb.get_center().x])
	var n_mi := 0
	var n_surf := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		n_mi += 1
		n_surf += (mi as MeshInstance3D).mesh.get_surface_count()
	print("[probe] %-18s ok  size=(%.2f, %.2f, %.2f) anims=%d tint=%s meshes=%d surfaces=%d" % [id, bb.size.x, bb.size.y, bb.size.z,
		ap.get_animation_list().size() if ap else 0, _has_tint(root), n_mi, n_surf])
	root.free()


# ------------------------------------------------------------------ motion (CPU skinning)

## Rest vertices of every skinned MeshInstance3D, pre-multiplied by their bind pose, grouped by
## skeleton bone: {"part": String, "bone": int, "bone_name": String, "verts": PackedVector3Array}.
func _skin_groups(root: Node3D, sk: Skeleton3D) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var skin := mi.skin
		var bind_bone: Array[int] = []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(b))
			bind_bone.append(bi)
		var groups := {}   # bind index -> PackedVector3Array
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or verts.is_empty():
				continue
			var k := int(bones.size() / verts.size())
			for v in verts.size():
				var best := 0
				for j in k:
					if weights[v * k + j] > weights[v * k + best]:
						best = j
				var bind := int(bones[v * k + best])
				if not groups.has(bind):
					groups[bind] = PackedVector3Array()
				groups[bind].append(skin.get_bind_pose(bind) * verts[v])
		for bind in groups:
			var bi: int = bind_bone[bind]
			out.append({"part": String(mi.name), "bone": bi, "bone_name": String(sk.get_bone_name(bi)), "verts": groups[bind]})
	return out


func _seek(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	ap.play(anim)
	ap.seek(t, true)
	ap.pause()
	sk.force_update_all_bone_transforms()


## Lowest / highest posed y (model space) of the selected groups. bones / parts empty = all.
func _y_range(groups: Array, sk: Skeleton3D, to_root: Transform3D, bones: Array = [], parts: Array = []) -> Vector2:
	var lo := INF
	var hi := -INF
	var poses := {}
	for g in groups:
		if not bones.is_empty() and not (g["bone_name"] in bones):
			continue
		if not parts.is_empty() and not (g["part"] in parts):
			continue
		var bi: int = g["bone"]
		if not poses.has(bi):
			poses[bi] = to_root * sk.get_bone_global_pose(bi)
		var xf: Transform3D = poses[bi]
		var vs: PackedVector3Array = g["verts"]
		for v in vs:
			var y: float = (xf * v).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return Vector2(lo, hi)


func _probe_motion(id: String) -> void:
	var root := _load(id)
	if root == null:
		return
	add_child(root)
	var ap := Assets.prepare_animations(root)
	var sk := Assets.find_skeleton(root)
	if ap == null or sk == null:
		root.free()
		return
	var to_root := _rel_xform(root, sk)
	var groups := _skin_groups(root, sk)
	var feet := ["foot_l", "foot_r", "toe_l", "toe_r"]
	var line := "[motion] %-18s" % id
	# Run: planted-foot speed per foot.
	if not (id in NO_RUN) and ap.has_animation("run"):
		var len := ap.get_animation("run").length
		var n := int(roundf(len * SAMPLE_RATE))
		var dt := len / n
		for side in ["r", "l"]:
			var bi := sk.find_bone("foot_" + side)
			var ys: Array[float] = []
			var zs: Array[float] = []
			for f in n + 1:
				_seek(ap, sk, "run", f * dt)
				var o := (to_root * sk.get_bone_global_pose(bi)).origin
				ys.append(o.y)
				zs.append(o.z)
			var ymin: float = ys.min()
			var sum := 0.0
			var cnt := 0
			for f in range(1, n + 1):
				if ys[f] < ymin + 0.02 and ys[f - 1] < ymin + 0.02:
					sum -= (zs[f] - zs[f - 1]) / dt   # facing +Z: a planted foot moves toward -Z
					cnt += 1
			var speed := sum / maxf(1.0, cnt)
			_check(cnt >= 3 and absf(speed - RUN_REF_SPEED) <= RUN_SPEED_TOL,
				"%s: run planted-foot speed %s %.2f m/s over %d samples (want %.1f +- %.1f)" % [id, side, speed, cnt, RUN_REF_SPEED, RUN_SPEED_TOL])
			line += " run_%s=%.2f" % [side, speed]
	# Feet on the floor.
	if not (id in HOVERING):
		var worst_lo := INF
		var worst_hi := -INF
		var where := ""
		for a in ap.get_animation_list():
			if String(a) in NO_CONTACT:
				continue
			var len := ap.get_animation(a).length
			var n := maxi(2, int(roundf(len * SAMPLE_RATE)))
			var lo := INF
			var hi := -INF
			for f in n + 1:
				_seek(ap, sk, a, len * f / n)
				var r := _y_range(groups, sk, to_root, feet)
				lo = minf(lo, r.x)
				hi = maxf(hi, r.x)
			_check(lo >= -CONTACT_TOL and hi <= CONTACT_TOL, "%s: %s lowest foot vertex %.3f..%.3f m (want within +-%.2f of the floor)" % [id, a, lo, hi, CONTACT_TOL])
			if lo < worst_lo:
				worst_lo = lo
			if hi > worst_hi:
				worst_hi = hi
				where = String(a)
		line += " feet=%.3f..%.3f(%s)" % [worst_lo, worst_hi, where]
	# Corpse at the end of die.
	if ap.has_animation("die"):
		_seek(ap, sk, "die", ap.get_animation("die").length)
		# players: the base look is checked like a monster; gear pieces (all present in the model)
		# only loosely; the runtime-simulated hair / cape bones are left out
		var solid: Array = []
		var gear: Array = []
		for g in groups:
			if String(g["bone_name"]) in SIM_BONES:
				continue
			if PlayerGear.is_piece(String(g["part"])):
				gear.append(g)
			else:
				solid.append(g)
		var all_r := _y_range(solid, sk, to_root)
		var core := _y_range(solid, sk, to_root, CORE_BONES)
		if not gear.is_empty():
			var gr := _y_range(gear, sk, to_root)
			_check(gr.x >= GEAR_CORPSE_MIN and gr.y <= GEAR_CORPSE_MAX, "%s: die end: gear spans y %.2f..%.2f (want %.2f..%.2f)" % [id, gr.x, gr.y, GEAR_CORPSE_MIN, GEAR_CORPSE_MAX])
			line += " gear=%.2f..%.2f" % [gr.x, gr.y]
		_check(all_r.x >= -0.03, "%s: die end: a vertex %.3f m below the floor" % [id, all_r.x])
		_check(core.x >= -0.02, "%s: die end: torso/head %.3f m below the floor" % [id, core.x])
		var h: float = CHARACTERS[id][1]
		_check(all_r.y <= h * 0.4, "%s: die end: corpse sticks up to %.2f m" % [id, all_r.y])
		line += " corpse=%.3f..%.2f core>=%.3f" % [all_r.x, all_r.y, core.x]
		if root.find_child("Weapon", true, false) != null:
			var w := _y_range(groups, sk, to_root, [], ["Weapon"])
			_check(w.x >= -0.03 and w.y - w.x <= 0.6, "%s: die end: weapon spans y %.2f..%.2f (want flat on the floor)" % [id, w.x, w.y])
			line += " weapon=%.2f..%.2f" % [w.x, w.y]
	# Boss slam: the built-in maul rests on the floor at the hit frame.
	if id == "char_gravebreaker":
		var t: float = HIT_FRAME["attack_slam"] * ap.get_animation("attack_slam").length
		_seek(ap, sk, "attack_slam", t)
		var w := _y_range(groups, sk, to_root, [], ["Weapon"])
		_check(w.x >= -0.03 and w.x <= 0.05, "%s: attack_slam hit frame: maul lowest point %.3f m (want ~0)" % [id, w.x])
		line += " slam_weapon=%.3f" % w.x
	# Player: a two-handed weapon_maul on grip_r (BoneAttachment3D: origin at the bone head, bone
	# basis) rests on the floor at the slam's hit frame.
	if id in PLAYER_IDS:
		var maul := _load("weapon_maul")
		if maul != null:
			var t: float = HIT_FRAME["attack_slam"] * ap.get_animation("attack_slam").length
			_seek(ap, sk, "attack_slam", t)
			var grip := to_root * sk.get_bone_global_pose(sk.find_bone("grip_r"))
			var lo := INF
			for n in maul.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var xf := grip * _rel_xform(maul, mi)
				for sidx in mi.mesh.get_surface_count():
					var vs: PackedVector3Array = mi.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX]
					for v in vs:
						lo = minf(lo, (xf * v).y)
			maul.free()
			_check(lo >= -0.03 and lo <= 0.05, "%s: attack_slam hit frame: held weapon_maul lowest point %.3f m (want ~0)" % [id, lo])
			line += " slam_maul=%.3f" % lo
	motion_report.append(line)
	root.free()


## Attachment axes (§14.2): grip_r +Y forward-up in the idle/rest pose (character faces +Z),
## grip_r +X ~ blade-flat normal (horizontal), grip_l +Y up, head/chest +Y up with +Z forward.
func _check_axes(id: String, sk: Skeleton3D) -> void:
	var g := sk.get_bone_global_rest(sk.find_bone("grip_r"))
	_check(g.basis.y.z > 0.3 and g.basis.y.y > 0.3, "%s: grip_r +Y not forward-up (%s)" % [id, g.basis.y])
	_check(absf(g.basis.x.y) < 0.35, "%s: grip_r +X not horizontal (%s)" % [id, g.basis.x])
	_check(g.origin.x < -0.1, "%s: grip_r not on the right side (-X) (%s)" % [id, g.origin])
	var gl := sk.get_bone_global_rest(sk.find_bone("grip_l"))
	_check(gl.basis.y.y > 0.9, "%s: grip_l +Y not up (%s)" % [id, gl.basis.y])
	_check(gl.basis.z.z > 0.5, "%s: grip_l +Z not forward (%s)" % [id, gl.basis.z])
	for b in ["head", "chest"]:
		var t := sk.get_bone_global_rest(sk.find_bone(b))
		_check(t.basis.y.y > 0.99 and t.basis.z.z > 0.99, "%s: %s bone not straight up / roll 0 (%s)" % [id, b, t.basis])


func _probe_item(id: String) -> void:
	var root := _load(id)
	if root == null:
		return
	_check(_has_tint(root), "%s: no tint* material" % id)
	_check(root.find_children("*", "Skeleton3D", true, false).is_empty(), "%s: unexpected skeleton" % id)
	var bb := _aabb(root)
	var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var r: Array = ITEMS[id]
	_check(longest >= r[0] and longest <= r[1], "%s: longest side %.2f not in [%.2f, %.2f]" % [id, longest, r[0], r[1]])
	var c := bb.get_center()
	if id.begins_with("weapon_"):
		_check(bb.has_point(Vector3.ZERO) or bb.grow(0.02).has_point(Vector3.ZERO), "%s: grip (origin) not inside the model" % id)
		if id != "weapon_crossbow":
			_check(bb.size.y >= bb.size.x and bb.size.y >= bb.size.z, "%s: not along +Y (%s)" % [id, bb.size])
		if id != "weapon_bow":  # the bow's limbs are symmetric around the grip
			_check(bb.end.y > -bb.position.y, "%s: extends more below the grip than above" % id)
	elif id == "offhand_quiver":
		_check(c.z < -0.03 and bb.position.z < -0.2, "%s: not behind the chest (centre z %.2f)" % [id, c.z])
		_check(bb.end.y > 0.25, "%s: opening not above the chest bone (%.2f)" % [id, bb.end.y])
	elif id.begins_with("armor_helmet"):
		_check(absf(c.x) < 0.03 and bb.position.y > -0.15 and bb.position.y < 0.18 and bb.end.y > 0.25, "%s: not around the head bone (%s)" % [id, bb])
	elif id == "offhand_shield":
		_check(bb.grow(0.02).has_point(Vector3.ZERO), "%s: handle (origin) not inside" % id)
		_check(c.z > 0.02, "%s: face not toward +Z (front) (centre z %.2f)" % [id, c.z])
	elif id == "offhand_focus":
		_check(bb.position.y > -0.05 and bb.position.y < 0.1 and absf(c.x) < 0.03 and absf(c.z) < 0.03, "%s: not floating above the hand (%s)" % [id, bb])
	else:
		_check(absf(bb.position.y) < 0.03, "%s: not resting on y=0 (%.3f)" % [id, bb.position.y])
		_check(absf(c.x) < 0.06 and absf(c.z) < 0.08, "%s: not centred (%s)" % [id, c])
	print("[probe] %-18s ok  size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f)" % [id, bb.size.x, bb.size.y, bb.size.z, c.x, c.y, c.z])
	root.free()


func _probe_icon(id: String) -> void:
	var path := ICON_DIR + id + ".png"
	if not _check(ResourceLoader.exists(path), "%s: icon %s missing" % [id, path]):
		return
	var tex := load(path) as Texture2D
	if _check(tex != null, "%s: icon not a texture" % id):
		_check(tex.get_width() == 128 and tex.get_height() == 128, "%s: icon size %dx%d" % [id, tex.get_width(), tex.get_height()])
