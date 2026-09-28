"""Intelligence gear of the player (tools/blender/player; the rules are in pl_gear): the mages'
hoods, circlets, crowns, robes, gloves and boots, after the reference sheets:
  tier 1  common "novice mage": a blue hood with a patterned border, a blue hooded shawl with a
          brooch over a long beige robe, layered blue / teal over-skirts, two belts, a satchel and
          a book; fingerless gloves with wrapped bracers; cross-strapped boots with cloth wraps;
  tier 2  rare "spellblade" / "battle mage": a silver half-helm with a nasal, cheek guards, a violet
          gem and a plume; a navy coat with steel pauldrons and breastplate, crossed straps, a rune
          panel, purple under-skirts and a purple cape with a star; dark gloves under runed steel
          vambraces; heeled boots with greaves and knee cops;
  tier 3  unique "storm seer": a dark spiked crown with a glowing gem (over the hair); a long dark
          rune robe with a black fur mantle, white and pale blue torn layers, a medallion belt and
          a long rune cape; long black gloves with runed silver bracers; armoured heeled boots.
Tinted with the item colour: the hood, the plume, the crown's metal, the robe / coat / shawl cloth
(and the tier 3 cape), the glove fabric and the boot wraps / leather. Linen, leather straps,
silver, steel, fur and gems keep their colours.
"""
import math

from mathutils import Vector

import pl_body
import pl_rig
from pl_mesh import (R, T, box, cyl, double_sided, fan_cap, flip, foot_box, mat, merge, octa, patch, ribbon, ring,
	rings_loft, rnd, sawtooth, sphere, strand, tint, tube, wrap_bands, xf)

FAM = "int"
HELM_HIDES = {1: ["HairTop", "HairBack"], 2: ["HairTop"], 3: []}
NOTES = {
	("helm", 1): "blue hood with a patterned border (face open, front hair strands show)",
	("helm", 2): "silver half-helm: nasal, cheek guards, violet gem, plume",
	("helm", 3): "dark spiked crown with a glowing gem, worn over the hair",
	("chest", 1): "beige robe, blue shawl with brooch, blue / teal over-skirt, belts, satchel, book",
	("chest", 2): "navy coat, steel pauldrons and breastplate, straps, rune panel, purple cape",
	("chest", 3): "long dark rune robe, black fur mantle, white / pale blue layers, rune cape",
	("gloves", 1): "fingerless leather gloves, wrapped cloth bracers",
	("gloves", 2): "dark gloves under runed steel vambraces",
	("gloves", 3): "long black gloves, runed silver bracers",
	("boots", 1): "cross-strapped leather boots, cloth wraps over the trousers",
	("boots", 2): "heeled boots with steel greaves and knee cops",
	("boots", 3): "tall armoured heeled boots, silver plates, glowing runes",
}

# Fixed materials: sRGB hex, roughness, metallic[, emission strength].
MATS = {
	"linen": ("c3b394", 0.92, 0.0),
	"linen_dark": ("9a8a6e", 0.92, 0.0),
	"lining": ("2d2f3b", 0.95, 0.0),
	"border": ("cdb993", 0.9, 0.0),
	"border_dark": ("6d5a43", 0.9, 0.0),
	"teal": ("3e6a6e", 0.9, 0.0),
	"leather": ("5c4331", 0.75, 0.0),
	"leather_dark": ("3d2d21", 0.75, 0.0),
	"bronze": ("a07e4a", 0.45, 0.6),
	"book": ("4b3024", 0.8, 0.0),
	"pages": ("d9ccae", 0.9, 0.0),
	"silver": ("b4b9c2", 0.38, 0.75),
	"silver_dark": ("767b85", 0.42, 0.7),
	"steel": ("858b95", 0.4, 0.7),
	"gold": ("c9a55a", 0.35, 0.8),
	"trim": ("c9ccd3", 0.6, 0.3),
	"purple": ("532c4e", 0.88, 0.0),
	"purple_dark": ("3a2039", 0.9, 0.0),
	"white": ("dcd8cf", 0.9, 0.0),
	"pale_blue": ("9fb3c9", 0.9, 0.0),
	"fur_black": ("25262e", 1.0, 0.0),
	"fur_dark": ("383945", 1.0, 0.0),
	"sole": ("2e241b", 0.9, 0.0),
	"gem_violet": ("b27cff", 0.3, 0.0, 3.0),
	"gem_blue": ("78c2ff", 0.3, 0.0, 4.0),
	"rune_violet": ("a47cff", 0.4, 0.0, 2.0),
	"rune_blue": ("86ccff", 0.4, 0.0, 2.5),
}
# Tinted surfaces per (slot, tier): linear grey (albedo x item tint), roughness, metallic.
TINTS = {
	("helm", 1): (0.42, 0.9, 0.0),     # the hood
	("helm", 2): (0.4, 0.85, 0.0),     # the plume
	("helm", 3): (0.1, 0.38, 0.7),     # the crown's dark metal
	("chest", 1): (0.38, 0.9, 0.0),    # the shawl and the over-skirt
	("chest", 2): (0.18, 0.85, 0.0),   # the navy coat
	("chest", 3): (0.12, 0.85, 0.0),   # the dark robe and its cape
	("gloves", 1): (0.45, 0.9, 0.0),   # the bracer wraps
	("gloves", 2): (0.16, 0.6, 0.0),   # the gloves
	("gloves", 3): (0.07, 0.5, 0.0),   # the long gloves
	("boots", 1): (0.62, 0.9, 0.0),    # the cloth wraps
	("boots", 2): (0.18, 0.6, 0.0),    # the boot leather
	("boots", 3): (0.1, 0.5, 0.0),     # the tall boots
}


def build(L, reg):
	g = _Int(L)
	for tier in (1, 2, 3):
		for slot in ("helm", "chest", "gloves", "boots"):
			hides = HELM_HIDES[tier] if slot == "helm" else None
			name = reg.piece(slot, FAM, tier, hides=hides, notes=NOTES[(slot, tier)])
			getattr(g, "%s_%d" % (slot, tier))(name)


# ----------------------------------------------------------------------------------- geometry

def V(*a):
	return Vector(a[0]) if len(a) == 1 else Vector(a)


def _compact(geo):
	"""Drop the vertices no face uses."""
	verts, faces = geo
	used, out_v, out_f = {}, [], []
	for f in faces:
		nf = []
		for i in f:
			if i not in used:
				used[i] = len(out_v)
				out_v.append(Vector(verts[i]))
			nf.append(used[i])
		out_f.append(nf)
	return out_v, out_f


def _loft(rings, skip=None, key=None, closed=True):
	"""Quads between consecutive rings (bottom -> top, points CCW seen from above: outward faces).
	skip(band, seg) leaves a face out; key(band, seg) splits the faces into groups -> {key: geo}."""
	n = len(rings[0])
	verts, idx = [], []
	for r in rings:
		idx.append(list(range(len(verts), len(verts) + len(r))))
		verts.extend(Vector(p) for p in r)
	groups = {}
	for i in range(len(rings) - 1):
		a, b = idx[i], idx[i + 1]
		for k in range(n if closed else n - 1):
			if skip is not None and skip(i, k):
				continue
			k1 = (k + 1) % n
			groups.setdefault(key(i, k) if key else 0, []).append([a[k], a[k1], b[k1], b[k]])
	out = {g: _compact((verts, fs)) for g, fs in groups.items()}
	return out if key else out.get(0, ([], []))


def _split(geo, key):
	"""Split a geometry's faces into groups by key(face index) -> {key: geo}."""
	verts, faces = geo
	groups = {}
	for i, f in enumerate(faces):
		groups.setdefault(key(i), []).append(f)
	return {g: _compact((verts, fs)) for g, fs in groups.items()}


def _arc(z, w, fd, bd, angles, cy=0.0, sq=2.05, jag=None):
	"""Points of a superellipse ring (like pl_mesh.ring) at the given angles: degrees from the front,
	+ toward the character's left (+X); increasing angles run CCW seen from above."""
	ex = 2.0 / sq
	pts = []
	for k, th in enumerate(angles):
		a = math.radians(th - 90.0)
		c, s = math.cos(a), math.sin(a)
		x = w * math.copysign(abs(c) ** ex, c)
		y = cy + (fd if s < 0 else bd) * math.copysign(abs(s) ** ex, s)
		p = Vector((x, y, z))
		if jag is not None:
			p.z += jag(k, x, y)
		pts.append(p)
	return pts


def _sy(w, d, x, sq=2.2):
	"""|y| of a superellipse ring (half width w, depth d) at x."""
	u = min(1.0, abs(x) / w)
	return d * (1.0 - u ** sq) ** (1.0 / sq)


def _basis(nrm, up):
	n = V(nrm).normalized()
	u = V(up)
	u = u - n * u.dot(n)
	if u.length < 1e-6:
		u = V((0, 0, 1)) - n * n.z
	u.normalize()
	return n, u, u.cross(n)


def _star(c, nrm, up, r_out, r_in, pts=8, h=0.005):
	"""A low star plate on a surface (raised centre)."""
	n, u, s = _basis(nrm, up)
	c = V(c)
	verts = [c + n * h]
	m = pts * 2
	for i in range(m):
		a = math.pi * i / pts
		r = r_out if i % 2 == 0 else r_in
		verts.append(c + (u * math.cos(a) + s * math.sin(a)) * r + n * 0.001)
	faces = [[0, 1 + (i + 1) % m, 1 + i] for i in range(m)]
	return verts, faces


def _annulus(c, nrm, up, r_out, r_in, seg=12, h=0.003):
	"""A flat ring on a surface (emblems)."""
	n, u, s = _basis(nrm, up)
	c = V(c)
	verts = []
	for i in range(seg):
		a = 2.0 * math.pi * i / seg
		d = u * math.cos(a) + s * math.sin(a)
		verts.append(c + d * r_out + n * h)
		verts.append(c + d * r_in + n * h)
	faces = []
	for i in range(seg):
		j = (i + 1) % seg
		faces.append([2 * i, 2 * i + 1, 2 * j + 1, 2 * j])
	return verts, faces


def _disc(c, nrm, r, thick=0.008, n=8):
	"""A medallion / brooch: a short cylinder along the normal."""
	nn = V(nrm).normalized()
	c = V(c)
	return cyl(c - nn * thick * 0.5, c + nn * thick * 0.5, r, n=n, side=(0, 0, 1))


def _glyph(c, nrm, up, s, kind, lift=0.004):
	"""A small rune on a surface: a stem and two strokes (flat quads)."""
	n, u, side = _basis(nrm, up)
	c = V(c)
	out = [patch(c, n, s * 0.2, s, up=u, lift=lift)]
	kind %= 4
	if kind == 0:      # like fehu: two strokes up to the right
		for dz in (0.28, 0.02):
			d = (u * 0.55 + side * 0.83).normalized()
			out.append(patch(c + u * (s * dz) + side * (s * 0.2), n, s * 0.16, s * 0.5, up=d, lift=lift))
	elif kind == 1:    # like algiz: two strokes from the top, spread
		for sx in (-1.0, 1.0):
			d = (u * 0.7 + side * 0.7 * sx).normalized()
			out.append(patch(c + u * (s * 0.3) + side * (s * 0.15 * sx), n, s * 0.16, s * 0.45, up=d, lift=lift))
	elif kind == 2:    # like tiwaz: an arrow head
		for sx in (-1.0, 1.0):
			d = (u * 0.7 - side * 0.7 * sx).normalized()
			out.append(patch(c + u * (s * 0.33) + side * (s * 0.14 * sx), n, s * 0.16, s * 0.42, up=d, lift=lift))
	else:              # like nauthiz: one crossing stroke
		d = (u * 0.5 + side * 0.86).normalized()
		out.append(patch(c, n, s * 0.16, s * 0.75, up=d, lift=lift))
	return merge(*out)


def _fur_along(pts, height, tuft, seed=1, drop=0.0, axis=(0.0, 0.0)):
	"""Fur tufts along a closed ring of points (like pl_mesh.fur_ring, for hems that are not flat):
	spikes leaning out and down from every segment."""
	r = rnd(seed)
	verts, faces = [], []
	ax = V((axis[0], axis[1], 0.0))
	n = len(pts)
	for k in range(n):
		p0, p1 = V(pts[k]), V(pts[(k + 1) % n])
		mid = (p0 + p1) * 0.5
		out = V((mid.x, mid.y, 0.0)) - ax
		out.normalize()
		h = height * (0.7 + 0.6 * r.random())
		tip = mid + out * tuft * (0.6 + 0.8 * r.random()) + V((0, 0, -h * 0.35 - drop * r.random()))
		top = mid - out * 0.01 + V((0, 0, h * 0.65))
		i = len(verts)
		verts += [p0, p1, tip, top]
		faces += [[i, i + 1, i + 2], [i + 1, i, i + 3], [i, i + 2, i + 3], [i + 1, i + 3, i + 2]]
	return verts, faces


def _edge_jag(n, depth, rnd_=0.0, seed=0):
	"""sawtooth() for an open arc of n points whose two end points (the opening's edges) stay put."""
	f = sawtooth(n, depth, rnd=rnd_, seed=seed)
	return lambda k, x, y: 0.0 if k in (0, n - 1) else f(k, x, y)


def _offset(geo, d, axis=(0.0, 0.0)):
	"""Move every vertex by d along its horizontal direction from a vertical axis (d < 0: inward)."""
	verts, faces = geo
	ax = V((axis[0], axis[1], 0.0))
	out = []
	for v in verts:
		h = V((v.x, v.y, 0.0)) - ax
		if h.length > 1e-6:
			h.normalize()
		out.append(V(v) + h * d)
	return out, faces


# ----------------------------------------------------------------------------------- builder

class _Int:
	def __init__(self, L):
		self.L = L
		self.J = L.J
		self.k = 0.94 if L.female else 1.0
		self.hz = L.J["head_z"]
		self.nr = 0.055 if L.female else (0.066 if L.look == "m2" else 0.06)
		self.baggy = 0.95 if L.female else 1.02
		self.hand_k = 0.88 if L.female else (1.08 if L.look == "m2" else 1.0)
		self._m = {}
		self.wt = pl_rig.w_torso(self.J)
		self.ws = pl_rig.w_skirt(self.J)
		self.wh = pl_rig.w_head(self.J)
		J = self.J
		# hood / collar: chest -> neck -> head by height
		self.w_hood = pl_rig.chain([V((0, 0, J["shoulder_z"] - 0.1)), V((0, 0, J["neck_z"])), V((0, 0, self.hz)),
			V((0, 0, J["head_top"] + 0.2))], ["chest", "neck", "head"], [0.03, 0.035])

	# -- materials
	def m(self, key):
		if key not in self._m:
			spec = MATS[key]
			emit = spec[0] if len(spec) > 3 else None
			self._m[key] = mat("int_" + key, spec[0], rough=spec[1], metal=spec[2], emit=emit,
				strength=spec[3] if len(spec) > 3 else 0.0)
		return self._m[key]

	def t(self, slot, tier):
		key = "tint_%s_int%d" % (slot, tier)
		if key not in self._m:
			g, rough, metal = TINTS[(slot, tier)]
			self._m[key] = tint(key, grey=g, rough=rough, metal=metal)
		return self._m[key]

	def add(self, name, geo, material, weights, M=None):
		if geo[1]:
			self.L.add(name, geo, material, weights, M)

	def add_groups(self, name, groups, mats, weights, double=False, inner=None):
		"""Add {key: geo} groups with mats[key]; double: also the back faces (inner[key] or the same
		material: trims and borders only show outside)."""
		for key, geo in groups.items():
			self.add(name, geo, mats[key], weights)
			if double:
				self.add(name, flip(geo), mats[(inner or {}).get(key, key)], weights)

	# -- body measures
	def arm_at(self, side, z):
		"""(x, y, radius) of the upper arm (rest pose) at height z."""
		J = self.J
		sh, el = J["shoulder_" + side], J["elbow_" + side]
		t = max(0.0, min(1.0, (sh.z - z) / (sh.z - el.z)))
		p = sh.lerp(el, t)
		return p.x, p.y, self.L.arm_radius(t * 0.5)[0]

	def trouser_r(self, z):
		L = self.L
		return max(L.trouser_radius(zz, self.baggy) for zz in (z - 0.03, z, z + 0.03))

	def skirt_dims(self, z, z_top, z_bot, grow, flare, widen=0.02, deepen=0.03):
		"""(half width, front, back) of a hem at height z (like Look.skirt: the hips, then flaring)."""
		L = self.L
		w0, f0, b0 = L.torso_at(min(z_top, 0.93))
		t = max(0.0, (z_top - z) / max(1e-6, z_top - z_bot))
		bw, bf, bb = L.torso_at(z) if z > 0.84 else (w0, f0, b0)
		k = grow + flare * t
		return max(bw, w0 * 0.98) + k + widen * t, max(bf, f0 * 0.98) + k + deepen * t, max(bb, b0 * 0.98) + k + deepen * t

	def hem_rings(self, zs, z_top, z_bot, grow, flare, angles=None, n=16, jag=None, jag_rows=1, sq=2.05):
		"""Rings bottom -> top of a skirt / coat / robe; closed rings (n points) or open arcs at
		`angles`. jag(k, x, y) tears the lowest `jag_rows` rings alike."""
		out = []
		for i, z in enumerate(sorted(zs)):
			w, fd, bd = self.skirt_dims(z, z_top, z_bot, grow, flare)
			j = jag if i < jag_rows else None
			if angles is None:
				out.append(ring(z, w, fd, bd, n=n, sq=sq, jag=j))
			else:
				out.append(_arc(z, w, fd, bd, angles, sq=sq, jag=j))
		return out

	def extent(self, parts, z0, z1, margin=0.0):
		"""(max |x|, front, back) of the named parts' vertices between two heights (unit space)."""
		mx, fr, bk = 0.0, 0.0, 0.0
		for pn in parts:
			P = self.L.parts.get(pn)
			if P is None:
				continue
			for v in P.verts:
				if z0 <= v.z <= z1:
					mx = max(mx, abs(v.x))
					fr = max(fr, -v.y)
					bk = max(bk, v.y)
		return mx + margin, fr + margin, bk + margin

	def mantle_rings(self, reach, drops, depth=0.035, n=16, jag=None, border=0.0):
		"""A shawl / mantle over the shoulders: rings bottom -> top from the hem up to a collar round
		the neck. drops = (front, side, back) heights of the hem; the side covers the upper arms."""
		L, J = self.L, self.J
		nz = J["neck_z"]
		zf, zs_, zb = drops

		def zfn(row_f, row_s, row_b):
			def f(k):
				th = 2.0 * math.pi * k / n
				c = math.cos(th)
				fr, bk = max(0.0, c) ** 1.5, max(0.0, -c) ** 1.5
				return row_s + (row_f - row_s) * fr + (row_b - row_s) * bk
			return f

		def row(zf_, zs2, zb_, w, fd, bd, jag_=None):
			pts = ring(0.0, w, fd, bd, n=n, sq=2.1)
			zf2 = zfn(zf_, zs2, zb_)
			for k, p in enumerate(pts):
				p.z = zf2(k)
				if jag_ is not None:
					p.z += jag_(k, p.x, p.y)
			return pts

		ax, _ay, ar = self.arm_at("l", J["shoulder_z"])
		z1 = nz - 0.035
		_w, f1, b1 = L.torso_at(z1)
		r1 = row(z1, J["shoulder_z"] - 0.002, z1, ax + ar + reach, f1 + depth, b1 + depth)
		z2s = (J["shoulder_z"] + zs_) * 0.5 + 0.01
		x2, _y2, a2 = self.arm_at("l", z2s)
		z2f = (z1 + zf) * 0.5
		_w, f2, b2 = L.torso_at(z2f)
		r2 = row(z2f, z2s, (z1 + zb) * 0.5, x2 + a2 + reach + 0.006, max(f2, f1) + depth + 0.004, max(b2, b1) + depth + 0.004)
		x3, _y3, a3 = self.arm_at("l", zs_)
		_w, f3, b3 = L.torso_at(zf)
		w3, fd3, bd3 = x3 + a3 + reach + 0.014, max(f3, f2) + depth + 0.01, max(b3, b2) + depth + 0.01
		hem = row(zf, zs_, zb, w3, fd3, bd3, jag)
		r0 = ring(nz + 0.008, self.nr + 0.04, self.nr + 0.038, self.nr + 0.044, n=n, sq=2.1)
		rows = [hem]
		if border > 0.0:
			rows.append(row(zf + border, zs_ + border * 0.9, zb + border, w3 - 0.002, fd3 - 0.001, bd3 - 0.001, jag))
		return rows + [r2, r1, r0]

	def cape_rows(self, zs, width_top, width_bot, drape, n, curve=0.35, jag=None, jag_rows=1, clear=None):
		"""Rows (top -> bottom) of n + 1 points of a cape hanging down the back (like Look.cape).
		clear(x, z) -> the least y there (the skirts / belts the cape hangs over)."""
		L, J = self.L, self.J
		top = J["cape_top"]
		z_bot = zs[-1]
		rows = []
		for i, z in enumerate(zs):
			t = (top.z - z) / max(0.01, top.z - z_bot)
			w = width_top + (width_bot - width_top) * min(1.0, t * 1.6)
			_w, _fd, bd = L.torso_at(max(z, 1.0))
			y0 = bd + 0.02 + drape * t
			row = []
			for kk in range(n + 1):
				u = -1.0 + 2.0 * kk / n
				y = y0 + curve * w * (1 - u * u) * (0.6 if z > 1.2 else 0.25)
				if clear is not None:
					y = max(y, clear(u * w, z))
				dz = jag(kk, u) if (jag is not None and i >= len(zs) - jag_rows) else 0.0
				row.append(V((u * w, y, z + dz)))
			rows.append(row)
		return rows

	def back_clear(self, layers, belt=None):
		"""clear(x, z) for cape_rows: behind the hem layers [(z_top, z_bot, grow, flare)] and a belt
		(z0, z1, grow)."""
		L = self.L

		def f(x, z):
			y = -1.0
			for z_top, z_bot, grow, flare in layers:
				if z_bot - 0.06 <= z <= z_top + 0.02:
					w, _fd, bd = self.skirt_dims(z, z_top, z_bot, grow, flare)
					y = max(y, _sy(w, bd, x, 2.05) + 0.022)
			if belt is not None and belt[0] - 0.03 <= z <= belt[1] + 0.03:
				w, _fd, bd = L.torso_at(z)
				y = max(y, _sy(w + belt[2], bd + belt[2], x) + 0.02)
			return y
		return f

	@staticmethod
	def cape_faces(rows, band_key=None):
		"""Outer (+Y) faces of cape rows -> {key: geo} (key = band_key(band) or 0)."""
		verts = [p for r in rows for p in r]
		w_ = len(rows[0])
		groups = {}
		for i in range(len(rows) - 1):
			for kk in range(w_ - 1):
				a = i * w_ + kk
				groups.setdefault(band_key(i) if band_key else 0, []).append([a, a + 1, a + w_ + 1, a + w_])
		return {g: _compact((verts, fs)) for g, fs in groups.items()}

	@staticmethod
	def cape_center(rows, z):
		"""The cape's centre-line point at height z (rows top -> bottom, odd point count)."""
		c = len(rows[0]) // 2
		for a, b in zip(rows, rows[1:]):
			pa, pb = a[c], b[c]
			if pb.z <= z <= pa.z:
				t = (pa.z - z) / max(1e-6, pa.z - pb.z)
				return pa.lerp(pb, t)
		return rows[-1][c].copy()

	def front_y(self, x, z, grow):
		"""The torso's front surface (y, negative) at (x, z), grown."""
		w, fd, _bd = self.L.torso_at(z)
		return -_sy(w + grow, fd + grow, x)

	def hang_w(self, side, share=0.5):
		"""Weights for things hanging at a hip: the hips and that side's skirt panel."""
		return pl_rig.mix((pl_rig.rigid("hips"), 1.0 - share), (pl_rig.rigid("skirt_" + side), share))

	def dome_front(self, z_rel, grow):
		"""y of the front of Look.dome(.., grow) at z_rel above head_z."""
		spec, top = self.L.head_spec()
		z = min(z_rel, top - 0.02)
		_w, fd, _bd, cy = pl_body._interp_head(spec, z)
		shrink = 1.0 - max(0.0, (z - (top - 0.06)) / 0.06) * 0.35
		return -(fd + grow) * shrink + cy

	def arm_surface(self, side, t, out, grow):
		"""A point on a sleeve / bracer (Look.sleeve at `grow`) at t along the arm, in the direction
		`out` (perpendicular to the arm), and that direction made perpendicular."""
		L, J = self.L, self.J
		p = L.arm_path(side, t, t, steps=1)[0]
		d = J["upper_arm_dir_" + side] if t < 0.5 else J["forearm_dir_" + side]
		out = V(out)
		out = (out - d * out.dot(d)).normalized()
		fx = V((0, -1, 0))
		fx = (fx - d * fx.dot(d)).normalized()
		fy = d.cross(fx)
		rx, ry = L.arm_radius(t)
		rx, ry = rx + grow, ry + grow
		c, s = out.dot(fx), out.dot(fy)
		r = rx * ry / math.sqrt((ry * c) ** 2 + (rx * s) ** 2)
		return p + out * r, out

	# ------------------------------------------------------------------------------ helms

	def helm_1(self, name):
		"""The novice's hood: pulled up, face open, a patterned border round the face and the cowl."""
		L, J, k, hz = self.L, self.J, self.k, self.hz
		cloth = self.t("helm", 1)
		n = 12
		spec = [  # (z above head_z, half width, front, back, cy), bottom -> top
			(-0.022, 0.1, 0.1, 0.116, -0.012),
			(0.04, 0.12, 0.108, 0.13, -0.006),
			(0.105, 0.13, 0.118, 0.14, 0.0),
			(0.17, 0.128, 0.118, 0.142, 0.0),
			(0.222, 0.114, 0.104, 0.13, 0.008),
			(0.262, 0.072, 0.062, 0.096, 0.016),
		]
		head = [ring(hz + z * k, w * k, fd * k, bd * k, n=n, cy=cy * k, sq=2.1) for z, w, fd, bd, cy in spec]
		zc = J["neck_z"] - 0.006
		tw, tf, tb = L.torso_at(zc)
		cowl = ring(zc, tw + 0.02, tf + 0.026, tb + 0.024, n=n, sq=2.1)
		for i, dz in ((0, -0.035), (1, -0.012), (11, -0.012), (6, -0.045), (5, -0.018), (7, -0.018)):
			cowl[i].z += dz
		upper = [p.lerp(q, 0.3) for p, q in zip(cowl, head[0])]
		rings = [cowl, upper] + head          # bands: 0 border, 1 cowl, 2..5 round the face, 6 top
		face = {10, 11, 0, 1}
		opening = lambda i, s: 2 <= i <= 5 and s in face
		apex = V((0, 0.035 * k, hz + 0.3 * k))
		groups = _loft(rings, skip=opening, key=lambda i, s: ("b%d" % (s % 2)) if i == 0 else "c")
		mats = {"b0": self.m("border"), "b1": self.m("border_dark"), "c": cloth}
		self.add_groups(name, groups, mats, self.w_hood)
		self.add(name, fan_cap(head[-1], apex), cloth, self.w_hood)
		# the lining (seen round the face), a little inside
		lin = _loft(rings[1:], skip=lambda i, s: i == 0 or (1 <= i <= 4 and s in face))
		lin = merge(lin, fan_cap(head[-1], apex))
		self.add(name, flip(_offset(lin, -0.004, (0, 0.004))), self.m("lining"), self.w_hood)
		# the face border: a braid round the opening, light and dark
		B, C, D, E, F = rings[6], rings[5], rings[4], rings[3], rings[2]
		loop = [B[10], B[11], B[0], B[1], B[2], C[2], D[2], E[2], F[2], F[1], F[0], F[11], F[10], E[10], D[10], C[10], B[10]]
		rim = tube(loop, [0.011 * k] * len(loop), n=3, cap0=False, cap1=False)
		for key, geo in _split(rim, lambda i: (i // 3) % 2).items():
			self.add(name, geo, self.m("border" if key == 0 else "border_dark"), self.w_hood)

	def helm_2(self, name):
		"""The spellblade's half-helm: a silver dome, a brow band with a violet gem and a crest, a
		nasal, cheek guards and a plume down the back."""
		L, J, k, hz = self.L, self.J, self.k, self.hz
		silver, dark = self.m("silver"), self.m("silver_dark")
		wh = self.wh
		spec, top = L.head_spec()
		self.add(name, L.dome(0.14 * k, 0.03, n=12, rings=4), silver, wh)
		z0, z1, g = 0.125 * k, 0.178 * k, 0.036
		w0, f0, b0, c0 = pl_body._interp_head(spec, z0)
		w1, f1, b1, c1 = pl_body._interp_head(spec, z1)
		lo = ring(hz + z0, w0 + g, f0 + g, b0 + g, n=14, cy=c0, sq=2.2)
		hi = ring(hz + z1, w1 + g + 0.004, f1 + g + 0.004, b1 + g + 0.004, n=14, cy=c1, sq=2.2)
		inner = ring(hz + z0, w0 + g - 0.01, f0 + g - 0.01, b0 + g - 0.01, n=14, cy=c0, sq=2.2)
		self.add(name, rings_loft([lo, hi]), silver, wh)
		self.add(name, rings_loft([inner, lo]), dark, wh)
		# crest plate up the front of the dome, the gem on the band
		pts = [V((0, -(f1 + g + 0.004) + c1 - 0.002, hz + z1 - 0.012))]
		for zr in (0.2 * k, 0.232 * k):
			pts.append(V((0, self.dome_front(zr, 0.03) - 0.004, hz + zr)))
		self.add(name, ribbon(pts, [0.05 * k, 0.034 * k, 0.012], (0, -1, 0.4), thick=0.006), dark, wh)
		gz = hz + (z0 + z1) * 0.5
		self.add(name, octa(0.024 * k, center=(0, -(f0 + g) - 0.006, gz), scale=(1.0, 0.45, 1.0)), dark, wh)
		self.add(name, octa(0.016 * k, center=(0, -(f0 + g) - 0.014, gz), scale=(0.8, 0.6, 1.25)), self.m("gem_violet"), wh)
		# nasal down to the nose bridge
		nasal = ribbon([V((0, -(f0 + g) + 0.006, hz + z0 + 0.006)), V((0, -0.128 * k - 0.004, hz + 0.082 * k))],
			[0.024 * k, 0.014 * k], (0, -1, 0.15), thick=0.005)
		self.add(name, nasal, silver, wh)
		# cheek guards
		for sx in (-1.0, 1.0):
			a = V((sx * (w0 + g) * 0.86, -(f0 + g) * 0.5 + c0, hz + z0 + 0.008))
			b = V((sx * 0.094 * k, -0.068 * k, hz + 0.04 * k))
			guard = ribbon([a, a.lerp(b, 0.5) + V((sx * 0.006, 0, 0)), b], [0.058 * k, 0.05 * k, 0.034 * k], (sx, -0.45, 0.0), thick=0.005)
			self.add(name, guard, silver, wh)
		# the plume: a horsehair crest from the brow over the top, falling down the back
		plume = self.t("helm", 2)
		apex = hz + top + 0.03
		for sx, lz, w, dz in ((0.0, -0.04, 0.075, 0.0), (-0.022, 0.03, 0.058, -0.012), (0.022, 0.0, 0.058, -0.012),
				(0.0, 0.08, 0.05, 0.02)):
			pts = [V((sx * 0.5, -0.012 * k, apex - 0.018 + dz)), V((sx, 0.045 * k, apex + 0.045 * k + dz)),
				V((sx * 1.4, 0.13 * k, apex + 0.03 * k + dz)), V((sx * 1.8, 0.2 * k, apex - 0.045 + dz)),
				V((sx * 2.0, 0.235 * k, hz + 0.12 * k)), V((sx * 2.1, 0.225 * k, hz + lz * k))]
			self.add(name, strand(pts, w * k, 0.022, depth=0.5, n=3), plume, wh)

	def helm_3(self, name):
		"""The storm seer's crown: a dark band over the hair, spikes (tallest at the front, two
		horns at the back) and a glowing blue gem."""
		L, J, k, hz = self.L, self.J, self.k, self.hz
		metal = self.t("helm", 3)
		wh = self.wh
		spec, _top = L.head_spec()
		n = 14
		zf, zb, hgt = 0.15 * k, 0.178 * k, 0.042 * k
		ex, efr, ebk = self.extent(("Head", "HairTop", "HairBack"), hz + zf - 0.004, hz + zb + hgt + 0.008)
		hw, hf, hb, _hc = pl_body._interp_head(spec, (zf + zb) * 0.5 + hgt * 0.5)
		w = max(ex, hw + 0.012) + 0.008
		fd = max(efr, hf + 0.012) + 0.008
		bd = max(ebk, hb + 0.012) + 0.008

		def band_ring(dz, grow, flare):
			pts = ring(0.0, (w + grow) * flare, (fd + grow) * flare, (bd + grow) * flare, n=n, sq=2.2)
			for kk, p in enumerate(pts):
				back = (1.0 - math.cos(2.0 * math.pi * kk / n)) * 0.5
				p.z = hz + zf + (zb - zf) * back + dz
			return pts

		lo_o, hi_o = band_ring(0.0, 0.0, 1.0), band_ring(hgt, 0.0, 1.035)
		lo_i, hi_i = band_ring(0.0, -0.008, 1.0), band_ring(hgt, -0.008, 1.035)
		band = merge(rings_loft([lo_o, hi_o]), flip(rings_loft([lo_i, hi_i])), rings_loft([hi_o, hi_i]), rings_loft([lo_i, lo_o]))
		self.add(name, band, metal, wh)
		# spikes on the rim: (ring index, height, lean outward)
		spikes = []
		for kk, h, lean in ((0, 0.11, 0.2), (2, 0.062, 0.3), (12, 0.062, 0.3), (4, 0.05, 0.35), (10, 0.05, 0.35),
				(6, 0.088, 0.75), (8, 0.088, 0.75)):
			h *= k
			oa, ob = hi_o[kk].lerp(hi_o[kk - 1], 0.42), hi_o[kk].lerp(hi_o[(kk + 1) % n], 0.42)
			ia, ib = hi_i[kk].lerp(hi_i[kk - 1], 0.42), hi_i[kk].lerp(hi_i[(kk + 1) % n], 0.42)
			mid = (hi_o[kk] + hi_i[kk]) * 0.5
			out = V((mid.x, mid.y, 0.0)).normalized()
			apex = mid + V((0, 0, h)) + out * (h * lean)
			base = len(spikes)
			spikes.append(([oa, ob, ib, ia, apex], [[0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]))
		self.add(name, merge(*spikes), metal, wh)
		# the gem at the front, in a silver setting; small gems at the sides
		c = (lo_o[0] + hi_o[0]) * 0.5
		self.add(name, octa(0.028 * k, center=(c.x, c.y - 0.004, c.z + 0.004), scale=(0.9, 0.35, 1.3)), self.m("silver"), wh)
		self.add(name, octa(0.019 * k, center=(c.x, c.y - 0.013, c.z + 0.004), scale=(0.85, 0.6, 1.3)), self.m("gem_blue"), wh)
		for kk in (4, 10):
			c = (lo_o[kk] + hi_o[kk]) * 0.5
			out = V((c.x, c.y, 0.0)).normalized()
			self.add(name, octa(0.011 * k, center=tuple(c + out * 0.006), scale=(1.0, 1.0, 1.2)), self.m("gem_blue"), wh)

	# ------------------------------------------------------------------------------ chests

	def chest_1(self, name):
		"""The novice mage: beige robe to below the knee, blue / teal over-skirt with a border, a blue
		shawl over the shoulders with a brooch, two belts, a satchel and a book."""
		L, J = self.L, self.J
		lin, blue = self.m("linen"), self.t("chest", 1)
		wt, ws = self.wt, self.ws
		# robe body and sleeves
		self.add(name, rings_loft(L.shell([0.97, 1.08, 1.2, 1.3, 1.38, 1.452], 0.014, n=14)), lin, wt)
		for side in ("r", "l"):
			geo = L.sleeve(side, 0.0, 0.8, 0.016, steps=5, n=8, flare=0.022)
			self.add(name, pl_body._jag_end(geo, 8, 0.03, seed=61 if side == "r" else 62), lin, pl_rig.w_arm(J, side))
		# robe skirt: closed, torn, below the knee
		rings = self.hem_rings([1.0, 0.8, 0.62, 0.46], 1.0, 0.46, 0.02, 0.06, n=16,
			jag=sawtooth(16, 0.05, rnd=0.03, seed=63))
		self.add(name, _loft(rings), lin, ws)
		# the over-skirt: open at the front, a teal panel at the left front, a patterned hem border
		angles = [45, 52, 75, 100, 130, 160, 180, 200, 230, 260, 285, 308, 315]
		rings = self.hem_rings([1.02, 0.78, 0.44, 0.38], 1.02, 0.38, 0.036, 0.1, angles=angles,
			jag=sawtooth(len(angles), 0.05, rnd=0.03, seed=64), jag_rows=2)

		def key(i, s):
			if i == 0 or s in (0, 11):
				return "b%d" % (s % 2) if i == 0 else "b0"
			return "teal" if s in (1, 2) else "blue"
		groups = _loft(rings, key=key, closed=False)
		mats = {"b0": self.m("border"), "b1": self.m("border_dark"), "teal": self.m("teal"), "blue": blue}
		self.add_groups(name, groups, mats, ws, double=True, inner={"b0": "blue", "b1": "blue", "teal": "blue"})
		# the shawl over the shoulders: pointed front and back, patterned border at the hem
		sh = self.mantle_rings(0.03, (1.07, 1.21, 1.05), jag=sawtooth(16, 0.03, rnd=0.02, seed=65), border=0.045)
		groups = _loft(sh, key=lambda i, s: ("b%d" % (s % 2)) if i == 0 else "blue")
		wm = self.w_mantle(0.5)
		self.add_groups(name, groups, mats, wm, double=True, inner={"b0": "blue", "b1": "blue"})
		# the brooch on the shawl (upper left chest)
		p = sh[2][1].lerp(sh[3][1], 0.45)
		nrm = V((p.x * 0.6, -1.0, 0.35)).normalized()
		self.add(name, _disc(p + nrm * 0.006, nrm, 0.03, thick=0.008, n=8), self.m("bronze"), wt)
		self.add(name, octa(0.012, center=tuple(p + nrm * 0.013)), self.m("border"), wt)
		# two belts, the upper one slanting down to the right
		leather, dark, bronze = self.m("leather"), self.m("leather_dark"), self.m("bronze")
		for z, g, tilt, bx, m in ((0.995, 0.048, 0.0, 0.035, leather), (1.052, 0.044, 0.035, -0.055, dark)):
			w, fd, bd = L.torso_at(z)
			r0 = ring(z, w + g, fd + g, bd + g, n=16, sq=2.2)
			r1 = ring(z + 0.036, w + g, fd + g, bd + g, n=16, sq=2.2)
			for p in r0 + r1:
				p.z += tilt * p.x / (w + g)
			self.add(name, rings_loft([r0, r1]), m, wt)
			by = -_sy(w + g, fd + g, bx) - 0.006
			self.add(name, box((0.034, 0.012, 0.04), center=(bx, by, z + 0.018 + tilt * bx / (w + g))), bronze, wt)
		# satchel at the left hip, a book at the right hip, a medallion on the belt
		hw = self.skirt_dims(0.9, 1.02, 0.38, 0.036, 0.1)[0]
		c = V((hw + 0.028, 0.03, 0.885))
		wl = self.hang_w("l", 0.4)
		self.add(name, box((0.05, 0.12, 0.105), center=tuple(c), top=(0.92, 0.95)), leather, wl)
		self.add(name, box((0.058, 0.126, 0.045), center=tuple(c + V((0.004, 0, 0.04))), top=(0.9, 1.0)), dark, wl)
		self.add(name, box((0.008, 0.02, 0.1), center=tuple(c + V((-0.028, 0, 0.07)))), dark, wl)
		c = V((-(hw + 0.02), -0.045, 0.9))
		wr = self.hang_w("r", 0.4)
		self.add(name, box((0.034, 0.085, 0.105), center=tuple(c)), self.m("book"), wr)
		self.add(name, box((0.026, 0.078, 0.097), center=tuple(c + V((-0.006, 0, 0)))), self.m("pages"), wr)
		self.add(name, box((0.006, 0.014, 0.05), center=tuple(c + V((0.02, 0, 0.06)))), dark, wr)
		w, fd, _bd = L.torso_at(0.99)
		my = -_sy(w + 0.048, fd + 0.048, 0.03) - 0.012
		self.add(name, _disc(V((0.03, my, 0.94)), (0, -1, 0.1), 0.02, thick=0.006, n=8), bronze, self.hang_w("l", 0.3))

	def w_mantle(self, arm_share=0.35):
		"""Shawls and mantles: the torso, the sides over the shoulders partly following the upper arms."""
		J = self.J
		wt = self.wt
		shx = J["p"]["shoulder_x"]

		def f(v):
			w = dict(wt(v))
			kk = pl_rig.smoothstep(shx * 0.8, shx * 1.3, abs(v.x)) * arm_share
			if kk > 0:
				side = "l" if v.x > 0 else "r"
				tot = sum(w.values())
				w = {b: x * (1.0 - kk) for b, x in w.items()}
				w["upper_arm_" + side] = w.get("upper_arm_" + side, 0.0) + kk * tot
			return w
		return f

	def chest_2(self, name):
		"""The spellblade: a navy coat with a purple scarf, steel pauldrons and breastplate with a gold
		star, crossed straps, a belt, an open coat skirt over purple under-skirts, a rune panel and a
		purple cape with a gold star."""
		L, J = self.L, self.J
		coat, steel, trim = self.t("chest", 2), self.m("steel"), self.m("trim")
		purple, gold, leather = self.m("purple"), self.m("gold"), self.m("leather")
		wt, ws = self.wt, self.ws
		self.add(name, rings_loft(L.shell([0.97, 1.08, 1.2, 1.3, 1.38, 1.452], 0.014, n=14)), coat, wt)
		for side in ("r", "l"):
			wa = pl_rig.w_arm(J, side)
			self.add(name, L.sleeve(side, 0.0, 0.93, 0.02, steps=5, n=8, flare=-0.008), coat, wa)
			self.add(name, L.sleeve(side, 0.27, 0.32, 0.027, steps=1, n=8), trim, wa)
		# the scarf round the neck (bunched)
		nz = J["neck_z"]
		tw, tf, tb = L.torso_at(nz - 0.035)
		s0 = ring(nz - 0.035, min(tw + 0.03, self.nr + 0.12), tf + 0.04, tb + 0.035, n=12, sq=2.1)
		s1 = ring(nz + 0.005, self.nr + 0.05, self.nr + 0.056, self.nr + 0.05, n=12)
		s2 = ring(nz + 0.045, self.nr + 0.028, self.nr + 0.03, self.nr + 0.028, n=12)
		for kk, p in enumerate(s1):
			d = V((p.x, p.y, 0)).normalized()
			p += d * (0.01 if kk % 2 else -0.004)
		self.add(name, rings_loft([s0, s1, s2]), purple, pl_rig.w_torso(J))
		# breastplate: the front of the chest, a ridge down the middle, a gold star
		angles = [-60, -40, -20, 0, 20, 40, 60]
		rows = []
		for z in (1.12, 1.2, 1.28, 1.35, 1.405):
			w, fd, _bd = L.torso_at(z)
			r = _arc(z, w + 0.03, fd + 0.03, fd + 0.03, angles, sq=2.2)
			r[3].y -= 0.01
			rows.append(r)
		self.add(name, _loft(rows, closed=False), steel, wt)
		sy = self.front_y(0.0, 1.28, 0.03) - 0.012
		self.add(name, _star(V((0, sy, 1.28)), (0, -1, 0.15), (0, 0, 1), 0.036, 0.013), gold, wt)
		# crossed straps from the shoulders to the hips
		for sx in (-1.0, 1.0):
			pts = []
			for u in (0.0, 0.25, 0.5, 0.75, 1.0):
				x = sx * (0.11 - 0.26 * u)
				z = 1.44 - 0.42 * u
				g = 0.036 if z > 1.12 else 0.02
				pts.append(V((x, self.front_y(x, z, g) - (0.004 if sx < 0 else 0.008), z)))
			self.add(name, ribbon(pts, 0.03, (0, -1, 0), thick=0.005), leather, wt)
		# belt with a round silver buckle
		w, fd, bd = L.torso_at(1.0)
		g = 0.05
		self.add(name, rings_loft([ring(0.99, w + g, fd + g, bd + g, n=16, sq=2.2), ring(1.035, w + g, fd + g, bd + g, n=16, sq=2.2)]),
			leather, wt)
		self.add(name, _disc(V((0, -(fd + g) - 0.006, 1.012)), (0, -1, 0), 0.028, thick=0.008, n=8), self.m("silver"), wt)
		# pauldrons: a dome and two lames over each shoulder, a gold boss
		for side, sx in (("r", -1.0), ("l", 1.0)):
			sh = J["shoulder_" + side]
			r0 = L.arm_radius(0.0)[0] + 0.036
			dome = sphere(r0, seg_n=8, rings=3, scale=(1.0, 1.08, 0.78), cut=(0.0, 1.0))
			M = T(sh + V((sx * 0.012, 0, 0.012))) @ R(0, sx * 24.0, 0)
			wp = pl_rig.mix((pl_rig.rigid("clavicle_" + side), 0.35), (pl_rig.rigid("upper_arm_" + side), 0.65))
			self.add(name, xf(dome, M), steel, wp)
			out = V((sx, 0, 0.35)).normalized()
			self.add(name, _disc(sh + V((sx * 0.012, 0, 0.012)) + out * (r0 * 0.9), out, 0.022, thick=0.008, n=6), gold, wp)
			wa = pl_rig.w_arm(J, side)
			self.add(name, L.sleeve(side, 0.05, 0.12, 0.036, steps=1, n=8), steel, wa)
			self.add(name, L.sleeve(side, 0.115, 0.185, 0.032, steps=1, n=8), steel, wa)
		# purple under-skirt: long pointed hem, open at the front
		angles = [20, 50, 80, 110, 140, 170, 190, 220, 250, 280, 310, 340]
		rings = self.hem_rings([0.98, 0.7, 0.4], 0.98, 0.4, 0.022, 0.06, angles=angles,
			jag=sawtooth(len(angles), 0.1, rnd=0.02, seed=71))
		self.add(name, double_sided(_loft(rings, closed=False)), purple, ws)
		# the coat skirt: open at the front, a light trim along the front edges and the hem
		angles = [35, 41, 62, 90, 120, 150, 180, 210, 240, 270, 298, 319, 325]
		last = len(angles) - 2
		rings = self.hem_rings([1.0, 0.78, 0.55, 0.5], 1.0, 0.5, 0.034, 0.08, angles=angles,
			jag=_edge_jag(len(angles), 0.04, 0.02, seed=72), jag_rows=2)
		groups = _loft(rings, key=lambda i, s: "trim" if (i == 0 or s in (0, last)) else "coat", closed=False)
		self.add_groups(name, groups, {"trim": trim, "coat": coat}, ws, double=True, inner={"trim": "coat"})
		# the rune panel down the front
		pts, ws_ = [], []
		for z, wdt in ((0.99, 0.13), (0.8, 0.125), (0.6, 0.118), (0.42, 0.11), (0.34, 0.008)):
			_w, fd, _b = self.skirt_dims(z, 0.98, 0.4, 0.022, 0.06)
			pts.append(V((0, -fd - 0.014, z)))
			ws_.append(wdt)
		self.add(name, ribbon(pts, ws_, (0, -1, 0)), coat, ws)
		for sx in (-1.0, 1.0):
			edge = [p + V((sx * (wd * 0.5 - 0.007), -0.002, 0)) for p, wd in zip(pts[:-1], ws_[:-1])]
			self.add(name, ribbon(edge, 0.012, (0, -1, 0)), trim, ws)
		for i, z in enumerate((0.88, 0.72, 0.56)):
			_w, fd, _b = self.skirt_dims(z, 0.98, 0.4, 0.022, 0.06)
			self.add(name, _glyph(V((0, -fd - 0.016, z)), (0, -1, 0), (0, 0, 1), 0.06, i + 1, lift=0.002), trim, ws)
		# the purple cape with a gold star
		zs = [J["cape_top"].z, J["cape_top"].z - 0.12, 1.12, 1.0, 0.8, 0.6, 0.44]

		def cape_jag(kk, u):
			return -0.06 * (1.0 - abs(u)) - (0.03 if kk % 2 else 0.0)
		clear = self.back_clear([(1.0, 0.5, 0.034, 0.08), (0.98, 0.4, 0.022, 0.06)], belt=(0.99, 1.035, 0.05))
		rows = self.cape_rows(zs, 0.13, 0.27, 0.05, 6, jag=cape_jag, clear=clear)
		wc = pl_rig.w_cape(J)
		self.add_groups(name, self.cape_faces(rows), {0: purple}, wc, double=True)
		c = self.cape_center(rows, 1.13)
		self.add(name, _star(c + V((0, 0.004, 0)), (0, 1, 0), (0, 0, 1), 0.05, 0.018), gold, wc)
		# a book with a star at the left hip
		hw = self.skirt_dims(0.9, 1.0, 0.5, 0.034, 0.08)[0]
		c = V((hw + 0.018, -0.02, 0.9))
		wl = self.hang_w("l", 0.4)
		self.add(name, box((0.03, 0.085, 0.105), center=tuple(c)), self.m("book"), wl)
		self.add(name, octa(0.014, center=tuple(c + V((0.017, 0, 0))), scale=(0.5, 1.0, 1.0)), gold, wl)

	def chest_3(self, name):
		"""The storm seer: a long dark robe open at the front over white and pale blue torn layers,
		a tall collar, a black fur mantle with medallions, a medallion belt with charms, a rune panel
		and a long rune cape."""
		L, J = self.L, self.J
		robe, trim, white = self.t("chest", 3), self.m("trim"), self.m("white")
		wt, ws = self.wt, self.ws
		# robe body with a V neck over a white shirt
		body = L.shell([0.97, 1.08, 1.2, 1.3, 1.38, 1.452], 0.014, n=14)
		for i, rr in enumerate(body[-4:]):
			rr[0].z -= 0.05 * (i + 1) * 0.55
			rr[0].y -= 0.004
		self.add(name, rings_loft(body), robe, wt)
		shirt = L.shell([1.14, 1.25, 1.35, 1.45], 0.007, n=14)
		self.add(name, _loft(shirt, skip=lambda i, s: s not in (12, 13, 0, 1)), white, wt)
		# tall collar, open at the front
		nz, nr = J["neck_z"], self.nr
		c0 = ring(nz - 0.012, nr + 0.024, nr + 0.024, nr + 0.028, n=10)
		c1 = ring(nz + 0.075, nr + 0.04, nr + 0.04, nr + 0.046, n=10)
		self.add(name, double_sided(_loft([c0, c1], skip=lambda i, s: s in (9, 0))), robe, wt)
		# sleeves to below the elbow, a trim band and a torn trimmed cuff
		for side in ("r", "l"):
			wa = pl_rig.w_arm(J, side)
			geo = pl_body._jag_end(L.sleeve(side, 0.0, 0.56, 0.02, steps=4, n=8, flare=0.03), 8, 0.04, seed=81 if side == "r" else 82)
			for key, g in _split(geo, lambda i: "trim" if i >= 24 else "robe").items():
				self.add(name, g, trim if key == "trim" else robe, wa)
			self.add(name, L.sleeve(side, 0.24, 0.29, 0.028, steps=1, n=8), trim, wa)
		# the fur mantle: a short shawl with tufts at the hem and on the shoulders
		fur, fur_d = self.m("fur_black"), self.m("fur_dark")
		mt = self.mantle_rings(0.045, (1.29, 1.33, 1.27), depth=0.045)
		wm = self.w_mantle(0.3)
		self.add(name, _loft(mt), fur_d, wm)
		self.add(name, _fur_along(mt[0], 0.09, 0.065, seed=83, drop=0.03), fur, wm)
		self.add(name, _fur_along(mt[2], 0.07, 0.05, seed=84), fur, wm)
		for kk in (2, 14):
			p = mt[1][kk].lerp(mt[2][kk], 0.5)
			nrm = V((p.x * 0.5, -1.0, 0.5)).normalized()
			self.add(name, _disc(p + nrm * 0.03, nrm, 0.034, thick=0.01, n=8), self.m("silver_dark"), wm)
			self.add(name, octa(0.013, center=tuple(p + nrm * 0.042)), self.m("gem_blue"), wm)
		# the long robe: open at the front (+-60 deg), light trims along the edges and the hem
		angles = [60, 66, 95, 125, 155, 180, 205, 235, 265, 294, 300]
		rings = self.hem_rings([1.0, 0.72, 0.42, 0.175, 0.12], 1.0, 0.12, 0.036, 0.12, angles=angles,
			jag=sawtooth(len(angles), 0.05, rnd=0.03, seed=85), jag_rows=2)
		groups = _loft(rings, key=lambda i, s: "trim" if (i == 0 or s in (0, 9)) else "robe", closed=False)
		self.add_groups(name, groups, {"trim": trim, "robe": robe}, ws, double=True, inner={"trim": "robe"})
		# white (long) and pale blue (shorter, deeply torn) layers in the opening
		for mkey, ang_l, zs, grow, flare, depth, seed in (
				("white", [18, 40, 65, 95], [0.98, 0.55, 0.12], 0.02, 0.1, 0.05, 86),
				("pale_blue", [26, 45, 70, 100], [0.99, 0.65, 0.32], 0.028, 0.105, 0.1, 87)):
			for sx in (1.0, -1.0):
				ang = ang_l if sx > 0 else [360 - a for a in reversed(ang_l)]
				rings = self.hem_rings(zs, zs[0], zs[-1], grow, flare, angles=ang,
					jag=sawtooth(len(ang), depth, rnd=0.03, seed=seed + (0 if sx > 0 else 10)))
				self.add(name, double_sided(_loft(rings, closed=False)), self.m(mkey), ws)
		# the rune panel down the front
		pts, wd = [], []
		for z, wdt in ((0.99, 0.13), (0.72, 0.12), (0.45, 0.112), (0.2, 0.105), (0.11, 0.008)):
			_w, fd, _b = self.skirt_dims(z, 0.98, 0.12, 0.02, 0.1)
			pts.append(V((0, -fd - 0.012, z)))
			wd.append(wdt)
		self.add(name, ribbon(pts, wd, (0, -1, 0)), robe, ws)
		for sx in (-1.0, 1.0):
			edge = [p + V((sx * (w_ * 0.5 - 0.007), -0.002, 0)) for p, w_ in zip(pts[:-1], wd[:-1])]
			self.add(name, ribbon(edge, 0.012, (0, -1, 0)), trim, ws)
		for i, z in enumerate((0.9, 0.76, 0.62, 0.48, 0.34)):
			_w, fd, _b = self.skirt_dims(z, 0.98, 0.12, 0.02, 0.1)
			self.add(name, _glyph(V((0, -fd - 0.014, z)), (0, -1, 0), (0, 0, 1), 0.055, i, lift=0.002), trim, ws)
		# the belt: a wide band, a big medallion with a gem, two charms
		w, fd, bd = L.torso_at(1.0)
		g = 0.05
		self.add(name, rings_loft([ring(0.985, w + g, fd + g, bd + g, n=16, sq=2.2), ring(1.055, w + g - 0.004, fd + g - 0.004, bd + g - 0.004, n=16, sq=2.2)]),
			self.m("leather_dark"), wt)
		my = -(fd + g) - 0.008
		self.add(name, _disc(V((0, my, 1.02)), (0, -1, 0), 0.046, thick=0.01, n=10), self.m("silver"), wt)
		self.add(name, _star(V((0, my - 0.005, 1.02)), (0, -1, 0), (0, 0, 1), 0.04, 0.016), self.m("silver_dark"), wt)
		self.add(name, octa(0.016, center=(0, my - 0.012, 1.02), scale=(1.0, 0.7, 1.2)), self.m("gem_blue"), wt)
		for sx in (-1.0, 1.0):
			x = sx * 0.1
			y = -_sy(w + g, fd + g, x) - 0.004
			hw = self.hang_w("l" if sx > 0 else "r", 0.3)
			self.add(name, box((0.006, 0.006, 0.07), center=(x, y, 0.95)), self.m("silver_dark"), hw)
			self.add(name, octa(0.013, center=(x, y, 0.905), scale=(0.8, 0.8, 1.4)), self.m("gem_blue"), hw)
		# the long cape: a light hem trim, a pointed tail, a circle emblem and a line of runes
		zs = [J["cape_top"].z, J["cape_top"].z - 0.12, 1.12, 1.0, 0.8, 0.55, 0.3, 0.23, 0.17]

		def cape_jag(kk, u):
			return -0.08 * (1.0 - abs(u)) - (0.03 if kk % 2 else 0.0)
		clear = self.back_clear([(1.0, 0.12, 0.036, 0.12)], belt=(0.985, 1.055, 0.05))
		rows = self.cape_rows(zs, 0.15, 0.36, 0.08, 8, jag=cape_jag, jag_rows=2, clear=clear)
		wc = pl_rig.w_cape(J)
		groups = self.cape_faces(rows, band_key=lambda i: "trim" if i == len(rows) - 2 else "robe")
		self.add_groups(name, groups, {"trim": trim, "robe": robe}, wc, double=True, inner={"trim": "robe"})
		c = self.cape_center(rows, 0.98) + V((0, 0.004, 0))
		self.add(name, _annulus(c, (0, 1, 0), (0, 0, 1), 0.075, 0.059, seg=12), trim, wc)
		self.add(name, _star(c, (0, 1, 0), (0, 0, 1), 0.042, 0.014), trim, wc)
		for i, z in enumerate((0.8, 0.68, 0.56, 0.44)):
			p = self.cape_center(rows, z)
			self.add(name, _glyph(p, (0, 1, 0), (0, 0, 1), 0.055, i + 2, lift=0.004), trim, wc)

	# ------------------------------------------------------------------------------ gloves

	def gloves_1(self, name):
		"""Fingerless leather gloves (bare fingers) and wrapped cloth bracers with straps."""
		L, J = self.L, self.J
		wraps, leather, dark = self.t("gloves", 1), self.m("leather"), self.m("leather_dark")
		skin = L.mat("skin", rough=0.8)
		for side, sx in (("r", -1.0), ("l", 1.0)):
			wa = pl_rig.w_arm(J, side)
			L.build_hands(part=name, material=skin, scale=1.0, only=side)
			wr, kn = J["wrist_" + side], J["knuckle_" + side]
			Mf = pl_body._frame(wr, V((sx, 0, 0)), (kn - wr).normalized())
			k = self.hand_k * 1.12
			self.add(name, box((0.078 * k, 0.034 * k, 0.07 * k), center=(0, 0, 0.034 * k), top=(0.95, 0.9)), leather, wa, M=Mf)
			self.add(name, box((0.022 * k, 0.03 * k, 0.034 * k), center=(-sx * 0.034 * k, -0.018 * k, 0.03 * k), top=(0.85, 0.85)),
				leather, wa, M=Mf)
			self.add(name, L.sleeve(side, 0.62, 1.0, 0.012, steps=2, n=8), wraps, wa)
			d = J["forearm_dir_" + side]
			r0, r1 = L.arm_radius(0.74)[0] + 0.018, L.arm_radius(0.98)[0] + 0.017
			self.add(name, wrap_bands(wr - d * 0.13, wr - d * 0.005, r0, r1, 3, width=0.018, n=7, slant=24.0), dark, wa)

	def gloves_2(self, name):
		"""Dark gloves with cuffs, runed steel vambraces over the forearms."""
		L, J = self.L, self.J
		glove, steel = self.t("gloves", 2), self.m("steel")
		for side, sx in (("r", -1.0), ("l", 1.0)):
			wa = pl_rig.w_arm(J, side)
			L.glove(side, glove, grow=0.01, part=name)
			self.add(name, L.sleeve(side, 0.9, 1.0, 0.016, steps=1, n=8), glove, wa)
			self.add(name, L.sleeve(side, 0.57, 0.93, 0.026, steps=3, n=8, flare=-0.01), steel, wa)
			self._forearm_runes(name, side, (0.66, 0.74, 0.82), 0.024, self.m("rune_violet"), wa)
			# a ridge along the outside of the vambrace
			ridge, nrm = [], None
			for t, gr in ((0.6, 0.026), (0.75, 0.022), (0.9, 0.018)):
				p, nrm = self.arm_surface(side, t, (sx, 0.25, 0.0), gr + 0.001)
				ridge.append(p)
			self.add(name, ribbon(ridge, [0.018, 0.014, 0.01], nrm, thick=0.006), steel, wa)

	def gloves_3(self, name):
		"""Long black gloves to the elbow with a pointed top, runed silver bracers."""
		L, J = self.L, self.J
		glove, silver = self.t("gloves", 3), self.m("silver")
		for side, sx in (("r", -1.0), ("l", 1.0)):
			wa = pl_rig.w_arm(J, side)
			L.glove(side, glove, grow=0.008, part=name)
			self.add(name, L.sleeve(side, 0.5, 1.0, 0.009, steps=3, n=8), glove, wa)
			base, out = self.arm_surface(side, 0.57, (sx, 0.3, 0.0), 0.012)
			n_, u_, s_ = _basis(out, -J["forearm_dir_" + side])
			tip = base + u_ * 0.075
			wlo = pl_rig.rigid("lower_arm_" + side)
			self.add(name, ([base - s_ * 0.03, base + s_ * 0.03, tip, base - u_ * 0.02], [[0, 1, 2], [1, 0, 3]]), glove, wlo)
			self.add(name, ([base - s_ * 0.03 - out * 0.004, base + s_ * 0.03 - out * 0.004, tip - out * 0.004], [[1, 0, 2]]), glove, wlo)
			self.add(name, L.sleeve(side, 0.64, 0.93, 0.022, steps=2, n=8, flare=-0.004), silver, wa)
			self._forearm_runes(name, side, (0.72, 0.84), 0.021, self.m("rune_blue"), wa)

	def _forearm_runes(self, name, side, ts, grow, material, weights):
		J = self.J
		sx = -1.0 if side == "r" else 1.0
		d = J["forearm_dir_" + side]
		for i, t in enumerate(ts):
			p, out = self.arm_surface(side, t, (sx, 0.35, 0.0), grow)
			self.add(name, _glyph(p, out, -d, 0.034, i + (0 if side == "r" else 1), lift=0.002), material, weights)

	# ------------------------------------------------------------------------------ boots

	def _foot(self, name, side, leather, sole, heel=0.0, toe_point=0.0):
		"""A boot's foot and sole (a vertex row at the ball so the toes bend), optional heel block and
		pointed toe. The sole's bottom (and the heel's) stays at z = 0."""
		J = self.J
		ank, toe, hl = J["ankle_" + side], J["toe_" + side], J["heel_" + side]
		wl = pl_rig.w_leg(J, side)
		kb = 0.94 if self.L.female else (1.04 if self.L.look == "m2" else 1.0)
		cy = (hl.y + toe.y) * 0.5
		cuts = [J["ball_" + side].y]
		self.add(name, foot_box((0.104 * kb, 0.262 * kb, 0.085), center=(ank.x, cy, 0.047), top=(0.9, 0.7), shift=(0, 0.024),
			cuts=cuts), leather, wl)
		self.add(name, foot_box((0.108 * kb, 0.268 * kb, 0.02), center=(ank.x, cy - 0.002, 0.01), cuts=cuts), sole, wl)
		if toe_point > 0.0:
			self.add(name, box((0.07 * kb, 0.05, 0.05), center=(ank.x, toe.y - 0.015, 0.03), top=(0.3, 0.3), shift=(0, -toe_point)),
				leather, wl)
		if heel > 0.0:
			self.add(name, box((0.056 * kb, 0.056, heel), center=(ank.x, hl.y + 0.004, heel * 0.5), top=(1.3, 1.3)), sole, wl)

	def _leg_arc(self, side, z, r, angles, ry=1.03):
		"""Points round the leg at height z (angles from the front, + toward the character's left)."""
		c = self.L.leg_path(side, z, z, steps=1)[0]
		out = []
		for th in angles:
			a = math.radians(th)
			out.append(V((c.x + r * math.sin(a), c.y - r * ry * math.cos(a), z)))
		return out

	def boot_r(self, z, margin):
		return max(self.trouser_r(z), 0.056) + margin

	def boots_1(self, name):
		"""Leather boots to mid-shin with crossing straps, cloth wraps over the trouser legs."""
		L, J = self.L, self.J
		wraps, leather, dark = self.t("boots", 1), self.m("leather"), self.m("leather_dark")
		for side in ("r", "l"):
			wl = pl_rig.w_leg(J, side)
			self._foot(name, side, leather, self.m("sole"))
			self.add(name, L.leg_tube(side, 0.33, 0.05, lambda z: self.boot_r(z, 0.012), steps=3, n=8), leather, wl)
			a = L.leg_path(side, 0.08, 0.08, steps=1)[0]
			b = L.leg_path(side, 0.3, 0.3, steps=1)[0]
			self.add(name, wrap_bands(a, b, self.boot_r(0.1, 0.016), self.boot_r(0.3, 0.016), 4, width=0.016, n=8, slant=24.0),
				dark, wl)
			a = L.leg_path(side, 0.3, 0.3, steps=1)[0]
			b = L.leg_path(side, 0.45, 0.45, steps=1)[0]
			self.add(name, wrap_bands(a, b, self.boot_r(0.31, 0.014), self.boot_r(0.44, 0.016), 3, width=0.052, n=8, slant=12.0),
				wraps, wl)

	def boots_2(self, name):
		"""Heeled boots to below the knee, steel greaves with a ridge, knee cops, straps."""
		L, J = self.L, self.J
		leather, steel, dark = self.t("boots", 2), self.m("steel"), self.m("leather_dark")
		for side, sx in (("r", -1.0), ("l", 1.0)):
			wl = pl_rig.w_leg(J, side)
			self._foot(name, side, leather, self.m("sole"), heel=0.03)
			self.add(name, L.leg_tube(side, 0.44, 0.05, lambda z: self.boot_r(z, 0.012), steps=4, n=8), leather, wl)
			self.add(name, L.leg_tube(side, 0.46, 0.43, lambda z: self.boot_r(z, 0.018), steps=1, n=8), dark, wl)
			rows = []
			for z in (0.11, 0.2, 0.3, 0.4, 0.47):
				r = self.boot_r(min(z, 0.44), 0.024)
				row = self._leg_arc(side, z, r, [-72, -36, 0, 36, 72])
				row[2] += V((0, -0.008, 0.03 if z > 0.45 else 0.0))
				rows.append(row)
			self.add(name, _loft(rows, closed=False), steel, wl)
			for z in (0.2, 0.34):
				c = L.leg_path(side, z, z, steps=1)[0]
				r = self.boot_r(z, 0.02)
				self.add(name, rings_loft([ring(z, r, r * 1.03, n=8, cx=c.x, cy=c.y), ring(z + 0.022, r, r * 1.03, n=8, cx=c.x, cy=c.y)]),
					dark, wl)
			knee = J["knee_" + side]
			kr = self.trouser_r(J["knee_z"]) + 0.012
			self.add(name, sphere(0.056, seg_n=8, rings=3, center=(knee.x, knee.y - kr + 0.012, J["knee_z"] - 0.01),
				scale=(1.0, 0.55, 1.12)), steel, wl)
			self.add(name, octa(0.03, center=(knee.x + sx * 0.05, knee.y - kr * 0.6, J["knee_z"] - 0.01), scale=(0.35, 0.9, 1.2)),
				steel, wl)

	def boots_3(self, name):
		"""Tall armoured boots with heels and pointed toes: silver shin plates, pointed knee cops,
		toe caps, a flared cuff and glowing runes."""
		L, J = self.L, self.J
		leather, silver = self.t("boots", 3), self.m("silver")
		for side, sx in (("r", -1.0), ("l", 1.0)):
			wl = pl_rig.w_leg(J, side)
			self._foot(name, side, leather, self.m("sole"), heel=0.032, toe_point=0.03)
			toe, ank = J["toe_" + side], J["ankle_" + side]
			self.add(name, box((0.09, 0.07, 0.05), center=(ank.x, toe.y + 0.035, 0.05), top=(0.7, 0.6), shift=(0, -0.012)), silver, wl)
			self.add(name, L.leg_tube(side, 0.5, 0.05, lambda z: self.boot_r(z, 0.012), steps=4, n=8), leather, wl)
			self.add(name, L.leg_tube(side, 0.53, 0.47, lambda z: self.boot_r(min(z, 0.47), 0.02 + (z - 0.47) * 0.4), steps=1, n=8),
				silver, wl)
			rows = []
			for z in (0.1, 0.2, 0.3, 0.4, 0.46):
				r = self.boot_r(z, 0.024)
				row = self._leg_arc(side, z, r, [-64, -32, 0, 32, 64])
				row[2] += V((0, -0.008, 0.0))
				rows.append(row)
			self.add(name, _loft(rows, closed=False), silver, wl)
			c = self.L.leg_path(side, 0.3, 0.3, steps=1)[0]
			r = self.boot_r(0.3, 0.024) + 0.009
			for i, z in enumerate((0.34, 0.22)):
				p = V((c.x, c.y - r * 1.03, z))
				self.add(name, _glyph(p, (0, -1, 0), (0, 0, 1), 0.05, i + (1 if side == "r" else 2), lift=0.002),
					self.m("rune_blue"), wl)
			knee = J["knee_" + side]
			kr = self.trouser_r(J["knee_z"]) + 0.014
			kc = V((knee.x, knee.y - kr + 0.01, J["knee_z"] - 0.01))
			self.add(name, sphere(0.055, seg_n=8, rings=3, center=tuple(kc), scale=(1.0, 0.5, 1.1)), silver, wl)
			spike = ([kc + V((-0.03, -0.02, 0.02)), kc + V((0.03, -0.02, 0.02)), kc + V((0, -0.03, 0.1)), kc + V((0, 0.0, 0.04))],
				[[0, 1, 2], [1, 3, 2], [3, 0, 2]])
			self.add(name, spike, silver, wl)
