extends Node
## Autoload "Assets": loads the Blender-made models, meshes and icons by id, with generated
## placeholders when a file is missing, so gameplay code never hard-fails on art.
## OWNER: orchestrator. The asset catalogue (every id and its conventions) is in
## docs/ARCHITECTURE.md §14.
##
##   Assets.model("char_player")      -> Node3D  (new instance of assets/models/char_player.glb)
##   Assets.mesh("env_wall_a")        -> Mesh    (first mesh inside that glb, for MultiMesh use)
##   Assets.item_icon("weapon_sword") -> Texture2D (assets/icons/items/weapon_sword.png)
##   Assets.skill_icon("fireball")    -> Texture2D (assets/icons/skills/fireball.png)
##
## Model helpers (work for real models and placeholders):
##   var ap := Assets.prepare_animations(model)   # AnimationPlayer (deterministic, loops set) or null
##   Assets.find_skeleton(model) / Assets.find_part(model, "Torso")
##   Assets.attach_to_bone(model, "grip_r", Assets.model("weapon_sword"))
##   Assets.tint(model, Color(0.6, 0.3, 0.3), ["Torso", "Arms"])   # only tint_* materials
##   Assets.set_flash(model, 0.6, Color.WHITE)    # hit flash overlay (0 = off)
##   Assets.set_fade(model, 0.5)                  # 0 opaque .. 1 invisible (corpse fade)
##
## EVERYTHING Assets returns from its caches (Meshes, Materials, Animations, PackedScenes) is SHARED
## between all instances and areas: never mutate it. Tint/flash/fade through the helpers below (they
## use per-instance overrides), and duplicate() a Mesh before changing its surface materials.
## OWNER: orchestrator. FROZEN during waves 1-2 (report needed helpers instead of editing).

const MODEL_DIR := "res://assets/models/"
const ITEM_ICON_DIR := "res://assets/icons/items/"
const SKILL_ICON_DIR := "res://assets/icons/skills/"

var _scene_cache: Dictionary = {}   # id -> PackedScene (or null if missing)
var _mesh_cache: Dictionary = {}    # id -> Mesh
var _hidden_paths: Dictionary = {}  # id -> Array[NodePath] of nodes exported hidden
var _icon_cache: Dictionary = {}    # path -> Texture2D
var _placeholder_mats: Dictionary = {}


func has_model(id: String) -> bool:
	return _get_scene(id) != null


## New instance of a model. Never returns null: falls back to a coloured placeholder whose shape
## follows the id prefix (see _placeholder_mesh). Placeholders are tagged with meta "placeholder".
## Nodes exported with the glTF extras {"hidden": 1} (the player models' gear pieces) start hidden.
func model(id: String) -> Node3D:
	var ps := _get_scene(id)
	if ps != null:
		var inst := ps.instantiate()
		_hide_exported_hidden(id, inst)
		if inst is Node3D:
			return inst
		var wrapper := Node3D.new()
		wrapper.name = id
		wrapper.add_child(inst)
		return wrapper
	var root := Node3D.new()
	root.name = id
	root.set_meta("placeholder", true)
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	mi.mesh = _placeholder_mesh(id)
	mi.material_override = _placeholder_material(id)
	root.add_child(mi)
	return root


func _hide_exported_hidden(id: String, inst: Node) -> void:
	var paths: Variant = _hidden_paths.get(id)
	if paths == null:
		var found: Array[NodePath] = []
		for n in inst.find_children("*", "Node3D", true, false):
			if not n.has_meta("extras"):
				continue
			var ex: Variant = n.get_meta("extras")
			if ex is Dictionary and bool((ex as Dictionary).get("hidden", false)):
				found.append(inst.get_path_to(n))
		_hidden_paths[id] = found
		paths = found
	for p: NodePath in paths:
		var n := inst.get_node_or_null(p) as Node3D
		if n != null:
			n.visible = false


## The first Mesh found inside a model (depth-first). For environment kit pieces, which are
## exported as a single mesh with applied transforms, this is the whole piece.
func mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var result: Mesh = null
	var ps := _get_scene(id)
	if ps != null:
		var inst := ps.instantiate()
		var mi := _find_mesh_instance(inst)
		if mi != null:
			result = mi.mesh
		inst.free()
	if result == null:
		result = _placeholder_mesh(id)
		if result is ArrayMesh and result.get_surface_count() > 0:
			result.surface_set_material(0, _placeholder_material(id))
	_mesh_cache[id] = result
	return result


## Inventory icon for an item model id (Item.get_model_id()).
func item_icon(model_id: String) -> Texture2D:
	return _icon(ITEM_ICON_DIR + model_id + ".png", model_id)


func skill_icon(skill_id: String) -> Texture2D:
	return _icon(SKILL_ICON_DIR + skill_id + ".png", skill_id)


## Stable colour derived from an id (placeholders, fallback icons).
func color_for_id(id: String) -> Color:
	var h := float(hash(id) % 1000) / 1000.0
	return Color.from_hsv(absf(h), 0.55, 0.8)


# ------------------------------------------------------------------ model helpers

## Animations that loop. Everything else is a one-shot.
const LOOPING_ANIMATIONS: Array[String] = ["idle", "run", "channel", "walk", "walk_back", "walk_left", "walk_right", "parry_hold"]

## Bone attach points used for placeholder models (no skeleton). Character faces +Z, so its right
## hand is on -X.
const _PLACEHOLDER_BONES := {
	"grip_r": Vector3(-0.38, 0.95, 0.15),
	"grip_l": Vector3(0.38, 0.95, 0.15),
	"hand_r": Vector3(-0.38, 0.95, 0.1),
	"hand_l": Vector3(0.38, 0.95, 0.1),
	"head": Vector3(0, 1.62, 0),
	"chest": Vector3(0, 1.3, -0.12),
}

var _tint_cache: Dictionary = {}   # "matid|color" -> Material
var _flash_mats: Dictionary = {}   # color html -> StandardMaterial3D (alpha changed per call)


func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if found.size() > 0 else null


func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if found.size() > 0 else null


## A named body part / child mesh (e.g. "Torso", "Lid"), or null.
func find_part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


## Find the model's AnimationPlayer, make it deterministic (bones without a track in the current
## animation return to rest) and set LOOPING_ANIMATIONS to loop. Returns null for placeholders.
func prepare_animations(model: Node) -> AnimationPlayer:
	var ap := find_animation_player(model)
	if ap == null:
		return null
	ap.deterministic = true
	for anim_name in LOOPING_ANIMATIONS:
		if ap.has_animation(anim_name):
			var a := ap.get_animation(anim_name)
			if a.loop_mode == Animation.LOOP_NONE:
				a.loop_mode = Animation.LOOP_LINEAR
	return ap


## Parent `child` to a bone of `model` through a BoneAttachment3D (one per bone, reused). For
## models without that bone (placeholders), the child is placed at an approximate position.
## Returns the node `child` was added to.
func attach_to_bone(model: Node3D, bone: String, child: Node3D) -> Node3D:
	var sk := find_skeleton(model)
	if sk != null and sk.find_bone(bone) >= 0:
		var ba := sk.get_node_or_null("Attach_" + bone) as BoneAttachment3D
		if ba == null:
			ba = BoneAttachment3D.new()
			ba.name = "Attach_" + bone
			sk.add_child(ba)
			ba.bone_name = bone
		ba.add_child(child)
		return ba
	var holder := model.get_node_or_null("Attach_" + bone) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Attach_" + bone
		holder.position = _PLACEHOLDER_BONES.get(bone, Vector3(0, 1.0, 0))
		model.add_child(holder)
	holder.add_child(child)
	return holder


## Multiply the albedo of tintable surfaces by `color` using per-instance surface override
## materials. Tintable = materials whose name starts with "tint" (see §14.1); if the model has no
## such material at all, every surface is tinted. `parts` limits it to MeshInstance3Ds with those
## names. Color.WHITE removes the tint.
func tint(root: Node, color: Color, parts: PackedStringArray = PackedStringArray()) -> void:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
	# Placeholder models: one mesh with a material_override; tint it (parts are ignored).
	if root.get_meta("placeholder", false):
		for mi in meshes:
			if not mi.has_meta("base_mat"):
				mi.set_meta("base_mat", mi.material_override)
			var base: Material = mi.get_meta("base_mat")
			mi.material_override = base if color == Color.WHITE else _tinted(base, color)
		return
	var any_tint_named := false
	for mi in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and m.resource_name.begins_with("tint"):
				any_tint_named = true
	for mi in meshes:
		if mi.mesh == null:
			continue
		if not parts.is_empty() and not (String(mi.name) in parts):
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if any_tint_named and (src == null or not src.resource_name.begins_with("tint")):
				continue
			if color == Color.WHITE:
				mi.set_surface_override_material(i, null)
			else:
				mi.set_surface_override_material(i, _tinted(src, color))


func _tinted(src: Material, color: Color) -> Material:
	var key := "%d|%s" % [src.get_instance_id() if src else 0, color.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var m: Material
	if src is BaseMaterial3D:
		m = src.duplicate()
		(m as BaseMaterial3D).albedo_color = (src as BaseMaterial3D).albedo_color * color
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		m = sm
	_tint_cache[key] = m
	return m


## Hit-flash style overlay on every mesh under root. amount 0 removes it.
func set_flash(root: Node, amount: float, color: Color = Color.WHITE) -> void:
	var geoms := root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		geoms.append(root)
	if amount <= 0.0:
		for g in geoms:
			(g as GeometryInstance3D).material_overlay = null
		return
	var mat: StandardMaterial3D = root.get_meta("flash_mat") if root.has_meta("flash_mat") else null
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		root.set_meta("flash_mat", mat)
	mat.albedo_color = Color(color.r, color.g, color.b, clampf(amount, 0.0, 1.0))
	for g in geoms:
		if not (g is Label3D) and not (g is GPUParticles3D):
			(g as GeometryInstance3D).material_overlay = mat


## Fade every mesh under root (GeometryInstance3D.transparency): 0 opaque .. 1 invisible.
func set_fade(root: Node, transparency: float) -> void:
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).transparency = clampf(transparency, 0.0, 1.0)
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).transparency = clampf(transparency, 0.0, 1.0)


# ------------------------------------------------------------------ internals

func _get_scene(id: String) -> PackedScene:
	if _scene_cache.has(id):
		return _scene_cache[id]
	var path := MODEL_DIR + id + ".glb"
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_scene_cache[id] = ps
	return ps


func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var found := _find_mesh_instance(c)
		if found != null:
			return found
	return null


func _placeholder_material(id: String) -> StandardMaterial3D:
	if _placeholder_mats.has(id):
		return _placeholder_mats[id]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for_id(id)
	mat.roughness = 0.8
	_placeholder_mats[id] = mat
	return mat


## Shapes follow the conventions of the real assets: characters stand on y=0, weapons have the
## grip at the origin and extend along +Y, floor tiles have their top at y=0, walls rise from y=0.
func _placeholder_mesh(id: String) -> Mesh:
	if id.begins_with("char_"):
		var scale := 1.0
		if id in ["char_brute"]:
			scale = 1.35
		elif id in ["char_lich", "char_gravebreaker"]:
			scale = 1.7
		var cap := CapsuleMesh.new()
		cap.radius = 0.35 * scale
		cap.height = 1.8 * scale
		return _offset(cap, Vector3(0, 0.9 * scale, 0))
	if id == "offhand_shield":
		var sh := BoxMesh.new()
		sh.size = Vector3(0.6, 0.7, 0.08)
		return _offset(sh, Vector3(0, 0.0, 0))
	if id.begins_with("weapon_") or id.begins_with("offhand_"):
		var w := BoxMesh.new()
		var length := 1.4 if id in ["weapon_staff", "weapon_greatsword", "weapon_greataxe", "weapon_maul", "weapon_bow"] else 0.9
		w.size = Vector3(0.08, length, 0.08)
		return _offset(w, Vector3(0, length * 0.5, 0))
	if id.begins_with("env_floor"):
		var f := BoxMesh.new()
		f.size = Vector3(2.0, 0.1, 2.0)
		return _offset(f, Vector3(0, -0.05, 0))
	if id.begins_with("env_wall"):
		var wall := BoxMesh.new()
		wall.size = Vector3(2.0, 2.4, 2.0)
		return _offset(wall, Vector3(0, 1.2, 0))
	if id.begins_with("env_pillar"):
		var p := CylinderMesh.new()
		p.top_radius = 0.35
		p.bottom_radius = 0.4
		p.height = 2.4
		return _offset(p, Vector3(0, 1.2, 0))
	if id.begins_with("proj_"):
		var pr := BoxMesh.new()
		pr.size = Vector3(0.06, 0.06, 0.7)
		return _offset(pr, Vector3.ZERO)
	if id.begins_with("town_house"):
		var hb := BoxMesh.new()
		hb.size = Vector3(5, 4, 5)
		return _offset(hb, Vector3(0, 2, 0))
	if id.begins_with("town_tree"):
		var t := CylinderMesh.new()
		t.top_radius = 0.1
		t.bottom_radius = 1.4
		t.height = 4.0
		return _offset(t, Vector3(0, 2, 0))
	if id.begins_with("env_portal") or id.begins_with("env_waypoint"):
		var torus := TorusMesh.new()
		torus.inner_radius = 1.0
		torus.outer_radius = 1.25
		return _offset(torus, Vector3(0, 1.3, 0))
	var b := BoxMesh.new()
	b.size = Vector3(0.5, 0.5, 0.5)
	return _offset(b, Vector3(0, 0.25, 0))


func _offset(prim: PrimitiveMesh, offset: Vector3) -> ArrayMesh:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _icon(path: String, id: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = _placeholder_icon(id)
	_icon_cache[path] = tex
	return tex


func _placeholder_icon(id: String) -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := color_for_id(id)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			if d < 0.78:
				img.set_pixel(x, y, base.lerp(Color.WHITE, 0.25 * (1.0 - d)))
			elif d < 0.9:
				img.set_pixel(x, y, base.darkened(0.5))
	return ImageTexture.create_from_image(img)
