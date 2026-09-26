class_name StatusVisuals
extends Node3D
## Visual feedback for ailments on any Actor: burning flames (ignite), blue tint + frost (chill),
## ice shell (freeze), sparks (shock), green bubbles (poison), red drips (bleed).
## Player and Enemy call StatusVisuals.attach(self) in _ready(); it listens to
## Actor.ailment_changed. OWNER: skills (wave 2). CONTRACT — keep the public signature.
##
## Everything is built from shared meshes/shaders (VfxUtil) as children of this node, so the
## visuals follow the actor and vanish with it. Attaching twice returns the existing instance;
## detach() disconnects and frees it. Ailments already present when attached are shown at once.
## The model's materials are never touched (hit flashes own the material overlay).

const KINDS: Array[String] = ["ignite", "chill", "freeze", "shock", "poison", "bleed"]
const COLORS := {
	"ignite": Color(1.0, 0.5, 0.15),
	"chill": Color(0.55, 0.82, 1.0),
	"freeze": Color(0.6, 0.88, 1.0),
	"shock": Color(1.0, 0.95, 0.35),
	"poison": Color(0.45, 0.95, 0.3),
	"bleed": Color(0.75, 0.05, 0.08),
}

var actor: Actor = null
## kind -> Node3D holding that ailment's visuals.
var _fx: Dictionary = {}
var _radius := 0.4
var _height := 1.8
var _time := 0.0
var _arc_timer := 0.0
var _arcs: Array = []
var _materials: Dictionary = {}


static func attach(actor: Actor) -> StatusVisuals:
	var existing := actor.get_node_or_null("StatusVisuals")
	if existing is StatusVisuals and not existing.is_queued_for_deletion():
		return existing as StatusVisuals
	var sv := StatusVisuals.new()
	sv.name = "StatusVisuals"
	sv.actor = actor
	actor.add_child(sv)
	return sv


func _ready() -> void:
	if actor == null:
		actor = get_parent() as Actor
	if actor == null:
		return
	if not actor.ailment_changed.is_connected(_on_ailment_changed):
		actor.ailment_changed.connect(_on_ailment_changed)
	_radius = clampf(actor.get_collision_radius(), 0.25, 2.5)
	_height = clampf((actor.get_aim_point().y - (actor.global_position.y if actor.is_inside_tree() else actor.position.y)) * 1.6, 1.0, 5.0)
	for kind in actor.ailments.keys():
		_show(String(kind))


## Remove the visuals and stop listening.
func detach() -> void:
	if actor != null and is_instance_valid(actor) and actor.ailment_changed.is_connected(_on_ailment_changed):
		actor.ailment_changed.disconnect(_on_ailment_changed)
	for k in _fx.keys():
		_hide(k, false)
	queue_free()


## True while the ailment's visual is shown (tests).
func has_visual(kind: String) -> bool:
	return _fx.has(kind) and is_instance_valid(_fx[kind])


func get_active_kinds() -> Array:
	return _fx.keys()


func _on_ailment_changed(kind: String, active: bool) -> void:
	if active:
		_show(kind)
	else:
		_hide(kind, true)


func _show(kind: String) -> void:
	if has_visual(kind) or not KINDS.has(kind):
		return
	var root := Node3D.new()
	root.name = kind.capitalize()
	add_child(root)
	_fx[kind] = root
	var c: Color = COLORS[kind]
	var r := _radius
	var h := _height
	match kind:
		"ignite":
			VfxUtil.particles(root, Color.WHITE, {"amount": 30, "lifetime": 0.55, "speed": Vector2(0.4, 1.4), "gravity": 3.5, "spread": 20.0,
				"size": 0.42 * clampf(r / 0.4, 0.8, 3.0), "emit_radius": r * 0.85, "one_shot": false, "energy": 1.6,
				"ramp": VfxSpawn.hot_ramp(c)}, Vector3(0, h * 0.3, 0))
			VfxUtil.particles(root, Color(1.0, 0.85, 0.4), {"amount": 8, "lifetime": 0.8, "speed": Vector2(1.0, 2.2), "gravity": 1.0,
				"spread": 30.0, "size": 0.07, "emit_radius": r, "one_shot": false, "energy": 3.5}, Vector3(0, h * 0.5, 0))
			var glow := VfxUtil.ground_node(r * 2.0, {"color": c, "energy": 1.2, "radius": 3.0, "fill": 0.3, "fill_radius": 0.9})
			root.add_child(glow)
			_materials["ignite"] = glow.material_override
		"chill":
			var ring := VfxUtil.ground_node(r * 2.2, {"color": c, "energy": 1.5, "radius": 0.82, "thickness": 0.08, "gaps": 10.0, "fill": 0.12, "fill_radius": 0.82})
			root.add_child(ring)
			_materials["chill"] = ring.material_override
			VfxUtil.particles(root, Color(0.85, 0.95, 1.0), {"amount": 12, "lifetime": 1.1, "speed": Vector2(0.1, 0.4), "gravity": -0.8,
				"spread": 180.0, "size": 0.09, "emit_radius": r * 1.2, "one_shot": false, "energy": 2.4}, Vector3(0, h * 0.75, 0))
			VfxUtil.particles(root, c, {"amount": 8, "lifetime": 1.2, "speed": Vector2(0.05, 0.25), "gravity": 0.1, "spread": 180.0,
				"size": 0.5 * clampf(r / 0.4, 0.8, 3.0), "emit_radius": r * 0.8, "one_shot": false, "additive": false, "grow": true,
				"ramp": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.0)]}, Vector3(0, 0.25, 0))
		"freeze":
			var ice := VfxUtil.material("glass", {"color": c, "alpha": 0.62, "energy": 1.45})
			var body := VfxUtil.mesh_node(VfxUtil.sphere_mesh(6), ice)
			body.scale = Vector3(r * 1.55, h * 0.6, r * 1.55)
			body.position.y = h * 0.5
			root.add_child(body)
			for i in 7:
				var a := TAU * float(i) / 7.0 + randf_range(-0.3, 0.3)
				var sh := VfxUtil.mesh_node(VfxUtil.spike_mesh(), ice)
				var d := r * randf_range(0.7, 1.2)
				sh.position = Vector3(sin(a) * d, randf_range(0.0, h * 0.25), cos(a) * d)
				sh.rotation = Vector3(cos(a) * randf_range(0.2, 0.6), randf() * TAU, -sin(a) * randf_range(0.2, 0.6))
				var w := r * randf_range(0.35, 0.55)
				sh.scale = Vector3(w, h * randf_range(0.45, 0.8), w)
				root.add_child(sh)
			var floor_ice := VfxUtil.ground_node(r * 2.6, {"color": c, "energy": 1.8, "radius": 0.85, "thickness": 0.1, "fill": 0.4, "fill_radius": 0.85})
			root.add_child(floor_ice)
			root.scale = Vector3(0.6, 0.6, 0.6)
			_materials["freeze_grow"] = root
		"shock":
			VfxUtil.particles(root, c, {"amount": 12, "lifetime": 0.22, "speed": Vector2(1.5, 3.5), "gravity": -4.0, "spread": 180.0,
				"size": 0.08, "emit_radius": r * 1.1, "one_shot": false, "energy": 3.5}, Vector3(0, h * 0.5, 0))
			var am := VfxUtil.material("add", {"color": c.lerp(Color.WHITE, 0.25), "energy": 3.0, "alpha": 1.0})
			for i in 4:
				var arc := VfxUtil.mesh_node(ArrayMesh.new(), am)
				arc.top_level = true
				root.add_child(arc)
				_arcs.append(arc)
			var sr := VfxUtil.ground_node(r * 2.0, {"color": c, "energy": 1.6, "radius": 0.8, "thickness": 0.06, "gaps": 14.0})
			root.add_child(sr)
			_materials["shock"] = sr.material_override
			_arc_timer = 0.0
		"poison":
			VfxUtil.particles(root, c, {"amount": 12, "lifetime": 0.9, "speed": Vector2(0.3, 0.8), "gravity": 1.2, "spread": 25.0,
				"size": 0.13 * clampf(r / 0.4, 0.8, 3.0), "emit_radius": r * 0.8, "one_shot": false, "energy": 2.0}, Vector3(0, h * 0.3, 0))
			var pr := VfxUtil.ground_node(r * 2.1, {"color": c, "energy": 1.5, "radius": 0.75, "thickness": 0.14, "swirl": 1.0, "fill": 0.25, "fill_radius": 0.75})
			root.add_child(pr)
			_materials["poison"] = pr.material_override
		"bleed":
			VfxUtil.particles(root, c, {"amount": 10, "lifetime": 0.6, "speed": Vector2(0.2, 0.8), "gravity": -9.0, "spread": 40.0,
				"direction": Vector3.DOWN, "size": 0.09, "emit_radius": r * 0.7, "one_shot": false, "additive": false}, Vector3(0, h * 0.55, 0))
			var pool := VfxUtil.ground_node(r * 1.6, {"color": Color(0.35, 0.02, 0.03), "energy": 1.0, "radius": 3.0, "fill": 0.55, "fill_radius": 0.7, "gaps": 5.0}, false)
			pool.position.y = 0.035
			root.add_child(pool)
			_materials["bleed"] = pool.material_override


func _hide(kind: String, animate: bool) -> void:
	if not _fx.has(kind):
		return
	var root: Variant = _fx[kind]
	_fx.erase(kind)
	_materials.erase(kind)
	if kind == "shock":
		_arcs.clear()
	if kind == "freeze":
		_materials.erase("freeze_grow")
		if animate and actor != null and is_instance_valid(actor) and actor.is_inside_tree():
			VfxSpawn.ice_shatter(actor.global_position, _radius, _height, COLORS["freeze"])
	if root != null and is_instance_valid(root):
		(root as Node).queue_free()


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	_time += delta
	if _materials.has("ignite"):
		(_materials["ignite"] as ShaderMaterial).set_shader_parameter("alpha", 0.75 + 0.25 * sin(_time * 19.0) * sin(_time * 7.0))
	if _materials.has("chill"):
		(_materials["chill"] as ShaderMaterial).set_shader_parameter("spin", _time * 1.5)
	if _materials.has("shock"):
		(_materials["shock"] as ShaderMaterial).set_shader_parameter("spin", _time * 5.0)
	if _materials.has("poison"):
		(_materials["poison"] as ShaderMaterial).set_shader_parameter("spin", _time * 2.0)
	if _materials.has("freeze_grow"):
		var g: Node3D = _materials["freeze_grow"]
		if is_instance_valid(g):
			var s := minf(1.0, g.scale.x + delta * 6.0)
			g.scale = Vector3.ONE * s
	if not _arcs.is_empty():
		_arc_timer -= delta
		if _arc_timer <= 0.0:
			_arc_timer = 0.07
			for arc in _arcs:
				if not is_instance_valid(arc):
					continue
				var mi := arc as MeshInstance3D
				if randf() < 0.15:
					mi.visible = false
					continue
				mi.visible = true
				var a0 := randf() * TAU
				var a1 := a0 + randf_range(0.8, 2.2)
				var base := global_position
				var p0 := base + Vector3(sin(a0) * _radius * 1.15, randf_range(0.15, 0.95) * _height, cos(a0) * _radius * 1.15)
				var p1 := base + Vector3(sin(a1) * _radius * 1.15, randf_range(0.15, 0.95) * _height, cos(a1) * _radius * 1.15)
				mi.global_transform = Transform3D.IDENTITY
				mi.mesh = VfxUtil.ribbon_mesh(VfxUtil.jagged_points(p0, p1, 0.12, 6), 0.055)
