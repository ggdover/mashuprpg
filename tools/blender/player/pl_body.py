"""The player's bodies and default outfits (tools/blender/player), one per look:
  "f"   the female exile (ranger, sorcerer): long wavy brown hair, torn linen blouse under a brown
        overdress, a sash, layered torn skirts over dark trousers, shin wraps and sandals;
  "m1"  the exiled villager (warrior): shaggy dirty-blond hair and beard, a long-sleeved torn tunic,
        a ragged brown shawl, a rope belt, patched trousers, cloth wraps;
  "m2"  the exile (warrior, alternative): short black hair and stubble, a sleeveless torn tunic, rope
        belt, forearm wraps, patched trousers, shin wraps and leather boots.
Every part is a skinned mesh object (pl_mesh.WPart), named for the game's visibility rules
(scripts/entities/player/player_looks.gd):
  Head, HairTop (hidden under helmets), HairBack (hidden under hoods), HairFront (the female's strands
  over the shoulders), Body (skin: torso, arms), Hands (hidden under gloves),
  Outfit_Top, Outfit_Belt (hidden under body armour), Outfit_Legs, Outfit_Feet (hidden under boots),
  Outfit_Wraps (hidden under gloves).
"""
import math

from mathutils import Vector

import pl_rig
from pl_mesh import (R, S, T, WPart, band, box, cyl, fan_cap, flip, foot_box, merge, octa, patch, ribbon, ring, rings_loft,
	rnd, rope, sawtooth, sphere, strand, tube, wrap_bands, xf, mat, double_sided)



def V(*a):
	return Vector(a[0]) if len(a) == 1 else Vector(a)


# Palette (sRGB) per look.
PAL = {
	"f": dict(skin="d8ae94", skin_dark="b98a70", hair="6a4830", hair_hi="8a6444", lips="a86a5a", eye="2a2320",
		linen="b8a68b", linen_dark="8f7e66", over="5c4633", over_dark="45352a", sash="6b5139", skirt="5a4838",
		under="a8977c", trousers="4a443d", wrap="998a73", wrap_dark="6f6352", sole="4a3a2c", strap="5a4432"),
	"m1": dict(skin="cf9c7a", skin_dark="ad7c5c", hair="a8844f", hair_hi="c29d64", beard="8c6a3e", lips="9c6452",
		eye="2a2622", linen="b4a589", linen_dark="8e7f67", over="5f4a36", over_dark="47372a", rope="8a6c45",
		trousers="5b4a37", patch="3e3630", patch2="6e5d48", wrap="8e7f69", wrap_dark="6c604f", shoe="5e4b39"),
	"m2": dict(skin="c69276", skin_dark="a47458", hair="1f1a17", hair_hi="2e2723", beard="6a5446", lips="95604e",
		eye="231f1c", linen="a8957a", linen_dark="7a6853", dirt="6e5a45", rope="8f6f47", trousers="5d4b39",
		patch="3c342e", patch2="6a5946", wrap="7d7262", wrap_dark="5b5247", boot="5a3f2b", boot_dark="3f2c1f"),
}


class Look:
	"""Builds one look's parts in unit space."""

	def __init__(self, look):
		self.look = look
		self.J = pl_rig.joints(look)
		self.p = self.J["p"]
		self.pal = PAL[look]
		self.parts = {}
		self.female = look == "f"
		self.m = {}

	def mat(self, key, rough=0.85, metal=0.0):
		name = "%s_%s" % (key, self.look)
		if name not in self.m:
			self.m[name] = mat(name, self.pal[key], rough=rough, metal=metal)
		return self.m[name]

	def add(self, part, geo, material, weights, M=None):
		if part not in self.parts:
			self.parts[part] = WPart(part)
		self.parts[part].add(geo, material, weights, M)

	# ------------------------------------------------------------------------------ helpers

	def arm_path(self, side, t0=0.0, t1=1.0, steps=6):
		"""Points along shoulder -> elbow -> wrist, t in 0..1 (0.5 = elbow)."""
		J = self.J
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		out = []
		for i in range(steps + 1):
			t = t0 + (t1 - t0) * i / steps
			out.append(sh.lerp(el, t * 2.0) if t <= 0.5 else el.lerp(wr, (t - 0.5) * 2.0))
		return out

	def leg_path(self, side, z_top, z_bot, steps=6):
		"""Points down the leg between two heights (following hip -> knee -> ankle)."""
		J = self.J
		hip, knee, ank = J["hip_" + side], J["knee_" + side], J["ankle_" + side]
		out = []
		for i in range(steps + 1):
			z = z_top + (z_bot - z_top) * i / steps
			if z >= knee.z:
				t = (hip.z - z) / (hip.z - knee.z)
				p = hip.lerp(knee, t)
			else:
				t = (knee.z - z) / (knee.z - ank.z)
				p = knee.lerp(ank, t)
			out.append(V((p.x, p.y, z)))
		return out

	def torso_rings(self, spec, n=12, grow=0.0, jag=None, sq=2.2):
		"""spec: (z, w, fd, bd[, cy]) per ring, bottom -> top."""
		out = []
		for i, s in enumerate(spec):
			z, w, fd, bd = s[0], s[1], s[2], s[3]
			cy = s[4] if len(s) > 4 else 0.0
			j = jag if (jag is not None and i == 0) else None
			out.append(ring(z, w + grow, fd + grow, bd + grow, n=n, cy=cy, sq=sq, jag=j))
		return out

	# ------------------------------------------------------------------------------ fitting (gear)

	def torso_at(self, z):
		"""(half width, front depth, back depth) of the bare torso at height z (interpolated, clamped)."""
		spec = self.torso_spec()
		if z <= spec[0][0]:
			return spec[0][1], spec[0][2], spec[0][3]
		for a, b in zip(spec, spec[1:]):
			if a[0] <= z <= b[0]:
				t = (z - a[0]) / (b[0] - a[0])
				return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
		return spec[-1][1], spec[-1][2], spec[-1][3]

	def shell(self, zs, grow, n=14, sq=2.2, grow_front=0.0, grow_back=0.0, jag=None):
		"""Rings following the torso at the heights zs (bottom -> top), grown outward by `grow` (plus
		extra at the front / back). jag applies to the bottom ring."""
		out = []
		for i, z in enumerate(zs):
			w, fd, bd = self.torso_at(z)
			out.append(ring(z, w + grow, fd + grow + grow_front, bd + grow + grow_back, n=n, sq=sq,
				jag=jag if (jag is not None and i == 0) else None))
		return out

	def arm_radii(self):
		"""Skin radii (rx, ry) at arm_path(steps=6) points, shoulder -> wrist."""
		if self.look == "m2":
			return [(0.07, 0.068), (0.066, 0.063), (0.058, 0.056), (0.045, 0.043), (0.05, 0.047), (0.045, 0.04), (0.036, 0.03)]
		if self.female:
			return [(0.052, 0.05), (0.046, 0.045), (0.041, 0.04), (0.035, 0.034), (0.038, 0.035), (0.033, 0.029), (0.027, 0.023)]
		return [(0.058, 0.056), (0.052, 0.05), (0.046, 0.045), (0.04, 0.038), (0.043, 0.04), (0.038, 0.033), (0.031, 0.026)]

	def arm_radius(self, t):
		r = self.arm_radii()
		x = max(0.0, min(1.0, t)) * (len(r) - 1)
		i = min(int(x), len(r) - 2)
		f = x - i
		return (r[i][0] + (r[i + 1][0] - r[i][0]) * f, r[i][1] + (r[i + 1][1] - r[i][1]) * f)

	def sleeve(self, side, t0, t1, grow, steps=5, n=8, flare=0.0):
		"""A tube around the arm from t0 to t1 (0 shoulder, 0.5 elbow, 1 wrist), `grow` outside the
		skin, widening by `flare` toward t1. Weighted with pl_rig.w_arm."""
		pts = self.arm_path(side, t0, t1, steps=steps)
		if t0 <= 0.001:
			pts[0] = pts[0] + V(0, 0, 0.012)
		rr = []
		for i in range(len(pts)):
			t = t0 + (t1 - t0) * i / steps
			a, b = self.arm_radius(t)
			k = flare * i / steps
			rr.append((a + grow + k, b + grow + k))
		return tube(pts, rr, n=n, side=(0, -1, 0), cap0=False, cap1=False)

	def trouser_radius(self, z, baggy=1.0):
		"""Radius of the default trouser leg at height z (what boots and greaves wrap around)."""
		J = self.J
		t = max(0.0, min(1.0, (0.94 - z) / (0.94 - 0.2)))
		r = (0.1 - 0.02 * t + 0.012 * math.sin(t * math.pi)) * baggy
		if z < J["knee_z"] - 0.12:
			r *= 0.86 if z > 0.25 else 0.72
		return r

	def leg_tube(self, side, z_top, z_bot, radius_fn, steps=5, n=8, cap=False):
		"""A tube down the leg between two heights; radius_fn(z) -> r (or (rx, ry)). Weighted w_leg."""
		pts = self.leg_path(side, z_top, z_bot, steps=steps)
		rr = []
		for p in pts:
			r = radius_fn(p.z)
			rr.append(r if isinstance(r, tuple) else (r, r * 1.03))
		return tube(pts, rr, n=n, side=(0, -1, 0), cap0=cap, cap1=cap)

	def head_spec(self):
		"""Head rings (z above head_z, half width, front depth, back depth, cy) as built (unit, female
		already scaled)."""
		f = self.female
		k = 0.94 if f else 1.0
		jw = 0.074 if f else (0.086 if self.look == "m2" else 0.082)
		spec = [
			(0.018, 0.03, 0.028, 0.026, -0.072), (0.048, jw, 0.08, 0.062, -0.02),
			(0.08, jw + 0.012, 0.094, 0.086, -0.006), (0.115, 0.096, 0.1, 0.1, 0.0),
			(0.146, 0.099, 0.1, 0.108, 0.0), (0.176, 0.1, 0.097, 0.112, 0.004), (0.207, 0.094, 0.086, 0.108, 0.006),
			(0.234, 0.076, 0.065, 0.088, 0.008),
		]
		return [(s[0] * k, s[1] * k, s[2] * k, s[3] * k, s[4] * k) for s in spec], 0.254 * k

	def dome(self, z_from, grow, n=12, top_extra=0.0, rings=4):
		"""A helmet / hood dome over the skull from `z_from` (above head_z) up, `grow` outside the
		head (hair included: grow >= 0.025 clears the hair caps). Returns geometry (open bottom)."""
		hz = self.J["head_z"]
		spec, top = self.head_spec()
		pts = []
		zs = [z_from + (top - 0.02 - z_from) * i / (rings - 1) for i in range(rings)]
		for z in zs:
			w, fd, bd, cy = _interp_head(spec, z)
			shrink = 1.0 - max(0.0, (z - (top - 0.06)) / 0.06) * 0.35
			pts.append(ring(hz + z, (w + grow) * shrink, (fd + grow) * shrink, (bd + grow) * shrink, n=n, cy=cy, sq=2.2))
		geo = rings_loft(pts)
		cap = fan_cap(pts[-1], V((0, 0.01, hz + top + grow + top_extra)))
		return merge(geo, cap)

	def skirt(self, z_top, z_bot, grow, n=16, flare=0.05, jag=None, open_at=None, open_k=1, double=True, weights=None):
		"""A skirt / tabard / coat hem from the waist down: rings from z_top to z_bot following the
		hips then flaring out; skirt-panel weights. open_at: ring index of a front slit (None = closed)."""
		J = self.J
		zs = [z_top, (z_top * 2 + z_bot) / 3, (z_top + z_bot * 2) / 3, z_bot]
		rings = []
		w0, f0, b0 = self.torso_at(min(z_top, 0.93))
		for i, z in enumerate(zs):
			t = i / (len(zs) - 1)
			base_w, base_f, base_b = self.torso_at(z) if z > 0.84 else (w0, f0, b0)
			k = grow + flare * t
			rings.append(ring(z, max(base_w, w0 * 0.98) + k + 0.02 * t, base_f + k + 0.03 * t, base_b + k + 0.03 * t, n=n,
				sq=2.05, jag=jag if i == len(zs) - 1 else None))
		if open_at is None:
			geo = rings_loft(rings)
			return double_sided(geo) if double else geo
		return _open_front(list(reversed(rings)), open_k=open_k, double=double, open_at=open_at)

	def cape(self, width_top, width_bot, z_bot, drape=0.05, n=6, jag=None, curve=0.35):
		"""A cape hanging from the shoulders down the back to z_bot: a double-sided sheet, curved
		around the back, weighted to the cape bones (pl_rig.w_cape)."""
		J = self.J
		top = J["cape_top"]
		b = J["bones"]
		zs = [top.z, top.z - 0.12, 1.1, 0.8, 0.5, z_bot]
		zs = [z for z in zs if z >= z_bot] + ([z_bot] if zs[-1] != z_bot else [])
		zs = sorted(set(zs), reverse=True)
		rows = []
		for i, z in enumerate(zs):
			t = (top.z - z) / max(0.01, top.z - z_bot)
			w = width_top + (width_bot - width_top) * min(1.0, t * 1.6)
			w_, fd, bd = self.torso_at(max(z, 1.0))
			y0 = bd + 0.02 + drape * t
			row = []
			for k in range(n + 1):
				u = -1.0 + 2.0 * k / n
				x = u * w
				y = y0 - curve * w * (1 - u * u) * (0.6 if z > 1.2 else 0.25) * -1.0
				dz = jag(k, x, y) if (jag is not None and i == len(zs) - 1) else 0.0
				row.append(V((x, y, z + dz)))
			rows.append(row)
		verts, faces = [], []
		for row in rows:
			verts.extend(row)
		w_ = n + 1
		for i in range(len(rows) - 1):
			for k in range(n):
				a = i * w_ + k
				faces.append([a + w_, a + w_ + 1, a + 1, a])
		return double_sided((verts, faces))

	def fur_collar(self, z, grow, height=0.07, tuft=0.05, n=16, seed=1, depth_scale=1.0):
		"""A pelt / fur collar around the shoulders at height z (spiky tufts)."""
		w, fd, bd = self.torso_at(z)
		from pl_mesh import fur_ring
		return fur_ring((0, (bd - fd) * 0.5 * 0.5, 0), w + grow, ((fd + bd) * 0.5 + grow) * depth_scale, z, height,
			n=n, tuft=tuft, seed=seed)

	def glove(self, side, material, grow=0.008, part="Gloves"):
		"""A glove over the hand (the hand's blocks, a little bigger)."""
		self.build_hands(part=part, material=material, scale=1.0 + grow * 12.0, only=side)

	# ------------------------------------------------------------------------------ skin

	def torso_spec(self):
		"""The bare torso (bottom -> top) per look: (z, half width, front depth, back depth, cy)."""
		if self.look == "f":
			return [(0.84, 0.15, 0.1, 0.12), (0.93, 0.172, 0.108, 0.13), (1.0, 0.16, 0.095, 0.11), (1.07, 0.128, 0.085, 0.092),
				(1.15, 0.132, 0.092, 0.092), (1.23, 0.15, 0.125, 0.098), (1.3, 0.155, 0.12, 0.1), (1.36, 0.165, 0.092, 0.1),
				(1.415, 0.17, 0.07, 0.092), (1.44, 0.11, 0.062, 0.075), (1.46, 0.058, 0.052, 0.056)]
		if self.look == "m2":
			return [(0.84, 0.16, 0.1, 0.12), (0.93, 0.168, 0.105, 0.125), (1.0, 0.16, 0.1, 0.11), (1.07, 0.155, 0.098, 0.105),
				(1.15, 0.168, 0.105, 0.11), (1.24, 0.19, 0.125, 0.12), (1.31, 0.205, 0.13, 0.125), (1.37, 0.215, 0.105, 0.125),
				(1.42, 0.2, 0.075, 0.11), (1.448, 0.13, 0.07, 0.09), (1.47, 0.066, 0.06, 0.064)]
		return [(0.84, 0.155, 0.1, 0.118), (0.93, 0.163, 0.103, 0.122), (1.0, 0.155, 0.097, 0.108), (1.07, 0.148, 0.094, 0.1),
			(1.15, 0.155, 0.1, 0.102), (1.24, 0.172, 0.115, 0.108), (1.31, 0.185, 0.115, 0.112), (1.37, 0.195, 0.1, 0.115),
			(1.42, 0.185, 0.072, 0.1), (1.446, 0.12, 0.066, 0.084), (1.466, 0.06, 0.055, 0.058)]

	def build_skin(self):
		J = self.J
		skin = self.mat("skin", rough=0.8)
		wt = pl_rig.w_torso(J)
		spec = self.torso_spec()
		rings = self.torso_rings(spec, n=12)
		self.add("Body", rings_loft(rings, cap0=True), skin, wt)
		# neck
		nz, hz = J["neck_z"], J["head_z"]
		nr = 0.055 if self.female else (0.066 if self.look == "m2" else 0.06)
		neck = rings_loft([ring(nz - 0.03, nr, nr * 0.95, n=8), ring(hz + 0.02, nr * 0.9, nr * 0.86, n=8)])
		self.add("Head", neck, skin, pl_rig.w_head(J))
		# arms (bare skin tubes, shoulder -> wrist)
		if self.look == "m2":
			radii = [(0.07, 0.068), (0.066, 0.063), (0.058, 0.056), (0.045, 0.043), (0.05, 0.047), (0.045, 0.04), (0.036, 0.03)]
		elif self.female:
			radii = [(0.052, 0.05), (0.046, 0.045), (0.041, 0.04), (0.035, 0.034), (0.038, 0.035), (0.033, 0.029), (0.027, 0.023)]
		else:
			radii = [(0.058, 0.056), (0.052, 0.05), (0.046, 0.045), (0.04, 0.038), (0.043, 0.04), (0.038, 0.033), (0.031, 0.026)]
		for side in ("r", "l"):
			pts = self.arm_path(side, 0.0, 1.0, steps=6)
			pts[0] = pts[0] + V(0, 0, 0.01)
			self.add("Body", tube(pts, radii, n=7, side=(0, -1, 0)), skin, pl_rig.w_arm(J, side))
		self.build_hands()
		self.build_head()

	def build_hands(self, part="Hands", material=None, scale=1.0, only=None):
		J = self.J
		m = material or self.mat("skin", rough=0.8)
		k = (0.88 if self.female else (1.08 if self.look == "m2" else 1.0)) * scale
		for side, sx in (("r", -1.0), ("l", 1.0)):
			if only is not None and side != only:
				continue
			wr, kn = J["wrist_" + side], J["knuckle_" + side]
			ax = (kn - wr).normalized()
			fw = pl_rig.w_arm(J, side)
			# palm + fingers: a tapered block from the wrist, fingers curled toward the grip
			side_v = V((sx, 0, 0))
			Mf = _frame(wr, side_v, ax)
			palm = box((0.078 * k, 0.034 * k, 0.07 * k), center=(0, 0, 0.036 * k), top=(0.95, 0.9))
			fingers = box((0.074 * k, 0.05 * k, 0.045 * k), center=(0, -0.012 * k, 0.088 * k), top=(0.9, 0.7), shift=(0, -0.012 * k))
			thumb = box((0.022 * k, 0.03 * k, 0.05 * k), center=(-sx * 0.036 * k, -0.02 * k, 0.045 * k), top=(0.8, 0.8))
			for g in (palm, fingers, thumb):
				self.add(part, g, m, fw, M=Mf)

	def build_head(self):
		J = self.J
		hz = J["head_z"]
		skin = self.mat("skin", rough=0.8)
		wh = pl_rig.w_head(J)
		f = self.female
		k = 0.94 if f else 1.0
		# (z above hz, half width, front depth, back depth, cy)
		spec, top_z = self.head_spec()
		rings = [ring(hz + s[0], s[1], s[2], s[3], n=10, cy=s[4], sq=2.3) for s in spec]
		top = V((0, 0.012, hz + top_z))
		head = rings_loft(rings, cap0=True)
		self.add("Head", head, skin, wh)
		self.add("Head", fan_cap(rings[-1], top), skin, wh)
		# nose, brow, ears
		nose = box((0.03 * k, 0.03 * k, 0.05 * k), center=(0, -0.108 * k, hz + 0.105 * k), top=(0.6, 0.4), shift=(0, 0.01))
		self.add("Head", nose, skin, wh)
		browm = self.mat("hair") if not f else self.mat("hair")
		for sx in (-1, 1):
			brow = box((0.036 * k, 0.012, 0.009 * k), center=(sx * 0.042 * k, -0.099 * k, hz + 0.158 * k), top=(0.8, 0.8))
			self.add("Head", xf(brow, T(sx * 0.042 * k, -0.099 * k, hz + 0.158 * k) @ R(0, sx * (7 if f else 4), 0)
				@ T(-sx * 0.042 * k, 0.099 * k, -(hz + 0.158 * k))), browm, wh)
		cheek = self.mat("skin_dark")
		for sx in (-1, 1):
			self.add("Head", box((0.028 * k, 0.01, 0.022 * k), center=(sx * 0.07 * k, -0.092 * k, hz + 0.105 * k), top=(0.7, 0.7)), cheek, wh)
		for sx in (-1, 1):
			ear = box((0.018, 0.04 * k, 0.055 * k), center=(sx * 0.1 * k, 0.012, hz + 0.12 * k), top=(0.8, 0.8))
			self.add("Head", ear, skin, wh)
			eye = box((0.03 * k, 0.012, 0.014 * k), center=(sx * 0.042 * k, -0.098 * k, hz + 0.137 * k))
			self.add("Head", eye, self.mat("eye", rough=0.4), wh)
		mouth = box((0.042 * k, 0.012, 0.011), center=(0, -0.1 * k, hz + 0.062 * k))
		self.add("Head", mouth, self.mat("lips"), wh)
		if not f:
			self.build_beard()

	def build_beard(self):
		"""A beard / stubble shell over the jaw and chin (lower front of the head)."""
		J = self.J
		hz = J["head_z"]
		m = self.mat("beard", rough=0.95)
		grow = 0.009 if self.look == "m1" else 0.003
		jw = 0.086 if self.look == "m2" else 0.082
		top = 0.105 if self.look == "m1" else 0.084
		spec = [(0.018, 0.032, 0.03, 0.028, -0.074), (0.048, jw, 0.082, 0.062, -0.02), (0.08, jw + 0.012, 0.096, 0.086, -0.006),
			(top, 0.096, 0.1, 0.1, 0.0)]
		rings = []
		for s in spec:
			r = ring(hz + s[0], s[1] + grow, s[2] + grow, s[3] + grow, n=10, cy=s[4], sq=2.3)
			rings.append(r)
		verts, faces = rings_loft(rings, cap0=True)
		# keep only the front half (the jaw line) and drop the mouth area
		keep = []
		for f in faces:
			c = sum((verts[i] for i in f), V((0, 0, 0))) / len(f)
			if c.y < 0.02 and not (abs(c.x) < 0.03 and hz + 0.055 < c.z < hz + 0.095 and c.y < -0.05):
				keep.append(f)
		self.add("Head", (verts, keep), m, pl_rig.w_head(J))
		if self.look == "m1":
			# a moustache
			self.add("Head", box((0.07, 0.016, 0.014), center=(0, -0.108, hz + 0.076), top=(0.7, 0.8)), m, pl_rig.w_head(J))

	# ------------------------------------------------------------------------------ hair

	def build_hair(self):
		getattr(self, "hair_" + self.look)()

	def _cap(self, front, back, side, grow=0.01, n=12, top_extra=0.02, rows=5):
		"""Hair cap fitted over the head (the head_spec rings grown by `grow`, the same squared
		cross-section), its lower edge `front` above head_z at the face, `back` at the nape and
		`side` over the ears (unit heights, scaled like the head); a low point on the crown."""
		hz = self.J["head_z"]
		spec, top = self.head_spec()
		k = 0.94 if self.female else 1.0
		front, back, side = front * k, back * k, side * k
		z_max = top - 0.006
		ex = 2.0 / 2.3
		cols = []
		for c in range(n):
			a = -math.pi / 2 + 2.0 * math.pi * c / n
			cols.append((math.cos(a), math.sin(a)))
		rings = []
		for i in range(rows):
			t = i / (rows - 1)
			pts = []
			for cx_, sy_ in cols:
				zb = side + (front - side) * (-sy_) ** 1.5 if sy_ < 0 else side + (back - side) * sy_ ** 1.2
				z = zb + (z_max - zb) * t
				w, fd, bd, cy = _interp_head(spec, z)
				d = fd if sy_ < 0 else bd
				x = (w + grow) * math.copysign(abs(cx_) ** ex, cx_)
				y = cy + (d + grow) * math.copysign(abs(sy_) ** ex, sy_)
				pts.append(V((x, y, hz + z)))
			rings.append(pts)
		return merge(rings_loft(rings), fan_cap(rings[-1], V((0, 0.012 * k, hz + top + grow + top_extra * 0.5))))

	def hair_f(self):
		J = self.J
		hz = J["head_z"]
		m = self.mat("hair", rough=0.9)
		mh = self.mat("hair_hi", rough=0.9)
		wh = pl_rig.w_head(J)
		whair = pl_rig.w_hair(J)
		k = 0.94
		self.add("HairTop", self._cap(front=0.19, back=0.04, side=0.09, grow=0.012), m, wh)
		# locks over the temples, down past the ears
		for sx in (-1, 1):
			pts = [V((sx * 0.07 * k, -0.075 * k, hz + 0.21 * k)), V((sx * 0.1 * k, -0.07 * k, hz + 0.15 * k)),
				V((sx * 0.112 * k, -0.045 * k, hz + 0.07)), V((sx * 0.115 * k, -0.03 * k, hz + 0.0))]
			self.add("HairTop", strand(pts, 0.04, 0.02, depth=0.4, n=3), mh, wh)
		r = rnd(7)
		# side curtains over the ears, falling behind the shoulders
		for sx in (-1, 1):
			for j in range(3):
				y0 = -0.03 + 0.04 * j
				pts = [V((sx * 0.1 * k, y0, hz + 0.17 * k)), V((sx * 0.118 * k, y0 + 0.01, hz + 0.07)),
					V((sx * 0.13, y0 + 0.05, J["neck_z"] - 0.02)), V((sx * (0.14 + 0.01 * j), y0 + 0.09, J["neck_z"] - 0.14)),
					V((sx * (0.13 + 0.012 * j), y0 + 0.11, J["neck_z"] - 0.26 - 0.03 * j))]
				self.add("HairBack", strand(pts, 0.05, 0.018, depth=0.5, n=3), mh if j == 1 else m, whair)
		# the long hair down the back: wavy strands of varied length
		for kk in range(11):
			a = math.radians(-60 + 120 * kk / 10)
			bx, by = math.sin(a), math.cos(a)
			wave = 0.018 * (1 if kk % 2 else -1)
			top = V((bx * 0.08 * k, 0.03 + by * 0.09 * k, hz + 0.2 * k))
			mid = V((bx * 0.105, 0.05 + by * 0.11, hz + 0.03))
			sh = V((bx * 0.13 + wave, 0.07 + by * 0.12, J["neck_z"] - 0.08))
			low = V((bx * 0.13 - wave, 0.1 + by * 0.1, J["neck_z"] - 0.25))
			end = V((bx * 0.12 + wave * 0.5, 0.12 + by * 0.08, 1.02 + r.random() * 0.1 - abs(bx) * 0.1))
			self.add("HairBack", strand([top, mid, sh, low, end], 0.058, 0.02, depth=0.5, n=3), m if kk % 3 else mh, whair)
		# strands over the front of the shoulders
		wf = pl_rig.chain([V((0, 0, J["head_top"])), V((0, 0, hz)), V((0, 0, J["neck_z"])), V((0, 0, 1.2))],
			["head", "neck", "chest"], [0.05, 0.06])
		for sx, lz in ((-1, 1.2), (1, 1.27)):
			pts = [V((sx * 0.1 * k, -0.05, hz + 0.12)), V((sx * 0.12, -0.05, hz + 0.02)), V((sx * 0.13, -0.07, J["neck_z"] - 0.04)),
				V((sx * 0.14, -0.1, lz + 0.06)), V((sx * 0.135, -0.11, lz))]
			self.add("HairFront", strand(pts, 0.045, 0.016, depth=0.5, n=3), m, wf)

	def hair_m1(self):
		J = self.J
		hz = J["head_z"]
		m = self.mat("hair", rough=0.9)
		mh = self.mat("hair_hi", rough=0.9)
		wh = pl_rig.w_head(J)
		self.add("HairTop", self._cap(front=0.195, back=0.06, side=0.11, grow=0.014), m, wh)
		r = rnd(3)
		# shaggy tufts on top and a fringe over the forehead
		for k in range(10):
			a = 2 * math.pi * k / 10
			base = V((math.sin(a) * 0.07, 0.01 + math.cos(a) * 0.075, hz + 0.24))
			tip = base + V((math.sin(a) * 0.06, math.cos(a) * 0.05, -0.03 - r.random() * 0.03))
			self.add("HairTop", strand([base, tip], 0.05, 0.02, depth=0.5), mh if k % 2 else m, wh)
		for k in range(5):
			x = -0.06 + 0.03 * k
			pts = [V((x * 0.8, -0.085, hz + 0.23)), V((x * 1.05, -0.108, hz + 0.19)), V((x * 1.15, -0.112, hz + 0.16 + r.random() * 0.02))]
			self.add("HairTop", strand(pts, 0.032, 0.012, depth=0.5), m if k % 2 else mh, wh)
		# the lower hair: shaggy locks over the ears and down the nape (seen below helmets)
		for k in range(11):
			a = math.radians(-115 + 230 * k / 10)
			bx, by = math.sin(a), math.cos(a)
			top = V((bx * 0.1, 0.012 + by * 0.108, hz + 0.13))
			end = V((bx * 0.12, 0.02 + by * 0.12, hz - 0.03 - r.random() * 0.04 - (0.02 if abs(bx) < 0.5 else 0.0)))
			self.add("HairBack", strand([top, (top + end) * 0.5 + V((bx * 0.012, by * 0.012, 0)), end], 0.05, 0.018, depth=0.45),
				m if k % 3 else mh, wh)

	def hair_m2(self):
		J = self.J
		hz = J["head_z"]
		m = self.mat("hair", rough=0.95)
		mh = self.mat("hair_hi", rough=0.95)
		wh = pl_rig.w_head(J)
		self.add("HairTop", self._cap(front=0.205, back=0.07, side=0.13, grow=0.01), m, wh)
		r = rnd(5)
		# messy spikes, swept forward over the brow
		for k in range(12):
			a = 2 * math.pi * k / 12
			base = V((math.sin(a) * 0.065, 0.01 + math.cos(a) * 0.07, hz + 0.245))
			d = V((math.sin(a) * 0.5, math.cos(a) * 0.5 - 0.6, 0.35)).normalized()
			tip = base + d * (0.06 + r.random() * 0.03)
			self.add("HairTop", strand([base, tip], 0.045, 0.015, depth=0.6), mh if k % 3 == 0 else m, wh)
		for k in range(4):
			x = -0.05 + 0.033 * k
			pts = [V((x, -0.08, hz + 0.24)), V((x * 1.1, -0.11, hz + 0.205)), V((x * 1.2 + 0.01, -0.115, hz + 0.18))]
			self.add("HairTop", strand(pts, 0.03, 0.01, depth=0.5), m, wh)
		for k in range(5):
			a = math.radians(-70 + 140 * k / 4)
			bx, by = math.sin(a), math.cos(a)
			top = V((bx * 0.098, 0.012 + by * 0.106, hz + 0.13))
			end = V((bx * 0.101, 0.014 + by * 0.109, hz + 0.075))
			self.add("HairBack", strand([top, end], 0.04, 0.02, depth=0.35), m, wh)

	# ------------------------------------------------------------------------------ outfits

	def build_outfit(self):
		getattr(self, "outfit_" + self.look)()

	def trousers(self, part, m, top_z=1.03, bottom_z=0.22, baggy=1.0, knee_rip=None, patches=(), patch_mats=()):
		"""Trousers: a pelvis shell (waist -> crotch) and two leg tubes that gather at the shins."""
		J = self.J
		sh = self.torso_spec()
		wt = pl_rig.w_torso(J)
		pel = [ring(top_z, sh[2][1] + 0.012, sh[2][2] + 0.012, sh[2][3] + 0.014, n=12, sq=2.2),
			ring(0.95, sh[1][1] + 0.016, sh[1][2] + 0.014, sh[1][3] + 0.016, n=12, sq=2.2),
			ring(0.86, sh[0][1] + 0.014, sh[0][2] + 0.012, sh[0][3] + 0.014, n=12, sq=2.2)]
		self.add(part, rings_loft(list(reversed(pel))), m, wt)
		for side, sx in (("r", -1.0), ("l", 1.0)):
			pts = self.leg_path(side, 0.94, bottom_z, steps=7)
			rr = []
			for i, p in enumerate(pts):
				t = i / (len(pts) - 1)
				r = (0.1 - 0.02 * t + 0.012 * math.sin(t * math.pi)) * baggy
				if p.z < J["knee_z"] - 0.12:
					r *= 0.86 if p.z > bottom_z + 0.05 else 0.72
				rr.append((r, r * 1.02))
			self.add(part, tube(pts, rr, n=8, side=(0, -1, 0), cap0=False, cap1=True), m, pl_rig.w_leg(J, side))
		for (side, z, w, h, pm) in patches:
			sx = -1.0 if side == "r" else 1.0
			knee = J["knee_" + side]
			c = V((knee.x + sx * 0.02, knee.y - 0.098 * baggy, z))
			self.add(part, patch(c, (0.15 * sx, -1, 0), w, h), pm, pl_rig.w_leg(J, side))

	def shin_wraps(self, part, m, m2, z0=0.1, z1=0.4, count=6, r0=0.06, r1=0.075):
		J = self.J
		for side in ("r", "l"):
			ank = J["ankle_" + side]
			p0 = V((ank.x, ank.y - 0.005, z0))
			p1 = self.leg_path(side, z1, z1, steps=1)[0]
			geo = wrap_bands(p0, p1, r0, r1, count, width=0.045, n=8, slant=16.0, side=(1, 0, 0))
			self.add(part, geo, m if side == "r" else m2, pl_rig.w_leg(J, side))

	def rope_belt(self, part, m, z=1.02, knot_x=0.07, ends=((0.075, 0.8), (0.1, 0.84))):
		J = self.J
		sh = self.torso_spec()
		wt = pl_rig.w_torso(J)
		ring_pts = ring(z, sh[2][1] + 0.028, sh[2][2] + 0.026, sh[2][3] + 0.028, n=16, sq=2.2)
		pts = ring_pts + [ring_pts[0]]
		self.add(part, rope(pts, r=0.014, n=5), m, wt)
		knot = V((knot_x, -(sh[2][2] + 0.034), z - 0.01))
		self.add(part, sphere(0.022, 6, 3, center=tuple(knot), scale=(1.2, 0.8, 1.0)), m, wt)
		for dx, lz in ends:
			end = [knot + V((0, -0.005, -0.01)), knot + V((dx * 0.3, -0.012, -(knot.z - lz) * 0.5)), V((knot.x + dx * 0.4, knot.y - 0.01, lz))]
			self.add(part, rope(end, r=0.011, n=4), m, pl_rig.w_skirt(J, full=0.3))

	# -- female
	def outfit_f(self):
		J = self.J
		sh = self.torso_spec()
		linen = self.mat("linen")
		linen_d = self.mat("linen_dark")
		over = self.mat("over")
		over_d = self.mat("over_dark")
		wt = pl_rig.w_torso(J)
		# blouse: torso shell with a deep V, loose 3/4 sleeves with torn cuffs
		spec = [(0.99, 0.172, 0.108, 0.125), (1.07, 0.142, 0.1, 0.105), (1.15, 0.146, 0.106, 0.105), (1.23, 0.163, 0.137, 0.11),
			(1.3, 0.168, 0.132, 0.112), (1.365, 0.18, 0.105, 0.112), (1.418, 0.182, 0.08, 0.102), (1.452, 0.075, 0.065, 0.07)]
		rings = self.torso_rings(spec, n=12, grow=0.004)
		# V neck: pull the front centre vertices of the top rings down
		for i, rr in enumerate(rings[-4:]):
			f = rr[0]
			f.z -= 0.05 * (i + 1) * 0.55
			f.y += 0.02
		self.add("Outfit_Top", rings_loft(rings), linen, wt)
		for side in ("r", "l"):
			pts = self.arm_path(side, 0.0, 0.64, steps=5)
			pts[0] = pts[0] + V(0, 0, 0.012)
			rr = [(0.064, 0.062), (0.064, 0.062), (0.062, 0.06), (0.06, 0.058), (0.062, 0.058), (0.066, 0.062)]
			geo = tube(pts, rr, n=8, side=(0, -1, 0), cap0=False, cap1=False)
			self.add("Outfit_Top", _jag_end(geo, 8, 0.03, seed=11 if side == "r" else 12), linen, pl_rig.w_arm(J, side))
		# the overdress: sleeveless, open at the front, down over the hips
		ospec = [(0.9, 0.19, 0.125, 0.14), (1.0, 0.183, 0.118, 0.13), (1.1, 0.16, 0.112, 0.114), (1.2, 0.17, 0.14, 0.116),
			(1.3, 0.176, 0.138, 0.118), (1.38, 0.19, 0.11, 0.118), (1.425, 0.176, 0.083, 0.106)]
		orings = self.torso_rings(ospec, n=14, grow=0.012)
		self.add("Outfit_Top", _open_front(orings, open_k=2, seed=21, jag=0.05), over, wt)
		# sash: a wide band at the waist, a knot and two hanging ends
		band_r0 = ring(1.02, 0.176, 0.118, 0.13, n=14, sq=2.2)
		band_r1 = ring(1.1, 0.162, 0.113, 0.118, n=14, sq=2.2)
		self.add("Outfit_Belt", rings_loft([band_r0, band_r1]), self.mat("sash"), wt)
		knot = V((0.03, -0.128, 1.06))
		self.add("Outfit_Belt", sphere(0.028, 6, 3, center=tuple(knot), scale=(1.3, 0.7, 1.0)), self.mat("sash"), wt)
		for dx, lz, w in ((0.02, 0.74, 0.05), (0.065, 0.8, 0.04)):
			pts = [knot + V((0, -0.01, -0.02)), knot + V((dx * 0.5, -0.02, -0.14)), V((knot.x + dx, knot.y - 0.02, lz))]
			self.add("Outfit_Belt", ribbon(pts, [w, w * 0.9, w * 0.7], (0, -1, 0)), self.mat("sash"), pl_rig.w_skirt(J, full=0.3))
		# layered skirts: a beige underskirt to the knees, a brown wrap to mid-calf (shorter at the back
		# right, like the reference), both torn
		ws = pl_rig.w_skirt(J)
		under = [ring(1.0, 0.178, 0.12, 0.132, n=16, sq=2.1), ring(0.78, 0.205, 0.15, 0.16, n=16, sq=2.0),
			ring(0.44, 0.228, 0.172, 0.182, n=16, sq=1.9, jag=sawtooth(16, 0.07, rnd=0.05, seed=31))]
		self.add("Outfit_Top", double_sided(rings_loft(under)), linen_d, ws)
		wrap = [ring(1.01, 0.183, 0.124, 0.136, n=16, sq=2.1), ring(0.8, 0.212, 0.158, 0.166, n=16, sq=2.0),
			ring(0.56, 0.236, 0.178, 0.188, n=16, sq=1.9, jag=_asym_hem(16, seed=32))]
		self.add("Outfit_Top", _open_front(wrap, open_k=1, seed=33, jag=0.0, double=True, open_at=3), self.mat("skirt"), ws)
		# trousers with a torn left knee
		self.trousers("Outfit_Legs", self.mat("trousers"), bottom_z=0.2, baggy=0.95,
			patches=[("l", 0.5, 0.05, 0.035, self.mat("skin"))])
		# shin wraps + sandals with straps
		self.shin_wraps("Outfit_Feet", self.mat("wrap"), self.mat("wrap_dark"), z0=0.075, z1=0.36, count=6, r0=0.052, r1=0.064)
		for side, sx in (("r", -1.0), ("l", 1.0)):
			self.sandal(side, sx)
		# a wrist wrap on the right forearm
		wr = J["wrist_r"]
		d = J["forearm_dir_r"]
		self.add("Outfit_Wraps", wrap_bands(wr - d * 0.11, wr + d * 0.005, 0.036, 0.033, 3, width=0.03, n=7), self.mat("wrap"),
			pl_rig.w_arm(J, "r"))

	def sandal(self, side, sx):
		J = self.J
		ank, ball, toe = J["ankle_" + side], J["ball_" + side], J["toe_" + side]
		wf = pl_rig.w_leg(J, side)
		sole = foot_box((0.085, 0.24, 0.022), center=(ank.x, (J["heel_" + side].y + toe.y) * 0.5 - 0.005, 0.011), top=(1.0, 0.96),
			cuts=[ball.y])
		self.add("Outfit_Feet", sole, self.mat("sole"), wf)
		# the bare foot above the sole (toes show)
		foot = foot_box((0.07, 0.2, 0.05), center=(ank.x, (ank.y + toe.y) * 0.5 + 0.01, 0.047), top=(0.85, 0.7), shift=(0, 0.02),
			cuts=[ball.y])
		self.add("Outfit_Feet", foot, self.mat("skin"), wf)
		for y in (ball.y + 0.02, ank.y - 0.03):
			self.add("Outfit_Feet", band((ank.x, y, 0), 0.042, 0.02, 0.025, 0.045, n=6), self.mat("strap"), wf)

	# -- male 1
	def outfit_m1(self):
		J = self.J
		linen = self.mat("linen")
		linen_d = self.mat("linen_dark")
		wt = pl_rig.w_torso(J)
		ws = pl_rig.w_skirt(J)
		# the tunic: body down to the upper thigh (torn), long sleeves to mid forearm
		spec = [(1.0, 0.176, 0.118, 0.13), (1.1, 0.165, 0.112, 0.114), (1.2, 0.178, 0.124, 0.118), (1.3, 0.195, 0.125, 0.122),
			(1.37, 0.205, 0.106, 0.124), (1.425, 0.19, 0.08, 0.108), (1.46, 0.078, 0.068, 0.07)]
		rings = self.torso_rings(spec, n=12, grow=0.006)
		rings[-1][0].z -= 0.06
		rings[-2][0].z -= 0.02
		self.add("Outfit_Top", rings_loft(rings), linen, wt)
		skirt = [ring(1.0, 0.182, 0.124, 0.136, n=14, sq=2.1), ring(0.88, 0.2, 0.14, 0.152, n=14, sq=2.0),
			ring(0.76, 0.215, 0.152, 0.164, n=14, sq=1.95, jag=sawtooth(14, 0.055, rnd=0.035, seed=41))]
		self.add("Outfit_Top", double_sided(rings_loft(skirt)), linen, pl_rig.w_skirt_legs(J, share=0.25))
		for side in ("r", "l"):
			pts = self.arm_path(side, 0.0, 0.82, steps=6)
			pts[0] = pts[0] + V(0, 0, 0.012)
			rr = [(0.068, 0.066), (0.064, 0.062), (0.06, 0.058), (0.058, 0.056), (0.057, 0.055), (0.058, 0.055), (0.062, 0.058)]
			geo = tube(pts, rr, n=8, side=(0, -1, 0), cap0=False, cap1=False)
			self.add("Outfit_Top", _jag_end(geo, 8, 0.035, seed=43 if side == "r" else 44), linen, pl_rig.w_arm(J, side))
		# the neck lacing
		self.add("Outfit_Top", box((0.012, 0.01, 0.07), center=(0, -0.112, 1.39)), self.mat("over_dark"), wt)
		# the ragged shawl: over the shoulders and down the back, open at the front, torn
		sspec = [(1.2, 0.21, 0.12, 0.135), (1.31, 0.225, 0.13, 0.14), (1.39, 0.235, 0.11, 0.135), (1.445, 0.2, 0.085, 0.12),
			(1.49, 0.095, 0.075, 0.09)]
		srings = self.torso_rings(sspec, n=14, grow=0.012)
		# longer at the back and in two ragged ends in front
		for p in srings[0]:
			if p.y > 0.03:
				p.z -= 0.2 * min(1.0, p.y / 0.12)
			elif p.y < -0.05 and abs(p.x) < 0.16:
				p.z -= 0.08
		self.add("Outfit_Top", _open_front(srings, open_k=2, seed=45, jag=0.05, double=True), self.mat("over"), wt)
		self.rope_belt("Outfit_Belt", self.mat("rope"), z=1.02, knot_x=-0.07, ends=((-0.03, 0.78), (-0.07, 0.83)))
		self.trousers("Outfit_Legs", self.mat("trousers"), bottom_z=0.2, baggy=1.02,
			patches=[("l", 0.62, 0.07, 0.07, self.mat("patch")), ("r", 0.47, 0.06, 0.05, self.mat("patch2")),
				("r", 0.72, 0.05, 0.06, self.mat("patch"))])
		self.shin_wraps("Outfit_Feet", self.mat("wrap"), self.mat("wrap_dark"), z0=0.07, z1=0.38, count=6, r0=0.058, r1=0.07)
		for side, sx in (("r", -1.0), ("l", 1.0)):
			self.wrapped_shoe(side, sx, self.mat("shoe"))

	def wrapped_shoe(self, side, sx, m, h=0.075):
		J = self.J
		ank, toe = J["ankle_" + side], J["toe_" + side]
		wf = pl_rig.w_leg(J, side)
		shoe = foot_box((0.1, 0.245, h), center=(ank.x, (J["heel_" + side].y + toe.y) * 0.5, h * 0.5), top=(0.9, 0.7), shift=(0, 0.02),
			cuts=[J["ball_" + side].y])
		self.add("Outfit_Feet", shoe, m, wf)

	# -- male 2
	def outfit_m2(self):
		J = self.J
		linen = self.mat("linen")
		dirt = self.mat("dirt")
		wt = pl_rig.w_torso(J)
		# sleeveless tunic with a deep V and wide arm holes, torn hem at the upper thigh
		spec = [(1.0, 0.172, 0.114, 0.128), (1.1, 0.172, 0.113, 0.118), (1.2, 0.2, 0.135, 0.13), (1.3, 0.218, 0.14, 0.133),
			(1.37, 0.225, 0.115, 0.133), (1.42, 0.2, 0.084, 0.118), (1.46, 0.08, 0.07, 0.074)]
		rings = self.torso_rings(spec, n=12, grow=0.006)
		for i, rr in enumerate(rings[-4:]):
			rr[0].z -= 0.055 * (i + 1) * 0.6
			rr[0].y += 0.015
		self.add("Outfit_Top", rings_loft(rings), linen, wt)
		skirt = [ring(1.0, 0.178, 0.12, 0.134, n=14, sq=2.1), ring(0.88, 0.196, 0.136, 0.15, n=14, sq=2.0),
			ring(0.78, 0.208, 0.146, 0.16, n=14, sq=1.95, jag=sawtooth(14, 0.06, rnd=0.04, seed=51))]
		self.add("Outfit_Top", double_sided(rings_loft(skirt)), dirt, pl_rig.w_skirt_legs(J, share=0.25))
		# dirt stains on the chest
		for c, n, w, h in (((0.08, -0.14, 1.2), (0.3, -1, 0), 0.07, 0.09), ((-0.09, -0.135, 1.08), (-0.3, -1, 0), 0.06, 0.07),
				((0.0, 0.14, 1.22), (0, 1, 0), 0.14, 0.12)):
			self.add("Outfit_Top", patch(c, n, w, h), dirt, wt)
		self.rope_belt("Outfit_Belt", self.mat("rope"), z=1.03, knot_x=0.05, ends=((0.02, 0.76), (0.06, 0.86)))
		# forearm wraps
		for side in ("r", "l"):
			wr = J["wrist_" + side]
			d = J["forearm_dir_" + side]
			self.add("Outfit_Wraps", wrap_bands(wr - d * 0.14, wr + d * 0.01, 0.052, 0.042, 5, width=0.03, n=7), self.mat("wrap"),
				pl_rig.w_arm(J, side))
		self.trousers("Outfit_Legs", self.mat("trousers"), bottom_z=0.24, baggy=1.02,
			patches=[("r", 0.62, 0.075, 0.08, self.mat("patch")), ("l", 0.44, 0.06, 0.06, self.mat("patch")),
				("l", 0.7, 0.05, 0.05, self.mat("patch2"))])
		self.shin_wraps("Outfit_Feet", self.mat("wrap"), self.mat("wrap_dark"), z0=0.17, z1=0.4, count=4, r0=0.065, r1=0.072)
		for side, sx in (("r", -1.0), ("l", 1.0)):
			self.boot(side, sx)

	def boot(self, side, sx):
		J = self.J
		ank, toe = J["ankle_" + side], J["toe_" + side]
		wf = pl_rig.w_leg(J, side)
		m = self.mat("boot", rough=0.7)
		md = self.mat("boot_dark", rough=0.7)
		ball_y = J["ball_" + side].y
		foot = foot_box((0.108, 0.26, 0.09), center=(ank.x, (J["heel_" + side].y + toe.y) * 0.5, 0.045), top=(0.92, 0.72), shift=(0, 0.025),
			cuts=[ball_y])
		self.add("Outfit_Feet", foot, m, wf)
		self.add("Outfit_Feet", foot_box((0.112, 0.265, 0.02), center=(ank.x, (J["heel_" + side].y + toe.y) * 0.5, 0.01), cuts=[ball_y]), md, wf)
		shaft = tube([V((ank.x, ank.y, 0.05)), V((ank.x, ank.y - 0.005, 0.2))], [(0.062, 0.066), (0.064, 0.068)], n=8, side=(0, -1, 0))
		self.add("Outfit_Feet", shaft, m, wf)
		self.add("Outfit_Feet", band((ank.x, ank.y - 0.005, 0), 0.066, 0.07, 0.17, 0.2, n=8), md, wf)


# ----------------------------------------------------------------------------------- geometry helpers

def _frame(origin, xv, zv):
	from mathutils import Matrix
	z = Vector(zv).normalized()
	x = Vector(xv)
	x = (x - z * x.dot(z)).normalized()
	y = z.cross(x)
	M = Matrix.Identity(4)
	for i in range(3):
		M[i][0], M[i][1], M[i][2], M[i][3] = x[i], y[i], z[i], origin[i]
	return M


def _jag_end(geo, n, depth, seed=0):
	"""Tear the last ring of a tube (the last n vertices): alternate vertices pulled back/along."""
	verts, faces = geo
	r = rnd(seed)
	vs = [Vector(v) for v in verts]
	last = vs[-n:]
	prev = vs[-2 * n:-n]
	for k in range(n):
		d = last[k] - prev[k]
		if d.length > 1e-6:
			d.normalize()
		amt = depth * (1.0 if k % 2 == 0 else 0.1) * (0.6 + 0.8 * r.random())
		vs[len(vs) - n + k] = last[k] + d * amt
	return vs, faces


def _open_front(rings, open_k=2, seed=0, jag=0.0, double=True, open_at=0):
	"""Loft rings but leave `open_k` segments on each side of ring index `open_at` (the front centre)
	open; the bottom ring's free edge can be torn (jag). Double sided (the inside shows)."""
	n = len(rings[0])
	r = rnd(seed)
	if jag > 0.0:
		for k, p in enumerate(rings[0]):
			p.z -= jag * (1.0 if k % 2 == 0 else 0.15) * (0.5 + r.random())
	verts, faces, idx = [], [], []
	for rr in rings:
		ids = []
		for p in rr:
			ids.append(len(verts))
			verts.append(Vector(p))
		idx.append(ids)
	skip = set()
	for d in range(-open_k, open_k):
		skip.add((open_at + d) % n)
	for i in range(len(idx) - 1):
		a, b = idx[i], idx[i + 1]
		for k in range(n):
			if k in skip:
				continue
			k1 = (k + 1) % n
			faces.append([a[k], a[k1], b[k1], b[k]])
	geo = (verts, faces)
	return double_sided(geo) if double else geo


def _asym_hem(n, seed=0):
	"""A torn, asymmetric hem: long at the front left, shorter at the back right."""
	r = rnd(seed)
	vals = []
	for k in range(n):
		a = 2 * math.pi * k / n - math.pi / 2
		long = 0.5 + 0.5 * math.cos(a - math.radians(-40))      # longest toward the front-left
		vals.append(-0.13 * long - (0.05 if k % 2 == 0 else 0.0) - r.random() * 0.03 + 0.06)
	return lambda k, x, y: vals[k % n]


def _interp_head(spec, z):
	if z <= spec[0][0]:
		s = spec[0]
		return s[1], s[2], s[3], s[4]
	for a, b in zip(spec, spec[1:]):
		if a[0] <= z <= b[0]:
			t = (z - a[0]) / (b[0] - a[0])
			return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3, 4))
	s = spec[-1]
	return s[1], s[2], s[3], s[4]
