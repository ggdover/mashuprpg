class_name GroundItem
extends Interactable
## An item or gold pile lying on the ground: small model + floating name label (rarity coloured),
## light beam for rare/unique. Clicking picks it up (the Player walks into range first). Gold is
## picked up automatically when the player walks within 1.2 m. Collision layer 4 ("loot"), group
## "loot" (plus "interactable" from the base). OWNER: items (wave 1).
## GroundItem owns its Label3D and polls Input.is_action_pressed("highlight_items") (Alt) itself.
## It has two pick shapes: one over the model and one over the label, so clicking the label text
## picks the item up. The Player calls set_hovered() when the mouse is over it.
## See docs/ARCHITECTURE.md §9.6.
##
## Usage (normally through LootSystem.spawn_item / spawn_gold / spawn_drops):
##   var gi := GroundItem.new(); gi.setup_item(item); gi.pop_from(monster_pos)
##   gi.position = landing_spot; world.add_dynamic(gi)
##
## Node layout: GroundItem (Area3D at the landing spot, y = 0)
##   ├ ModelShape / LabelShape (CollisionShape3D pick shapes)
##   └ Visual (offset during the pop arc)
##       ├ Spin (random yaw; tumbles while flying) └ Holder (orientation + scale) └ <model>
##       ├ LabelRoot (placed by the label layout) ├ Label (Label3D) ├ Plate ├ Border (rare+)
##       ├ Beam (rare/unique)   └ Glow (magic+ ground disc)
##
## Labels of nearby loot are laid out in screen space (stacked along the camera's up axis, greedy
## in landing order) and re-laid out when a neighbour is picked up.

const LABEL_HEIGHT := 0.6
## Extra lift of the label along the camera's up axis so the text clears the model.
const LABEL_LIFT := 0.2
## Padding of the backing plate around the text and gap between stacked labels (metres).
const LABEL_PAD := Vector2(0.16, 0.03)
const LABEL_GAP := 0.04
const LABEL_BORDER := 0.025
## Camera used for label layout when the viewport has none (game camera: pitch 56°, yaw 0).
const DEFAULT_CAMERA_PITCH := 56.0
const LABEL_FONT_SIZE := 56
const LABEL_PIXEL_SIZE := 0.0045
const LABEL_OUTLINE := 8
const GOLD_PICKUP_RADIUS := 1.2
const POP_TIME := 0.5
const POP_HEIGHT := 1.3
const BEAM_HEIGHT := 7.0
const HOVER_FLASH := 0.3
## Longest side of the ground model per slot type (metres).
const MODEL_SIZES := {"weapon": 0.8, "offhand": 0.62, "body": 0.64, "helmet": 0.5, "gloves": 0.5, "boots": 0.52, "ring": 0.42, "amulet": 0.48, "belt": 0.56, "gold": 0.5}
## Tint of the gold pile's tint_* material (matches its icon).
const GOLD_TINT := Color(0.95, 0.77, 0.28)
const PLATE_COLOR := Color(0.02, 0.018, 0.015, 0.66)
const PLATE_HOVER_COLOR := Color(0.2, 0.16, 0.09, 0.8)

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 beam_color : source_color = vec4(1.0);
void fragment() {
	float bottom = clamp(UV.y, 0.0, 1.0);
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.4);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2);
	ALBEDO = beam_color.rgb;
	ALPHA = beam_color.a * pow(bottom, 1.8) * edge * pulse;
}
"""
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 glow_color : source_color = vec4(1.0);
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	ALBEDO = glow_color.rgb;
	ALPHA = glow_color.a * a * a;
}
"""

static var _beam_shader: Shader = null
static var _glow_shader: Shader = null
static var _material_cache: Dictionary = {}
static var _land_counter := 0

var item: Item = null
var gold: int = 0

var _visual: Node3D = null
var _spin: Node3D = null
var _holder: Node3D = null
var _model: Node3D = null
var _label: Label3D = null
var _label_root: Node3D = null
var _plate: MeshInstance3D = null
var _border: MeshInstance3D = null
var _beam: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _model_cs: CollisionShape3D = null
var _label_cs: CollisionShape3D = null
var _label_size := Vector2(1.0, 0.25)
var _land_order := 0
var _label_forced := false
var _alt_held := false
var _picked := false
var _landed := true
var _pop_pending := false
var _pop_origin := Vector3.ZERO
var _pop_offset := Vector3.ZERO
var _pop_t := 0.0
var _spin_axis := Vector3.RIGHT
var _yaw := 0.0
var _half_height := 0.1
var _last_cam_basis := Basis()


func _init() -> void:
	super._init()
	collision_layer = LAYER_LOOT
	add_to_group("loot")


func setup_item(p_item: Item) -> void:
	item = p_item
	gold = 0
	display_name = get_hover_name()
	if is_inside_tree():
		_build()


func setup_gold(amount: int) -> void:
	gold = maxi(0, amount)
	item = null
	display_name = get_hover_name()
	if is_inside_tree():
		_build()


func is_gold() -> bool:
	return item == null and gold > 0


func get_hover_name() -> String:
	if item:
		return item.get_display_name()
	return "%d Gold" % gold


func get_hover_color() -> Color:
	if item:
		return item.get_rarity_color()
	return UIStyle.COLOR_GOLD


func get_interact_range() -> float:
	return 1.8


func can_interact(_player: Node) -> bool:
	return enabled and not _picked


## Start a pop-arc spawn animation from `origin` (global position, e.g. the dying monster) to this
## node's position. Call before adding the node to the tree (or any time after, to replay it).
func pop_from(origin: Vector3) -> void:
	_pop_origin = origin
	_pop_pending = true
	if is_inside_tree():
		_start_pop()


## True once the pop arc has finished (gold is only auto-picked up after landing).
func is_landed() -> bool:
	return _landed


## True while the floating label is shown.
func is_label_visible() -> bool:
	return _label != null and _label.visible


## Global position of the label centre (where clicking the name picks the item up).
func get_label_position() -> Vector3:
	return _label_root.global_position if _label_root != null and _label_root.is_inside_tree() else global_position + Vector3(0, LABEL_HEIGHT, 0)


## Show/hide the floating label (Alt = show all). Normal items hide their label unless hovered or
## highlighted; magic and better (and gold) always show it. set_label_visible(true) forces the
## label on like holding Alt; false removes that request.
func set_label_visible(on: bool) -> void:
	_label_forced = on
	_update_label()


## Pick up: gold -> character.add_gold; item -> character.add_to_inventory (full: emit
## Events.inventory_full and stay on the ground). Emits Events.item_picked_up / gold_picked_up,
## Sfx "pickup_item"/"pickup_gold", then frees itself. The character is `player.character` when
## the player has one, else GameState.character.
func interact(player: Node) -> void:
	if _picked or not enabled:
		return
	var character := _resolve_character(player)
	if character == null:
		push_warning("GroundItem.interact: no character to receive %s" % get_hover_name())
		return
	if item == null:
		if gold > 0:
			character.add_gold(gold)
			Events.gold_picked_up.emit(gold)
			Sfx.play("pickup_gold", global_position)
		_despawn()
		return
	if character.add_to_inventory(item):
		Events.item_picked_up.emit(item)
		Sfx.play("pickup_item", global_position)
		_despawn()
	else:
		Events.inventory_full.emit()


# ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	_build()
	if _pop_pending:
		_start_pop()


func _process(_delta: float) -> void:
	if _label == null:
		return
	var alt := Input.is_action_pressed("highlight_items") if InputMap.has_action("highlight_items") else false
	if alt != _alt_held:
		_alt_held = alt
		_update_label()
	if _label.visible:
		_orient_label_shape()


func _physics_process(delta: float) -> void:
	if _picked:
		return
	if not _landed:
		_pop_t += delta / POP_TIME
		var t := minf(_pop_t, 1.0)
		var off := _pop_offset * (1.0 - t)
		off.y += POP_HEIGHT * 4.0 * t * (1.0 - t)
		_visual.position = off
		_spin.basis = Basis(_spin_axis, (1.0 - t) * TAU * 1.25) * Basis(Vector3.UP, _yaw)
		if t >= 1.0:
			_land()
		return
	if is_gold():
		var p: Variant = GameState.player
		if is_instance_valid(p) and (p as Node3D).is_inside_tree() and p.get("dead") != true:
			var d: Vector3 = (p as Node3D).global_position - global_position
			d.y = 0.0
			if d.length() <= GOLD_PICKUP_RADIUS:
				interact(p)


func _on_hover_changed(on: bool) -> void:
	if _model != null:
		# Workaround: Assets.set_flash reads get_meta("flash_mat", null), which errors when the
		# meta is missing, so seed it with an equivalent overlay material first.
		if not _model.has_meta("flash_mat"):
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_model.set_meta("flash_mat", fm)
		Assets.set_flash(_model, HOVER_FLASH if on else 0.0, get_hover_color().lightened(0.3))
	_update_label()


# ------------------------------------------------------------------ building

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_spin = Node3D.new()
	_spin.name = "Spin"
	_visual.add_child(_spin)
	_holder = Node3D.new()
	_holder.name = "Holder"
	_spin.add_child(_holder)
	_yaw = randf() * TAU
	_spin.basis = Basis(Vector3.UP, _yaw)
	_build_model()
	_build_label()
	_build_effects()
	_update_label()
	set_physics_process(not _landed or is_gold())


func _model_id() -> String:
	if item == null:
		return "loot_gold"
	var id := item.get_model_id()
	return id if id != "" else "loot_" + item.get_slot_type()


func _slot_key() -> String:
	return "gold" if item == null else item.get_slot_type()


## Orientation so the item lies flat: weapons/quivers on the flat of the blade (Godot +Y along the
## ground, blade flat facing up), shields and body armour on their back, the rest upright.
func _orientation() -> Basis:
	if item == null:
		return Basis()
	match item.get_slot_type():
		"weapon":
			return Basis(Vector3.FORWARD, deg_to_rad(90.0))
		"offhand":
			var wt := item.get_weapon_type()
			if wt == "quiver":
				return Basis(Vector3.FORWARD, deg_to_rad(90.0))
			if wt == "shield":
				return Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		"body", "gloves", "belt":
			return Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	return Basis()


func _build_model() -> void:
	var id := _model_id()
	_model = Assets.model(id)
	_holder.add_child(_model)
	var tint := item.get_tint() if item != null else GOLD_TINT
	if _model.get_meta("placeholder", false):
		_style_placeholder(tint)
	else:
		Assets.tint(_model, tint)
	for g in _model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var aabb := _local_aabb(_model)
	if aabb.size.length() < 0.001:
		aabb = AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 0.5, 0.5))
	var orient := _orientation()
	var oriented: AABB = Transform3D(orient, Vector3.ZERO) * aabb
	var longest := maxf(oriented.size.x, maxf(oriented.size.y, oriented.size.z))
	var s: float = MODEL_SIZES.get(_slot_key(), 0.6) / maxf(longest, 0.001)
	var basis := orient.scaled(Vector3(s, s, s))
	var scaled: AABB = Transform3D(basis, Vector3.ZERO) * aabb
	_half_height = scaled.size.y * 0.5
	var center := scaled.get_center()
	# Holder: bottom of the model at y = 0.02, centred on the node (spin pivot at mid height).
	_holder.transform = Transform3D(basis, Vector3(-center.x, -scaled.position.y - _half_height, -center.z))
	_spin.position = Vector3(0, _half_height + 0.02, 0)
	# Pick shape over the model (a little larger than the model for easy clicking).
	var box := BoxShape3D.new()
	var r := maxf(scaled.size.x, scaled.size.z)
	box.size = Vector3(maxf(r, 0.45) + 0.1, maxf(scaled.size.y, 0.25) + 0.1, maxf(r, 0.45) + 0.1)
	_model_cs = add_pick_shape(box, Vector3(0, box.size.y * 0.5, 0))
	_model_cs.name = "ModelShape"


## Placeholder models (no glb yet): replace the random placeholder colour by the item tint so the
## ground loot still reads (gold coins yellow, uniques in their tint).
func _style_placeholder(tint: Color) -> void:
	var col := tint
	var key := "ph|" + col.to_html()
	var mat: StandardMaterial3D = _material_cache.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.metallic = 0.35 if item == null else 0.15
		mat.roughness = 0.45
		_material_cache[key] = mat
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


func _build_label() -> void:
	_label_root = Node3D.new()
	_label_root.name = "LabelRoot"
	_label_root.position = Vector3(0, LABEL_HEIGHT, 0)
	_label_root.visible = false
	_visual.add_child(_label_root)
	_label = Label3D.new()
	_label.name = "Label"
	_label.text = get_hover_name()
	_label.font_size = LABEL_FONT_SIZE
	_label.pixel_size = LABEL_PIXEL_SIZE
	_label.outline_size = LABEL_OUTLINE
	_label.outline_modulate = Color(0, 0, 0, 0.92)
	_label.modulate = get_hover_color()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.double_sided = true
	_label.render_priority = 10
	_label.outline_render_priority = 9
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label_root.add_child(_label)
	var font: Font = _label.font if _label.font != null else ThemeDB.fallback_font
	var text_size := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	# Full label box (text + plate padding), used for layout and the pick shape.
	_label_size = Vector2(text_size.x, maxf(text_size.y, LABEL_FONT_SIZE)) * LABEL_PIXEL_SIZE + LABEL_PAD
	_plate = _make_plate(_label_size, 7)
	_plate.name = "Plate"
	_label_root.add_child(_plate)
	if item != null and item.rarity >= Item.Rarity.RARE:
		_border = MeshInstance3D.new()
		_border.name = "Border"
		_border.mesh = _frame_mesh(_label_size, LABEL_BORDER)
		_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_border.material_override = _plate_material(Color(get_hover_color(), 0.9), 8)
		_label_root.add_child(_border)
	var box := BoxShape3D.new()
	box.size = Vector3(_label_size.x + 0.04, _label_size.y + 0.04, 0.06)
	_label_cs = add_pick_shape(box, _label_root.position)
	_label_cs.name = "LabelShape"
	_label_cs.disabled = true


func _make_plate(size: Vector2, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _plate_material(PLATE_COLOR, priority)
	return mi


## A rectangular frame (outer = inner + 2 × thickness) in the XY plane, centred on the origin.
static func _frame_mesh(inner: Vector2, thickness: float) -> ArrayMesh:
	var hx := inner.x * 0.5
	var hy := inner.y * 0.5
	var ox := hx + thickness
	var oy := hy + thickness
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [x0, y0, x1, y1] rectangles: top, bottom, left, right.
	for r in [[-ox, hy, ox, oy], [-ox, -oy, ox, -hy], [-ox, -hy, -hx, hy], [hx, -hy, ox, hy]]:
		var a := Vector3(r[0], r[1], 0)
		var b := Vector3(r[2], r[1], 0)
		var c := Vector3(r[2], r[3], 0)
		var d := Vector3(r[0], r[3], 0)
		for v in [a, b, c, a, c, d]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(v)
	return st.commit()


## Billboarded, always-on-top translucent material for label plates (cached per colour).
static func _plate_material(col: Color, priority: int) -> StandardMaterial3D:
	var key := "plate|%s|%d" % [col.to_html(true), priority]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.render_priority = priority
	_material_cache[key] = m
	return m


func _build_effects() -> void:
	if item == null or item.rarity < Item.Rarity.MAGIC:
		return
	var col := item.get_rarity_color()
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.5, 1.5)
	_glow.mesh = plane
	_glow.position = Vector3(0, 0.015, 0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow_alpha := {Item.Rarity.MAGIC: 0.22, Item.Rarity.RARE: 0.4, Item.Rarity.UNIQUE: 0.55}.get(item.rarity, 0.3) as float
	_glow.material_override = _shader_material("glow", col, glow_alpha)
	_visual.add_child(_glow)
	if item.rarity < Item.Rarity.RARE:
		return
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.2
	cyl.height = BEAM_HEIGHT
	cyl.radial_segments = 14
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam.mesh = cyl
	_beam.position = Vector3(0, BEAM_HEIGHT * 0.5, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.material_override = _shader_material("beam", col, 0.5 if item.rarity == Item.Rarity.UNIQUE else 0.4)
	_visual.add_child(_beam)


static func _shader_material(kind: String, col: Color, alpha: float) -> ShaderMaterial:
	var key := "%s|%s|%.2f" % [kind, col.to_html(false), alpha]
	if _material_cache.has(key):
		return _material_cache[key]
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = _beam_shader if kind == "beam" else _glow_shader
	m.set_shader_parameter("beam_color" if kind == "beam" else "glow_color", Color(col.r, col.g, col.b, alpha))
	_material_cache[key] = m
	return m


# ------------------------------------------------------------------ behaviour

func _start_pop() -> void:
	_pop_pending = false
	if _visual == null:
		return
	_pop_offset = _pop_origin - global_position
	if _pop_offset.length() > 12.0:
		_pop_offset = _pop_offset.normalized() * 12.0
	_pop_t = 0.0
	_landed = false
	set_physics_process(true)
	_spin_axis = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	if _spin_axis.length() < 0.1:
		_spin_axis = Vector3.RIGHT
	_spin_axis = _spin_axis.normalized()
	_visual.position = _pop_offset
	if _beam != null:
		_beam.visible = false
	if _glow != null:
		_glow.visible = false
	_update_label()


func _land() -> void:
	_landed = true
	# Only gold needs per-frame work after landing (auto pickup).
	set_physics_process(is_gold())
	_visual.position = Vector3.ZERO
	_spin.basis = Basis(Vector3.UP, _yaw)
	var tw := create_tween()
	tw.tween_property(_spin, "scale", Vector3(1.18, 0.8, 1.18), 0.06)
	tw.tween_property(_spin, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow != null:
		_glow.visible = true
	if _beam != null:
		_beam.visible = true
		_beam.scale = Vector3(1, 0.05, 1)
		_beam.position.y = BEAM_HEIGHT * 0.025
		var tb := create_tween().set_parallel(true)
		tb.tween_property(_beam, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tb.tween_property(_beam, "position:y", BEAM_HEIGHT * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_land_counter += 1
	_land_order = _land_counter
	_layout_label()
	_update_label()


func _camera_basis() -> Basis:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.from_euler(Vector3(deg_to_rad(-DEFAULT_CAMERA_PITCH), 0.0, 0.0))


## Place the label above the item, stacked along the camera's up axis until it overlaps (in
## screen space) no label of loot that landed earlier. Always-visible labels (magic+, gold) only
## avoid other always-visible labels; normal-item labels avoid every label.
func _layout_label() -> void:
	if _label_root == null or not is_inside_tree():
		return
	var cb := _camera_basis()
	var right := cb.x
	var up := cb.y
	var others: Array[GroundItem] = []
	for n in get_tree().get_nodes_in_group("loot"):
		var gi := n as GroundItem
		if gi == null or gi == self or gi._picked or not gi._landed or gi._label_root == null:
			continue
		if gi._land_order > _land_order:
			continue
		if _always_show_label() and not gi._always_show_label():
			continue
		others.append(gi)
	var base := global_position + Vector3(0, LABEL_HEIGHT, 0) + up * LABEL_LIFT
	var step := _label_size.y + LABEL_GAP
	var pos := base
	for level in 12:
		pos = base + up * (step * level)
		var free := true
		for gi in others:
			var d := pos - gi._label_root.global_position
			if absf(d.dot(right)) < (_label_size.x + gi._label_size.x) * 0.5 + LABEL_GAP and absf(d.dot(up)) < (_label_size.y + gi._label_size.y) * 0.5 + LABEL_GAP * 0.5:
				free = false
				break
		if free:
			break
	_label_root.global_position = pos
	_label_cs.global_position = pos


## Re-layout labels of loot near this one (after it was picked up), in landing order.
func _relayout_neighbours() -> void:
	if not is_inside_tree():
		return
	var list: Array[GroundItem] = []
	for n in get_tree().get_nodes_in_group("loot"):
		var gi := n as GroundItem
		if gi == null or gi == self or gi._picked or not gi._landed:
			continue
		if gi.global_position.distance_to(global_position) < 8.0:
			list.append(gi)
	list.sort_custom(func(a: GroundItem, b: GroundItem) -> bool: return a._land_order < b._land_order)
	for gi in list:
		gi._layout_label()


func _always_show_label() -> bool:
	return item == null or item.rarity >= Item.Rarity.MAGIC


func _update_label() -> void:
	if _label == null:
		return
	var show := _landed and not _picked and (_always_show_label() or hovered or _alt_held or _label_forced)
	_label_root.visible = show
	_label.visible = show
	if _label_cs != null:
		_label_cs.disabled = not show
	var col := get_hover_color()
	_label.modulate = col.lightened(0.35) if hovered else col
	_label.outline_modulate = Color(0.32, 0.24, 0.1, 0.95) if hovered else Color(0, 0, 0, 0.92)
	if _plate != null:
		_plate.material_override = _plate_material(PLATE_HOVER_COLOR if hovered else PLATE_COLOR, 7)


## Keep the label pick box facing the camera like the billboarded text.
func _orient_label_shape() -> void:
	if _label_cs == null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var b := cam.global_transform.basis.orthonormalized()
	if b.is_equal_approx(_last_cam_basis):
		return
	_last_cam_basis = b
	_label_cs.global_basis = b


func _resolve_character(player: Node) -> CharacterData:
	if player != null and is_instance_valid(player) and "character" in player:
		var c: Variant = player.get("character")
		if c is CharacterData:
			return c
	return GameState.character


func _despawn() -> void:
	_picked = true
	enabled = false
	visible = false
	_relayout_neighbours()
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	queue_free()


## AABB of every mesh under root, in root's local space (root need not be in the tree).
static func _local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi is Label3D:
			continue
		var rel := Transform3D.IDENTITY
		var cur: Node = vi
		while cur != null and cur != root:
			if cur is Node3D:
				rel = (cur as Node3D).transform * rel
			cur = cur.get_parent()
		var box: AABB = rel * vi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
