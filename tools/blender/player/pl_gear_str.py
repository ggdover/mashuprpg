"""Strength gear of the player (tools/blender/player; rules in pl_gear.py): the warriors' iron and steel.

  tier 1 (common: the militia / axehand / exiled villager sheets): a riveted nasal spangenhelm; a
         studded leather jerkin to mid thigh over mail sleeves, leather shoulder pads, a small fur
         collar, a baldric and a belt with a pouch over a ragged linen hem; leather gloves with
         bracers; strapped fur-topped leather boots with round knee pads.
  tier 2 (rare: the axeguard sheet): a gilded spangenhelm with cheek guards; a scale cuirass and scale
         tassets over a long teal tunic with a red border, a fur mantle open at the front over a red
         scarf, a red cape with a pale beast emblem, a belt with a round buckle; plated gloves with
         runed vambraces; leather boots with steel greaves, knee cops and fur cuffs.
  tier 3 (unique: the wolf knight sheet): a wolf helm (ears, muzzle, cheek plates) over a blue hood;
         a ridged plate cuirass, layered pauldrons with wolf medallions, a wolf pelt with a wolf head
         on the left shoulder, a blue tabard with red strips over mail, a long blue cloak with a wolf
         emblem; runed gauntlets; "alpha" boots with wolf-head knee cops, fur and sabatons.
Steel / iron surfaces are tint_<slot>_str (the item's tint); leather, fur, cloth and gold stay fixed.
Everything is fitted with the Look's helpers (pl_body.Look) so it sits on all three bodies.
"""
import math

from mathutils import Vector

import cc_mesh
import pl_rig
from pl_body import _frame, _interp_head, _jag_end, _open_front
from pl_mesh import (R, T, box, double_sided, fan_cap, mat, merge, octa, ribbon, ring, rings_loft, rnd, sawtooth, seg,
	sphere, tint, tube, wrap_bands, xf)

FAM = "str"
TAU = 2.0 * math.pi
SIDES = (("r", -1.0), ("l", 1.0))


def V(*a):
	return Vector(a[0]) if len(a) == 1 else Vector(a)


def _mats():
	return {
		"helm": tint("tint_helm_str", grey=0.78, rough=0.4, metal=0.4),
		"chest": tint("tint_chest_str", grey=0.76, rough=0.42, metal=0.4),
		"mail": tint("tint_chest_str_mail", grey=0.5, rough=0.6, metal=0.35),
		"gloves": tint("tint_gloves_str", grey=0.76, rough=0.42, metal=0.4),
		"boots": tint("tint_boots_str", grey=0.76, rough=0.42, metal=0.4),
		"iron": mat("str_iron", "4d4b49", rough=0.5, metal=0.4),
		"leather": mat("str_leather", "5e412c", rough=0.8),
		"leather_dark": mat("str_leather_dark", "3a2a1e", rough=0.8),
		"leather_light": mat("str_leather_light", "7c5b3d", rough=0.8),
		"linen": mat("str_linen", "9a8a70", rough=0.95),
		"wool": mat("str_wool", "3f3a35", rough=0.95),
		"fur": mat("str_fur", "76644f", rough=1.0),
		"fur_light": mat("str_fur_light", "a0907a", rough=1.0),
		"gold": mat("str_gold", "b18c46", rough=0.35, metal=0.5),
		"teal": mat("str_teal", "2d4a4a", rough=0.85),
		"red": mat("str_red", "6d2424", rough=0.85),
		"red_dark": mat("str_red_dark", "4a1919", rough=0.85),
		"blue": mat("str_blue", "2a3860", rough=0.85),
		"pale": mat("str_pale", "cbbb94", rough=0.8),
		"wolf": mat("str_wolf", "8f887c", rough=1.0),
		"wolf_light": mat("str_wolf_light", "bcb5a6", rough=1.0),
		"wolf_dark": mat("str_wolf_dark", "57524a", rough=1.0),
		"dark": mat("str_dark", "1c1916", rough=0.6),
	}


def build(L, reg):
	M = _mats()
	for tier in (1, 2, 3):
		HELMS[tier](L, reg, M)
		CHESTS[tier](L, reg, M)
		GLOVES[tier](L, reg, M)
		BOOTS[tier](L, reg, M)


# ----------------------------------------------------------------------------------- shared helpers

def _const(w):
	"""A weight function giving every vertex the same weights (rigid plates riding on a blend)."""
	return lambda v: dict(w)


def _se(a, w, fd, bd, sq=2.2):
	"""Superellipse point at angle a (radians; -pi/2 = the front, 0 = the character's left)."""
	c, s = math.cos(a), math.sin(a)
	ex = 2.0 / sq
	return w * math.copysign(abs(c) ** ex, c), (fd if s < 0 else bd) * math.copysign(abs(s) ** ex, s)


def _ang(k, n):
	return -math.pi / 2 + TAU * k / n


def _rot_z(nrm):
	"""Rotation whose local Z is `nrm`."""
	return cc_mesh.frame(V(0, 0, 0), V(nrm))[0]


def _studs(pts, r=0.006, lift=0.002):
	"""Rivets / studs: [(point, outward normal)] -> flattened octahedra on the surface."""
	out = []
	for p, nrm in pts:
		nrm = V(nrm).normalized()
		out.append(xf(octa(r, scale=(1, 1, 0.55)), T(V(p) + nrm * lift) @ _rot_z(nrm)))
	return merge(*out)


def _disc(center, nrm, r, thick, n=8):
	"""A flat round plate (buckles, brooches, medallions) facing `nrm`."""
	nrm = V(nrm).normalized()
	c = V(center)
	return cc_mesh.cyl(c - nrm * thick * 0.5, c + nrm * thick * 0.5, r, n=n)


def _cap(center, up, out, rx, ry, h, n=10, rim=-0.35, mid=0.45, mid_k=0.78):
	"""A dome cap (pauldrons, knee cops, couters): a rim ellipse (rx along `out`, ry across) at rim*h
	along `up`, a middle ring (mid_k of the size) at mid*h, the top at h."""
	z = V(up).normalized()
	x = V(out) - z * V(out).dot(z)
	x.normalize()
	y = z.cross(x)
	c = V(center)

	def P(px, py, pz):
		return c + x * px + y * py + z * pz
	r0 = [P(rx * math.cos(TAU * k / n), ry * math.sin(TAU * k / n), rim * h) for k in range(n)]
	r1 = [P(rx * mid_k * math.cos(TAU * k / n), ry * mid_k * math.sin(TAU * k / n), mid * h) for k in range(n)]
	return merge(rings_loft([r0, r1]), fan_cap(r1, P(0, 0, h)))


def _sheet(rows, double=True):
	"""Quads between rows of points (rows top -> bottom, points left -> right around the body)."""
	verts, faces = [], []
	m = len(rows[0])
	for row in rows:
		verts.extend(V(p) for p in row)
	for i in range(len(rows) - 1):
		for c in range(m - 1):
			a = i * m + c
			faces.append([a + m, a + m + 1, a + 1, a])
	geo = (verts, faces)
	return double_sided(geo) if double else geo


def _fur_edge(pts, outs, height, tuft, seed=1, drop=0.0, closed=False):
	"""Fur along a polyline (the edge of a pelt, a cuff): one clump per segment hanging down and out
	along `outs` (outward vectors per point) like overlapping shingles."""
	r = rnd(seed)
	up = V(0, 0, 1)
	verts, faces = [], []
	count = len(pts) if closed else len(pts) - 1
	for k in range(count):
		k1 = (k + 1) % len(pts)
		p0, p1 = V(pts[k]), V(pts[k1])
		o = (V(outs[k]) + V(outs[k1])).normalized()
		m = (p0 + p1) * 0.5
		h = height * (0.7 + 0.6 * r.random())
		tip = m + o * tuft * (0.45 + 0.6 * r.random()) - up * (h * 0.75 + drop * r.random())
		top = m - o * 0.012 + up * h * 0.4
		i = len(verts)
		verts += [p0, p1, tip, top]
		faces += [[i, i + 1, i + 2], [i + 1, i, i + 3], [i, i + 2, i + 3], [i + 1, i + 3, i + 2]]
	return verts, faces


def _fur_loop(center, rx, ry, z, height, n=14, tuft=0.04, seed=1, drop=0.0, open_front=0.0):
	"""A ring of fur clumps (collars, cuffs) around an ellipse at height z; open_front (degrees) leaves
	that much of the front bare."""
	c = V(center)
	pts, outs = [], []
	if open_front <= 0.0:
		angs = [TAU * (k + 0.5) / n for k in range(n)]
	else:
		a0 = -math.pi / 2 + math.radians(open_front) * 0.5
		span = TAU - math.radians(open_front)
		angs = [a0 + span * k / n for k in range(n + 1)]
	for a in angs:
		pts.append(c + V(math.cos(a) * rx, math.sin(a) * ry, z))
		outs.append(V(math.cos(a) / rx, math.sin(a) / ry, 0).normalized())
	return _fur_edge(pts, outs, height, tuft, seed=seed, drop=drop, closed=open_front <= 0.0)


def _strip(pts, width, normals):
	"""A single-sided flat strip along pts facing `normals` (per point): trims on surfaces seen from
	one side only."""
	pts = [V(p) for p in pts]
	verts, faces = [], []
	for i, p in enumerate(pts):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		side = t.cross(V(normals[i])).normalized()
		verts += [p - side * width * 0.5, p + side * width * 0.5]
	for i in range(len(pts) - 1):
		a = i * 2
		f = [a, a + 1, a + 3, a + 2]
		nrm = (verts[f[1]] - verts[f[0]]).cross(verts[f[2]] - verts[f[0]])
		faces.append(f if nrm.dot(V(normals[i])) > 0 else list(reversed(f)))
	return verts, faces


def _shape(pts, cw=True):
	"""A 2D outline (x, z) ordered clockwise (seen from the front) when cw, else counter-clockwise."""
	area = 0.0
	for i in range(len(pts)):
		a, b = pts[i], pts[(i + 1) % len(pts)]
		area += a[0] * b[1] - b[0] * a[1]
	ccw = area > 0
	return list(reversed(pts)) if ccw == cw else list(pts)


# -- head

def _hk(L):
	return 0.94 if L.female else 1.0


def _hair_room(L):
	"""Extra depth at the back of a helmet for the female's long hair (it leaves the skull high up
	and would poke through a snug bowl)."""
	return 0.02 if L.female else 0.0


def _hpt(L, a, z, g, sq=2.2, shrink=True, zdim=None):
	"""Point on the head grown by g at angle a and height z above head_z (zdim: the height whose head
	size is used; default z). Near the crown the rings shrink like pl_body.Look.dome."""
	spec, top = L.head_spec()
	w, fd, bd, cy = _interp_head(spec, z if zdim is None else zdim)
	sh = (1.0 - max(0.0, (z - (top - 0.06)) / 0.06) * 0.35) if shrink else 1.0
	x, y = _se(a, (w + g) * sh, (fd + g) * sh, (bd + g) * sh, sq)
	return V(x, y + cy, L.J["head_z"] + z)


def _tilt(vf, vb, a):
	"""Blend a front value to a back value by the angle around the head."""
	return vf + (vb - vf) * (math.sin(a) + 1.0) * 0.5


def _hring(L, zf, zb, gf, gb, n=12):
	"""A ring around the head: height zf / grow gf at the front, zb / gb at the back."""
	out = []
	for k in range(n):
		a = _ang(k, n)
		out.append(_hpt(L, a, _tilt(zf, zb, a), _tilt(gf, gb, a)))
	return out


def _helm_shell(L, zf, zb, gf, gb, apex=0.02, n=12, flare=0.0, dome=(34.0, 66.0), lift=0.7):
	"""A helmet bowl from a tilted rim (front zf, back zb above head_z; grown gf / gb) up over the
	skull: it follows the head up to its widest ring, then closes in a rounded dome (lift x grow above
	the crown) with a slight point (apex). Returns (geometry, rings bottom -> top, tip)."""
	k = _hk(L)
	spec, top = L.head_spec()
	hz = L.J["head_z"]
	ze = 0.176 * k
	rows = [[], [], []]
	eq = []
	for c in range(n):
		a = _ang(c, n)
		zr, g = _tilt(zf, zb, a), _tilt(gf, gb, a)
		z_eq = max(ze, zr + 0.012)
		rows[0].append(_hpt(L, a, zr, g + flare, shrink=False))
		rows[1].append(_hpt(L, a, (zr + z_eq) * 0.5, g + flare * 0.3, shrink=False))
		p = _hpt(L, a, z_eq, g, shrink=False)
		rows[2].append(p)
		eq.append((p, g))
	cy = _interp_head(spec, ze)[3]
	for th in dome:
		c_, s_ = math.cos(math.radians(th)), math.sin(math.radians(th))
		row = []
		for p, g in eq:
			z_top = hz + top + g * lift + apex
			row.append(V(p.x * c_, cy + (p.y - cy) * c_, p.z + (z_top - p.z) * s_))
		rows.append(row)
	tip = V(0, cy + (gb - gf) * 0.3, hz + top + (gf + gb) * 0.5 * lift + apex + 0.012)
	return merge(rings_loft(rows), fan_cap(rows[-1], tip)), rows, tip


def _hband(L, zf, zb, h, gf, gb, n=12, lip=None):
	"""A band around a helmet rim (height h); lip=(gf, gb) closes it underneath down to the bowl."""
	r0 = _hring(L, zf, zb, gf, gb, n)
	r1 = _hring(L, zf + h, zb + h, gf, gb, n)
	geo = rings_loft([r0, r1])
	if lip is not None:
		geo = merge(geo, rings_loft([_hring(L, zf, zb, lip[0], lip[1], n), r0]))
	return geo


def _hout(L, p):
	return (V(p) - V(0, 0.005, L.J["head_z"] + 0.12)).normalized()


def _col_strip(L, rings, k, tip, w0, w1, lift=0.004, first=0):
	"""A raised strip up a helmet bowl along vertex column k of its rings, ending at the tip."""
	pts, nrm = [], []
	for r in rings[first:]:
		o = _hout(L, r[k])
		pts.append(V(r[k]) + o * lift)
		nrm.append(o)
	pts.append(V(tip) + V(0, 0, lift))
	nrm.append(V(0, 0, 1))
	ws = [w0 + (w1 - w0) * i / (len(pts) - 1) for i in range(len(pts))]
	return ribbon(pts, ws, nrm)


def _cheek_guard(L, side, zf, zb, z_bot, g, a_front, a_back, cols=2, rows=3, taper=0.4, flare=0.012):
	"""A plate hanging from a helmet rim over the cheek between the angles a_front (by the cheekbone)
	and a_back (before the ear), right side; the left side mirrors. It hangs straight (the head size
	of the cheek level) and narrows toward the bottom. Double sided."""
	if side == "l":
		a_front, a_back = math.pi - a_front, math.pi - a_back
	out = []
	for i in range(rows + 1):
		t = i / rows
		af = a_front + (a_back - a_front) * taper * t * t
		row = []
		for c in range(cols + 1):
			a = af + (a_back - af) * c / cols
			z0 = _tilt(zf, zb, a) + 0.004
			z = z0 + (z_bot - z0) * t
			row.append(_hpt(L, a, z, g + flare * t, shrink=False, zdim=max(z, 0.1)))
		out.append(row)
	return _sheet(out)


# -- torso

def _tdims(L, z, g=0.0):
	w, fd, bd = L.torso_at(z)
	return w + g, fd + g, bd + g


def _tout(L, p):
	w, fd, bd = L.torso_at(p.z)
	d = fd if p.y < 0 else bd
	return V(p.x / (w * w), p.y / (d * d), 0.0).normalized()


def _front_y(L, x, z, g, sq=2.2):
	w, fd, _bd = _tdims(L, z, g)
	u = min(0.995, abs(x) / w)
	return -fd * (1.0 - u ** sq) ** (1.0 / sq)


def _back_y(L, x, z, g, sq=2.2):
	w, _fd, bd = _tdims(L, z, g)
	u = min(0.995, abs(x) / w)
	return bd * (1.0 - u ** sq) ** (1.0 / sq)


def _sdims(L, z, grow, flare, ref=(1.0, 0.45)):
	"""The skirt surface (pl_body.Look.skirt's shape) at height z for a skirt spanning ref."""
	z_top, z_bot = ref
	w0, f0, b0 = L.torso_at(min(z_top, 0.93))
	t = max(0.0, min(1.0, (z_top - z) / (z_top - z_bot)))
	bw, bf, bb = L.torso_at(z) if z > 0.84 else (w0, f0, b0)
	k = grow + flare * t
	return max(bw, w0 * 0.98) + k + 0.02 * t, bf + k + 0.03 * t, bb + k + 0.03 * t


def _sring(L, z, grow, flare, n=16, jag=None, ref=(1.0, 0.45)):
	w, fd, bd = _sdims(L, z, grow, flare, ref)
	return ring(z, w, fd, bd, n=n, sq=2.05, jag=jag)


def _skirt(L, zs, grow, flare, n=16, jag=None, ref=(1.0, 0.45), open_k=0, double=True):
	"""A skirt / hem through the heights zs (top -> bottom) on the ref skirt surface; open_k > 0
	leaves a slit at the front."""
	rings = [_sring(L, z, grow, flare, n, jag if i == len(zs) - 1 else None, ref) for i, z in enumerate(zs)]
	rings = list(reversed(rings))
	if open_k:
		return _open_front(rings, open_k=open_k, double=double, open_at=0)
	geo = rings_loft(rings)
	return double_sided(geo) if double else geo


def _panel(L, zs, grow, flare, a0, a1, cols=3, jag=None, ref=(1.0, 0.45)):
	"""A cloth panel (tabards, hanging cloths) on the skirt surface between the angles a0..a1."""
	rows = []
	for i, z in enumerate(zs):
		w, fd, bd = _sdims(L, z, grow, flare, ref)
		row = []
		for c in range(cols + 1):
			a = a0 + (a1 - a0) * c / cols
			x, y = _se(a, w, fd, bd, 2.05)
			dz = jag(c, x, y) if (jag is not None and i == len(zs) - 1) else 0.0
			row.append(V(x, y, z + dz))
		rows.append(row)
	return _sheet(rows)


def _belt(L, z0, z1, grow, n=16, ref=(1.0, 0.45)):
	return rings_loft([_sring(L, z0, grow, 0.0, n, ref=ref), _sring(L, z1, grow, 0.0, n, ref=ref)])


def _pouch(L, a, z, grow, size=(0.075, 0.04, 0.07), ref=(1.0, 0.45)):
	"""A leather pouch hanging from the belt at angle a, and its flap."""
	w, fd, bd = _sdims(L, z, grow, 0.0, ref)
	x, y = _se(a, w, fd, bd, 2.05)
	o = V(x / (w * w), y / ((fd if y < 0 else bd) ** 2), 0).normalized()
	c = V(x, y, z) + o * (size[1] * 0.5)
	rot = math.degrees(math.atan2(o.x, -o.y))
	M = T(c) @ R(0, 0, rot)
	body = box(size, center=(0, 0, -size[2] * 0.5), top=(1.0, 0.9))
	flap = box((size[0] * 1.06, size[1] * 1.15, 0.014), center=(0, -0.003, -0.004))
	return xf(body, M), xf(flap, M)


def _arm_out(L, side, t):
	"""(point on the arm axis, unit vector to the outside of the arm, arm direction) at t."""
	J = L.J
	sx = -1.0 if side == "r" else 1.0
	p = L.arm_path(side, t, t, steps=1)[0]
	d = J["forearm_dir_" + side] if t > 0.5 else J["upper_arm_dir_" + side]
	o = V(sx, 0, 0) - d * d.x * sx
	return p, o.normalized(), d


def _arm_tube(L, side, t0, t1, grow_fn, steps=3, n=8):
	"""A tube around the arm between t0 and t1 whose grow follows grow_fn(u) (u = 0..1)."""
	pts = L.arm_path(side, t0, t1, steps=steps)
	rr = []
	for i in range(len(pts)):
		u = i / steps
		a, b = L.arm_radius(t0 + (t1 - t0) * u)
		g = grow_fn(u)
		rr.append((a + g, b + g))
	return tube(pts, rr, n=n, side=(0, -1, 0), cap0=False, cap1=False)


def _arm_plate(L, side, t0, t1, grow, w0, w1, thick=0.006, lift=0.0):
	"""A long plate (bracer plate, rune strip) on the outside of the arm between t0 and t1."""
	p0, o0, d = _arm_out(L, side, t0)
	p1, o1, _d = _arm_out(L, side, t1)
	r0 = max(L.arm_radius(t0)) + grow + lift
	r1 = max(L.arm_radius(t1)) + grow + lift
	across = d.cross(o0).normalized()
	return seg(p0 + o0 * (r0 + thick * 0.5), p1 + o1 * (r1 + thick * 0.5), [(0, w0, thick * 0.7), (1, w1, thick * 0.7)],
		n=4, side=across)


def _cape(L, w_top, w_bot, z_bot, yc, n=8, curve=0.35, jag=None, zs=None):
	"""A cape from the shoulders (J cape_top) down to z_bot: its centre line at y = yc(z) (outside the
	armour), the sides wrapped forward. Double sided. Returns (geometry, surf) where surf(x, z) is the
	point of the cape's outer surface."""
	top = L.J["cape_top"]
	zs = zs or [top.z, top.z - 0.1, 1.15, 1.0, 0.8, 0.6, 0.4, 0.2]
	zs = [z for z in zs if z > z_bot + 0.05] + [z_bot]

	def width(z):
		t = (top.z - z) / max(0.01, top.z - z_bot)
		return w_top + (w_bot - w_top) * min(1.0, t * 1.6)

	def surf(x, z):
		w = width(z)
		u = max(-1.0, min(1.0, x / w))
		return V(x, yc(z) - curve * w * (0.6 if z > 1.2 else 0.35) * u * u, z)
	rows = []
	for i, z in enumerate(zs):
		w = width(z)
		row = []
		for k in range(n + 1):
			p = surf(w * (-1.0 + 2.0 * k / n), z)
			if jag is not None and i == len(zs) - 1:
				p.z += jag(k, p.x, p.y)
			row.append(p)
		rows.append(row)
	return _sheet(rows), surf, width


def _emblem(surf, outline, cx, cz, s, lift=0.004):
	"""A flat emblem on a cape's outer surface (facing +Y): outline (x, z) in units of s."""
	verts = [surf(cx + x * s, cz + z * s) + V(0, lift, 0) for (x, z) in _shape(outline, cw=True)]
	return verts, [list(range(len(verts)))]


def _cape_strip(surf, xz, w, lift=0.003):
	"""A flat strip on a cape's outer surface along the points xz, facing +Y."""
	pts = [surf(x, z) + V(0, lift, 0) for (x, z) in xz]
	verts, faces = [], []
	for i, p in enumerate(pts):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		side = t.cross(V(0, 1, 0)).normalized()
		verts += [p - side * w * 0.5, p + side * w * 0.5]
	for i in range(len(pts) - 1):
		a = i * 2
		faces.append([a, a + 2, a + 3, a + 1])
	# face +Y: flip if the first quad looks forward
	f = faces[0]
	nrm = (verts[f[1]] - verts[f[0]]).cross(verts[f[2]] - verts[f[0]])
	if nrm.y < 0:
		faces = [list(reversed(f)) for f in faces]
	return verts, faces


def _back_line(L, fns, margin):
	"""yc(z) for a cape: the deepest armour point at or above z (fns: [(z_lo, z_hi, fn(z) -> y)]), so
	it never decreases downward (the cape hangs outward over wide hems), plus a margin."""
	def raw(z):
		best = 0.0
		for lo, hi, fn in fns:
			if lo <= z <= hi:
				best = max(best, fn(z))
		return best

	def yc(z):
		best = 0.0
		zz = 1.5
		while zz >= z:
			best = max(best, raw(zz))
			zz -= 0.02
		return max(best, raw(z)) + margin
	return yc


# -- legs

def _shaft_r(L, z, extra=0.014):
	"""Radius of a boot shaft at height z: outside the default trousers (all looks) around z."""
	r = max(L.trouser_radius(z + dz, 1.02) for dz in (-0.03, 0.0, 0.03))
	if z < 0.17:
		r = min(r, 0.058)
	return max(0.064, r + extra)


def _boot_base(L, name, side, upper, sole, z_top=0.4, steps=4):
	"""Foot, sole and the shaft up to z_top. Returns the shaft top (point, radius)."""
	J = L.J
	wf = pl_rig.w_leg(J, side)
	ank, toe, heel = J["ankle_" + side], J["toe_" + side], J["heel_" + side]
	cy = (heel.y + toe.y) * 0.5
	L.add(name, box((0.114, 0.272, 0.096), center=(ank.x, cy - 0.004, 0.048), top=(0.9, 0.7), shift=(0, 0.03)), upper, wf)
	L.add(name, box((0.118, 0.278, 0.022), center=(ank.x, cy - 0.004, 0.011)), sole, wf)
	pts = L.leg_path(side, z_top, 0.06, steps=steps)
	rr = [_shaft_r(L, p.z) for p in pts]
	L.add(name, tube(pts, [(r, r * 1.03) for r in rr], n=8, side=(0, -1, 0), cap0=False, cap1=False), upper, wf)
	return pts[0], rr[0]


def _leg_pt(L, side, z):
	return L.leg_path(side, z, z, steps=1)[0]


def _knee_const(L, side, k_up=0.45):
	return _const({"upper_leg_" + side: k_up, "lower_leg_" + side: 1.0 - k_up})


def _greave(L, side, z0, z1, grow, half=75.0, cols=5, rows=3):
	"""A curved steel plate over the front of the shin between z0 (top) and z1."""
	out = []
	for i in range(rows + 1):
		z = z0 + (z1 - z0) * i / rows
		c = _leg_pt(L, side, z)
		r = _shaft_r(L, z) + grow
		row = []
		for k in range(cols + 1):
			a = math.radians(-90.0 - half + 2.0 * half * k / cols)
			row.append(V(c.x + math.cos(a) * r, c.y + math.sin(a) * r * 1.03, z))
		out.append(row)
	return _sheet(out, double=False), out


def _fur_cuff(L, side, z, r, seed, n=10, height=0.05, tuft=0.035):
	c = _leg_pt(L, side, z)
	return _fur_loop((c.x, c.y, 0), r, r * 1.03, z, height, n=n, tuft=tuft, seed=seed, drop=0.012)


def _knee_dome(L, side, r, depth, lift=0.004):
	"""A domed plate on the front of the knee (center, geometry)."""
	J = L.J
	knee = J["knee_" + side]
	rk = L.trouser_radius(knee.z, 1.02)
	c = V(knee.x, knee.y - rk - lift, knee.z - 0.01)
	dome = sphere(r, 8, 2, cut=(0.0, 1.0), scale=(1.0, 1.0, depth / r))
	return c, xf(dome, T(c) @ R(90, 0, 0))


# ----------------------------------------------------------------------------------- helms

def _helm1(L, reg, M):
	name = reg.piece("helm", FAM, 1, notes="riveted nasal spangenhelm")
	J, k = L.J, _hk(L)
	wh = pl_rig.w_head(J)
	zf, zb, gf, gb = 0.17 * k, 0.115 * k, 0.026, 0.046 + _hair_room(L)
	shell, rings, tip = _helm_shell(L, zf, zb, gf, gb, apex=0.028, n=12)
	L.add(name, shell, M["helm"], wh)
	L.add(name, _hband(L, zf - 0.006, zb - 0.006, 0.034, gf + 0.008, gb + 0.008, lip=(gf, gb)), M["iron"], wh)
	for col in (0, 3, 6, 9):
		L.add(name, _col_strip(L, rings, col, tip, 0.022, 0.01, first=1), M["iron"], wh)
	yb = _hpt(L, -math.pi / 2, zf + 0.012, gf + 0.008).y
	hz = J["head_z"]
	nasal = [V(0, yb - 0.003, hz + zf + 0.03), V(0, yb - 0.003, hz + zf - 0.012), V(0, -(0.123 * k + 0.012), hz + 0.09 * k)]
	L.add(name, ribbon(nasal, [0.024, 0.022, 0.017], [V(0, -1, 0)] * 3, thick=0.006), M["iron"], wh)
	pts = []
	for col in (1, 2, 4, 5, 7, 8, 10, 11):
		a = _ang(col, 12)
		p = _hpt(L, a, _tilt(zf, zb, a) + 0.011, _tilt(gf, gb, a) + 0.008)
		pts.append((p, _hout(L, p)))
	L.add(name, _studs(pts, r=0.0065), M["iron"], wh)


def _helm2(L, reg, M):
	name = reg.piece("helm", FAM, 2, notes="gilded spangenhelm with cheek guards")
	J, k = L.J, _hk(L)
	hz = J["head_z"]
	wh = pl_rig.w_head(J)
	zf, zb, gf, gb = 0.172 * k, 0.085 * k, 0.028, 0.05 + _hair_room(L)
	shell, rings, tip = _helm_shell(L, zf, zb, gf, gb, apex=0.024, n=12, flare=0.012)
	L.add(name, shell, M["helm"], wh)
	L.add(name, _hband(L, zf - 0.006, zb - 0.006, 0.03, gf + 0.021, gb + 0.021, lip=(gf + 0.012, gb + 0.012)), M["gold"], wh)
	for col in (0, 3, 6, 9):
		L.add(name, _col_strip(L, rings, col, tip, 0.02, 0.012, first=1), M["gold"], wh)
	L.add(name, octa(0.016, center=tuple(tip + V(0, 0, 0.012)), scale=(1, 1, 1.6)), M["gold"], wh)
	# brow ridges over the eyes, rising from the nasal
	for sx in (-1.0, 1.0):
		pts, nrm = [], []
		for da, dz in ((6.0, 0.004), (19.0, 0.024), (33.0, 0.006)):
			a = math.radians(-90.0 + sx * da)
			p = _hpt(L, a, _tilt(zf, zb, a) + dz, _tilt(gf, gb, a) + 0.024)
			pts.append(p)
			nrm.append(_hout(L, p))
		L.add(name, ribbon(pts, [0.012, 0.016, 0.01], nrm), M["gold"], wh)
	yb = _hpt(L, -math.pi / 2, zf + 0.012, gf + 0.021).y
	nasal = [V(0, yb - 0.002, hz + zf + 0.028), V(0, yb - 0.002, hz + zf - 0.012), V(0, -(0.123 * k + 0.013), hz + 0.086 * k)]
	L.add(name, ribbon(nasal, [0.026, 0.022, 0.034], [V(0, -1, 0)] * 3, thick=0.007), M["helm"], wh)
	studs = []
	for side in ("r", "l"):
		L.add(name, _cheek_guard(L, side, zf, zb, 0.035 * k, gf + 0.006, math.radians(-120.0), math.radians(-166.0)),
			M["helm"], wh)
		for a_deg, z in ((-150.0, 0.12), (-138.0, 0.075)):
			a = math.radians(a_deg) if side == "r" else math.pi - math.radians(a_deg)
			p = _hpt(L, a, z * k, gf + 0.006 + 0.01, shrink=False, zdim=max(z * k, 0.1))
			studs.append((p, _hout(L, p)))
	L.add(name, _studs(studs, r=0.0065), M["gold"], wh)


def _hood(L, n=12):
	"""A cloth hood around the head, open for the face, closing under the chin and ending in a short
	cowl on the shoulders (under any body armour's collar)."""
	J, k = L.J, _hk(L)
	hz = J["head_z"]
	g = 0.045
	rows = [(0.15 * k, 0.1, 0.1, 0.11, 0.0), (0.07 * k, 0.1, 0.1, 0.106, -0.005), (-0.02 * k, 0.092, 0.1, 0.1, -0.01)]
	rings = []
	for (z, w, fd, bd, cy) in rows:
		rings.append(ring(hz + z, w + g, fd + g, bd + g, n=n, cy=cy, sq=2.2))
	for z, gg in ((J["neck_z"] - 0.005, 0.018), (1.415, 0.014)):
		w, fd, bd = L.torso_at(z)
		rings.append(ring(z, w + gg, fd + gg, bd + gg, n=n, sq=2.2))
	rings = list(reversed(rings))            # bottom -> top
	skip_front = {n - 2, n - 1, 0, 1}
	verts, faces, idx = [], [], []
	for r in rings:
		idx.append([len(verts) + i for i in range(n)])
		verts.extend(r)
	upper, lower = [], []
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		for kk in range(n):
			if i >= 2 and kk in skip_front:
				continue
			f = [a[kk], a[(kk + 1) % n], b[(kk + 1) % n], b[kk]]
			(upper if i >= 2 else lower).append(f)
	geo_upper = double_sided((verts, upper))
	return merge(geo_upper, (verts, lower))


def _helm3(L, reg, M):
	name = reg.piece("helm", FAM, 3, hides=["HairTop", "HairBack", "HairFront"], notes="wolf helm over a blue hood")
	J, k = L.J, _hk(L)
	hz = J["head_z"]
	wh = pl_rig.w_head(J)
	hood_w = pl_rig.chain([V(0, 0, J["head_top"] + 0.1), V(0, 0, hz + 0.02), V(0, 0, J["neck_z"] - 0.01), V(0, 0, 1.2)],
		["head", "neck", "chest"], [0.04, 0.04])
	L.add(name, _hood(L), M["blue"], hood_w)
	zf, zb, gf, gb = 0.19 * k, 0.065 * k, 0.056, 0.064
	shell, rings, tip = _helm_shell(L, zf, zb, gf, gb, apex=0.0, n=12, flare=0.01, lift=0.55)
	L.add(name, shell, M["helm"], wh)
	L.add(name, _hband(L, zf - 0.006, zb - 0.006, 0.022, gf + 0.013, gb + 0.013), M["gold"], wh)
	# a gilded ridge over the crown, from the brow to the nape
	pts, nrm = [], []
	for r in rings[2:]:
		pts.append(V(r[0]) + _hout(L, r[0]) * 0.005)
		nrm.append(_hout(L, r[0]))
	pts.append(tip + V(0, 0, 0.004))
	nrm.append(V(0, 0, 1))
	for r in reversed(rings[1:]):
		pts.append(V(r[6]) + _hout(L, r[6]) * 0.005)
		nrm.append(_hout(L, r[6]))
	L.add(name, _strip(pts, 0.016, nrm), M["gold"], wh)
	# the wolf's face: its snout running down over the nose like a broad nasal, gilded eyes under
	# frowning brows, and tall ears
	fy = _hpt(L, -math.pi / 2, 0.225 * k, gf, shrink=False).y
	top_s = V(0, fy + 0.01, hz + 0.232 * k)
	nose = V(0, -(0.123 * k + 0.03), hz + 0.092 * k)
	L.add(name, seg(top_s, nose, [(0, 0.04, 0.036), (0.45, 0.03, 0.028), (1, 0.019, 0.019)], n=4, side=(1, 0, 0)), M["helm"], wh)
	L.add(name, octa(0.013, center=tuple(nose + V(0, -0.012, -0.004)), scale=(1.3, 1.0, 0.8)), M["dark"], wh)
	for sx in (-1.0, 1.0):
		a = math.radians(-90.0 + sx * 24.0)
		e = _hpt(L, a, 0.2 * k, gf + 0.004, shrink=False)
		L.add(name, octa(0.012, center=tuple(e), scale=(1.4, 0.7, 0.8)), M["gold"], wh)
		b0 = _hpt(L, math.radians(-90.0 + sx * 10.0), 0.218 * k, gf + 0.01, shrink=False)
		b1 = _hpt(L, math.radians(-90.0 + sx * 38.0), 0.232 * k, gf + 0.008, shrink=False)
		L.add(name, seg(b0, b1, [(0, 0.012, 0.012), (1, 0.008, 0.006)], n=4, side=(0, 0, 1)), M["helm"], wh)
		eb = _hpt(L, math.radians(-90.0 + sx * 40.0), 0.262 * k, gf * 0.9, shrink=False)
		et = eb + V(sx * 0.028, 0.03, 0.088)
		L.add(name, seg(eb - V(0, 0, 0.02), et, [(0, 0.04, 0.016), (1, 0.003, 0.003)], n=4, side=(1, 0, 0)), M["helm"], wh)
	for side in ("r", "l"):
		L.add(name, _cheek_guard(L, side, zf, zb, 0.02 * k, gf + 0.004, math.radians(-116.0), math.radians(-170.0), taper=0.3),
			M["helm"], wh)


# ----------------------------------------------------------------------------------- chests

def _shoulder_const(side):
	return _const({"clavicle_" + side: 0.5, "upper_arm_" + side: 0.5})


def _chest1(L, reg, M):
	name = reg.piece("chest", FAM, 1, notes="studded leather jerkin, mail sleeves, fur collar")
	J = L.J
	wt, ws = pl_rig.w_torso(J), pl_rig.w_skirt(J)
	ref = (1.0, 0.64)
	g = 0.028
	rings = L.shell([0.97, 1.07, 1.17, 1.27, 1.35, 1.405, 1.445, 1.468], g, n=14)
	L.add(name, rings_loft(rings), M["leather"], wt)
	# studs over the chest
	studs = []
	for i in (1, 2, 3, 4):
		for kk in (1, 13) + ((2, 12) if i in (2, 4) else ()):
			p = rings[i][kk]
			studs.append((p, _tout(L, p)))
	L.add(name, _studs(studs, r=0.0068), M["chest"], wt)
	# the jerkin's lower half, split at the front, over a ragged linen hem
	L.add(name, _skirt(L, [1.0, 0.9, 0.8, 0.72], 0.034, 0.03, n=14, jag=sawtooth(14, 0.028, rnd=0.02, seed=61), ref=ref,
		open_k=1), M["leather"], ws)
	L.add(name, _skirt(L, [0.99, 0.86, 0.74, 0.64], 0.022, 0.04, n=14, jag=sawtooth(14, 0.05, rnd=0.04, seed=62), ref=ref),
		M["linen"], ws)
	# mail sleeves, dark wool under them, leather shoulder pads
	ar = L.arm_radius(0.0)[0]
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.add(name, L.sleeve(side, 0.0, 0.47, 0.014, steps=4, n=8, flare=0.012), M["mail"], wa)
		L.add(name, _jag_end(L.sleeve(side, 0.42, 0.7, 0.007, steps=2, n=8), 8, 0.02, seed=63 if side == "r" else 64),
			M["wool"], wa)
		up = V(sx * math.sin(math.radians(28)), 0, math.cos(math.radians(28)))
		c = J["shoulder_" + side] + V(sx * 0.012, 0, 0.012)
		L.add(name, _cap(c, up, V(sx, 0, 0), ar + 0.046, ar + 0.04, 0.07, n=10, rim=-0.42), M["leather_light"],
			_shoulder_const(side))
		# rivets along the pad's outer edge
		edge = []
		zax = up.normalized()
		xax = (V(sx, 0, 0) - zax * zax.x * sx).normalized()
		yax = zax.cross(xax)
		for a in (-0.7, 0.0, 0.7):
			p = c + xax * (ar + 0.046) * 0.93 * math.cos(a) + yax * (ar + 0.04) * 0.93 * math.sin(a) + zax * (-0.42 * 0.07 + 0.012)
			edge.append((p, (xax * math.cos(a) + yax * math.sin(a) + zax * 0.6).normalized()))
		L.add(name, _studs(edge, r=0.006), M["chest"], _shoulder_const(side))
	# small fur collar
	w, fd, bd = L.torso_at(1.445)
	L.add(name, _fur_loop((0, 0.012, 0), w + 0.03, (fd + bd) * 0.5 + 0.032, 1.452, 0.055, n=14, tuft=0.03, seed=65),
		M["fur"], wt)
	# belt, buckle, pouch
	L.add(name, _belt(L, 0.985, 1.045, 0.046, n=14, ref=ref), M["leather_dark"], wt)
	w, fd, bd = _sdims(L, 1.015, 0.046, 0.0, ref)
	L.add(name, box((0.05, 0.012, 0.046), center=(0.0, -fd - 0.005, 1.015)), M["chest"], wt)
	body, flap = _pouch(L, math.radians(-148.0), 0.99, 0.046, ref=ref)
	L.add(name, body, M["leather_light"], wt)
	L.add(name, flap, M["leather_dark"], wt)
	# baldric from the left shoulder across the chest to the right hip, and down the back
	L.add(name, _baldric(L, g + 0.007, 0.04), M["leather_dark"], wt)


def _baldric(L, g, width):
	pts, nrm = [], []
	w0 = L.torso_at(1.43)[0]
	x_top = 0.72 * w0
	for s in (0.0, 0.25, 0.5, 0.75, 1.0):
		z = 1.43 - 0.41 * s
		x = x_top + (-0.82 * L.torso_at(1.02)[0] - x_top) * s
		p = V(x, _front_y(L, x, z, g), z)
		pts.append(p)
		nrm.append(_tout(L, p))
	# over the shoulder
	ztop = 1.448 + g * 0.6
	pts.insert(0, V(x_top, 0.0, ztop))
	nrm.insert(0, V(0, 0, 1))
	back = []
	for s in (0.0, 0.3, 0.65, 1.0):
		z = 1.43 - 0.41 * s
		x = x_top + (-0.82 * L.torso_at(1.02)[0] - x_top) * s
		p = V(x, _back_y(L, x, z, g), z)
		back.append((p, _tout(L, p)))
	for p, o in back:
		pts.insert(0, p)
		nrm.insert(0, o)
	return ribbon(pts, width, nrm, thick=0.005)


def _mantle(L, M, name, fur, fur_edge, seed, back_extra, open_k=2, n=16, low=1.28, w_low=None, w_mid=None, front=0.07,
		front_rise=0.0):
	"""A fur mantle over the shoulders, open at the front: a loft (bottom edge torn) with fur tufts
	along its edge and a fur ruff around the neck. w_low / w_mid: half widths at the bottom and at
	the shoulders (default: over the arms); front_rise lifts the bottom edge toward the front (a pelt
	long at the back, ending at the shoulders in front). Returns the rings (bottom -> top)."""
	J = L.J
	wt = pl_rig.w_torso(J)
	sx_ = J["p"]["shoulder_x"]
	ar = L.arm_radius(0.0)[0]
	nr = 0.055 if L.female else (0.066 if L.look == "m2" else 0.06)
	wb, fb, bb = L.torso_at(low)
	w1, f1, b1 = L.torso_at(1.39)
	w_low = sx_ + ar + 0.075 if w_low is None else w_low
	w_mid = sx_ + ar + 0.06 if w_mid is None else w_mid
	spec = [(low, w_low, fb + front, bb + back_extra),
		(1.39, w_mid, f1 + front + 0.005, b1 + back_extra + 0.005),
		(1.462, nr + 0.1, nr + 0.066, nr + 0.08),
		(1.505, nr + 0.056, nr + 0.046, nr + 0.056)]
	rings = []
	for i, (z, w, fd, bd) in enumerate(spec):
		rings.append(ring(z, w, fd, bd, n=n, sq=2.1, jag=sawtooth(n, 0.045, rnd=0.03, seed=seed) if i == 0 else None))
	if front_rise:
		for p in rings[0]:
			if p.y < 0.0:
				p.z += front_rise * min(1.0, -p.y / spec[0][2]) ** 0.7
	L.add(name, _open_front(rings, open_k=open_k, double=True), M[fur], wt)
	# tufts along the bottom edge (the open front excluded) and around the neck
	for ri, h, tuft, sd in ((0, 0.07, 0.05, seed + 1), (1, 0.06, 0.045, seed + 2)):
		r = rings[ri]
		arc = range(open_k + 1, n - open_k)
		pts = [V(r[kk]) + V(0, 0, -0.01 if ri == 0 else 0.0) for kk in arc]
		outs = [V(p.x, p.y, 0).normalized() for p in pts]
		L.add(name, _fur_edge(pts, outs, h, tuft, seed=sd, drop=0.03 if ri == 0 else 0.0), M[fur_edge], wt)
	L.add(name, _fur_loop((0, 0.012, 0), nr + 0.098, nr + 0.078, 1.482, 0.065, n=14, tuft=0.04, seed=seed + 3,
		open_front=70.0), M[fur], wt)
	return rings


def _chest2(L, reg, M):
	name = reg.piece("chest", FAM, 2, notes="scale cuirass over a teal tunic, fur mantle, red cape")
	J = L.J
	wt, ws = pl_rig.w_torso(J), pl_rig.w_skirt(J)
	ref = (1.0, 0.48)
	g = 0.032
	zs = [0.97, 1.05, 1.13, 1.21, 1.29, 1.37, 1.44]
	for i in range(len(zs) - 1):
		top = L.shell([zs[i + 1]], g, n=16)[0]
		bot = L.shell([zs[i] - 0.014], g + 0.012, n=16, jag=sawtooth(16, 0.018, seed=70 + i))[0]
		L.add(name, rings_loft([bot, top]), M["chest"], wt)
	L.add(name, rings_loft(L.shell([1.44, 1.468], g, n=16)), M["chest"], wt)
	# scale tassets over the tunic
	for i, (z1, z0) in enumerate(((1.0, 0.875), (0.9, 0.775))):
		top = _sring(L, z1, 0.047 + 0.008 * i, 0.06, 16, ref=ref)
		bot = _sring(L, z0, 0.057 + 0.008 * i, 0.06, 16, jag=sawtooth(16, 0.02, seed=80 + i), ref=ref)
		L.add(name, rings_loft([bot, top]), M["chest"], ws)
	# the long teal tunic with a red border
	hem = sawtooth(16, 0.02, rnd=0.012, seed=82)
	L.add(name, _skirt(L, [1.0, 0.82, 0.64, 0.48], 0.034, 0.06, n=16, jag=hem, ref=ref, open_k=1), M["teal"], ws)
	L.add(name, _skirt(L, [0.545, 0.48], 0.037, 0.06, n=16, jag=hem, ref=ref, open_k=1), M["red"], ws)
	L.add(name, _skirt(L, [0.56, 0.545], 0.038, 0.06, n=16, ref=ref, open_k=1, double=False), M["gold"], ws)
	# red cloth hanging at the front over a pale border
	a = math.radians
	L.add(name, _panel(L, [0.99, 0.8, 0.62, 0.53], 0.074, 0.06, a(-110.0), a(-70.0), cols=2, ref=ref), M["pale"], ws)
	L.add(name, _panel(L, [0.99, 0.8, 0.63, 0.555], 0.078, 0.06, a(-106.0), a(-74.0), cols=2, ref=ref), M["red"], ws)
	# teal sleeves with red cuffs
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.add(name, L.sleeve(side, 0.0, 0.62, 0.016, steps=4, n=8, flare=0.014), M["teal"], wa)
		L.add(name, L.sleeve(side, 0.57, 0.63, 0.034, steps=1, n=8), M["red"], wa)
	# belt with a round gilded buckle, pouches
	L.add(name, _belt(L, 0.985, 1.05, 0.066, ref=ref), M["leather_dark"], wt)
	w, fd, bd = _sdims(L, 1.018, 0.066, 0.0, ref)
	L.add(name, _disc(V(0, -fd - 0.006, 1.018), V(0, -1, 0), 0.034, 0.012, n=10), M["gold"], wt)
	for ang in (-150.0, -30.0):
		body, flap = _pouch(L, math.radians(ang), 0.992, 0.066, size=(0.07, 0.04, 0.065), ref=ref)
		L.add(name, body, M["leather"], wt)
		L.add(name, flap, M["leather_dark"], wt)
	# fur mantle, red scarf, brooches
	back_extra = 0.062 if L.female else 0.085
	rings = _mantle(L, M, name, "fur", "fur_light", 90, back_extra)
	scarf = []
	for x, z in ((-0.1, 1.46), (-0.055, 1.405), (0.0, 1.37), (0.055, 1.405), (0.1, 1.46)):
		scarf.append(V(x, _front_y(L, x, z, g + 0.016), z))
	L.add(name, ribbon(scarf, [0.05, 0.06, 0.07, 0.06, 0.05], [V(0, -1, 0.3)] * 5), M["red"], wt)
	for sx in (-1.0, 1.0):
		p = rings[1][2 if sx > 0 else 14]
		o = V(p.x, p.y, 0).normalized()
		L.add(name, _disc(p + o * 0.012 + V(0, 0, -0.03), o, 0.03, 0.012, n=8), M["gold"], wt)
	# red cape with a pale beast and pale borders
	sx_ = J["p"]["shoulder_x"]
	yc = _back_line(L, [(0.95, 1.46, lambda z: L.torso_at(z)[2] + g + 0.012),
		(0.48, 1.0, lambda z: _sdims(L, z, 0.057, 0.06, ref)[2] if z >= 0.775 else _sdims(L, z, 0.034, 0.06, ref)[2]),
		(0.98, 1.05, lambda z: _sdims(L, z, 0.066, 0.0, ref)[2])], 0.02)
	cape, surf, width = _cape(L, sx_ * 1.0, sx_ * 1.65, 0.3, yc, n=8, curve=0.35,
		jag=sawtooth(9, 0.03, rnd=0.025, seed=91))
	wc = pl_rig.w_cape(J)
	L.add(name, cape, M["red"], wc)
	L.add(name, _emblem(surf, [(x, z - 0.5) for x, z in RAMPANT_BEAST], 0.0, 0.86, 0.32), M["pale"], wc)
	for sx in (-1.0, 1.0):
		xz = [(sx * (width(z) - 0.035), z) for z in (1.22, 1.0, 0.8, 0.6, 0.42, 0.34)]
		L.add(name, _cape_strip(surf, xz, 0.022), M["pale"], wc)


def _chest3(L, reg, M):
	name = reg.piece("chest", FAM, 3, notes="wolf knight: plate, wolf pelt, blue tabard and cloak")
	J = L.J
	wt, ws = pl_rig.w_torso(J), pl_rig.w_skirt(J)
	ref = (1.0, 0.42)
	g = 0.034
	rings = L.shell([0.97, 1.06, 1.15, 1.24, 1.32, 1.39, 1.44, 1.468], g, n=16)
	for i in range(1, 6):
		rings[i][0].y -= 0.012            # the breastplate's ridge
	L.add(name, rings_loft(rings), M["chest"], wt)
	L.add(name, rings_loft(L.shell([1.438, 1.474], g + 0.007, n=16)), M["gold"], wt)
	L.add(name, rings_loft(L.shell([0.958, 0.992], g + 0.008, n=16)), M["gold"], wt)
	# fauld lames, mail skirt, tabard panels, red strips
	for i, (z1, z0) in enumerate(((0.975, 0.9), (0.915, 0.84))):
		top = _sring(L, z1, 0.046 + 0.008 * i, 0.05, 16, ref=ref)
		bot = _sring(L, z0, 0.054 + 0.008 * i, 0.05, 16, ref=ref)
		L.add(name, rings_loft([bot, top]), M["chest"], ws)
	L.add(name, _skirt(L, [1.0, 0.88, 0.76, 0.64], 0.036, 0.04, n=16, jag=sawtooth(16, 0.012, seed=101), ref=ref,
		double=False), M["mail"], ws)
	a = math.radians
	for center in (-90.0, 90.0):
		L.add(name, _panel(L, [0.99, 0.8, 0.6, 0.4], 0.072, 0.05, a(center - 26.0), a(center + 26.0), cols=3,
			jag=sawtooth(4, 0.02, seed=102), ref=ref), M["pale"], ws)
		L.add(name, _panel(L, [0.99, 0.8, 0.6, 0.43], 0.076, 0.05, a(center - 21.0), a(center + 21.0), cols=3, ref=ref),
			M["blue"], ws)
	knot = []
	for z in (0.94, 0.8, 0.66, 0.52):
		w, fd, bd = _sdims(L, z, 0.08, 0.05, ref)
		knot.append(V(0, -fd, z))
	L.add(name, ribbon(knot, [0.03, 0.022, 0.03, 0.02], [V(0, -1, 0)] * 4), M["pale"], ws)
	r = rnd(103)
	for ang in (-128.0, -52.0, 128.0, 52.0):
		pts, nrm = [], []
		for z in (0.97, 0.8, 0.6 - r.random() * 0.06):
			w, fd, bd = _sdims(L, z, 0.066, 0.045, ref)
			x, y = _se(a(ang), w, fd, bd, 2.05)
			pts.append(V(x, y, z))
			nrm.append(V(x, y, 0).normalized())
		L.add(name, ribbon(pts, [0.036, 0.032, 0.024], nrm), M["red"], ws)
	# blue sleeves, steel rerebraces with gold rims, couters, layered pauldrons with wolf medallions
	ar = L.arm_radius(0.0)[0]
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.add(name, L.sleeve(side, 0.0, 0.62, 0.016, steps=4, n=8, flare=0.012), M["blue"], wa)
		L.add(name, L.sleeve(side, 0.12, 0.42, 0.032, steps=2, n=8), M["chest"], wa)
		L.add(name, L.sleeve(side, 0.4, 0.44, 0.037, steps=1, n=8), M["gold"], wa)
		el, o, d = _arm_out(L, side, 0.5)
		back = V(0, 1, 0) - d * d.y
		L.add(name, _cap(el + back.normalized() * (L.arm_radius(0.5)[1] + 0.008), back, V(sx, 0, 0), 0.05, 0.045, 0.035,
			n=8, rim=-0.3), M["chest"], wa)
		up = V(sx * math.sin(math.radians(30)), 0, math.cos(math.radians(30)))
		c = J["shoulder_" + side] + V(sx * 0.016, 0, 0.02)
		wsh = _shoulder_const(side)
		L.add(name, _cap(c + V(sx * 0.03, 0, -0.07), up, V(sx, 0, 0), ar + 0.06, ar + 0.052, 0.07, n=10, rim=-0.3), M["gold"], wsh)
		L.add(name, _cap(c + V(sx * 0.024, 0, -0.058), up, V(sx, 0, 0), ar + 0.056, ar + 0.05, 0.075, n=10, rim=-0.3), M["chest"], wsh)
		L.add(name, _cap(c, up, V(sx, 0, 0), ar + 0.052, ar + 0.046, 0.09, n=10, rim=-0.35), M["chest"], wsh)
		mp = c + V(sx * 0.04, -(ar + 0.05), 0.0)
		L.add(name, _disc(mp, V(sx * 0.35, -1, 0.2), 0.026, 0.01, n=8), M["gold"], wsh)
	# the wolf pelt and its head on the left shoulder
	back_extra = 0.065 if L.female else 0.095
	sx_ = J["p"]["shoulder_x"]
	_mantle(L, M, name, "wolf", "wolf_light", 110, back_extra, open_k=3, low=1.14, w_low=sx_ + 0.075, w_mid=sx_ + 0.012,
		front=0.05, front_rise=0.13)
	# a gilded wolf medallion on the breastplate
	fy = _front_y(L, 0.0, 1.27, g) - 0.012
	L.add(name, _disc(V(0, fy - 0.004, 1.27), V(0, -1, 0.15), 0.042, 0.01, n=10), M["gold"], wt)
	L.add(name, _disc(V(0, fy - 0.011, 1.27), V(0, -1, 0.15), 0.026, 0.008, n=8), M["chest"], wt)
	_wolf_head(L, M, name)
	# belt with a round buckle and a pouch
	L.add(name, _belt(L, 0.992, 1.05, 0.084, ref=ref), M["leather_dark"], wt)
	w, fd, bd = _sdims(L, 1.02, 0.084, 0.0, ref)
	L.add(name, _disc(V(0, -fd - 0.007, 1.02), V(0, -1, 0), 0.04, 0.014, n=10), M["gold"], wt)
	body, flap = _pouch(L, math.radians(-155.0), 0.995, 0.084, size=(0.07, 0.04, 0.065), ref=ref)
	L.add(name, body, M["leather"], wt)
	L.add(name, flap, M["leather_dark"], wt)
	# the long blue cloak with a wolf emblem and a knotted line
	sx_ = J["p"]["shoulder_x"]
	yc = _back_line(L, [(0.95, 1.46, lambda z: L.torso_at(z)[2] + g + 0.01),
		(0.4, 1.0, lambda z: _sdims(L, z, 0.08, 0.05, ref)[2]),
		(0.98, 1.06, lambda z: _sdims(L, z, 0.084, 0.0, ref)[2])], 0.022)
	cape, surf, width = _cape(L, sx_ * 1.12, sx_ * 1.95, 0.1, yc, n=8, curve=0.45,
		jag=sawtooth(9, 0.05, rnd=0.03, seed=111), zs=[J["cape_top"].z, J["cape_top"].z - 0.1, 1.15, 1.0, 0.8, 0.6, 0.38])
	wc = pl_rig.w_cape(J)
	L.add(name, cape, M["blue"], wc)
	L.add(name, _emblem(surf, WOLF_HEAD, 0.0, 0.86, 0.14), M["pale"], wc)
	L.add(name, _cape_strip(surf, [(0.0, 0.74), (0.0, 0.6), (0.0, 0.46), (0.0, 0.32)], 0.026), M["pale"], wc)
	for zc in (0.66, 0.44):
		L.add(name, _emblem(surf, [(0.0, 1.0), (0.7, 0.0), (0.0, -1.0), (-0.7, 0.0)], 0.0, zc, 0.045, lift=0.006), M["pale"], wc)


def _wolf_head(L, M, name):
	"""A stylised wolf head lying on the left shoulder of the pelt, looking forward."""
	J = L.J
	sx_ = J["p"]["shoulder_x"]
	wsh = _const({"clavicle_l": 0.6, "chest": 0.4})
	c = V(sx_ + 0.035, -0.035, 1.482)
	skull = box((0.1, 0.11, 0.075), center=tuple(c), top=(0.75, 0.8), shift=(0, 0.01))
	L.add(name, skull, M["wolf"], wsh)
	nose = c + V(-0.004, -0.14, -0.018)
	L.add(name, seg(c + V(0, -0.04, -0.004), nose, [(0, 0.034, 0.028), (1, 0.018, 0.015)], n=4, side=(1, 0, 0)), M["wolf"], wsh)
	L.add(name, octa(0.013, center=tuple(nose + V(0, -0.006, 0.004)), scale=(1.2, 1.0, 0.8)), M["dark"], wsh)
	for dx in (-0.03, 0.03):
		L.add(name, seg(c + V(dx, 0.01, 0.03), c + V(dx * 1.5, 0.03, 0.085), [(0, 0.02, 0.01), (1, 0.002, 0.002)], n=4,
			side=(1, 0, 0)), M["wolf_dark"], wsh)
		L.add(name, octa(0.008, center=tuple(c + V(dx * 0.9, -0.058, 0.016)), scale=(1.2, 0.6, 0.6)), M["dark"], wsh)


# ----------------------------------------------------------------------------------- gloves

def _hand_frame(L, side, scale):
	J = L.J
	sx = -1.0 if side == "r" else 1.0
	wr, kn = J["wrist_" + side], J["knuckle_" + side]
	k = (0.88 if L.female else (1.08 if L.look == "m2" else 1.0)) * scale
	return _frame(wr, V(sx, 0, 0), (kn - wr).normalized()), k


def _gloves1(L, reg, M):
	name = reg.piece("gloves", FAM, 1, notes="leather gloves, bracers with an iron plate")
	J = L.J
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.glove(side, M["leather"], grow=0.008, part=name)
		L.add(name, L.sleeve(side, 0.62, 0.97, 0.013, steps=3, n=8, flare=0.008), M["leather_dark"], wa)
		L.add(name, L.sleeve(side, 0.93, 1.0, 0.02, steps=1, n=8, flare=0.01), M["leather"], wa)
		L.add(name, _arm_plate(L, side, 0.66, 0.92, 0.021, 0.026, 0.02), M["gloves"], wa)
		for t in (0.7, 0.88):
			L.add(name, L.sleeve(side, t - 0.018, t + 0.018, 0.02, steps=1, n=8), M["leather"], wa)


def _gloves2(L, reg, M):
	name = reg.piece("gloves", FAM, 2, notes="plated gloves, runed vambraces")
	J = L.J
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.glove(side, M["leather_dark"], grow=0.008, part=name)
		Mf, k = _hand_frame(L, side, 1.096)
		L.add(name, box((0.07 * k, 0.012, 0.052 * k), center=(0, 0.022 * k, 0.04 * k), top=(0.9, 1.0)), M["gloves"], wa, M=Mf)
		L.add(name, box((0.074 * k, 0.014, 0.024 * k), center=(0, 0.018 * k, 0.083 * k)), M["gloves"], wa, M=Mf)
		L.add(name, L.sleeve(side, 0.58, 0.96, 0.02, steps=3, n=8, flare=0.006), M["gloves"], wa)
		for t0, t1 in ((0.57, 0.61), (0.92, 0.97)):
			L.add(name, L.sleeve(side, t0, t1, 0.027, steps=1, n=8), M["gold"], wa)
		for t in (0.7, 0.84):
			L.add(name, _arm_plate(L, side, t - 0.034, t + 0.034, 0.026, 0.012, 0.012, thick=0.005), M["gold"], wa)


def _gloves3(L, reg, M):
	name = reg.piece("gloves", FAM, 3, notes="runed plate gauntlets with flared cuffs")
	J = L.J
	for side, sx in SIDES:
		wa = pl_rig.w_arm(J, side)
		L.glove(side, M["leather_dark"], grow=0.008, part=name)
		Mf, k = _hand_frame(L, side, 1.096)
		L.add(name, box((0.074 * k, 0.014, 0.056 * k), center=(0, 0.023 * k, 0.04 * k), top=(0.88, 1.0)), M["gloves"], wa, M=Mf)
		L.add(name, box((0.078 * k, 0.016, 0.026 * k), center=(0, 0.02 * k, 0.084 * k)), M["gloves"], wa, M=Mf)
		L.add(name, _arm_tube(L, side, 0.54, 0.97, lambda u: 0.02 + 0.03 * (1.0 - u) ** 1.5, steps=3), M["gloves"], wa)
		L.add(name, _arm_tube(L, side, 0.535, 0.575, lambda u: 0.054 - 0.006 * u, steps=1), M["gold"], wa)
		L.add(name, L.sleeve(side, 0.93, 0.975, 0.026, steps=1, n=8), M["gold"], wa)
		for t in (0.7, 0.82):
			L.add(name, _arm_plate(L, side, t - 0.04, t + 0.04, 0.022 + 0.03 * (1.0 - (t - 0.54) / 0.43) ** 1.5, 0.014, 0.01,
				thick=0.005), M["gold"], wa)


# ----------------------------------------------------------------------------------- boots

def _boots1(L, reg, M):
	name = reg.piece("boots", FAM, 1, notes="strapped fur-topped boots, round knee pads")
	J = L.J
	for side, sx in SIDES:
		wf = pl_rig.w_leg(J, side)
		top, r = _boot_base(L, name, side, M["leather"], M["leather_dark"], z_top=0.4)
		p0, p1 = _leg_pt(L, side, 0.12), _leg_pt(L, side, 0.33)
		L.add(name, wrap_bands(p0, p1, _shaft_r(L, 0.12) + 0.004, _shaft_r(L, 0.33) + 0.004, 2, width=0.03, n=8, slant=14.0,
			side=(1, 0, 0)), M["leather_dark"], wf)
		L.add(name, _fur_cuff(L, side, 0.392, r + 0.004, seed=120 + (0 if side == "r" else 1), n=9), M["fur"], wf)
		c, dome = _knee_dome(L, side, 0.05, 0.022)
		L.add(name, dome, M["boots"], _knee_const(L, side))
		kz = J["knee_" + side].z - 0.06
		L.add(name, L.leg_tube(side, kz + 0.011, kz - 0.011, lambda z: L.trouser_radius(z, 1.02) + 0.007, steps=1, n=8),
			M["leather_dark"], wf)


def _boots2(L, reg, M):
	name = reg.piece("boots", FAM, 2, notes="leather boots, steel greaves, knee cops, fur cuffs")
	J = L.J
	for side, sx in SIDES:
		wf = pl_rig.w_leg(J, side)
		top, r = _boot_base(L, name, side, M["leather"], M["leather_dark"], z_top=0.42)
		gv, rows = _greave(L, side, 0.405, 0.1, 0.012)
		L.add(name, gv, M["boots"], wf)
		lc = _leg_pt(L, side, rows[0][0].z)
		L.add(name, ribbon([p + V(0, 0, -0.004) for p in rows[0]], 0.014,
			[V(p.x - lc.x, p.y - lc.y, 0).normalized() for p in rows[0]]), M["gold"], wf)
		p0, p1 = _leg_pt(L, side, 0.13), _leg_pt(L, side, 0.3)
		L.add(name, wrap_bands(p0, p1, _shaft_r(L, 0.13) + 0.016, _shaft_r(L, 0.3) + 0.016, 2, width=0.024, n=8, slant=0.0,
			side=(1, 0, 0)), M["leather_dark"], wf)
		L.add(name, _fur_cuff(L, side, 0.415, r + 0.01, seed=130 + (0 if side == "r" else 1), n=10, height=0.055), M["fur"], wf)
		c, dome = _knee_dome(L, side, 0.056, 0.026, lift=0.012)
		kc = _knee_const(L, side)
		L.add(name, dome, M["boots"], kc)
		L.add(name, _disc(c + V(0, 0.002, 0), V(0, -1, 0), 0.064, 0.008, n=8), M["gold"], kc)


def _boots3(L, reg, M):
	name = reg.piece("boots", FAM, 3, notes="alpha boots: wolf-head knee cops, plated greaves, fur, sabatons")
	J = L.J
	for side, sx in SIDES:
		wf = pl_rig.w_leg(J, side)
		ank, toe = J["ankle_" + side], J["toe_" + side]
		top, r = _boot_base(L, name, side, M["leather_dark"], M["dark"], z_top=0.42)
		L.add(name, box((0.1, 0.07, 0.03), center=(ank.x, toe.y + 0.065, 0.072), top=(0.85, 0.75), shift=(0, 0.012)),
			M["boots"], wf)
		gv, rows = _greave(L, side, 0.41, 0.1, 0.014)
		L.add(name, gv, M["boots"], wf)
		mid = [row[len(row) // 2] for row in rows]
		L.add(name, ribbon([p + V(0, -0.004, 0) for p in mid], 0.012, [V(0, -1, 0)] * len(mid)), M["gold"], wf)
		p0 = _leg_pt(L, side, 0.2)
		L.add(name, wrap_bands(p0 - V(0, 0, 0.02), p0 + V(0, 0, 0.02), _shaft_r(L, 0.2) + 0.018, _shaft_r(L, 0.2) + 0.018, 1,
			width=0.026, n=8, slant=0.0, side=(1, 0, 0)), M["leather"], wf)
		L.add(name, _fur_cuff(L, side, 0.435, r + 0.014, seed=140 + (0 if side == "r" else 1), n=9, height=0.06, tuft=0.04),
			M["wolf"], wf)
		# the wolf-head knee cop: a dome, a muzzle pointing down, ears, eyes
		c, dome = _knee_dome(L, side, 0.06, 0.03, lift=0.016)
		kc = _knee_const(L, side)
		L.add(name, dome, M["boots"], kc)
		L.add(name, seg(c + V(0, -0.02, -0.006), c + V(0, -0.05, -0.078), [(0, 0.024, 0.016), (1, 0.009, 0.006)], n=4,
			side=(1, 0, 0)), M["boots"], kc)
		for dx in (-0.032, 0.032):
			L.add(name, seg(c + V(dx, -0.012, 0.036), c + V(dx * 1.45, -0.004, 0.082), [(0, 0.013, 0.006), (1, 0.001, 0.001)],
				n=4, side=(1, 0, 0)), M["boots"], kc)
		L.add(name, box((0.05, 0.008, 0.009), center=tuple(c + V(0, -0.028, 0.012))), M["gold"], kc)


# a rampant beast facing left (the axeguard's emblem), x in -0.5..0.5, z in 0..1
RAMPANT_BEAST = [(-0.10, 1.00), (0.05, 0.96), (0.13, 0.82), (0.10, 0.66), (0.22, 0.50), (0.30, 0.50), (0.36, 0.66),
	(0.32, 0.86), (0.44, 0.72), (0.40, 0.48), (0.30, 0.36), (0.28, 0.22), (0.24, 0.0), (0.06, 0.0), (0.10, 0.1), (0.0, 0.2),
	(-0.12, 0.26), (-0.26, 0.14), (-0.32, 0.2), (-0.16, 0.34), (-0.08, 0.42), (-0.28, 0.46), (-0.36, 0.52), (-0.30, 0.58),
	(-0.12, 0.56), (-0.30, 0.66), (-0.40, 0.74), (-0.34, 0.80), (-0.14, 0.70), (-0.2, 0.78), (-0.36, 0.82), (-0.24, 0.86),
	(-0.38, 0.92), (-0.22, 0.98)]
# a wolf's head seen from the front (the wolf knight's emblem), x in -0.75..0.75, z in -0.9..1
WOLF_HEAD = [(-0.55, 1.0), (-0.25, 0.55), (0.0, 0.62), (0.25, 0.55), (0.55, 1.0), (0.62, 0.35), (0.75, 0.0), (0.4, -0.45),
	(0.15, -0.75), (0.0, -0.9), (-0.15, -0.75), (-0.4, -0.45), (-0.75, 0.0), (-0.62, 0.35)]

HELMS = {1: _helm1, 2: _helm2, 3: _helm3}
CHESTS = {1: _chest1, 2: _chest2, 3: _chest3}
GLOVES = {1: _gloves1, 2: _gloves2, 3: _gloves3}
BOOTS = {1: _boots1, 2: _boots2, 3: _boots3}
