class_name WorldInteractable
extends Interactable
## Shared behaviour of the world's interactables (portals, gate, merchant, stash, chests,
## shrines): a model, hover highlight (brighten + rim-light overlay on the model, label colour), a floating
## name label (Label3D, shown on hover or always), an optional light (within the World's light
## budget), and the minimap marker kind.
## Subclasses build their visuals in _build() (called from _ready). OWNER: world.

## Hover overlay, two passes: a multiplicative brighten of what is already drawn (keeps the
## model's detail; a flat additive fill washes small dark models out in the dungeons) followed by
## an additive rim light in the highlight colour.
const HOVER_GAIN_CODE := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float gain = 1.5;
void fragment() {
	ALBEDO = vec3(gain);
}
"""
const HOVER_RIM_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float rim_amount = 0.3;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color.rgb * rim_amount * f * f * f;
}
"""
## Hover highlight strength in daylight (town) / in the dark dungeons (see flash()).
const HOVER_AMOUNT_DAY := 0.1
const HOVER_AMOUNT_DARK := 0.22

static var _gain_shader: Shader = null
static var _rim_shader: Shader = null

## The visual model (child of this node). Hover flash is applied to it only.
var model: Node3D = null
var label: Label3D = null
## Height of the floating label above the node origin.
var label_height := 2.6
## Portals keep their label visible; everything else shows it on hover.
var always_show_label := false
## Minimap marker: "portal" | "waypoint" | "vendor" | "stash" | "chest" | "" (none).
var marker_kind := ""
var highlight_color := Color(1.0, 0.85, 0.55)
var light: OmniLight3D = null
var _built := false


func _ready() -> void:
	if not _built:
		_built = true
		_build()
		_make_label()


## Override: create the model, pick shapes, effects.
func _build() -> void:
	pass


## Minimap marker kind right now ("" = no marker, e.g. an opened chest).
func get_minimap_kind() -> String:
	return marker_kind


func _make_label() -> void:
	label = Label3D.new()
	label.name = "Label"
	label.text = get_hover_name()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0085
	label.font_size = 44
	label.outline_size = 12
	label.modulate = get_hover_color()
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position = Vector3(0, label_height, 0)
	label.render_priority = 10
	label.outline_render_priority = 9
	label.visible = always_show_label and enabled
	add_child(label)


func refresh_label() -> void:
	if label == null:
		return
	label.text = get_hover_name()
	label.modulate = get_hover_color().lightened(0.25) if hovered else get_hover_color()
	label.visible = enabled and (always_show_label or hovered)


func _on_hover_changed(on: bool) -> void:
	if model != null and is_instance_valid(model):
		flash(model, hover_amount() if on else 0.0, highlight_color)
	refresh_label()


## Hover highlight strength here: softer in the dark dungeons than in the daylit town.
func hover_amount() -> float:
	var w := find_world()
	if w != null and not w.is_daylit() and w.theme != "arena":
		return HOVER_AMOUNT_DARK
	return HOVER_AMOUNT_DAY


## The World this interactable belongs to (null when it is not inside one).
func find_world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	return null


## Hover highlight on every mesh under root (per-instance material_overlay; shared meshes and
## materials are untouched): amount 0 removes it. Brightens the model x (1 + 6 * amount) and adds
## a rim light of 1.4 x amount in `color`.
static func flash(root: Node, amount: float, color: Color) -> void:
	var geoms := root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		geoms.append(root)
	if amount <= 0.0:
		for g in geoms:
			(g as GeometryInstance3D).material_overlay = null
		return
	var mat: ShaderMaterial = null
	if root.has_meta("hover_mat"):
		mat = root.get_meta("hover_mat") as ShaderMaterial
	if mat == null:
		if _gain_shader == null:
			_gain_shader = Shader.new()
			_gain_shader.code = HOVER_GAIN_CODE
			_rim_shader = Shader.new()
			_rim_shader.code = HOVER_RIM_CODE
		mat = ShaderMaterial.new()
		mat.shader = _gain_shader
		var rim := ShaderMaterial.new()
		rim.shader = _rim_shader
		mat.next_pass = rim
		root.set_meta("hover_mat", mat)
	mat.set_shader_parameter("gain", 1.0 + amount * 6.0)
	var rim_mat := mat.next_pass as ShaderMaterial
	if rim_mat != null:
		rim_mat.set_shader_parameter("color", color)
		rim_mat.set_shader_parameter("rim_amount", amount * 1.4)
	for g in geoms:
		if not (g is Label3D) and not (g is GPUParticles3D):
			(g as GeometryInstance3D).material_overlay = mat


## Stop being hoverable / clickable (opened chest, used shrine).
func disable_interaction() -> void:
	enabled = false
	if hovered:
		set_hovered(false)
	collision_layer = 0
	input_ray_pickable = false
	refresh_label()


## The interactable's own OmniLight3D (stored in `light`). Inside a World it first reserves a
## slot of the area's light budget (World.reserve_light_slot); without one it goes unlit and
## returns null (`light` stays null).
func add_light(color: Color, energy: float, light_range: float, offset: Vector3) -> OmniLight3D:
	var w := find_world()
	if w != null and not w.reserve_light_slot():
		return null
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.position = offset
	add_child(light)
	return light


## Merged AABB of every mesh under `root`, in root space.
static func model_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


static func is_placeholder(m: Node) -> bool:
	return m != null and bool(m.get_meta("placeholder", false))


## Simple stone material for code-built fallback shapes.
static func stone_material(color: Color, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func mesh_node(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi
