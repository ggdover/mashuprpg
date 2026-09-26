extends Node
## Validation probe for the assets-environment module (docs/ARCHITECTURE.md §14.5).
##   tools/gtest.sh assets-environment res://tools/godot/probe_environment.tscn
## Loads every env_* / town_* / proj_* model and every skill icon and checks the §14.1/§14.4
## conventions (single-mesh kit pieces, tint_ materials, AABBs and origins, the chest Lid pivot,
## projectile orientation, emissive parts, icon format). Prints a report; exit code = failures.
## OWNER: assets-environment.

const KIT_FLOORS: Array[String] = ["env_floor_a", "env_floor_b", "env_floor_c"]
const KIT_WALLS: Array[String] = ["env_wall_a", "env_wall_b"]
const DUNGEON_PROPS: Array[String] = [
	"env_torch", "env_brazier", "env_crate", "env_barrel", "env_bones", "env_rubble",
	"env_rock_a", "env_rock_b", "env_crystal", "env_chest", "env_portal", "env_waypoint",
]
const TOWN: Array[String] = [
	"town_house_a", "town_house_b", "town_house_c", "town_well", "town_tree_a", "town_tree_b",
	"town_fence", "town_lamp", "town_stall", "town_stash", "town_cart", "town_bush", "town_rock",
]
const PROJECTILES: Array[String] = ["proj_arrow", "proj_bolt", "proj_ice_spear", "proj_meteor"]
const EMISSIVE: Array[String] = [
	"env_torch", "env_brazier", "env_crystal", "env_portal", "env_waypoint", "town_lamp",
	"proj_ice_spear", "proj_meteor",
]
const WITH_LID: Array[String] = ["env_chest", "town_stash"]
## §8.4 player skill ids (frozen) -> assets/icons/skills/<id>.png
const SKILL_IDS: Array[String] = [
	"basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam", "whirlwind",
	"infernal_blow", "war_cry", "power_shot", "split_arrow", "rain_of_arrows", "explosive_bolt",
	"scatter_shot", "rapid_fire", "ice_shot", "venom_arrow", "fireball", "ice_spear", "frost_nova",
	"chain_lightning", "teleport", "spark", "meteor", "blood_rite",
]
const KIT_TRI_BUDGET := 500
const EPS := 0.012
## Wall blocks: 2 x 2 m, top at 2.4. Their dark core and bottom plate start at WALL_MIN_Y (below
## the floor tiles' edge groove, bottom at -0.045) so no see-through slit shows at the wall base.
const WALL_TOP_Y := 2.4
const WALL_MIN_Y := -0.06

var _fails := 0
var _checks := 0
var _lines: PackedStringArray = []


func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(_on_timeout)
	_run()
	print("\n".join(_lines))
	print("[probe_environment] %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(_fails)


func _on_timeout() -> void:
	print("[probe_environment] TIMEOUT")
	get_tree().quit(99)


func _run() -> void:
	for id in KIT_FLOORS:
		_check_kit(id, "floor")
	for id in KIT_WALLS:
		_check_kit(id, "wall")
	_check_kit("env_pillar", "pillar")
	for id in DUNGEON_PROPS:
		_check_prop(id)
	for id in TOWN:
		_check_prop(id)
	for id in PROJECTILES:
		_check_projectile(id)
	_check_icons()


# ------------------------------------------------------------------ helpers

func _check(ok: bool, id: String, what: String) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
		_lines.append("  [FAIL] %s: %s" % [id, what])
	return ok


func _load(id: String) -> Node3D:
	var path := "res://assets/models/%s.glb" % id
	if not _check(ResourceLoader.exists(path), id, "missing " + path):
		return null
	var ps := load(path) as PackedScene
	if not _check(ps != null, id, "not a PackedScene"):
		return null
	var inst := ps.instantiate() as Node3D
	_check(inst != null, id, "root is not a Node3D")
	return inst


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


## Transform of `node` relative to `root` (the root's own transform included, as a placed model).
func _xform_to_root(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		if n == root:
			break
		n = n.get_parent()
	return xf


func _aabb(root: Node3D) -> AABB:
	var first := true
	var box := AABB()
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		var a := _xform_to_root(root, mi) * mi.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.size() > 0:
			n += idx.size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _materials(root: Node3D) -> Array[Material]:
	var out: Array[Material] = []
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null:
				out.append(m)
	return out


func _has_emission(root: Node3D) -> bool:
	for m in _materials(root):
		if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
			return true
	return false


## Every environment material is single-sided (glTF doubleSided = false -> CULL_BACK); the
## Blender build checks (build_all.py --check) guarantee no back face is ever visible.
func _check_culling(id: String, root: Node3D) -> void:
	var bad: PackedStringArray = []
	for m in _materials(root):
		if m is BaseMaterial3D and (m as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_BACK:
			bad.append(m.resource_name)
	_check(bad.is_empty(), id, "materials must cull back faces (doubleSided = false): %s" % ", ".join(bad))


func _is_identity(xf: Transform3D) -> bool:
	return xf.origin.length() < 1e-4 and xf.basis.is_equal_approx(Basis.IDENTITY)


## Mean vertex position of the surfaces whose material name contains `key` (root space).
func _material_centroid(root: Node3D, key: String) -> Variant:
	var sum := Vector3.ZERO
	var count := 0
	for mi in _meshes(root):
		var xf := _xform_to_root(root, mi)
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m == null or not m.resource_name.contains(key):
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				sum += xf * v
				count += 1
	if count == 0:
		return null
	return sum / count


func _fmt(a: AABB) -> String:
	return "pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]


func _near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


# ------------------------------------------------------------------ checks

func _check_kit(id: String, kind: String) -> void:
	var inst := _load(id)
	if inst == null:
		return
	var f0 := _fails
	var meshes := _meshes(inst)
	_check(meshes.size() == 1, id, "kit piece must be exactly ONE mesh (found %d)" % meshes.size())
	if meshes.is_empty():
		inst.free()
		return
	var mi := meshes[0]
	_check(_is_identity(_xform_to_root(inst, mi)), id, "mesh node must have an identity transform")
	var mesh_from_assets := Assets.mesh(id)
	_check(mesh_from_assets != null and mesh_from_assets.get_surface_count() == mi.mesh.get_surface_count(), id, "Assets.mesh() does not return the kit mesh")
	var tris := _tris(mi.mesh)
	_check(tris <= KIT_TRI_BUDGET, id, "%d tris > budget %d" % [tris, KIT_TRI_BUDGET])
	_check_culling(id, inst)
	var all_tint := true
	for m in _materials(inst):
		if not m.resource_name.begins_with("tint_"):
			all_tint = false
	_check(all_tint, id, "every kit material must be tint_* (tinted per theme)")
	var a := _aabb(inst)
	match kind:
		"floor":
			_check(_near(a.end.y, 0.0, 0.002), id, "floor top must be at y = 0 (%.3f)" % a.end.y)
			_check(_near(a.size.x, 2.0) and _near(a.size.z, 2.0), id, "floor must be 2x2 m (%s)" % _fmt(a))
			_check(_near(a.get_center().x, 0.0) and _near(a.get_center().z, 0.0), id, "floor must be centred")
			_check(a.position.y < -0.02 and a.position.y > -0.5, id, "floor thickness looks wrong (%s)" % _fmt(a))
		"wall":
			# the visible block rises from y = 0; only the hidden core/bottom plate reach WALL_MIN_Y
			_check(_near(a.position.y, WALL_MIN_Y, 0.002), id, "wall core must start at y = %.2f (min y %.3f)" % [WALL_MIN_Y, a.position.y])
			_check(_near(a.end.y, WALL_TOP_Y, 0.002), id, "wall top must be at y = %.1f (%.3f)" % [WALL_TOP_Y, a.end.y])
			_check(_near(a.size.x, 2.0) and _near(a.size.z, 2.0), id, "wall must be 2 x 2 m (%s)" % _fmt(a))
			_check(_near(a.get_center().x, 0.0) and _near(a.get_center().z, 0.0), id, "wall must be centred")
		"pillar":
			_check(_near(a.position.y, 0.0, 0.002), id, "pillar must rise from y = 0")
			_check(a.size.y > 2.0 and a.size.y < 3.2, id, "pillar height %.2f" % a.size.y)
			_check(a.size.x <= 2.0 and a.size.z <= 2.0, id, "pillar must fit its 2x2 cell")
			_check(_near(a.get_center().x, 0.0, 0.05) and _near(a.get_center().z, 0.0, 0.05), id, "pillar must be centred")
	_report(id, _fails == f0, "tris=%d %s" % [tris, _fmt(a)])
	# tint_ variants: tint_stone is the neutral base (~0.8 linear); _b / _c / _dark / _top are
	# intentionally darker so relative shading survives the per-theme tint
	var tints: PackedStringArray = []
	for m in _materials(inst):
		if m is BaseMaterial3D:
			var c := (m as BaseMaterial3D).albedo_color
			tints.append("%s=%.2f" % [m.resource_name, c.r])
	_lines.append("        materials (albedo, sRGB): %s" % ", ".join(tints))
	inst.free()


func _check_prop(id: String) -> void:
	var inst := _load(id)
	if inst == null:
		return
	var f0 := _fails
	var a := _aabb(inst)
	var tris := 0
	for mi in _meshes(inst):
		tris += _tris(mi.mesh)
		if mi.name != "Lid":
			_check(_is_identity(_xform_to_root(inst, mi)), id, "mesh '%s' must have an identity transform" % mi.name)
	_check(_meshes(inst).size() > 0, id, "no mesh")
	_check_culling(id, inst)
	if id == "env_torch":
		# origin on the wall face at floor level, sticking out along +Z
		_check(a.position.z > -0.02, id, "torch must not go into the wall (min z %.2f)" % a.position.z)
		_check(a.end.z > 0.2 and a.end.z < 0.8, id, "torch must stick out along +Z (max z %.2f)" % a.end.z)
		_check(a.position.y > 1.0 and a.end.y < 2.4, id, "sconce height (%s)" % _fmt(a))
	else:
		_check(_near(a.position.y, 0.0, 0.02), id, "base must rest on y = 0 (min y %.3f)" % a.position.y)
		_check(absf(a.get_center().x) < 0.25 * maxf(a.size.x, 1.0), id, "origin must be at the base centre (x)")
		_check(absf(a.get_center().z) < 0.25 * maxf(a.size.z, 1.0), id, "origin must be at the base centre (z)")
	if id.begins_with("town_house"):
		_check(a.size.x <= 6.5 and a.size.z <= 6.5 and a.size.x >= 4.5 and a.size.z >= 4.5, id, "house footprint ~6x6 (%s)" % _fmt(a))
		_check(a.size.y >= 4.5 and a.size.y <= 7.5, id, "house height ~6 m (%.2f)" % a.size.y)
	if id == "town_fence":
		_check(_near(a.size.x, 2.0, 0.15), id, "fence segment must be ~2 m along X (%.2f)" % a.size.x)
	if id.begins_with("town_tree"):
		_check(a.size.y >= 3.5 and a.size.y <= 9.0, id, "tree height %.2f" % a.size.y)
	if id in EMISSIVE:
		_check(_has_emission(inst), id, "needs an emissive material")
	if id in WITH_LID:
		_check_lid(id, inst)
	_report(id, _fails == f0, "tris=%d %s" % [tris, _fmt(a)])
	inst.free()


func _check_lid(id: String, inst: Node3D) -> void:
	var lid := Assets.find_part(inst, "Lid")
	if not _check(lid != null, id, "missing child mesh 'Lid'"):
		return
	_check(lid.transform.basis.is_equal_approx(Basis.IDENTITY), id, "Lid must have identity rotation")
	var hinge := lid.position
	var body := AABB()
	for mi in _meshes(inst):
		if mi != lid:
			body = _xform_to_root(inst, mi) * mi.mesh.get_aabb()
			break
	_check(hinge.y > 0.2 and _near(hinge.y, body.end.y, 0.06), id, "Lid pivot must be on the top edge (hinge %s, base top %.2f)" % [hinge, body.end.y])
	_check(hinge.z < 0.0 and _near(hinge.z, body.position.z, 0.06), id, "Lid pivot must be on the BACK edge (hinge z %.2f, base back %.2f)" % [hinge.z, body.position.z])
	var la := lid.mesh.get_aabb()
	_check(la.end.z > 0.3 and la.position.y > -0.08, id, "Lid geometry must extend forward (+Z) from the hinge (%s)" % _fmt(la))
	# opening per §13 swings the lid up and back behind the hinge
	var opened := Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(110)), hinge) * la
	_check(opened.end.z < hinge.z + 0.35 and opened.end.y > hinge.y + 0.3, id, "opened lid (rotation.x = -110 deg) must swing up/back (%s)" % _fmt(opened))


func _check_projectile(id: String) -> void:
	var inst := _load(id)
	if inst == null:
		return
	var f0 := _fails
	var a := _aabb(inst)
	var tris := 0
	for mi in _meshes(inst):
		tris += _tris(mi.mesh)
		_check(_is_identity(_xform_to_root(inst, mi)), id, "mesh must have an identity transform")
	_check_culling(id, inst)
	var c := a.get_center()
	_check(c.length() < 0.35 * a.get_longest_axis_size(), id, "origin must be at the centre (%s)" % _fmt(a))
	if id == "proj_meteor":
		var trail: Variant = _material_centroid(inst, "trail")
		_check(trail != null and (trail as Vector3).z < -0.1, id, "flame trail must be behind (-Z), i.e. the rock flies along +Z")
	else:
		_check(a.get_longest_axis_index() == Vector3.AXIS_Z, id, "must point along Z (%s)" % _fmt(a))
		var tip: Variant = _material_centroid(inst, "tip")
		_check(tip != null and (tip as Vector3).z > 0.1, id, "tip must be at +Z (tip centroid %s)" % str(tip))
	_report(id, _fails == f0, "tris=%d %s" % [tris, _fmt(a)])
	inst.free()


func _check_icons() -> void:
	var sigs: Dictionary = {}
	for sid in SKILL_IDS:
		var path := "res://assets/icons/skills/%s.png" % sid
		var id := "icon:" + sid
		if not _check(ResourceLoader.exists(path), id, "missing " + path):
			continue
		var tex := load(path) as Texture2D
		if not _check(tex != null, id, "not a texture"):
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var f0 := _fails
		_check(img.get_width() == 128 and img.get_height() == 128, id, "must be 128x128 (%dx%d)" % [img.get_width(), img.get_height()])
		_check(img.get_pixel(1, 1).a < 0.05 and img.get_pixel(126, 126).a < 0.05, id, "corners must be transparent (round badge)")
		_check(img.get_pixel(64, 64).a > 0.95, id, "badge centre must be opaque")
		var s := img.duplicate() as Image
		s.resize(16, 16, Image.INTERPOLATE_BILINEAR)
		sigs[sid] = s
		_report(id, _fails == f0, "%dx%d" % [img.get_width(), img.get_height()])
	# every icon must be clearly different from every other one
	var ids := sigs.keys()
	var closest := 1e9
	var pair := ""
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := _img_diff(sigs[ids[i]], sigs[ids[j]])
			if d < closest:
				closest = d
				pair = "%s ~ %s" % [ids[i], ids[j]]
	if ids.size() > 1:
		_check(closest > 0.02, "icons", "two icons are nearly identical: %s (%.3f)" % [pair, closest])
		_lines.append("  icons: most similar pair %s (mean diff %.3f)" % [pair, closest])


func _img_diff(a: Image, b: Image) -> float:
	var total := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	return total / float(a.get_width() * a.get_height())


func _report(id: String, ok: bool, detail: String) -> void:
	_lines.append("%s %-18s %s" % ["[OK]  " if ok else "[FAIL]", id, detail])
