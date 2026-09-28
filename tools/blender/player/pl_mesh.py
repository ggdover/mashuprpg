"""Mesh helpers for the player (tools/blender/player): weighted parts and the organic low-poly
shapes the player needs (bodies from rings, torn hems, fur, straps, wraps, rope, hair strands).

All geometry is built in UNIT space (the look's joints before its scale, pl_rig.joints) as
(verts, faces) with outward-facing counter-clockwise faces, then added to a WPart with a weight
function (pl_rig.w_* / chain / rigid) that gives every vertex its bone weights at add time.
Colours: pl_mesh.C (sRGB hex) -> materials via mat(); tintable gear materials are named tint_<x>.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector

from cc_mesh import (R, S, T, box, cyl, double_sided, hexc, icosphere, lin, loft, merge, octa, seg, slab, sphere,  # noqa: F401
	torus, tube, xf)
import cc_mesh
import pl_rig


def mat(name, hex_or_rgb, rough=0.8, metal=0.0, emit=None, strength=0.0):
	c = hexc(hex_or_rgb) if isinstance(hex_or_rgb, str) else hex_or_rgb
	e = hexc(emit) if isinstance(emit, str) else emit
	return cc_mesh.mat(name, c, rough=rough, metal=metal, emit=e, strength=strength)


def tint(name, grey=0.8, rough=0.7, metal=0.0):
	return cc_mesh.tint_mat(name, rough=rough, metal=metal, grey=grey)


# ----------------------------------------------------------------------------------- parts

class WPart:
	"""One exported mesh object: geometry, per-face material, per-vertex bone weights."""

	def __init__(self, name):
		self.name = name
		self.verts = []
		self.faces = []
		self.fmats = []
		self.vw = []
		self.mats = []

	def add(self, geo, material, weights, M=None):
		verts, faces = geo if M is None else xf(geo, M)
		names = [m.name for m in self.mats]
		if material.name not in names:
			self.mats.append(material)
			names.append(material.name)
		mi = names.index(material.name)
		off = len(self.verts)
		for v in verts:
			v = Vector(v)
			self.verts.append(v)
			self.vw.append(pl_rig.normalized(weights(v)))
		for f in faces:
			self.faces.append([i + off for i in f])
			self.fmats.append(mi)
		return self

	def tri_count(self):
		return sum(len(f) - 2 for f in self.faces)


def foot_box(size, center=(0, 0, 0), top=(1.0, 1.0), shift=(0.0, 0.0), cuts=()):
	"""cc_mesh.box (tapered top face) with extra cross-sections at the absolute Y values `cuts`
	(e.g. the ball of the foot, so the toes bend without bending the whole sole). -Y = the front."""
	sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
	cx, cy, cz = center
	tx, ty = sx * top[0], sy * top[1]
	us = [0.0] + sorted((y - (cy - sy)) / (2.0 * sy) for y in cuts if cy - sy + 1e-4 < y < cy + sy - 1e-4) + [1.0]
	verts, rings = [], []
	for u in us:
		yb = cy - sy + 2.0 * sy * u
		yt = cy - ty + shift[1] + 2.0 * ty * u
		rings.append([len(verts) + k for k in range(4)])
		verts += [Vector((cx - sx, yb, cz - sz)), Vector((cx + sx, yb, cz - sz)),
			Vector((cx + tx + shift[0], yt, cz + sz)), Vector((cx - tx + shift[0], yt, cz + sz))]
	faces = [list(rings[0])]
	for i in range(len(rings) - 1):
		a, b = rings[i], rings[i + 1]
		for k in range(4):
			faces.append([b[k], b[(k + 1) % 4], a[(k + 1) % 4], a[k]])
	faces.append(list(reversed(rings[-1])))
	return verts, faces


def build(part, arm, scale):
	"""Create the skinned Blender object for a WPart (vertices scaled to the look's size)."""
	me = bpy.data.meshes.new(part.name)
	me.from_pydata([tuple(v * scale) for v in part.verts], [], part.faces)
	for m in part.mats:
		me.materials.append(m)
	if len(me.polygons) != len(part.faces):
		raise RuntimeError("%s: polygon count mismatch %d vs %d" % (part.name, len(me.polygons), len(part.faces)))
	me.polygons.foreach_set("material_index", part.fmats)
	me.shade_flat()
	me.update()
	ob = bpy.data.objects.new(part.name, me)
	bpy.context.scene.collection.objects.link(ob)
	ob.parent = arm
	groups = {}
	for i, w in enumerate(part.vw):
		for b, x in w.items():
			groups.setdefault(b, []).append((i, x))
	for b, items in groups.items():
		if b not in arm.data.bones:
			raise RuntimeError("%s: unknown bone %s" % (part.name, b))
		vg = ob.vertex_groups.new(name=b)
		for i, x in items:
			vg.add([i], x, "REPLACE")
	mod = ob.modifiers.new("Armature", "ARMATURE")
	mod.object = arm
	return ob


# ----------------------------------------------------------------------------------- rings

def ring(z, w, fd, bd=None, n=10, cx=0.0, cy=0.0, sq=2.0, phase=None, jag=None, x_scale=None):
	"""A closed ring at height z (points CCW seen from above, first point at the front centre when
	phase is None): half width w along X, depth fd toward the front (-Y) and bd toward the back.
	sq > 2 squares it off (superellipse exponent). jag(k, x, y) -> dz lets hems tear."""
	bd = fd if bd is None else bd
	pts = []
	a0 = -math.pi / 2 if phase is None else math.radians(phase)
	for k in range(n):
		a = a0 + 2.0 * math.pi * k / n
		c, s = math.cos(a), math.sin(a)
		ex = 2.0 / sq
		x = w * math.copysign(abs(c) ** ex, c)
		d = fd if s < 0 else bd
		y = d * math.copysign(abs(s) ** ex, s)
		if x_scale is not None:
			x *= x_scale(y)
		p = Vector((cx + x, cy + y, z))
		if jag is not None:
			p.z += jag(k, x, y)
		pts.append(p)
	return pts


def rings_loft(rings, cap0=False, cap1=False, closed=True):
	"""Faces between consecutive rings of equal point counts (CCW seen from +Z when going up)."""
	verts, faces, idx = [], [], []
	for r in rings:
		ids = []
		for p in r:
			ids.append(len(verts))
			verts.append(Vector(p))
		idx.append(ids)
	n = len(rings[0])
	span = n if closed else n - 1
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		for k in range(span):
			k1 = (k + 1) % n
			faces.append([a[k], a[k1], b[k1], b[k]])
	if cap0:
		faces.append(list(reversed(idx[0])))
	if cap1:
		faces.append(list(idx[-1]))
	return verts, faces


def fan_cap(r, center, up=True):
	"""Close a ring with a fan to a centre point (a rounded top / bottom)."""
	verts = [Vector(p) for p in r] + [Vector(center)]
	c = len(r)
	faces = []
	for k in range(len(r)):
		k1 = (k + 1) % len(r)
		faces.append([k, k1, c] if up else [k1, k, c])
	return verts, faces


def flip(geo):
	verts, faces = geo
	return verts, [list(reversed(f)) for f in faces]


def sawtooth(n, depth, rnd=None, seed=0, every=1, bias=0.0):
	"""jag() for ring(): alternate vertices hang lower (torn cloth). rnd adds a random extra drop."""
	r = random.Random(seed)
	drops = [(-depth if (k // every) % 2 == 0 else 0.0) + (-r.random() * rnd if rnd else 0.0) + bias for k in range(n)]
	return lambda k, x, y: drops[k % n]


# ----------------------------------------------------------------------------------- sheets & strands

def ribbon(points, widths, normals, thick=0.0):
	"""A flat strip along a polyline: widths per point, normals per point (the strip's face
	direction); double sided, or a thin slab when thick > 0."""
	pts = [Vector(p) for p in points]
	verts, faces = [], []
	L, Rr = [], []
	for i, p in enumerate(pts):
		if i == 0:
			t = pts[1] - pts[0]
		elif i == len(pts) - 1:
			t = pts[-1] - pts[-2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t.normalize()
		nrm = Vector(normals[i]) if isinstance(normals, (list, tuple)) and not isinstance(normals[0], (int, float)) else Vector(normals)
		side = t.cross(nrm)
		if side.length < 1e-6:
			side = Vector((1, 0, 0))
		side.normalize()
		w = widths[i] if isinstance(widths, (list, tuple)) else widths
		L.append(p - side * (w * 0.5))
		Rr.append(p + side * (w * 0.5))
	for i in range(len(pts)):
		verts.append(L[i])
		verts.append(Rr[i])
	for i in range(len(pts) - 1):
		a = i * 2
		faces.append([a, a + 1, a + 3, a + 2])
	geo = (verts, faces)
	if thick > 0.0:
		nrm_list = normals if isinstance(normals, (list, tuple)) and not isinstance(normals[0], (int, float)) else [normals] * len(pts)
		back = [Vector(v) - Vector(nrm_list[i // 2]).normalized() * thick for i, v in enumerate(verts)]
		n = len(verts)
		allv = verts + back
		fs = [list(f) for f in faces] + [[j + n for j in reversed(f)] for f in faces]
		for i in range(len(pts) - 1):
			a = i * 2
			fs.append([a, a + 2, a + 2 + n, a + n])
			fs.append([a + 1 + n, a + 3 + n, a + 3, a + 1])
		fs.append([0, n, n + 1, 1])
		e = (len(pts) - 1) * 2
		fs.append([e + 1, e + 1 + n, e + n, e])
		return allv, fs
	return double_sided(geo)


def strand(points, w0, w1, depth=0.35, n=3):
	"""A hair strand / lock: a tapered prism along a polyline (triangular section by default) that
	ends in a point."""
	pts = [Vector(p) for p in points]
	radii = []
	for i in range(len(pts)):
		t = i / (len(pts) - 1)
		w = w0 + (w1 - w0) * t
		radii.append((w, w * depth) if i < len(pts) - 1 else (0.0, 0.0))
	return tube(pts, radii, n=n, cap0=True, cap1=False)


def fur_ring(center, rx, ry, z, height, n=14, tuft=0.05, seed=1, drop=0.0, up=(0, 0, 1)):
	"""A ring of fur: spiky tufts around an ellipse (pelt collars, boot cuffs). Returns geometry of
	triangular spikes leaning outward/down."""
	r = random.Random(seed)
	verts, faces = [], []
	c = Vector(center)
	for k in range(n):
		a0 = 2 * math.pi * k / n
		a1 = 2 * math.pi * (k + 1) / n
		am = (a0 + a1) * 0.5
		p0 = c + Vector((math.cos(a0) * rx, math.sin(a0) * ry, z))
		p1 = c + Vector((math.cos(a1) * rx, math.sin(a1) * ry, z))
		out = Vector((math.cos(am), math.sin(am), 0.0))
		h = height * (0.7 + 0.6 * r.random())
		tip = c + Vector((math.cos(am) * (rx + tuft * (0.6 + 0.8 * r.random())), math.sin(am) * (ry + tuft * (0.6 + 0.8 * r.random())),
			z - h * 0.35 - drop * r.random()))
		top = c + Vector((math.cos(am) * rx * 0.96, math.sin(am) * ry * 0.96, z + h * 0.65))
		i = len(verts)
		verts += [p0, p1, tip, top]
		faces += [[i, i + 1, i + 2], [i + 1, i, i + 3], [i, i + 2, i + 3], [i + 1, i + 3, i + 2]]
	return verts, faces


def band(center, rx, ry, z0, z1, n=10, bulge=0.0, cy=0.0, tilt=0.0):
	"""A short tube band (belts, wraps, cuffs): an open-ended loft between z0 and z1."""
	ra = ring(z0, rx, ry, n=n, cy=cy, phase=0.0)
	rb = ring(z1, rx + bulge, ry + bulge, n=n, cy=cy, phase=0.0)
	if tilt:
		M = T(center) @ R(tilt, 0, 0) @ T(-Vector(center))
		ra = [M @ p for p in ra]
		rb = [M @ p for p in rb]
	geo = rings_loft([[p + Vector((center[0], center[1], 0)) for p in ra], [p + Vector((center[0], center[1], 0)) for p in rb]])
	return geo


def wrap_bands(p0, p1, r0, r1, count, width=0.035, n=7, slant=18.0, side=(1, 0, 0)):
	"""Cloth wraps around a limb between p0 and p1: `count` slanted rings (radius r0 -> r1)."""
	p0, p1 = Vector(p0), Vector(p1)
	M, length = cc_mesh.frame(p0, p1, side)
	out = []
	for i in range(count):
		t = (i + 0.5) / count
		r = r0 + (r1 - r0) * t
		z = length * t
		sl = math.radians(slant) * (1 if i % 2 == 0 else -1)
		ra, rb = [], []
		for k in range(n):
			a = 2 * math.pi * k / n
			c, s = math.cos(a), math.sin(a)
			dz = math.tan(sl) * r * c
			ra.append(Vector((r * c, r * s, z - width * 0.5 + dz)))
			rb.append(Vector((r * 1.04 * c, r * 1.04 * s, z + width * 0.5 + dz)))
		out.append(xf(rings_loft([ra, rb]), M))
	return merge(*out)


def rope(points, r=0.012, twist=3.0, n=5):
	"""A twisted rope along a polyline (belts, straps): two thin intertwined tubes."""
	pts = [Vector(p) for p in points]
	out = []
	for phase in (0.0, math.pi):
		path = []
		total = 0.0
		for i, p in enumerate(pts):
			if i > 0:
				total += (p - pts[i - 1]).length
			a = phase + total / max(r * 6, 1e-3) * twist * 0.05
			t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
			side = t.cross(Vector((0, 0, 1)))
			if side.length < 1e-5:
				side = Vector((1, 0, 0))
			side.normalize()
			up = side.cross(t)
			path.append(p + (side * math.cos(a) + up * math.sin(a)) * r * 0.55)
		out.append(tube(path, [r * 0.7] * len(path), n=n))
	return merge(*out)


def strap(points, width, normal_hint=(0, -1, 0), lift=0.004, thick=0.006):
	"""A leather strap lying on a surface along `points` (offset by lift along the normal hint)."""
	nh = Vector(normal_hint)
	pts = [Vector(p) + nh.normalized() * lift for p in points]
	return ribbon(pts, width, nh, thick=thick)


def rivets(points, r=0.007, normal=(0, -1, 0)):
	out = []
	nrm = Vector(normal).normalized()
	for p in points:
		out.append(xf(octa(r, scale=(1, 1, 0.6)), T(Vector(p) + nrm * r * 0.4) @ cc_mesh.frame(Vector((0, 0, 0)), nrm)[0]))
	return merge(*out) if out else ([], [])


def patch(center, normal, w, h, up=(0, 0, 1), lift=0.003):
	"""A thin rectangular patch on a surface (sewn cloth patches, plates)."""
	c = Vector(center)
	nrm = Vector(normal).normalized()
	u = Vector(up)
	u = (u - nrm * u.dot(nrm))
	if u.length < 1e-5:
		u = Vector((1, 0, 0)) - nrm * nrm.x
	u.normalize()
	side = u.cross(nrm)
	c = c + nrm * lift
	verts = [c - side * w * 0.5 - u * h * 0.5, c + side * w * 0.5 - u * h * 0.5, c + side * w * 0.5 + u * h * 0.5, c - side * w * 0.5 + u * h * 0.5]
	return verts, [[0, 1, 2, 3]]


def mirror_x(geo):
	return xf(geo, cc_mesh.MIRROR_X)


def rnd(seed):
	return random.Random(seed)
