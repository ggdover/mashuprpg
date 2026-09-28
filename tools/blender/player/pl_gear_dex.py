"""Dexterity gear of the player (tools/blender/player; rules in pl_gear.py): hunters' and rangers'
leather, hoods, fur and cloaks.
  tier 1 (common hunter): a green hood with a leather brow band; a stitched leather vest over a long
         linen shirt, a green cowl, crossed straps, belt and pouches; leather gloves with wrapped
         bracers; tall cross-laced boots with fur cuffs.
  tier 2 (rare ranger): a steel cap with gold bands, nasal and leather cheek flaps over a dark green
         hood; a knee-long dark green coat with gold borders, a big fur mantle, harness, a gold
         buckled belt with pouches and a green cloak with a tree emblem; runed leather bracers with
         gold trim over dark gloves; tall laced boots with fur cuffs and bronze buckles.
  tier 3 (unique frostbound hunter): a dark winged helm (gold wings, brow arches, nasal, leather
         cheek guards); a huge white fur mantle with a wolf's head, a navy coat with fur-trimmed
         hems and a rune tabard, straps with gold medallions and a long blue cloak with a white
         emblem; dark runed bracers with gold trim; plated dark boots with knee cops, straps and
         gold trim.
Tinted (tint_*_dex*): the leather of every piece (vests, harness leather, brow band, cheek guards,
gloves, bracers, boots); cloth, fur, linen, straps, metal and trims keep their colours.
A chest piece also hides the female's front hair strands (HairFront), which would cut through
cowls and mantles.
"""
import math
import random

from mathutils import Matrix, Vector

import pl_rig
from pl_body import _interp_head, _jag_end, _open_front
from pl_mesh import (band, box, cyl, double_sided, fan_cap, foot_box, mat, merge, octa, patch, ribbon, ring, rings_loft,
	sawtooth, slab, sphere, tint, tube, wrap_bands, xf, R, T)

FAM = "dex"
SQ = 2.2
CHEST_HIDES = ["Outfit_Top", "Outfit_Belt", "HairFront"]


def V(*a):
	return Vector(a[0]) if len(a) == 1 else Vector(a)


# ----------------------------------------------------------------------------------- materials

def M(key):
	"""The family's fixed materials (sRGB)."""
	spec = {
		"green": ("4d5933", 0.95, 0.0), "linen": ("c0b394", 0.95, 0.0), "strap": ("3d2a1b", 0.7, 0.0),
		"belt": ("33241a", 0.7, 0.0), "iron": ("8b8983", 0.45, 0.7), "sole": ("2b221a", 0.9, 0.0),
		"fur": ("8b7a63", 1.0, 0.0), "coat": ("2d3a28", 0.9, 0.0), "cloak": ("2a3625", 0.9, 0.0),
		"gold": ("b38c45", 0.4, 0.75), "bronze": ("9a6a38", 0.45, 0.7), "fur_brown": ("7a6a55", 1.0, 0.0),
		"fur_light": ("a39377", 1.0, 0.0), "thread": ("bba874", 0.7, 0.3), "steel": ("8e9197", 0.4, 0.75),
		"glove_dark": ("2c241d", 0.8, 0.0), "navy": ("252f48", 0.9, 0.0), "navy_dark": ("1b2233", 0.9, 0.0),
		"tabard": ("3a4a66", 0.9, 0.0), "rune": ("dcdfd8", 0.8, 0.0), "fur_white": ("cbc4b6", 1.0, 0.0),
		"fur_grey": ("8e8880", 1.0, 0.0), "blue": ("2a3a60", 0.9, 0.0), "steel_dark": ("4f5566", 0.45, 0.4),
		"eye": ("d9a03a", 0.4, 0.0), "nose": ("1e1a18", 0.6, 0.0),
	}
	hexc, rough, metal = spec[key]
	return mat("dex_" + key, hexc, rough=rough, metal=metal)


def TINT(slot, tier, grey, key=""):
	"""A tinted leather surface: tint_<slot>_dex_<tier>[_key] (one material per brightness; the game
	multiplies its albedo by the item's tint)."""
	return tint("tint_%s_dex_%d%s" % (slot, tier, ("_" + key) if key else ""), grey=grey, rough=0.75)


# ----------------------------------------------------------------------------------- surfaces

def _ell(a, w, fd, bd, z, cy=0.0, sq=SQ):
	"""The point at angle a (degrees: 0 front centre, +90 the character's left (+X), 180 back) of a
	superellipse ring like pl_mesh.ring()."""
	ar = math.radians(a - 90.0)
	c, s = math.cos(ar), math.sin(ar)
	ex = 2.0 / sq
	x = w * math.copysign(abs(c) ** ex, c)
	d = fd if s < 0 else bd
	y = cy + d * math.copysign(abs(s) ** ex, s)
	return Vector((x, y, z))


def interp(zs, vs):
	"""Piecewise linear function through (zs[i], vs[i]) (zs ascending), clamped at the ends."""
	def f(z):
		if z <= zs[0]:
			return vs[0]
		for i in range(len(zs) - 1):
			if z <= zs[i + 1]:
				t = (z - zs[i]) / (zs[i + 1] - zs[i])
				return vs[i] + (vs[i + 1] - vs[i]) * t
		return vs[-1]
	return f


class Torso:
	"""The bare torso of a Look grown outward (grow + grow_fn(z)): points and normals by (angle,
	height), so straps, belts, buckles and patches can lie on a garment."""

	def __init__(self, L, grow, grow_fn=None):
		self.L = L
		self.g = grow
		self.grow_fn = grow_fn

	def dims(self, z):
		w, fd, bd = self.L.torso_at(z)
		g = self.g + (self.grow_fn(z) if self.grow_fn else 0.0)
		return w + g, fd + g, bd + g

	def pt(self, a, z, lift=0.0):
		w, fd, bd = self.dims(z)
		p = _ell(a, w, fd, bd, z)
		if lift:
			p = p + self.nrm(a, z) * lift
		return p

	def nrm(self, a, z):
		ta = self.pt(a + 1.0, z) - self.pt(a - 1.0, z)
		tz = self.pt(a, z + 0.005) - self.pt(a, z - 0.005)
		n = ta.cross(tz)
		return n.normalized() if n.length > 1e-9 else Vector((0, -1, 0))

	def ring(self, z, n=16, jag=None, extra=0.0):
		w, fd, bd = self.dims(z)
		return ring(z, w + extra, fd + extra, bd + extra, n=n, sq=SQ, jag=jag)


def frame_at(p, n, up=(0, 0, 1)):
	"""Local frame at p: x = side, y = up (projected), z = the normal n."""
	n = Vector(n).normalized()
	u = Vector(up)
	u = u - n * u.dot(n)
	if u.length < 1e-6:
		u = Vector((0, 1, 0)) - n * n.y
	u.normalize()
	s = u.cross(n)
	Mx = Matrix.Identity(4)
	for i in range(3):
		Mx[i][0], Mx[i][1], Mx[i][2], Mx[i][3] = s[i], u[i], n[i], p[i]
	return Mx


def place(geo, p, n, up=(0, 0, 1)):
	return xf(geo, frame_at(p, n, up))


def disc(r, thick, n=8):
	"""A flat round plate along local +Z (medallions, buckles, studs)."""
	return cyl((0, 0, 0), (0, 0, thick), r, n=n)


def path_az(ctrl, steps=1):
	out = []
	for i in range(len(ctrl) - 1):
		a0, z0 = ctrl[i]
		a1, z1 = ctrl[i + 1]
		for s in range(steps):
			t = s / steps
			out.append((a0 + (a1 - a0) * t, z0 + (z1 - z0) * t))
	out.append(ctrl[-1])
	return out


def strap_on(Tr, ctrl, width, lift=0.004, steps=1):
	"""A strap lying on the Torso surface Tr along control points (angle, height)."""
	pts, nrms = [], []
	for a, z in path_az(ctrl, steps):
		n = Tr.nrm(a, z)
		pts.append(Tr.pt(a, z) + n * lift)
		nrms.append(n)
	return ribbon(pts, width, nrms)


STRAP_FRONT = [(-46, 1.0), (-24, 1.06), (0, 1.13), (22, 1.21), (40, 1.29), (54, 1.37)]
STRAP_BACK = [(126, 1.37), (150, 1.26), (180, 1.14), (208, 1.06), (234, 1.0)]


def x_straps(L, name, Tr, material, width, lift=0.003):
	"""Two straps crossing on the chest and on the back (from the hips to under the collar)."""
	wt = pl_rig.w_torso(L.J)
	for sgn, lf in ((1.0, lift), (-1.0, lift + 0.003)):
		for part in (STRAP_FRONT, STRAP_BACK):
			L.add(name, strap_on(Tr, [(sgn * a, z) for a, z in part], width, lift=lf), material, wt)


def strap_z(a):
	"""Height of the front strap (STRAP_FRONT) at angle a (for studs / medallions on it)."""
	a = abs(a)
	pts = [(x, z) for x, z in STRAP_FRONT if x >= 0]
	for (a0, z0), (a1, z1) in zip(pts, pts[1:]):
		if a0 <= a <= a1:
			return z0 + (z1 - z0) * (a - a0) / (a1 - a0)
	return pts[-1][1]


def loft_rows(rows):
	"""Faces between rows of equal length ordered bottom -> top, points CCW seen from above (the
	faces point outward). Rows may be open arcs."""
	verts, faces, idx = [], [], []
	for r in rows:
		ids = []
		for p in r:
			ids.append(len(verts))
			verts.append(Vector(p))
		idx.append(ids)
	m = len(rows[0])
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		for k in range(m - 1):
			faces.append([a[k], a[k + 1], b[k + 1], b[k]])
	return verts, faces


def arc_row(z, w, fd, bd, n, opening=0.0, cy=0.0, jag=None, sq=SQ):
	"""n + 1 points from angle `opening` around the back to 360 - opening (a closed ring when the
	opening is 0: the first and last points meet at the front centre)."""
	row = []
	for j in range(n + 1):
		a = opening + (360.0 - 2.0 * opening) * j / n
		p = _ell(a, w, fd, bd, z, cy, sq)
		if jag is not None:
			p.z += jag(j, p.x, p.y)
		row.append(p)
	return row


def ang_of(x, y):
	return math.degrees(math.atan2(x, -y))


def dagged(points, amp, seed=0):
	"""jag() for torn cloth: every other vertex hangs lower, with some noise."""
	r = random.Random(seed)
	vals = [(-amp if k % 2 == 0 else -amp * 0.15) * (0.6 + 0.8 * r.random()) for k in range(points + 1)]
	return lambda k, x, y: vals[k % len(vals)]


def tufts_along(points, height, tuft, seed=0, closed=True, center=(0.0, 0.0), down=0.35, every=1, out_fn=None):
	"""Fur tufts (closed tetrahedra like pl_mesh.fur_ring) on the segments of a CCW polyline."""
	r = random.Random(seed)
	verts, faces = [], []
	m = len(points) if closed else len(points) - 1
	for k in range(0, m, every):
		p0 = Vector(points[k])
		p1 = Vector(points[(k + 1) % len(points)])
		mid = (p0 + p1) * 0.5
		if out_fn is not None:
			out = out_fn(mid)
		else:
			out = Vector((mid.x - center[0], mid.y - center[1], 0.0))
			out = out.normalized() if out.length > 1e-6 else Vector((0, -1, 0))
		h = height * (0.7 + 0.6 * r.random())
		tip = mid + out * (tuft * (0.6 + 0.8 * r.random())) + Vector((0, 0, -h * down))
		top = mid - out * 0.004 + Vector((0, 0, h * (1.0 - down)))
		i = len(verts)
		verts += [p0, p1, tip, top]
		faces += [[i, i + 1, i + 2], [i + 1, i, i + 3], [i, i + 2, i + 3], [i + 1, i + 3, i + 2]]
	return verts, faces


def stroke_quads(strokes, surf, lift=0.006, facing=(0, 1, 0)):
	"""Flat strokes ((x0, z0), (x1, z1), width) on a surface surf(x, z) -> point, facing outward."""
	verts, faces = [], []
	fv = Vector(facing)
	for (x0, z0), (x1, z1), wd in strokes:
		d = Vector((x1 - x0, z1 - z0))
		if d.length < 1e-6:
			continue
		d.normalize()
		nx, nz = -d.y * wd * 0.5, d.x * wd * 0.5
		c = [(x0 - nx, z0 - nz), (x1 - nx, z1 - nz), (x1 + nx, z1 + nz), (x0 + nx, z0 + nz)]
		pts = [surf(x, z) + fv * lift for x, z in c]
		i = len(verts)
		verts += pts
		f = [i, i + 1, i + 2, i + 3]
		if (pts[1] - pts[0]).cross(pts[3] - pts[0]).dot(fv) < 0:
			f.reverse()
		faces.append(f)
	return verts, faces


# ----------------------------------------------------------------------------------- weights

def w_hood(J):
	"""Head weights on the skull, torso weights on the neck and shoulders, blended at the neck."""
	wh = pl_rig.w_head(J)
	wt = pl_rig.w_torso(J)
	z0 = J["neck_z"] - 0.01
	z1 = J["head_z"] - 0.01

	def f(v):
		t = pl_rig.smoothstep(z0, z1, v.z)
		out = {}
		if t > 0.0:
			for b, x in wh(v).items():
				out[b] = out.get(b, 0.0) + x * t
		if t < 1.0:
			for b, x in wt(v).items():
				out[b] = out.get(b, 0.0) + x * (1.0 - t)
		return out
	return f


# ----------------------------------------------------------------------------------- heads

def head_dims(L):
	spec, top = L.head_spec()
	return max(s[1] for s in spec), max(s[2] for s in spec), max(s[3] for s in spec), top


def neck_r(L):
	return 0.055 if L.female else (0.066 if L.look == "m2" else 0.06)


HOOD_ROWS = [  # (z above head_z, width k, front k, back k, cy, face opening degrees)
	(0.262, 0.64, 0.5, 0.86, 0.036, 0),
	(0.232, 0.94, 0.86, 1.12, 0.024, 0),
	(0.195, 1.04, 0.98, 1.2, 0.012, 16),
	(0.15, 1.07, 1.03, 1.25, 0.004, 42),
	(0.1, 1.07, 1.03, 1.25, 0.0, 53),
	(0.045, 1.02, 0.98, 1.2, 0.0, 52),
	(-0.015, 0.96, 0.93, 1.12, 0.0, 40),
]


def hood_dims_at(L, rows, dz, g):
	"""(w, fd, bd, cy) of a hood made of `rows` at dz above head_z."""
	hw, hf, hb, _top = head_dims(L)
	rs = sorted(rows, key=lambda r: r[0])
	if dz <= rs[0][0]:
		r = rs[0]
	elif dz >= rs[-1][0]:
		r = rs[-1]
	else:
		for a, b in zip(rs, rs[1:]):
			if a[0] <= dz <= b[0]:
				t = (dz - a[0]) / (b[0] - a[0])
				r = tuple(a[i] + (b[i] - a[i]) * t for i in range(6))
				break
	return hw * r[1] + g, hf * r[2] + g, hb * r[3] + g, r[4]


def hood(L, name, material, g=0.03, n=12, rows=HOOD_ROWS, cap_grow=0.045, cap_drop=0.07, cap_jag=0.035, seed=1, top=True,
		peak_back=0.06, peak_up=-0.012):
	"""A hood pulled up: a dome over the skull with the face open, closing under the chin, flowing
	into a short ragged capelet over the shoulders."""
	J = L.J
	hz = J["head_z"]
	hw, hf, hb, htop = head_dims(L)
	k = 0.94 if L.female else 1.0
	head_rows = []
	for (dz, kw, kf, kb, cy, op) in rows:
		head_rows.append(arc_row(hz + dz * k, hw * kw + g, hf * kf + g, hb * kb + g, n, op, cy))
	# under the chin, round the neck base (outside the shoulders' slope)
	nz = J["neck_z"] + 0.012
	tw, tf, tb = L.torso_at(nz)
	nr = neck_r(L)
	neck = arc_row(nz, max(tw + g * 0.6, nr + g + 0.03), max(tf + g * 0.6, nr + g + 0.035), max(tb + g * 0.6, nr + g + 0.06), n)
	Tc = Torso(L, cap_grow)
	cz = J["shoulder_z"] + 0.005
	cap1 = arc_row(cz, *Tc.dims(cz), n)
	ez = J["shoulder_z"] - cap_drop
	w, fd, bd = Tc.dims(ez)
	cap2 = arc_row(ez, w + 0.012, fd + 0.012, bd + 0.012, n, jag=dagged(n, cap_jag, seed=seed))
	allrows = [cap2, cap1, neck] + list(reversed(head_rows))
	wf = w_hood(J)
	L.add(name, loft_rows(allrows[1:]), material, wf)
	L.add(name, double_sided(loft_rows(allrows[:2])), material, wf)
	if top:
		peak = V((0, hb * rows[0][3] * 0.5 + peak_back, hz + htop + g + peak_up))
		L.add(name, fan_cap(head_rows[0][:-1], peak), material, wf)


def round_dome(L, z_brim, grow, n=12, extra=0.012, thetas=(0.0, 30.0, 56.0, 76.0), grow_back=0.0, point=0.0):
	"""An ellipsoid helmet dome from the brim ring (z_brim above head_z) over the skull: rings and
	the top point."""
	hz = L.J["head_z"]
	spec, top = L.head_spec()
	w, fd, bd, cy = _interp_head(spec, z_brim)
	w, fd, bd = w + grow, fd + grow, bd + grow + grow_back
	H = top + grow + extra - z_brim
	rings = []
	for th in thetas:
		t = math.radians(th)
		c = math.cos(t)
		rings.append(ring(hz + z_brim + H * math.sin(t), w * c, fd * c, bd * c, n=n, cy=cy * c, sq=2.2))
	return rings, V((0, cy * 0.2 + 0.006, hz + z_brim + H + point)), (w, fd, bd, cy, H)


def ridge(points, r, n=4):
	return tube(points, [r] * len(points), n=n, side=(1, 0, 0))


# ----------------------------------------------------------------------------------- torso shapes

def cowl(L, name, material, n=16, grow=0.03, roll=0.035, drop=0.08, front_drop=0.07, back_drop=0.03, seed=3, jag_amp=0.035):
	"""A cloth cowl / scarf round the neck lying on the shoulders with a torn edge (hood down)."""
	J = L.J
	wt = pl_rig.w_torso(J)
	nr = neck_r(L)
	nz = J["neck_z"]
	top = ring(nz + 0.045, nr + roll * 0.7, nr + roll * 0.8, nr + roll * 0.75, n=n, sq=2.0)
	Tr = Torso(L, grow)
	w, fd, bd = Tr.dims(nz + 0.01)
	mid = ring(nz + 0.012, max(w, nr + roll * 1.6), max(fd, nr + roll * 1.7), max(bd, nr + roll * 1.6), n=n, sq=2.1)
	sz = J["shoulder_z"]
	sh = Tr.ring(sz - 0.005, n=n, extra=0.004)
	w, fd, bd = Tr.dims(sz - drop)
	jag0 = dagged(n, jag_amp, seed=seed)

	def jag(k, x, y):
		a = ang_of(x, y)
		f = math.exp(-(a / 40.0) ** 2) * front_drop + math.exp(-((abs(a) - 180.0) / 50.0) ** 2) * back_drop
		return jag0(k, x, y) - f
	edge = ring(sz - drop, w + 0.012, fd + 0.012, bd + 0.012, n=n, sq=SQ, jag=jag)
	L.add(name, rings_loft([sh, mid, top]), material, wt)
	L.add(name, double_sided(rings_loft([edge, sh])), material, wt)


def shell_rings(L, zs, gs, n=16, jag=None):
	out = []
	for i, (z, g) in enumerate(zip(zs, gs)):
		w, fd, bd = L.torso_at(z)
		out.append(ring(z, w + g, fd + g, bd + g, n=n, sq=SQ, jag=jag if i == 0 else None))
	return out


def skirt_dims(L, z_top, z_bot, grow, flare, steps=3, back=1.0):
	"""Ring sizes of a hem from the waist down (like Look.skirt): [(z, w, fd, bd)] top -> bottom.
	back scales the flare toward the back (a cloak hangs there)."""
	zs = [z_top + (z_bot - z_top) * i / steps for i in range(steps + 1)]
	w0, f0, b0 = L.torso_at(min(z_top, 0.93))
	out = []
	for i, z in enumerate(zs):
		t = i / steps
		bw, bf, bb = L.torso_at(z) if z > 0.84 else (w0, f0, b0)
		k = grow + flare * t
		kb = grow + (flare * t + 0.03 * t) * back
		out.append((z, max(bw, w0 * 0.98) + k + 0.02 * t, bf + k + 0.03 * t, bb + kb))
	return out


def coat_skirt(L, name, material, z_top, z_bot, grow, flare, n=16, slit=1, jag=None, steps=3, back=1.0):
	"""A coat hem (double sided, w_skirt) with a front slit of `slit` segments each side."""
	dims = skirt_dims(L, z_top, z_bot, grow, flare, steps, back)
	rings = [ring(z, w, fd, bd, n=n, sq=2.05, jag=jag if i == len(dims) - 1 else None) for i, (z, w, fd, bd) in enumerate(dims)]
	ws = pl_rig.w_skirt(L.J)
	if slit:
		L.add(name, _open_front(list(reversed(rings)), open_k=slit, double=True, open_at=0), material, ws)
	else:
		L.add(name, double_sided(rings_loft(list(reversed(rings)))), material, ws)
	return dims, rings


def slit_borders(L, name, material, rings, width, slit=1, lift=0.004):
	"""Trim strips down both edges of a coat's front slit (rings from coat_skirt, top -> bottom)."""
	n = len(rings[0])
	for e in (slit, n - slit):
		pts, nrms = [], []
		for r in rings:
			p = r[e]
			o = V((p.x, p.y, 0.0)).normalized()
			pts.append(p + o * lift)
			nrms.append(o)
		L.add(name, ribbon(pts, width, nrms), material, pl_rig.w_skirt(L.J))


def hem_band(L, name, material, dims, z0, z1, extra=0.005, n=16, slit=1):
	"""A trim band on a coat hem between heights z0 < z1 (dims from skirt_dims)."""
	def at(z):
		zs = [d[0] for d in reversed(dims)]
		f = [interp(zs, [d[i] for d in reversed(dims)]) for i in (1, 2, 3)]
		return f[0](z) + extra, f[1](z) + extra, f[2](z) + extra
	r0 = ring(z0, *at(z0), n=n, sq=2.05)
	r1 = ring(z1, *at(z1), n=n, sq=2.05)
	geo = _open_front([r0, r1], open_k=slit, double=False, open_at=0) if slit else rings_loft([r0, r1])
	L.add(name, geo, material, pl_rig.w_skirt(L.J))


def belt(L, name, material, z0, z1, grow, n=16):
	Tr = Torso(L, grow)
	L.add(name, rings_loft([Tr.ring(z0, n=n), Tr.ring(z1, n=n)]), material, pl_rig.w_torso(L.J))
	return Tr


def on_surface(L, name, geo, material, Tr, a, z, lift=0.0, up=(0, 0, 1), weights=None):
	n = Tr.nrm(a, z)
	L.add(name, place(geo, Tr.pt(a, z) + n * lift, n, up), material, weights or pl_rig.w_torso(L.J))


def pouch(L, name, m_body, m_flap, Tr, a, z, w=0.075, h=0.085, d=0.04, weights=None):
	"""A leather pouch hanging from a belt at angle a (top at z)."""
	on_surface(L, name, box((w, h, d), center=(0, -h * 0.5, d * 0.5)), m_body, Tr, a, z, weights=weights)
	on_surface(L, name, box((w * 1.06, h * 0.42, d * 1.12), center=(0, -h * 0.2, d * 0.56), top=(1.0, 0.8)), m_flap, Tr, a, z,
		weights=weights)


def mantle(L, name, fur, fur2, reach=0.1, thick=0.055, drop_front=0.2, drop_side=0.15, drop_back=0.26, n=18, seed=5,
		tuft=0.05, tuft_h=0.07, ruff=True, extra_row=False, collar=0.05, opening=(0.0, 14.0, 26.0, 34.0)):
	"""A fur mantle / pelt over the shoulders and upper arms, open at the front: a collar round the
	neck, a shelf over the shoulders, the pelt over the arms, a ragged tufted edge (w_torso).
	opening: the front opening (degrees each side) of the collar, shelf, arm and edge rows."""
	J = L.J
	wt = pl_rig.w_torso(J)
	sx = J["p"]["shoulder_x"]
	sz = J["shoulder_z"]
	nz = J["neck_z"]
	nr = neck_r(L)
	top = arc_row(nz + 0.045, nr + collar, nr + collar + 0.008, nr + collar + 0.04, n, opening[0], sq=2.0)
	w, fd, bd = L.torso_at(sz + 0.03)
	shelf = arc_row(sz + 0.04, max(w, sx) + reach * 0.62, fd + thick, bd + thick, n, opening[1], sq=2.7)
	w, fd, bd = L.torso_at(sz - 0.07)
	arm = arc_row(sz - 0.07, max(w, sx) + reach, fd + thick + 0.012, bd + thick + 0.018, n, opening[2], sq=2.4)
	r = random.Random(seed)
	tears = [r.random() for _ in range(n + 1)]

	def jag(k, x, y):
		a = abs(ang_of(x, y))
		ff = math.exp(-(a / 45.0) ** 2)
		fb = math.exp(-((a - 180.0) / 55.0) ** 2)
		base = -(drop_side + (drop_front - drop_side) * ff + (drop_back - drop_side) * fb)
		return base + 0.07 - (0.035 if k % 2 == 0 else 0.0) * (0.5 + tears[k % (n + 1)])
	w, fd, bd = L.torso_at(max(sz - drop_side, 1.0))
	edge = arc_row(sz - 0.07, max(w, sx) + reach + 0.012, fd + thick + 0.02, bd + thick + 0.026, n, opening[3], sq=2.3, jag=jag)
	rows = [edge, arm, shelf, top]
	L.add(name, double_sided(loft_rows(rows)), fur, wt)
	inner = arc_row(nz + 0.04, nr + 0.012, nr + 0.014, nr + 0.014, n, opening[0], sq=2.0)
	L.add(name, loft_rows([top, inner]), fur, wt)
	L.add(name, tufts_along(edge, tuft_h, tuft, seed=seed + 1, closed=False), fur2, wt)
	if ruff:
		L.add(name, tufts_along(top, tuft_h * 0.8, tuft * 0.7, seed=seed + 2, every=2, down=0.2, closed=False), fur2, wt)
	if extra_row:
		L.add(name, tufts_along(arm, tuft_h, tuft * 0.8, seed=seed + 3, every=1, down=0.3, closed=False), fur, wt)
	# fur along the two front edges
	for j in (0, len(edge) - 1):
		col = [rows[i][j] for i in range(4)]
		out = V((0, -1, 0))
		L.add(name, tufts_along(col, tuft_h * 0.7, tuft * 0.6, seed=seed + 4 + j, closed=False, out_fn=lambda m: out, down=0.1), fur2, wt)
	return edge


CLOAK_POW = 1.3      # the drape grows as t^CLOAK_POW down the cloak (the top stays under mantles)
CLOAK_TOP_CURVE = 0.35


def cloak_rows(L, width_top, width_bot, z_bot, drape=0.05, n=6, curve=0.35, jag=None, top_y=0.0):
	"""Rows like Look.cape (a sheet hanging from the shoulders down the back), top -> bottom; the
	drape grows as t^CLOAK_POW and the top bulges less (it hides under mantles)."""
	J = L.J
	top = J["cape_top"]
	zs = [top.z, top.z - 0.12, 1.1, 0.8, 0.5, z_bot]
	zs = sorted(set(z for z in zs if z >= z_bot), reverse=True)
	if zs[-1] != z_bot:
		zs.append(z_bot)
	rows = []
	for i, z in enumerate(zs):
		t = (top.z - z) / max(0.01, top.z - z_bot)
		w = width_top + (width_bot - width_top) * min(1.0, t * 1.6)
		_w, _fd, bd = L.torso_at(max(z, 1.0))
		y0 = bd + 0.02 + drape * t ** CLOAK_POW + (top_y if i == 0 else 0.0)
		row = []
		for k in range(n + 1):
			u = -1.0 + 2.0 * k / n
			x = u * w
			y = y0 + curve * w * (1 - u * u) * (CLOAK_TOP_CURVE if z > 1.2 else 0.25)
			dz = jag(k, x, y) if (jag is not None and i == len(zs) - 1) else 0.0
			row.append(V((x, y, z + dz)))
		rows.append(row)
	return rows


def drape_over(L, dims, z_bot, width_top, width_bot, curve=0.35, margin=0.012, minimum=0.05):
	"""The cloak drape (Look.cape / cloak_rows) that keeps the cloak's back centre outside a coat
	hem (dims from skirt_dims) by `margin`."""
	top = L.J["cape_top"]
	need = minimum
	for (z, w, fd, bd) in dims:
		if z < z_bot:
			continue
		t = (top.z - z) / max(0.01, top.z - z_bot)
		wc = width_top + (width_bot - width_top) * min(1.0, t * 1.6)
		bulge = curve * wc * (CLOAK_TOP_CURVE if z > 1.2 else 0.25)
		y0 = L.torso_at(max(z, 1.0))[2] + 0.02
		need = max(need, (bd + margin - bulge - y0) / max(t, 0.05) ** CLOAK_POW)
	return need


def cloak_geo(rows):
	verts, faces = [], []
	for row in rows:
		verts.extend(row)
	w_ = len(rows[0])
	for i in range(len(rows) - 1):
		for k in range(w_ - 1):
			a = i * w_ + k
			faces.append([a + w_, a + w_ + 1, a + 1, a])
	return double_sided((verts, faces))


def cloak_surf(rows):
	"""surf(x, z) -> the point on a cloak (rows top -> bottom, before the hem's jag)."""
	def row_at(row, x):
		if x <= row[0].x:
			return row[0].copy()
		for a, b in zip(row, row[1:]):
			if a.x <= x <= b.x:
				t = (x - a.x) / max(1e-9, b.x - a.x)
				return a.lerp(b, t)
		return row[-1].copy()

	def f(x, z):
		for i in range(len(rows) - 1):
			z0, z1 = rows[i][0].z, rows[i + 1][0].z
			if z1 <= z <= z0 or i == len(rows) - 2:
				t = (z0 - z) / max(1e-9, z0 - z1)
				p = row_at(rows[i], x).lerp(row_at(rows[i + 1], x), t)
				p.z = z
				return p
		return row_at(rows[0], x)
	return f


def cloak(L, name, material, emblem_m, strokes, width_top=0.2, width_bot=0.3, z_bot=0.35, drape=0.06, n=6, curve=0.35, jag=None,
		border=None, top_y=0.0):
	rows = cloak_rows(L, width_top, width_bot, z_bot, drape, n, curve, jag, top_y)
	wc = pl_rig.w_cape(L.J)
	L.add(name, cloak_geo(rows), material, wc)
	surf = cloak_surf(rows)
	if strokes:
		L.add(name, stroke_quads(strokes, surf, lift=0.006), emblem_m, wc)
	if border is not None:
		bm, bz, bw = border
		row = rows[-1]
		pts = [surf(p.x * 0.97, max(p.z, z_bot) + bz) for p in row]
		L.add(name, ribbon([p + V((0, 0.007, 0)) for p in pts], bw, (0, 1, 0)), bm, wc)
	return rows


# ----------------------------------------------------------------------------------- arms / legs

def bracer(L, side, t0, t1, grow, taper=0.004, n=8, steps=2):
	"""A bracer round the forearm from t0 to t1 (grow outside the skin, less by `taper` at t1; thick
	enough to hold sleeve ends tucked in). Returns (geometry, grow_at(t))."""
	pts = L.arm_path(side, t0, t1, steps=steps)
	rr = []
	for i in range(steps + 1):
		t = t0 + (t1 - t0) * i / steps
		a, b = L.arm_radius(t)
		k = grow - taper * i / steps
		rr.append((a + k, b + k))
	return tube(pts, rr, n=n, side=(0, -1, 0), cap0=False, cap1=False), lambda t: grow - taper * (t - t0) / (t1 - t0)


def arm_band(L, side, t, width, grow, n=8):
	"""A thin ring round the arm at t (trims, cuffs)."""
	pts = L.arm_path(side, t - width * 0.5, t + width * 0.5, steps=1)
	a, b = L.arm_radius(t)
	return tube(pts, [(a + grow, b + grow)] * 2, n=n, side=(0, -1, 0), cap0=False, cap1=False)


def arm_plate(L, side, t, grow, out=(1.0, 0.3)):
	"""(point, outward normal, direction along the arm) for a plate on the outer side of the arm at t."""
	sx = -1.0 if side == "r" else 1.0
	pts = L.arm_path(side, t - 0.02, t + 0.02, steps=1)
	c = (pts[0] + pts[1]) * 0.5
	d = (pts[1] - pts[0]).normalized()
	o = V((sx * out[0], out[1], 0.0))
	o = (o - d * o.dot(d)).normalized()
	a, b = L.arm_radius(t)
	return c + o * ((a + b) * 0.5 + grow), o, d


def trouser_clear(L, z, clear=0.012):
	"""Radius a boot shaft needs at height z to cover the default trousers (and the shin)."""
	baggy = 0.95 if L.female else 1.02
	r = max(L.trouser_radius(zz, baggy) for zz in (z - 0.03, z, z + 0.03))
	return r + clear


def shaft_r(L, z, clear=0.014):
	"""Boot shaft radius at z: over the default trousers above their hem, narrowing to the ankle."""
	bottom = 0.24 if L.look == "m2" else 0.2
	ank = (0.06 if L.female else 0.064) + clear * 0.25
	zb = bottom - 0.03
	if z >= zb:
		return max(ank, trouser_clear(L, z, clear))
	top_r = max(ank, trouser_clear(L, zb, clear))
	t = max(0.0, min(1.0, (z - 0.08) / (zb - 0.08)))
	return ank + (top_r - ank) * t


def boot_shaft(L, side, top, clear=0.014, steps=5, n=8):
	zs = [top + (0.05 - top) * i / steps for i in range(steps + 1)]
	pts = [leg_point(L, side, z) for z in zs]
	rr = []
	for p in pts:
		r = shaft_r(L, p.z, clear)
		rr.append((r, r * 1.04))
	return tube(pts, rr, n=n, side=(0, -1, 0), cap0=False, cap1=False)


def laces(L, side, z0, z1, count, clear, width=0.02, slant=18.0, n=6, extra=0.005):
	"""Cross-lacing round a boot shaft: slanted bands alternating direction (an X from the front)."""
	out = []
	for i in range(count):
		z = z0 + (z1 - z0) * (i + 0.5) / count
		c = leg_point(L, side, z)
		r = shaft_r(L, z, clear) + extra
		sl = math.tan(math.radians(slant) * (1 if i % 2 == 0 else -1))
		ra, rb = [], []
		for k in range(n):
			a = 2.0 * math.pi * k / n
			ca, sa = math.cos(a), math.sin(a)
			dz = sl * r * ca
			ra.append(V((c.x + r * ca, c.y + r * 1.04 * sa, z - width * 0.5 + dz)))
			rb.append(V((c.x + r * 1.03 * ca, c.y + r * 1.07 * sa, z + width * 0.5 + dz)))
		out.append(rings_loft([ra, rb]))
	return merge(*out)


def shoe(L, name, side, material, sole_m, h=0.1, w=None, toe_h=0.045, sole=0.022, heel_back=0.03, toe_out=0.028):
	"""A boot foot: a tapered tube from the heel to a rounded toe over a flat sole (w_leg)."""
	J = L.J
	if w is None:
		w = 0.062 if L.female else 0.066
	ank, hl, toe, ball = J["ankle_" + side], J["heel_" + side], J["toe_" + side], J["ball_" + side]
	x = ank.x
	yb = hl.y + heel_back
	yt = toe.y - toe_out
	pts = [V((x, yb, h * 0.5)), V((x, ank.y, h * 0.52)), V((x, ball.y, toe_h * 0.62 + 0.012)), V((x, yt + 0.02, toe_h * 0.5)),
		V((x, yt, toe_h * 0.42))]
	rr = [(w * 0.8, h * 0.5), (w, h * 0.52), (w * 1.02, toe_h * 0.62 + 0.012), (w * 0.82, toe_h * 0.5), (w * 0.45, toe_h * 0.3)]
	wl = pl_rig.w_leg(J, side)
	L.add(name, tube(pts, rr, n=6, side=(1, 0, 0)), material, wl)
	# the sole bends at the ball like the foot (bottom at z = 0 at rest)
	L.add(name, foot_box((w * 2.1, yb - yt + 0.012, sole), center=(x, (yb + yt) * 0.5, sole * 0.5), top=(1.0, 0.97),
		cuts=[ball.y]), sole_m, wl)
	return yb, yt


def leg_point(L, side, z):
	return L.leg_path(side, z, z, steps=1)[0]


def fur_cuff(L, name, side, z, fur, fur2, r_extra=0.02, h=0.045, tufts=9, seed=0):
	c = leg_point(L, side, z)
	r = shaft_r(L, z, r_extra)
	wl = pl_rig.w_leg(L.J, side)
	L.add(name, band((c.x, c.y, 0), r, r * 1.05, z - h * 0.5, z + h * 0.5, n=8, bulge=0.006), fur, wl)
	pts = ring(z - h * 0.45, r + 0.004, r * 1.05 + 0.004, n=tufts, cy=c.y, cx=c.x, sq=2.0)
	L.add(name, tufts_along(pts, h * 1.2, 0.022, seed=seed, center=(c.x, c.y), down=0.55), fur2, wl)


def strap_band(L, side, z, width, clear, n=7):
	"""A strap round the boot shaft at z."""
	c = leg_point(L, side, z)
	r = shaft_r(L, z, clear)
	return band((c.x, c.y, 0), r, r * 1.05, z - width * 0.5, z + width * 0.5, n=n)


def buckle_at(L, side, z, clear, size=0.022, thick=0.006):
	"""A small buckle on the outer front of a strap round the boot shaft."""
	sx = -1.0 if side == "r" else 1.0
	c = leg_point(L, side, z)
	r = shaft_r(L, z, clear)
	n = V((sx * 0.9, -0.44, 0.0)).normalized()
	p = V((c.x, c.y, z)) + n * r
	return place(box((size, size * 0.9, thick), center=(0, 0, thick * 0.5)), p, n)


# ----------------------------------------------------------------------------------- tier 1

def helm_1(L, reg):
	J = L.J
	name = reg.piece("helm", FAM, 1, hides=["HairTop", "HairBack"], notes="common hunter: green hood, leather brow band")
	g = 0.03
	hood(L, name, M("green"), g=g, n=12, seed=11)
	hz = J["head_z"]
	wh = pl_rig.w_head(J)
	k = 0.94 if L.female else 1.0
	d0 = hood_dims_at(L, HOOD_ROWS, 0.19, g + 0.007)
	d1 = hood_dims_at(L, HOOD_ROWS, 0.224, g + 0.007)
	b0 = ring(hz + 0.19 * k, d0[0], d0[1], d0[2], n=12, sq=SQ, cy=d0[3])
	b1 = ring(hz + 0.224 * k, d1[0], d1[1], d1[2], n=12, sq=SQ, cy=d1[3])
	L.add(name, rings_loft([b0, b1]), TINT("helm", 1, 0.8), wh)
	fy = ((d0[3] - d0[1]) + (d1[3] - d1[1])) * 0.5 - 0.004
	L.add(name, octa(0.011, center=(0, fy, hz + 0.207 * k), scale=(1, 0.6, 1)), M("iron"), wh)


def chest_1(L, reg):
	J = L.J
	name = reg.piece("chest", FAM, 1, hides=CHEST_HIDES, notes="common hunter: leather vest over a long linen shirt, green cowl, straps")
	wt = pl_rig.w_torso(J)
	leather = TINT("chest", 1, 0.8)
	dark = TINT("chest", 1, 0.45, "dark")
	linen = M("linen")
	strap_m = M("strap")
	iron = M("iron")
	# the linen shirt: sleeves torn below the elbow, a long ragged hem below the vest
	for side in ("r", "l"):
		geo = L.sleeve(side, 0.0, 0.78, 0.013, steps=5, n=8, flare=0.014)
		L.add(name, _jag_end(geo, 8, 0.035, seed=61 if side == "r" else 62), linen, pl_rig.w_arm(J, side))
	hem_z = 0.72 if L.female else 0.7
	L.add(name, L.skirt(1.0, hem_z, 0.016, n=16, flare=0.03, jag=sawtooth(16, 0.05, rnd=0.04, seed=63)), linen,
		pl_rig.w_skirt_legs(J, share=0.25))
	# the vest: stitched leather, the hem flared over the shirt and cut in two front points
	zs = [0.875, 0.955, 1.05, 1.15, 1.25, 1.33, 1.4, 1.445]
	gs = [0.058, 0.04, 0.027, 0.024, 0.024, 0.024, 0.022, 0.02]
	rng = random.Random(64)
	tears = [rng.random() for _ in range(16)]

	def vjag(k, x, y):
		a = ang_of(x, y)
		return -math.exp(-((abs(a) - 24.0) / 13.0) ** 2) * 0.06 - (0.03 * tears[k % 16] if k % 2 else 0.0)
	L.add(name, rings_loft(shell_rings(L, zs, gs, n=16, jag=vjag)), leather, wt)
	Tv = Torso(L, 0.0, grow_fn=interp(zs, gs))
	for a, z, w, h in ((-32, 1.12, 0.07, 0.06), (38, 1.02, 0.06, 0.05), (150, 1.22, 0.09, 0.07), (-120, 1.05, 0.05, 0.06)):
		L.add(name, patch(Tv.pt(a, z), Tv.nrm(a, z), w, h, lift=0.004), dark, wt)
	L.add(name, strap_on(Tv, [(0, 1.0), (0, 1.1), (0, 1.2), (0, 1.33)], 0.012, lift=0.004), strap_m, wt)
	# crossed straps (front and back; their ends hide under the cowl) with an iron ring where they cross
	Ts = Torso(L, 0.004, grow_fn=interp(zs, gs))
	x_straps(L, name, Ts, strap_m, 0.034)
	on_surface(L, name, disc(0.024, 0.008, n=8), iron, Ts, 0, strap_z(0), lift=0.006)
	cowl(L, name, M("green"), n=16, grow=0.03, seed=65)
	Tb = belt(L, name, M("belt"), 0.97, 1.03, 0.038)
	on_surface(L, name, box((0.05, 0.05, 0.012), center=(0, 0, 0.006)), iron, Tb, -6, 1.0)
	pouch(L, name, leather, dark, Tb, -42, 0.99)
	pouch(L, name, leather, dark, Tb, 118, 0.99, w=0.06, h=0.07, d=0.035)


def gloves_1(L, reg):
	J = L.J
	name = reg.piece("gloves", FAM, 1, notes="common hunter: leather gloves, wrapped bracers")
	glove = TINT("gloves", 1, 0.5)
	light = TINT("gloves", 1, 0.75, "light")
	for side in ("r", "l"):
		L.glove(side, glove, grow=0.009, part=name)
		wa = pl_rig.w_arm(J, side)
		geo, gt = bracer(L, side, 0.66, 0.99, 0.03, taper=0.01, n=8, steps=2)
		L.add(name, geo, light, wa)
		p0, p1 = L.arm_path(side, 0.69, 0.95, steps=1)
		ra = sum(L.arm_radius(0.69)) * 0.5 + gt(0.69) + 0.003
		rb = sum(L.arm_radius(0.95)) * 0.5 + gt(0.95) + 0.003
		L.add(name, wrap_bands(p0, p1, ra, rb, 3, width=0.022, n=6, slant=24.0, side=(0, -1, 0)), M("strap"), wa)


def boots_1(L, reg):
	J = L.J
	name = reg.piece("boots", FAM, 1, notes="common hunter: tall laced boots with fur cuffs")
	leather = TINT("boots", 1, 0.55)
	top = 0.4
	for side in ("r", "l"):
		wl = pl_rig.w_leg(J, side)
		shoe(L, name, side, leather, M("sole"))
		L.add(name, boot_shaft(L, side, top, 0.014, steps=4), leather, wl)
		L.add(name, laces(L, side, 0.11, top - 0.04, 5, 0.014, width=0.018, slant=20.0), M("strap"), wl)
		fur_cuff(L, name, side, top, M("fur"), M("fur"), seed=71 if side == "r" else 72)


# ----------------------------------------------------------------------------------- tier 2

T2_HOOD = [  # the dark green hood under the steel cap (only the part below the cap)
	(0.162, 1.0, 0.97, 1.12, 0.004, 30),
	(0.1, 1.04, 1.0, 1.16, 0.0, 52),
	(0.045, 1.0, 0.97, 1.12, 0.0, 51),
	(-0.015, 0.95, 0.92, 1.06, 0.0, 40),
]


def helm_2(L, reg):
	J = L.J
	name = reg.piece("helm", FAM, 2, hides=["HairTop", "HairBack"], notes="rare ranger: gold-banded steel cap, cheek flaps, dark green hood")
	hz = J["head_z"]
	wh = pl_rig.w_head(J)
	k = 0.94 if L.female else 1.0
	hood(L, name, M("coat"), g=0.022, n=12, rows=T2_HOOD, cap_grow=0.05, cap_drop=0.08, cap_jag=0.03, seed=21, top=False)
	steel, gold = M("steel"), M("gold")
	zb = 0.166 * k
	rr, top, (w, fd, bd, cy, H) = round_dome(L, zb, 0.036, n=12, extra=0.012, point=0.022)
	L.add(name, merge(rings_loft(rr), fan_cap(rr[-1], top)), steel, wh)
	# gold brim band, four bands meeting at a finial, the nasal
	c1 = math.cos(math.asin(min(1.0, 0.024 / H)))
	b0 = ring(hz + zb - 0.012, w + 0.008, fd + 0.008, bd + 0.008, n=12, cy=cy, sq=2.2)
	b1 = ring(hz + zb + 0.024, w * c1 + 0.008, fd * c1 + 0.008, bd * c1 + 0.008, n=12, cy=cy * c1, sq=2.2)
	L.add(name, rings_loft([b0, b1]), gold, wh)
	for ang in (0.0, 90.0):
		line = [_nearest_on_ring(r_, ang) for r_ in rr[1:]] + [top] + [_nearest_on_ring(r_, ang + 180.0) for r_ in reversed(rr[1:])]
		line = [p + (p - V((0, 0.0, hz + 0.1))).normalized() * 0.005 for p in line]
		L.add(name, ridge(line, 0.009, n=3), gold, wh)
	L.add(name, octa(0.016, center=tuple(top + V((0, 0, 0.01))), scale=(1, 1, 1.3)), gold, wh)
	p0 = V((0, cy - fd - 0.012, hz + zb + 0.005))
	p1 = V((0, -0.125 * k - 0.012, hz + 0.078 * k))
	L.add(name, cyl(p0, p1, 0.014, 0.01, n=4, side=(1, 0, 0)), gold, wh)
	# leather cheek flaps with a rivet
	leather = TINT("helm", 2, 0.55)
	hw = head_dims(L)[0]
	for sx in (-1.0, 1.0):
		c = V((sx * (hw + 0.034), -0.03 * k, hz + 0.1 * k))
		flap = box((0.014, 0.07 * k, 0.12 * k), center=(0, 0, -0.06 * k), top=(1.0, 0.8), shift=(0, 0.004))
		L.add(name, xf(flap, T(c) @ R(0, sx * 7.0, 0)), leather, wh)


def _nearest_on_ring(r, ang):
	"""The point of a ring (from pl_mesh.ring: CCW from the front centre) at angle ang (degrees)."""
	n = len(r)
	f = (ang % 360.0) / 360.0 * n
	i = int(f) % n
	t = f - int(f)
	return r[i].lerp(r[(i + 1) % n], t)


def tree_strokes(x0, z0, h, spread, w=0.016, levels=3, roots=True):
	"""A stylised tree (trunk, upward branches, roots) as strokes for stroke_quads."""
	s = [((x0, z0), (x0, z0 + h), w)]
	for i in range(levels):
		zb = z0 + h * (0.35 + 0.2 * i)
		ln = spread * (1.0 - 0.22 * i)
		for sx in (-1.0, 1.0):
			s.append(((x0, zb), (x0 + sx * ln, zb + ln * 0.9), w * 0.75))
	if roots:
		for sx in (-1.0, 1.0):
			s.append(((x0, z0 + h * 0.08), (x0 + sx * spread * 0.6, z0 - h * 0.08), w * 0.7))
	return s


def chest_2(L, reg):
	J = L.J
	name = reg.piece("chest", FAM, 2, hides=CHEST_HIDES,
		notes="rare ranger: dark green coat with gold borders, fur mantle, harness, green cloak with a tree emblem")
	wt = pl_rig.w_torso(J)
	coat, gold = M("coat"), M("gold")
	leather = TINT("chest", 2, 0.55)
	# coat body, knee-long hem with a front slit and a gold border
	zs = [0.9, 1.0, 1.1, 1.2, 1.3, 1.38, 1.43, 1.458]
	gs = [0.04, 0.03, 0.022, 0.02, 0.02, 0.02, 0.018, 0.016]
	L.add(name, rings_loft(shell_rings(L, zs, gs, n=16)), coat, wt)
	hem = 0.52 if L.female else 0.5
	dims, srings = coat_skirt(L, name, coat, 1.0, hem, 0.034, 0.07, n=16, slit=1, back=0.6)
	hem_band(L, name, gold, dims, hem + 0.004, hem + 0.036, extra=0.004, slit=1)
	hem_band(L, name, M("thread"), dims, hem + 0.05, hem + 0.062, extra=0.004, slit=1)
	slit_borders(L, name, gold, srings, 0.024)
	Tc = Torso(L, 0.002, grow_fn=interp(zs, gs))
	L.add(name, strap_on(Tc, [(0, 1.04), (0, 1.14), (0, 1.25), (0, 1.36)], 0.026, lift=0.002), gold, wt)
	# sleeves: coat sleeves to the elbow with a gold border, dark leather under-sleeves
	for side in ("r", "l"):
		wa = pl_rig.w_arm(J, side)
		L.add(name, L.sleeve(side, 0.0, 0.47, 0.02, steps=3, n=8, flare=0.016), coat, wa)
		L.add(name, arm_band(L, side, 0.45, 0.04, 0.036), gold, wa)
		L.add(name, L.sleeve(side, 0.4, 0.8, 0.01, steps=2, n=8, flare=0.004), leather, wa)
	# harness: crossed straps + gold studs, belt with a round gold buckle and pouches
	Ts = Torso(L, 0.004, grow_fn=interp(zs, gs))
	x_straps(L, name, Ts, leather, 0.036)
	on_surface(L, name, disc(0.026, 0.01, n=8), gold, Ts, 0, strap_z(0), lift=0.008)
	Tb = belt(L, name, M("belt"), 0.975, 1.045, 0.05)
	on_surface(L, name, disc(0.034, 0.012, n=10), gold, Tb, 0, 1.01)
	pouch(L, name, leather, M("belt"), Tb, -38, 0.995, w=0.07, h=0.08, d=0.04)
	pouch(L, name, leather, M("belt"), Tb, 42, 0.995, w=0.06, h=0.07, d=0.036)
	pouch(L, name, leather, M("belt"), Tb, 106, 0.995, w=0.08, h=0.06, d=0.045)
	# fur mantle and the cloak with a tree emblem
	mantle(L, name, M("fur_brown"), M("fur_light"), reach=0.1, thick=0.055, drop_front=0.2, drop_side=0.15, drop_back=0.28,
		n=18, seed=25, tuft=0.05, tuft_h=0.07, extra_row=True)
	strokes = tree_strokes(0.0, 0.58, 0.46, 0.115, w=0.024)
	cz = 0.33 if not L.female else 0.36
	cloak(L, name, M("cloak"), M("thread"), strokes, width_top=0.2, width_bot=0.3, z_bot=cz,
		drape=drape_over(L, dims, cz, 0.2, 0.3, margin=0.016), n=6, curve=0.35, jag=lambda k, x, y: -0.12 * (1.0 - abs(x) / 0.3) + (0.02 if k % 2 else 0.0),
		border=(gold, 0.05, 0.02))


def gloves_2(L, reg):
	J = L.J
	name = reg.piece("gloves", FAM, 2, notes="rare ranger: runed leather bracers with gold trim, dark gloves")
	leather = TINT("gloves", 2, 0.55)
	gold = M("gold")
	for side in ("r", "l"):
		wa = pl_rig.w_arm(J, side)
		L.glove(side, M("glove_dark"), grow=0.009, part=name)
		geo, gt = bracer(L, side, 0.6, 0.97, 0.03, taper=0.008, n=8, steps=2)
		L.add(name, geo, leather, wa)
		L.add(name, arm_band(L, side, 0.615, 0.03, gt(0.615) + 0.005), gold, wa)
		L.add(name, arm_band(L, side, 0.955, 0.03, gt(0.955) + 0.005), gold, wa)
		p, o, d = arm_plate(L, side, 0.78, 0.03)
		L.add(name, place(box((0.012, 0.1, 0.006), center=(0, 0, 0.003)), p, o, d), gold, wa)
		for dz, ang in ((0.025, 35.0), (-0.025, -35.0)):
			q = p + d * dz
			L.add(name, xf(place(box((0.01, 0.045, 0.005), center=(0, 0, 0.003)), V((0, 0, 0)), o, d),
				T(q) @ _rot_about(o, ang)), gold, wa)


def _rot_about(axis, deg):
	return Matrix.Rotation(math.radians(deg), 4, Vector(axis))


def boots_2(L, reg):
	J = L.J
	name = reg.piece("boots", FAM, 2, notes="rare ranger: tall laced boots, fur cuffs, bronze buckles")
	leather = TINT("boots", 2, 0.45)
	bronze = M("bronze")
	top = 0.43
	for side in ("r", "l"):
		wl = pl_rig.w_leg(J, side)
		shoe(L, name, side, leather, M("sole"), h=0.105)
		L.add(name, boot_shaft(L, side, top, 0.015, steps=4), leather, wl)
		L.add(name, laces(L, side, 0.15, top - 0.05, 4, 0.015, width=0.018, slant=22.0), M("strap"), wl)
		L.add(name, strap_band(L, side, 0.1, 0.026, 0.02), M("belt"), wl)
		L.add(name, buckle_at(L, side, 0.1, 0.022), bronze, wl)
		fur_cuff(L, name, side, top, M("fur_brown"), M("fur_light"), r_extra=0.024, h=0.055, tufts=10, seed=81 if side == "r" else 82)


# ----------------------------------------------------------------------------------- tier 3

def wing(sx, scale=1.0):
	"""A gold wing (3 feathers), in the YZ plane: grows back (+Y) and up from the origin."""
	poly = [(0.0, 0.0), (0.035, 0.0), (0.07, 0.028), (0.068, 0.05), (0.1, 0.07), (0.092, 0.095), (0.125, 0.125), (0.1, 0.14),
		(0.125, 0.19), (0.07, 0.15), (0.03, 0.1), (0.0, 0.045)]
	poly = [(y * scale, z * scale) for y, z in poly]
	return slab(poly, 0.014, axis="x")


def helm_3(L, reg):
	J = L.J
	name = reg.piece("helm", FAM, 3, hides=["HairTop"], notes="unique frostbound: dark winged helm, gold brow arches, nasal, cheek guards")
	hz = J["head_z"]
	wh = pl_rig.w_head(J)
	steel, gold = M("steel_dark"), M("gold")
	k = 0.94 if L.female else 1.0
	zb = 0.164 * k
	rr, top, (w, fd, bd, cy, H) = round_dome(L, zb, 0.034, n=12, extra=0.016, point=0.03, grow_back=0.022)
	L.add(name, merge(rings_loft(rr), fan_cap(rr[-1], top)), steel, wh)
	c1 = math.cos(math.asin(min(1.0, 0.022 / H)))
	b0 = ring(hz + zb - 0.014, w + 0.008, fd + 0.008, bd + 0.008, n=12, cy=cy, sq=2.2)
	b1 = ring(hz + zb + 0.022, w * c1 + 0.008, fd * c1 + 0.008, bd * c1 + 0.008, n=12, cy=cy * c1, sq=2.2)
	L.add(name, rings_loft([b0, b1]), gold, wh)
	line = [_nearest_on_ring(r_, 0.0) for r_ in rr[1:]] + [top] + [_nearest_on_ring(r_, 180.0) for r_ in reversed(rr[1:])]
	line = [p + (p - V((0, 0.0, hz + 0.1))).normalized() * 0.006 for p in line]
	L.add(name, ridge(line, 0.011, n=3), gold, wh)
	# brow arches over the eyes meeting at the nasal
	fy = cy - fd - 0.004
	for sx in (-1.0, 1.0):
		pts = [V((0, fy - 0.004, hz + zb - 0.012)), V((sx * 0.032 * k, fy + 0.004, hz + 0.156 * k)), V((sx * 0.062 * k, fy + 0.016, hz + 0.15 * k)),
			V((sx * 0.09 * k, fy + 0.04, hz + 0.122 * k))]
		L.add(name, ridge(pts, 0.008, n=4), gold, wh)
	p0 = V((0, fy - 0.004, hz + zb - 0.01))
	p1 = V((0, -0.125 * k - 0.012, hz + 0.074 * k))
	L.add(name, cyl(p0, p1, 0.014, 0.011, n=4, side=(1, 0, 0)), steel, wh)
	# leather cheek guards
	leather = TINT("helm", 3, 0.32)
	hw = head_dims(L)[0]
	for sx in (-1.0, 1.0):
		c = V((sx * (hw + 0.03), -0.028 * k, hz + 0.105 * k))
		guard = box((0.014, 0.085 * k, 0.12 * k), center=(0, 0, -0.06 * k), top=(1.0, 0.75), shift=(0, -0.006))
		L.add(name, xf(guard, T(c) @ R(0, sx * 8.0, 0)), leather, wh)
		L.add(name, octa(0.009, center=(c.x + sx * 0.009, c.y - 0.02, c.z - 0.02), scale=(0.6, 1, 1)), gold, wh)
	# wings from the sides of the dome, sweeping up and back, fanned outward
	for sx in (-1.0, 1.0):
		t = math.radians(18.0)
		base = _ell(90.0 * sx, w * math.cos(t), fd * math.cos(t), bd * math.cos(t), hz + zb + H * math.sin(t), cy)
		base = base + V((sx * 0.004, -0.02, 0.0))
		Mw = T(base) @ R(0, 0, -sx * 32.0) @ R(0, sx * 12.0, 0) @ R(-12.0, 0, 0)
		L.add(name, xf(wing(sx, 1.08 * k), Mw), gold, wh)


def rune_strokes(x0, z0, h, w=0.016):
	"""An algiz-like rune with a crossbar (the frostbound's sign)."""
	return [((x0, z0), (x0, z0 + h), w), ((x0, z0 + h * 0.55), (x0 - h * 0.35, z0 + h * 0.95), w),
		((x0, z0 + h * 0.55), (x0 + h * 0.35, z0 + h * 0.95), w), ((x0 - h * 0.22, z0 + h * 0.25), (x0 + h * 0.22, z0 + h * 0.25), w * 0.8),
		((x0, z0 + h * 0.08), (x0 - h * 0.18, z0 - h * 0.1), w * 0.8), ((x0, z0 + h * 0.08), (x0 + h * 0.18, z0 - h * 0.1), w * 0.8)]


def wolf_head(scale=1.0):
	"""A low-poly wolf's head (the pelt's head lying on a shoulder), snout along -Y, local origin at the skull."""
	s = scale
	fur = [box((0.1 * s, 0.1 * s, 0.075 * s), center=(0, 0, 0), top=(0.8, 0.75), shift=(0, 0.005 * s)),
		box((0.055 * s, 0.085 * s, 0.042 * s), center=(0, -0.085 * s, -0.012 * s), top=(0.8, 0.9)),
		box((0.042 * s, 0.07 * s, 0.018 * s), center=(0, -0.078 * s, -0.04 * s))]
	for sx in (-1.0, 1.0):
		fur.append(cyl((sx * 0.03 * s, 0.018 * s, 0.03 * s), (sx * 0.042 * s, 0.035 * s, 0.085 * s), 0.02 * s, 0.0, n=3))
	eyes = merge(*[octa(0.009 * s, center=(sx * 0.03 * s, -0.045 * s, 0.018 * s), scale=(1, 0.6, 0.6)) for sx in (-1.0, 1.0)])
	nose = box((0.022 * s, 0.018 * s, 0.018 * s), center=(0, -0.13 * s, -0.004 * s))
	return merge(*fur), eyes, nose


def chest_3(L, reg):
	J = L.J
	name = reg.piece("chest", FAM, 3, hides=CHEST_HIDES,
		notes="unique frostbound: white fur mantle with a wolf head, navy fur-trimmed coat, rune tabard, blue cloak")
	wt = pl_rig.w_torso(J)
	navy, gold = M("navy"), M("gold")
	white, grey = M("fur_white"), M("fur_grey")
	leather = TINT("chest", 3, 0.35)
	zs = [0.9, 1.0, 1.1, 1.2, 1.3, 1.38, 1.43, 1.458]
	gs = [0.042, 0.032, 0.024, 0.022, 0.022, 0.022, 0.02, 0.018]
	L.add(name, rings_loft(shell_rings(L, zs, gs, n=16)), navy, wt)
	hem = 0.43 if not L.female else 0.45
	dims, rings_ = coat_skirt(L, name, navy, 1.0, hem, 0.036, 0.075, n=16, slit=1, back=0.55)
	bot = dims[-1]
	hem_pts = ring(bot[0] + 0.012, bot[1] + 0.006, bot[2] + 0.006, bot[3] + 0.006, n=24, sq=2.05)
	L.add(name, tufts_along(hem_pts, 0.055, 0.024, seed=91, down=0.65, every=2), white, pl_rig.w_skirt(J))
	L.add(name, tufts_along(hem_pts[1:] + hem_pts[:1], 0.05, 0.02, seed=92, down=0.65, every=2), grey, pl_rig.w_skirt(J))
	# the front tabard with a white rune
	ws = pl_rig.w_skirt(J)
	tz0, tz1 = hem + 0.05, 1.0
	front = interp([dd[0] for dd in reversed(dims)], [dd[2] for dd in reversed(dims)])

	def tab_surf(x, z):
		return V((x, -(front(z) + 0.012), z))
	tab = []
	for z in (tz0, (tz0 + tz1) * 0.5, tz1):
		tab.append([tab_surf(-0.075, z), tab_surf(0.075, z)])
	verts = [p for row in tab for p in row]
	faces = [[0, 1, 3, 2], [2, 3, 5, 4]]
	L.add(name, double_sided((verts, faces)), M("tabard"), ws)
	L.add(name, stroke_quads(rune_strokes(0.0, tz0 + 0.12, 0.16, w=0.014), tab_surf, lift=0.004, facing=(0, -1, 0)), M("rune"), ws)
	# sleeves with fur cuffs
	for side in ("r", "l"):
		wa = pl_rig.w_arm(J, side)
		L.add(name, L.sleeve(side, 0.0, 0.64, 0.02, steps=4, n=8, flare=0.012), navy, wa)
		pts = L.arm_path(side, 0.6, 0.66, steps=1)
		a, b = L.arm_radius(0.63)
		cuff = tube(pts, [(a + 0.036, b + 0.036), (a + 0.042, b + 0.042)], n=8, side=(0, -1, 0), cap0=False, cap1=False)
		L.add(name, cuff, white, wa)
	# straps with gold medallions, belt with a big medallion, pouches
	Ts = Torso(L, 0.004, grow_fn=interp(zs, gs))
	x_straps(L, name, Ts, leather, 0.036)
	for a, r in ((0, 0.032), (-30, 0.026), (30, 0.026)):
		on_surface(L, name, disc(r, 0.012, n=10), gold, Ts, a, strap_z(a), lift=0.008)
	Tb = belt(L, name, M("navy_dark"), 0.97, 1.05, 0.052)
	on_surface(L, name, disc(0.04, 0.014, n=10), gold, Tb, 0, 1.01)
	on_surface(L, name, disc(0.018, 0.016, n=6), M("rune"), Tb, 0, 1.01, lift=0.012)
	pouch(L, name, leather, M("navy_dark"), Tb, -42, 0.995, w=0.07, h=0.085, d=0.042)
	pouch(L, name, leather, M("navy_dark"), Tb, 108, 0.995, w=0.075, h=0.07, d=0.045)
	# the huge fur mantle with a wolf's head on the left shoulder
	mantle(L, name, grey, white, reach=0.12, thick=0.07, drop_front=0.24, drop_side=0.18, drop_back=0.34, n=18, seed=35,
		tuft=0.06, tuft_h=0.09, extra_row=True, collar=0.06)
	sx_ = J["p"]["shoulder_x"]
	head_c = V((sx_ * 1.02, -0.05, J["shoulder_z"] + 0.085))
	fur_geo, eyes, nose = wolf_head(1.05 if not L.female else 0.92)
	Mh = T(head_c) @ R(0, 0, 24.0) @ R(-14.0, 0, 0)
	L.add(name, xf(fur_geo, Mh), grey, wt)
	L.add(name, xf(eyes, Mh), M("eye"), wt)
	L.add(name, xf(nose, Mh), M("nose"), wt)
	# the long blue cloak with a white emblem and border
	strokes = tree_strokes(0.0, 0.55, 0.42, 0.11, w=0.02, levels=3) + rune_strokes(0.0, 1.06, 0.12, w=0.014)
	cz = 0.14 if not L.female else 0.17
	cloak(L, name, M("blue"), M("rune"), strokes, width_top=0.22, width_bot=0.34, z_bot=cz,
		drape=drape_over(L, dims, cz, 0.22, 0.34, margin=0.05), n=8, curve=0.35, jag=lambda k, x, y: -0.1 * (1.0 - abs(x) / 0.34) + (0.025 if k % 2 else 0.0),
		border=(M("rune"), 0.05, 0.024))


def gloves_3(L, reg):
	J = L.J
	name = reg.piece("gloves", FAM, 3, notes="unique frostbound: dark runed steel bracers with gold trim, dark leather gloves")
	leather = TINT("gloves", 3, 0.35)
	steel, gold = M("steel_dark"), M("gold")
	for side in ("r", "l"):
		wa = pl_rig.w_arm(J, side)
		L.glove(side, leather, grow=0.01, part=name)
		geo, gt = bracer(L, side, 0.58, 0.97, 0.032, taper=0.008, n=8, steps=2)
		L.add(name, geo, steel, wa)
		L.add(name, arm_band(L, side, 0.595, 0.035, gt(0.595) + 0.005), gold, wa)
		L.add(name, arm_band(L, side, 0.955, 0.03, gt(0.955) + 0.005), gold, wa)
		p, o, d = arm_plate(L, side, 0.77, 0.032)
		L.add(name, place(box((0.03, 0.13, 0.012), center=(0, 0, 0.006), top=(0.6, 1.0)), p, o, d), steel, wa)
		for dz, ang in ((0.0, 0.0), (0.03, 40.0), (0.03, -40.0)):
			q = p + d * dz + o * 0.012
			L.add(name, xf(place(box((0.008, 0.05 if ang == 0 else 0.032, 0.005), center=(0, 0, 0.003)), V((0, 0, 0)), o, d),
				T(q) @ _rot_about(o, ang)), gold, wa)


def boots_3(L, reg):
	J = L.J
	name = reg.piece("boots", FAM, 3, notes="unique frostbound: plated dark boots, knee cops, straps, gold trim")
	leather = TINT("boots", 3, 0.35)
	steel, gold = M("steel_dark"), M("gold")
	top = 0.46
	for side in ("r", "l"):
		wl = pl_rig.w_leg(J, side)
		wk = pl_rig.rigid("lower_leg_" + side)
		shoe(L, name, side, leather, M("sole"), h=0.11)
		L.add(name, boot_shaft(L, side, top, 0.016, steps=4), leather, wl)
		# greave: a ridged plate over the shin, gold along its top edge and ridge
		rows = []
		for z in (0.14, 0.29, 0.43):
			c = leg_point(L, side, z)
			r = shaft_r(L, z, 0.016) + 0.01
			row = []
			for a in (-54.0, -27.0, 0.0, 27.0, 54.0):
				rr = r + (0.012 if a == 0.0 else 0.0)
				row.append(c + V((math.sin(math.radians(a)) * rr, -math.cos(math.radians(a)) * rr * 1.04, 0.0)))
			rows.append(row)
		L.add(name, loft_rows(rows), steel, wl)
		axis = leg_point(L, side, 0.43)
		L.add(name, ribbon([p + V((0, 0, 0.002)) for p in rows[-1]], 0.016, [(p - axis).normalized() for p in rows[-1]]), gold, wl)
		ridge_pts = [row[2] + V((0, -0.003, 0)) for row in rows]
		L.add(name, ribbon(ridge_pts, 0.012, (0, -1, 0)), gold, wl)
		# knee cop with a gold boss
		kn = J["knee_" + side]
		rk = trouser_clear(L, kn.z, 0.0)
		n = V((0, -1, 0.12))
		L.add(name, place(sphere(0.054, seg_n=6, rings=2, scale=(1.0, 1.15, 0.5)), V((kn.x, kn.y - rk - 0.004, kn.z - 0.01)), n), steel, wk)
		L.add(name, place(disc(0.02, 0.01, n=6), V((kn.x, kn.y - rk - 0.03, kn.z - 0.01)), n), gold, wk)
		# straps (one over the greave) with a gold buckle, a gold band round the top
		L.add(name, strap_band(L, side, 0.1, 0.024, 0.03, n=6), M("belt"), wl)
		L.add(name, buckle_at(L, side, 0.1, 0.034), gold, wl)
		L.add(name, strap_band(L, side, 0.34, 0.024, 0.04, n=6), M("belt"), wl)
		L.add(name, strap_band(L, side, top - 0.012, 0.024, 0.02, n=6), gold, wl)


# ----------------------------------------------------------------------------------- build

def build(L, reg):
	for fn in (helm_1, chest_1, gloves_1, boots_1, helm_2, chest_2, gloves_2, boots_2, helm_3, chest_3, gloves_3, boots_3):
		fn(L, reg)
