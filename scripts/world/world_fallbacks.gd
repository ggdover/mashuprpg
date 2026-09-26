class_name WorldFallbacks
extends RefCounted
## Code-built stand-ins for environment / town props whose glb does not exist yet (Assets would
## return a coloured box). They follow the §14.1 conventions (origin at the base centre, walls /
## floors on the 2 m grid, torches sticking out along +Z from the wall face) and use material
## names like the real kit (tint_* = tintable), so the World treats them exactly like real
## assets. Only used while `Assets.has_model(id)` is false. OWNER: world.

static var _cache: Dictionary = {}


## [{"mesh": ArrayMesh, "xform": Transform3D, "mats": Array, "name": String, "placeholder": false}]
## or [] when there is no stand-in for this id.
static func parts(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var pieces: Array = _pieces(id)
	var out: Array = []
	if not pieces.is_empty():
		var mesh := ArrayMesh.new()
		var mats: Array = []
		# One surface per material (pieces sharing a material are merged).
		var by_mat: Dictionary = {}
		var mat_order: Array = []
		for p in pieces:
			var m: Material = p[2]
			if not by_mat.has(m):
				by_mat[m] = []
				mat_order.append(m)
			(by_mat[m] as Array).append(p)
		for m in mat_order:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for p in by_mat[m]:
				var prim: PrimitiveMesh = p[0]
				var xf: Transform3D = p[1]
				var arrays := prim.get_mesh_arrays()
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for i in verts.size():
						st.set_normal((xf.basis * norms[i]).normalized())
						st.add_vertex(xf * verts[i])
				else:
					for i in indices:
						st.set_normal((xf.basis * norms[i]).normalized())
						st.add_vertex(xf * verts[i])
			st.commit(mesh)
			mats.append(m)
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, mats[s])
		out.append({"mesh": mesh, "xform": Transform3D.IDENTITY, "mats": mats, "name": id, "placeholder": false})
	_cache[id] = out
	return out


static func _mat(mname: String, color: Color, emission_energy: float = 0.0, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mname
	m.albedo_color = color
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m


static func _t(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(top: float, bottom: float, height: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sphere(r: float, seg: int = 7, rings: int = 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


static func _prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


## [primitive, transform, material] lists per id.
static func _pieces(id: String) -> Array:
	match id:
		"env_torch":
			var iron := _mat("iron", Color(0.16, 0.15, 0.15), 0.0, 0.5)
			var wood := _mat("wood", Color(0.3, 0.2, 0.12))
			var flame := _mat("flame", Color(1.0, 0.55, 0.18), 5.0)
			return [
				[_box(Vector3(0.16, 0.34, 0.05)), _t(Vector3(0, 1.72, 0.025)), iron],
				[_box(Vector3(0.07, 0.07, 0.3)), _t(Vector3(0, 1.72, 0.16)), iron],
				[_cyl(0.05, 0.035, 0.42, 6), _t(Vector3(0, 1.86, 0.3), Vector3(0.35, 0, 0)), wood],
				[_cyl(0.085, 0.06, 0.09, 6), _t(Vector3(0, 2.05, 0.37), Vector3(0.35, 0, 0)), iron],
				[_prism(Vector3(0.16, 0.3, 0.16)), _t(Vector3(0, 2.22, 0.39)), flame],
			]
		"env_crystal":
			var glass := _mat("crystal", Color(0.45, 0.9, 1.0), 3.2, 0.2)
			var rock := _mat("tint_rock", Color(0.8, 0.8, 0.8))
			return [
				[_sphere(0.35, 6, 3), _t(Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.3, 0.45, 1.0)), rock],
				[_prism(Vector3(0.22, 1.1, 0.22)), _t(Vector3(0, 0.55, 0), Vector3(0.1, 0.3, -0.12)), glass],
				[_prism(Vector3(0.18, 0.75, 0.18)), _t(Vector3(0.22, 0.35, 0.08), Vector3(0.1, 0.8, -0.5)), glass],
				[_prism(Vector3(0.16, 0.6, 0.16)), _t(Vector3(-0.2, 0.3, -0.05), Vector3(-0.2, 0.2, 0.55)), glass],
			]
		"env_brazier":
			var iron2 := _mat("iron", Color(0.2, 0.18, 0.17), 0.0, 0.5)
			var coals := _mat("coals", Color(1.0, 0.45, 0.12), 4.0)
			return [
				[_cyl(0.28, 0.35, 0.12, 8), _t(Vector3(0, 0.06, 0)), iron2],
				[_cyl(0.07, 0.09, 0.8, 6), _t(Vector3(0, 0.5, 0)), iron2],
				[_cyl(0.48, 0.28, 0.3, 10), _t(Vector3(0, 1.0, 0)), iron2],
				[_cyl(0.4, 0.4, 0.05, 10), _t(Vector3(0, 1.13, 0)), coals],
				[_prism(Vector3(0.3, 0.45, 0.3)), _t(Vector3(0, 1.36, 0)), coals],
			]
		"env_pillar":
			var st := _mat("tint_stone", Color(0.8, 0.8, 0.8))
			var st2 := _mat("tint_stone_dark", Color(0.66, 0.66, 0.68))
			return [
				[_box(Vector3(1.0, 0.3, 1.0)), _t(Vector3(0, 0.15, 0)), st2],
				[_cyl(0.33, 0.36, 2.2, 8), _t(Vector3(0, 1.4, 0)), st],
				[_box(Vector3(0.95, 0.28, 0.95)), _t(Vector3(0, 2.62, 0)), st2],
			]
		"env_rock_a", "env_rock_b", "town_rock":
			var rk := _mat("tint_rock", Color(0.8, 0.78, 0.74))
			if id == "env_rock_a":
				return [
					[_sphere(0.5, 6, 3), _t(Vector3(0, 0.2, 0), Vector3(0, 0.3, 0.1), Vector3(1.2, 0.8, 0.9)), rk],
					[_sphere(0.3, 5, 3), _t(Vector3(0.45, 0.12, 0.2), Vector3(0.2, 1.0, 0)), rk],
				]
			return [[_sphere(0.35, 6, 3), _t(Vector3(0, 0.12, 0), Vector3(0, 0.6, 0), Vector3(1.2, 0.7, 1.0)), rk]]
		"env_rubble":
			var rb := _mat("tint_stone", Color(0.75, 0.74, 0.72))
			return [
				[_box(Vector3(0.3, 0.16, 0.24)), _t(Vector3(0.1, 0.08, 0.05), Vector3(0.2, 0.5, 0.1)), rb],
				[_box(Vector3(0.22, 0.12, 0.2)), _t(Vector3(-0.2, 0.06, -0.1), Vector3(0.1, 1.2, -0.2)), rb],
				[_box(Vector3(0.18, 0.1, 0.14)), _t(Vector3(-0.05, 0.05, 0.25), Vector3(0.0, 2.2, 0.3)), rb],
				[_box(Vector3(0.14, 0.09, 0.12)), _t(Vector3(0.28, 0.05, -0.2), Vector3(0.3, 0.7, 0.0)), rb],
			]
		"env_bones":
			var bone := _mat("bone", Color(0.82, 0.78, 0.66))
			return [
				[_sphere(0.12, 6, 4), _t(Vector3(0.05, 0.1, 0.0), Vector3.ZERO, Vector3(1.0, 0.9, 1.15)), bone],
				[_cyl(0.025, 0.025, 0.45, 5), _t(Vector3(-0.15, 0.03, 0.1), Vector3(PI * 0.5, 0.7, 0)), bone],
				[_cyl(0.025, 0.025, 0.4, 5), _t(Vector3(0.2, 0.03, -0.1), Vector3(PI * 0.5, -0.4, 0)), bone],
				[_cyl(0.02, 0.02, 0.3, 5), _t(Vector3(-0.05, 0.03, -0.2), Vector3(PI * 0.5, 1.6, 0)), bone],
			]
		"env_crate":
			var wd := _mat("tint_wood", Color(0.62, 0.45, 0.28))
			var wd2 := _mat("tint_wood_dark", Color(0.45, 0.31, 0.18))
			return [
				[_box(Vector3(0.75, 0.75, 0.75)), _t(Vector3(0, 0.375, 0)), wd],
				[_box(Vector3(0.8, 0.1, 0.8)), _t(Vector3(0, 0.72, 0)), wd2],
				[_box(Vector3(0.8, 0.1, 0.8)), _t(Vector3(0, 0.05, 0)), wd2],
			]
		"env_barrel":
			var wb := _mat("tint_wood", Color(0.55, 0.38, 0.22))
			var hoop := _mat("iron", Color(0.25, 0.24, 0.24), 0.0, 0.5)
			return [
				[_cyl(0.3, 0.3, 0.9, 10), _t(Vector3(0, 0.45, 0)), wb],
				[_cyl(0.34, 0.34, 0.12, 10), _t(Vector3(0, 0.45, 0)), wb],
				[_cyl(0.315, 0.315, 0.05, 10), _t(Vector3(0, 0.2, 0)), hoop],
				[_cyl(0.315, 0.315, 0.05, 10), _t(Vector3(0, 0.72, 0)), hoop],
			]
		"town_house_a", "town_house_b", "town_house_c":
			var wall_c := Color(0.78, 0.7, 0.56) if id != "town_house_b" else Color(0.72, 0.64, 0.54)
			var walls := _mat("wall", wall_c)
			var beams := _mat("beam", Color(0.33, 0.22, 0.14))
			var roof := _mat("roof", Color(0.5, 0.22, 0.16) if id != "town_house_c" else Color(0.3, 0.32, 0.38))
			var door := _mat("door", Color(0.3, 0.2, 0.12))
			var win := _mat("window", Color(1.0, 0.75, 0.4), 1.5)
			var h := 3.2 if id != "town_house_c" else 3.6
			return [
				[_box(Vector3(5.2, 0.4, 5.2)), _t(Vector3(0, 0.2, 0)), beams],
				[_box(Vector3(5.0, h, 5.0)), _t(Vector3(0, 0.4 + h * 0.5, 0)), walls],
				[_box(Vector3(5.1, 0.25, 5.1)), _t(Vector3(0, 0.4 + h, 0)), beams],
				[_prism(Vector3(6.0, 2.4, 5.8)), _t(Vector3(0, 0.4 + h + 1.2, 0), Vector3(0, PI * 0.5, 0)), roof],
				[_box(Vector3(1.1, 2.0, 0.1)), _t(Vector3(0, 1.4, 2.52)), door],
				[_box(Vector3(0.8, 0.7, 0.1)), _t(Vector3(-1.6, 2.0, 2.52)), win],
				[_box(Vector3(0.8, 0.7, 0.1)), _t(Vector3(1.6, 2.0, 2.52)), win],
				[_box(Vector3(0.6, 1.4, 0.6)), _t(Vector3(1.4, 0.4 + h + 1.6, -1.0)), beams],
			]
		"town_tree_a", "town_tree_b":
			var bark := _mat("bark", Color(0.32, 0.22, 0.14))
			var leaf := _mat("leaves", Color(0.24, 0.42, 0.16) if id == "town_tree_a" else Color(0.2, 0.36, 0.18))
			if id == "town_tree_a":
				return [
					[_cyl(0.16, 0.26, 2.2, 6), _t(Vector3(0, 1.1, 0)), bark],
					[_sphere(1.5, 7, 4), _t(Vector3(0, 3.1, 0), Vector3.ZERO, Vector3(1.0, 0.85, 1.0)), leaf],
					[_sphere(1.0, 6, 4), _t(Vector3(0.7, 3.9, 0.3)), leaf],
					[_sphere(0.9, 6, 4), _t(Vector3(-0.6, 3.7, -0.4)), leaf],
				]
			return [
				[_cyl(0.14, 0.22, 1.4, 6), _t(Vector3(0, 0.7, 0)), bark],
				[_cyl(0.0, 1.5, 2.2, 7), _t(Vector3(0, 2.2, 0)), leaf],
				[_cyl(0.0, 1.15, 1.8, 7), _t(Vector3(0, 3.3, 0)), leaf],
				[_cyl(0.0, 0.75, 1.4, 7), _t(Vector3(0, 4.3, 0)), leaf],
			]
		"town_fence":
			var fw := _mat("wood", Color(0.45, 0.32, 0.2))
			return [
				[_box(Vector3(0.12, 1.1, 0.12)), _t(Vector3(-0.94, 0.55, 0)), fw],
				[_box(Vector3(0.12, 1.1, 0.12)), _t(Vector3(0.94, 0.55, 0)), fw],
				[_box(Vector3(2.0, 0.1, 0.06)), _t(Vector3(0, 0.85, 0)), fw],
				[_box(Vector3(2.0, 0.1, 0.06)), _t(Vector3(0, 0.45, 0)), fw],
			]
		"town_lamp":
			var metal := _mat("iron", Color(0.14, 0.14, 0.15), 0.0, 0.5)
			var lampglass := _mat("lamp", Color(1.0, 0.78, 0.45), 4.0)
			return [
				[_cyl(0.18, 0.22, 0.25, 8), _t(Vector3(0, 0.12, 0)), metal],
				[_cyl(0.06, 0.07, 2.8, 6), _t(Vector3(0, 1.5, 0)), metal],
				[_box(Vector3(0.3, 0.36, 0.3)), _t(Vector3(0, 3.05, 0)), lampglass],
				[_prism(Vector3(0.44, 0.22, 0.44)), _t(Vector3(0, 3.34, 0)), metal],
			]
		"town_well":
			var ws := _mat("stone", Color(0.55, 0.54, 0.52))
			var ww := _mat("wood", Color(0.38, 0.26, 0.16))
			var water := _mat("water", Color(0.1, 0.22, 0.3), 0.0, 0.1)
			var wroof := _mat("roof", Color(0.45, 0.22, 0.15))
			return [
				[_cyl(1.1, 1.2, 0.9, 12), _t(Vector3(0, 0.45, 0)), ws],
				[_cyl(0.85, 0.85, 0.05, 12), _t(Vector3(0, 0.75, 0)), water],
				[_box(Vector3(0.15, 2.2, 0.15)), _t(Vector3(-0.95, 1.6, 0)), ww],
				[_box(Vector3(0.15, 2.2, 0.15)), _t(Vector3(0.95, 1.6, 0)), ww],
				[_box(Vector3(2.1, 0.1, 0.1)), _t(Vector3(0, 2.3, 0)), ww],
				[_prism(Vector3(2.6, 0.8, 1.8)), _t(Vector3(0, 2.9, 0)), wroof],
			]
		"town_stall":
			var sw := _mat("wood", Color(0.46, 0.32, 0.2))
			var cloth := _mat("cloth", Color(0.7, 0.2, 0.15))
			var goods := _mat("goods", Color(0.8, 0.68, 0.35))
			return [
				[_box(Vector3(2.8, 0.9, 1.0)), _t(Vector3(0, 0.45, 0.2)), sw],
				[_box(Vector3(0.1, 2.4, 0.1)), _t(Vector3(-1.35, 1.2, 0.65)), sw],
				[_box(Vector3(0.1, 2.4, 0.1)), _t(Vector3(1.35, 1.2, 0.65)), sw],
				[_box(Vector3(0.1, 2.6, 0.1)), _t(Vector3(-1.35, 1.3, -0.55)), sw],
				[_box(Vector3(0.1, 2.6, 0.1)), _t(Vector3(1.35, 1.3, -0.55)), sw],
				[_box(Vector3(3.0, 0.08, 1.6)), _t(Vector3(0, 2.55, 0.05), Vector3(-0.2, 0, 0)), cloth],
				[_box(Vector3(0.4, 0.3, 0.4)), _t(Vector3(-0.8, 1.05, 0.2)), goods],
				[_box(Vector3(0.3, 0.4, 0.3)), _t(Vector3(0.7, 1.1, 0.3)), goods],
			]
		"town_cart":
			var cw := _mat("wood", Color(0.5, 0.35, 0.2))
			var wheel := _mat("wheel", Color(0.3, 0.2, 0.12))
			return [
				[_box(Vector3(1.4, 0.5, 2.2)), _t(Vector3(0, 0.75, 0)), cw],
				[_cyl(0.5, 0.5, 0.1, 10), _t(Vector3(-0.78, 0.5, 0), Vector3(0, 0, PI * 0.5)), wheel],
				[_cyl(0.5, 0.5, 0.1, 10), _t(Vector3(0.78, 0.5, 0), Vector3(0, 0, PI * 0.5)), wheel],
				[_box(Vector3(0.08, 0.08, 1.6)), _t(Vector3(-0.3, 0.6, 1.8)), cw],
				[_box(Vector3(0.08, 0.08, 1.6)), _t(Vector3(0.3, 0.6, 1.8)), cw],
			]
		"town_bush":
			var bl := _mat("leaves", Color(0.22, 0.4, 0.15))
			return [
				[_sphere(0.6, 6, 4), _t(Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1.0, 0.75, 1.0)), bl],
				[_sphere(0.4, 6, 3), _t(Vector3(0.45, 0.35, 0.15)), bl],
			]
	return []
