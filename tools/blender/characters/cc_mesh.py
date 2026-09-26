"""Low-poly mesh construction helpers for the assets-characters build (Blender 5.2).

Geometry is built as plain Python lists (verts, faces) by small primitive functions, transformed
with mathutils matrices and accumulated into `Part`s (one Part = one exported mesh object).
Every vertex of a Part remembers the bone it is skinned to (100% weight, rigid segments).

Winding convention: faces are counter-clockwise seen from outside (outward normals).
Materials: `mat()` creates Principled materials; colours are given in sRGB and converted to linear.
"""
import math

import bpy
from mathutils import Matrix, Vector


# ----------------------------------------------------------------------------------- colours

def srgb(c):
	"""sRGB component -> linear."""
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(rgb):
	return tuple(srgb(c) for c in rgb[:3])


def hexc(h):
	h = h.lstrip("#")
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ----------------------------------------------------------------------------------- materials

def mat(name, color, rough=0.75, metal=0.0, emit=None, strength=0.0, linear=False):
	"""Get or create a Principled material. `color` is sRGB unless linear=True.
	Tintable materials must be named tint_<x> (base colour ~0.8 linear grey for gear)."""
	m = bpy.data.materials.get(name)
	if m is not None:
		return m
	m = bpy.data.materials.new(name)
	col = tuple(color[:3]) if linear else lin(color)
	nt = m.node_tree
	b = nt.nodes.get("Principled BSDF")
	b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
	b.inputs["Roughness"].default_value = rough
	b.inputs["Metallic"].default_value = metal
	if emit is not None:
		e = lin(emit)
		b.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
		b.inputs["Emission Strength"].default_value = strength
	m.diffuse_color = (col[0], col[1], col[2], 1.0)
	m.roughness = rough
	m.metallic = metal
	m.use_backface_culling = True
	return m


def tint_mat(name, rough=0.7, metal=0.0, grey=0.8):
	"""A tintable gear material: base colour (grey, grey, grey) linear."""
	assert name.startswith("tint_"), name
	return mat(name, (grey, grey, grey), rough=rough, metal=metal, linear=True)


def glow(name, color, strength=4.0):
	"""Emissive material (eyes, runes, gems). Base colour = emission colour."""
	return mat(name, color, rough=0.4, emit=color, strength=strength)


# ----------------------------------------------------------------------------------- geometry

def V(*a):
	if len(a) == 1:
		return Vector(a[0])
	return Vector(a)


def xf(geo, M):
	"""Transform geometry by a 4x4 matrix (flips winding for mirroring matrices)."""
	verts, faces = geo
	out = [M @ Vector(v) for v in verts]
	if M.to_3x3().determinant() < 0:
		faces = [list(reversed(f)) for f in faces]
	return out, faces


def double_sided(geo):
	"""Duplicate the vertices and add reversed faces (thin sheets visible from both sides)."""
	verts, faces = geo
	n = len(verts)
	used = sorted({i for f in faces for i in f})
	remap = {old: n + k for k, old in enumerate(used)}
	out_v = [Vector(v) for v in verts] + [Vector(verts[i]) for i in used]
	out_f = [list(f) for f in faces] + [[remap[i] for i in reversed(f)] for f in faces]
	return out_v, out_f


def merge(*geos):
	verts, faces = [], []
	for g in geos:
		off = len(verts)
		verts.extend(Vector(v) for v in g[0])
		faces.extend([i + off for i in f] for f in g[1])
	return verts, faces


def T(x=0.0, y=0.0, z=0.0):
	if isinstance(x, (tuple, list, Vector)):
		return Matrix.Translation(Vector(x))
	return Matrix.Translation(Vector((x, y, z)))


def R(rx=0.0, ry=0.0, rz=0.0):
	"""Rotation matrix from degrees, applied X then Y then Z (extrinsic)."""
	from mathutils import Euler
	return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix().to_4x4()


def S(x=1.0, y=None, z=None):
	if y is None:
		y = x
	if z is None:
		z = x
	return Matrix.Diagonal((x, y, z, 1.0))


MIRROR_X = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))


def frame(p0, p1, side=(1, 0, 0)):
	"""Matrix whose local Z runs p0 -> p1 (origin p0), local X ~ `side` (made perpendicular)."""
	p0 = Vector(p0)
	p1 = Vector(p1)
	z = p1 - p0
	length = z.length
	z.normalize()
	x = Vector(side)
	x = x - z * x.dot(z)
	if x.length < 1e-5:
		x = Vector((0, 1, 0)) - z * z.y
		if x.length < 1e-5:
			x = Vector((1, 0, 0)) - z * z.x
	x.normalize()
	y = z.cross(x)
	M = Matrix.Identity(4)
	for i in range(3):
		M[i][0] = x[i]
		M[i][1] = y[i]
		M[i][2] = z[i]
		M[i][3] = p0[i]
	return M, length


def loft(rings, n=6, cap0=True, cap1=True, phase=None):
	"""Loft along +Z. rings: (z, rx, ry[, cx, cy]). A ring with rx=ry=0 is a single point (cone tip).
	phase: start angle in degrees (default: half a segment, so boxes are axis aligned for n=4)."""
	if phase is None:
		phase = 180.0 / n
	verts, faces, idx = [], [], []
	for r in rings:
		z, rx, ry = r[0], r[1], r[2]
		cx = r[3] if len(r) > 3 else 0.0
		cy = r[4] if len(r) > 4 else 0.0
		if rx == 0 and ry == 0:
			idx.append([len(verts)])
			verts.append(Vector((cx, cy, z)))
			continue
		ring = []
		for k in range(n):
			a = math.radians(phase) + 2.0 * math.pi * k / n
			ring.append(len(verts))
			verts.append(Vector((cx + rx * math.cos(a), cy + ry * math.sin(a), z)))
		idx.append(ring)
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		if len(a) == 1 and len(b) == 1:
			continue
		if len(a) == 1:
			for k in range(n):
				faces.append([a[0], b[(k + 1) % n], b[k]])
			continue
		if len(b) == 1:
			for k in range(n):
				faces.append([a[k], a[(k + 1) % n], b[0]])
			continue
		for k in range(n):
			faces.append([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]])
	if cap0 and len(idx[0]) > 1:
		faces.append(list(reversed(idx[0])))
	if cap1 and len(idx[-1]) > 1:
		faces.append(list(idx[-1]))
	return verts, faces


def seg(p0, p1, rings, n=6, side=(1, 0, 0), cap0=True, cap1=True, phase=None):
	"""Loft between two points. rings: (t, rx, ry[, cx, cy]) with t in 0..1 along p0->p1;
	rx along `side`, ry along the perpendicular (z x side)."""
	M, length = frame(p0, p1, side)
	rr = []
	for r in rings:
		rr.append((r[0] * length,) + tuple(r[1:]))
	return xf(loft(rr, n, cap0, cap1, phase), M)


def cyl(p0, p1, r0, r1=None, n=6, side=(1, 0, 0), ry0=None, ry1=None):
	if r1 is None:
		r1 = r0
	return seg(p0, p1, [(0, r0, ry0 if ry0 else r0), (1, r1, ry1 if ry1 else r1)], n, side)


def box(size, center=(0, 0, 0), top=(1.0, 1.0), shift=(0.0, 0.0)):
	"""Axis aligned box (optionally tapered: `top` scales the top face, `shift` moves it)."""
	sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
	cx, cy, cz = center
	tx, ty = sx * top[0], sy * top[1]
	verts = [
		Vector((cx - sx, cy - sy, cz - sz)), Vector((cx + sx, cy - sy, cz - sz)),
		Vector((cx + sx, cy + sy, cz - sz)), Vector((cx - sx, cy + sy, cz - sz)),
		Vector((cx - tx + shift[0], cy - ty + shift[1], cz + sz)), Vector((cx + tx + shift[0], cy - ty + shift[1], cz + sz)),
		Vector((cx + tx + shift[0], cy + ty + shift[1], cz + sz)), Vector((cx - tx + shift[0], cy + ty + shift[1], cz + sz)),
	]
	faces = [[3, 2, 1, 0], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	return verts, faces


def bevel_box(size, center=(0, 0, 0), b=0.2):
	"""Box with chamfered vertical edges (octagonal footprint) and chamfered top/bottom rims.
	b = chamfer as a fraction of the smaller half extent."""
	sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
	c = min(sx, sy, sz) * b
	cx, cy, cz = center

	def ring(z, inset):
		ax, ay = sx - inset, sy - inset
		k = c
		pts = [(ax - k, -ay), (ax, -ay + k), (ax, ay - k), (ax - k, ay), (-ax + k, ay), (-ax, ay - k), (-ax, -ay + k), (-ax + k, -ay)]
		return pts
	rings = [(-sz, c), (-sz + c, 0.0), (sz - c, 0.0), (sz, c)]
	verts, faces, idx = [], [], []
	for z, inset in rings:
		r = []
		for (x, y) in ring(z, inset):
			r.append(len(verts))
			verts.append(Vector((cx + x, cy + y, cz + z)))
		idx.append(r)
	n = 8
	for i in range(3):
		a, bb = idx[i], idx[i + 1]
		for k in range(n):
			faces.append([a[k], a[(k + 1) % n], bb[(k + 1) % n], bb[k]])
	faces.append(list(reversed(idx[0])))
	faces.append(list(idx[-1]))
	return verts, faces


def sphere(r, seg_n=8, rings=5, center=(0, 0, 0), scale=(1, 1, 1), cut=None):
	"""Low poly UV sphere. cut: (z0, z1) fractions of -1..1 to keep only a band (caps closed)."""
	rr = []
	z0, z1 = (-1.0, 1.0) if cut is None else cut
	steps = rings + 1
	for i in range(steps + 1):
		t = -math.pi / 2 + math.pi * i / steps
		zz = math.sin(t)
		if zz < z0 - 1e-6 or zz > z1 + 1e-6:
			continue
		rad = math.cos(t)
		if abs(rad) < 1e-6:
			rad = 0.0
		rr.append((zz * r * scale[2], rad * r * scale[0], rad * r * scale[1]))
	if cut is not None:
		if rr[0][0] > z0 * r * scale[2] + 1e-6:
			t = math.asin(max(-1, min(1, z0)))
			rr.insert(0, (z0 * r * scale[2], math.cos(t) * r * scale[0], math.cos(t) * r * scale[1]))
		if rr[-1][0] < z1 * r * scale[2] - 1e-6:
			t = math.asin(max(-1, min(1, z1)))
			rr.append((z1 * r * scale[2], math.cos(t) * r * scale[0], math.cos(t) * r * scale[1]))
	g = loft(rr, seg_n, True, True, phase=0.0)
	return xf(g, T(center))


def icosphere(r, center=(0, 0, 0), scale=(1, 1, 1)):
	"""20-face icosahedron (gems, knobs)."""
	t = (1.0 + 5 ** 0.5) / 2.0
	vs = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
		(t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
	fs = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
		[7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	k = r / math.sqrt(1 + t * t)
	verts = [Vector((center[0] + v[0] * k * scale[0], center[1] + v[1] * k * scale[1], center[2] + v[2] * k * scale[2])) for v in vs]
	return verts, [list(f) for f in fs]


def octa(r, center=(0, 0, 0), scale=(1, 1, 1)):
	"""Octahedron (gems, crystals)."""
	c = Vector(center)
	pts = [(1, 0, 0), (0, 1, 0), (-1, 0, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
	verts = [c + Vector((p[0] * r * scale[0], p[1] * r * scale[1], p[2] * r * scale[2])) for p in pts]
	faces = [[0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4], [1, 0, 5], [2, 1, 5], [3, 2, 5], [0, 3, 5]]
	return verts, faces


def slab(poly, thick, axis="x", edge=None):
	"""Extrude a 2D polygon. axis='x': poly is in (y, z), extruded along x by +-thick/2.
	edge: optional function (u, v) -> thickness multiplier (0..1) to thin blades toward edges.
	Polygon winding may be either; faces are fixed up to point outward."""
	pts = [Vector((p[0], p[1])) for p in poly]
	area = 0.0
	for i in range(len(pts)):
		a, b = pts[i], pts[(i + 1) % len(pts)]
		area += a.x * b.y - b.x * a.y
	if area < 0:
		pts = list(reversed(pts))
	n = len(pts)
	verts = []
	for p in pts:
		t = thick * (edge(p.x, p.y) if edge else 1.0) / 2.0
		verts.append(Vector((t, p.x, p.y)))
	for p in pts:
		t = thick * (edge(p.x, p.y) if edge else 1.0) / 2.0
		verts.append(Vector((-t, p.x, p.y)))
	faces = [list(range(n)), list(reversed(range(n, 2 * n)))]
	for i in range(n):
		j = (i + 1) % n
		faces.append([i, n + i, n + j, j])
	# (y,z) CCW seen from +x -> front face normal +x. Verify orientation of the side faces.
	g = (verts, faces)
	if axis == "x":
		return g
	if axis == "y":   # poly in (x, z), extruded along y
		return xf(g, Matrix(((0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))))
	if axis == "z":   # poly in (x, y), extruded along z
		return xf(g, Matrix(((0, 1, 0, 0), (0, 0, 1, 0), (1, 0, 0, 0), (0, 0, 0, 1))))
	return g


def tube(points, radii, n=6, side=(1, 0, 0), cap0=True, cap1=True, phase=None):
	"""Loft along a polyline with parallel-transport frames. radii: r or (rx, ry) per point."""
	pts = [Vector(p) for p in points]
	if phase is None:
		phase = 180.0 / n
	tangents = []
	for i in range(len(pts)):
		if i == 0:
			t = pts[1] - pts[0]
		elif i == len(pts) - 1:
			t = pts[-1] - pts[-2]
		else:
			t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
		tangents.append(t.normalized())
	x = Vector(side)
	x = (x - tangents[0] * x.dot(tangents[0]))
	if x.length < 1e-5:
		x = Vector((0, 1, 0)) - tangents[0] * tangents[0].y
	x.normalize()
	frames = []
	for i, t in enumerate(tangents):
		if i > 0:
			x = x - t * x.dot(t)
			if x.length < 1e-6:
				x = frames[-1][0]
			x.normalize()
		y = t.cross(x)
		frames.append((x.copy(), y.copy()))
	verts, faces, idx = [], [], []
	for i, p in enumerate(pts):
		r = radii[i]
		rx, ry = (r, r) if not isinstance(r, (tuple, list)) else r
		fx, fy = frames[i]
		if rx == 0 and ry == 0:
			idx.append([len(verts)])
			verts.append(p.copy())
			continue
		ring = []
		for k in range(n):
			a = math.radians(phase) + 2.0 * math.pi * k / n
			ring.append(len(verts))
			verts.append(p + fx * (rx * math.cos(a)) + fy * (ry * math.sin(a)))
		idx.append(ring)
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		if len(a) == 1 and len(b) > 1:
			for k in range(n):
				faces.append([a[0], b[(k + 1) % n], b[k]])
		elif len(b) == 1 and len(a) > 1:
			for k in range(n):
				faces.append([a[k], a[(k + 1) % n], b[0]])
		elif len(a) > 1:
			for k in range(n):
				faces.append([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]])
	if cap0 and len(idx[0]) > 1:
		faces.append(list(reversed(idx[0])))
	if cap1 and len(idx[-1]) > 1:
		faces.append(list(idx[-1]))
	return verts, faces


def torus(R0, r, n_major=12, n_minor=4, center=(0, 0, 0), axis_rot=None):
	"""Torus in the XY plane (normal +Z)."""
	verts, faces = [], []
	for i in range(n_major):
		a = 2 * math.pi * i / n_major
		ca, sa = math.cos(a), math.sin(a)
		for j in range(n_minor):
			b = 2 * math.pi * j / n_minor + math.pi / n_minor
			rr = R0 + r * math.cos(b)
			verts.append(Vector((rr * ca, rr * sa, r * math.sin(b))))
	for i in range(n_major):
		for j in range(n_minor):
			a = i * n_minor + j
			b2 = ((i + 1) % n_major) * n_minor + j
			c = ((i + 1) % n_major) * n_minor + (j + 1) % n_minor
			d = i * n_minor + (j + 1) % n_minor
			faces.append([a, b2, c, d])
	g = (verts, faces)
	M = T(center)
	if axis_rot is not None:
		M = M @ axis_rot
	return xf(g, M)


def lathe(profile, n=8, phase=None, cap0=True, cap1=True):
	"""Revolve (r, z) profile around Z."""
	return loft([(z, r, r) for (r, z) in profile], n, cap0, cap1, phase)


# ----------------------------------------------------------------------------------- parts

class Part:
	"""Geometry for one exported mesh object, with per-face material and per-vertex bone."""

	def __init__(self, name):
		self.name = name
		self.verts = []
		self.faces = []
		self.fmats = []
		self.vbones = []
		self.mats = []

	def add(self, geo, material, bone=None, M=None):
		verts, faces = geo if M is None else xf(geo, M)
		if material.name not in [m.name for m in self.mats]:
			self.mats.append(material)
		mi = [m.name for m in self.mats].index(material.name)
		off = len(self.verts)
		for v in verts:
			self.verts.append(Vector(v))
			self.vbones.append(bone)
		for f in faces:
			self.faces.append([i + off for i in f])
			self.fmats.append(mi)
		return self

	def extend(self, other):
		"""Append another Part's geometry (materials are shared by name, so surfaces = unique materials)."""
		names = [m.name for m in self.mats]
		remap = []
		for m in other.mats:
			if m.name not in names:
				self.mats.append(m)
				names.append(m.name)
			remap.append(names.index(m.name))
		off = len(self.verts)
		self.verts.extend(Vector(v) for v in other.verts)
		self.vbones.extend(other.vbones)
		self.faces.extend([i + off for i in f] for f in other.faces)
		self.fmats.extend(remap[i] for i in other.fmats)
		return self

	def tri_count(self):
		return sum(len(f) - 2 for f in self.faces)


def link(ob):
	bpy.context.scene.collection.objects.link(ob)
	return ob


def build_object(part, arm_obj=None, smooth=False):
	"""Create the Blender mesh object for a Part (identity transform). With arm_obj, the object is
	parented to the armature with an Armature modifier and one vertex group per bone."""
	me = bpy.data.meshes.new(part.name)
	me.from_pydata([tuple(v) for v in part.verts], [], part.faces)
	for m in part.mats:
		me.materials.append(m)
	if len(me.polygons) != len(part.faces):
		raise RuntimeError("%s: polygon count mismatch %d vs %d" % (part.name, len(me.polygons), len(part.faces)))
	me.polygons.foreach_set("material_index", part.fmats)
	if smooth:
		me.shade_smooth()
	else:
		me.shade_flat()
	me.update()
	ob = bpy.data.objects.new(part.name, me)
	link(ob)
	if arm_obj is not None:
		ob.parent = arm_obj
		groups = {}
		for i, b in enumerate(part.vbones):
			if b is None:
				raise RuntimeError("%s: vertex %d has no bone" % (part.name, i))
			groups.setdefault(b, []).append(i)
		for b, ids in groups.items():
			if b not in arm_obj.data.bones:
				raise RuntimeError("%s: unknown bone %s" % (part.name, b))
			vg = ob.vertex_groups.new(name=b)
			vg.add(ids, 1.0, "REPLACE")
		mod = ob.modifiers.new("Armature", "ARMATURE")
		mod.object = arm_obj
	return ob


def total_tris():
	n = 0
	for ob in bpy.data.objects:
		if ob.type == "MESH":
			n += sum(len(p.vertices) - 2 for p in ob.data.polygons)
	return n


def hair_cap(hz, w, d, h, front=0.2, back=0.06, side=0.12, top_extra=0.022, n=10, cy=0.012, closed=True):
	"""Hair/hood cap over a head_loft head: lower edge at `front` above hz at the face, `back` at the
	nape and `side` over the ears (heights relative to hz)."""
	top = hz + h + top_extra
	rings = [(0.0, w, d), (0.35, w * 1.01, d * 1.01), (0.7, w * 0.86, d * 0.88), (1.0, 0.0, 0.0)]
	verts, faces, idx = [], [], []
	for t, rx, ry in rings:
		if rx == 0:
			idx.append([len(verts)])
			verts.append(Vector((0, cy, top)))
			continue
		ring = []
		for k in range(n):
			a = 2 * math.pi * k / n + math.pi / n
			x, y = math.cos(a), math.sin(a)
			# base height of this vertex column: front (y<0) -> front, back (y>0) -> back
			if y < 0:
				zb = side + (front - side) * (-y) ** 1.5
			else:
				zb = side + (back - side) * (y ** 1.2)
			z = hz + zb + (top - (hz + zb)) * t
			ring.append(len(verts))
			verts.append(Vector((x * rx, cy + y * ry, z)))
		idx.append(ring)
	for i in range(len(idx) - 1):
		a, bb = idx[i], idx[i + 1]
		if len(bb) == 1:
			for k in range(n):
				faces.append([a[k], a[(k + 1) % n], bb[0]])
		else:
			for k in range(n):
				faces.append([a[k], a[(k + 1) % n], bb[(k + 1) % n], bb[k]])
	if closed:
		faces.append(list(reversed(idx[0])))
	return verts, faces
