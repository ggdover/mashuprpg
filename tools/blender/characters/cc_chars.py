"""Rigged characters (docs/ARCHITECTURE.md §14.2-14.4). Each builder creates the armature and the
skinned mesh parts and returns (armature, animation style, action list).

Every mesh is modelled in the rest pose in "unit" coordinates (a 1.8 m humanoid at the origin facing
-Y) and scaled by the character's scale when added; each primitive is skinned 100% to one bone.
Parts: Head, Torso, Arms, Hands, Legs, Feet (+ Hair / Details / Weapon where useful); monsters and
the merchant join everything except "Weapon" into ONE skinned object "Body" (Body.build(merge=True)) =
one draw per material. Monsters keep their natural colours on tint_* materials (Assets.tint multiplies
them for rarity or archetype variants). The player models are built by tools/blender/player.
"""
import math
import random

from mathutils import Matrix, Vector

import cc_anim
from cc_mesh import (Part, R, S, T, box, build_object, cyl, glow, hair_cap, hexc, icosphere, lathe, loft, mat, octa, seg,
	slab, sphere, tint_mat, torus, tube, xf)
from cc_rig import create_armature, humanoid, pose


class Body:
	"""Collects Parts for one character; geometry is given in unit coordinates and scaled by s."""

	def __init__(self, J, s=1.0):
		self.J = J
		self.s = s
		self.parts = {}
		self.S = S(s)

	def add(self, part, geo, material, bone, M=None):
		if part not in self.parts:
			self.parts[part] = Part(part)
		MM = self.S if M is None else self.S @ M
		self.parts[part].add(geo, material, bone, MM)

	def both(self, part, fn, material):
		"""fn(side, sx) -> (geo, bone) or a list of them; called for 'r' (sx=-1) and 'l' (sx=+1)."""
		for side, sx in (("r", -1.0), ("l", 1.0)):
			res = fn(side, sx)
			if not isinstance(res, list):
				res = [res]
			for item in res:
				if len(item) == 3:
					geo, bone, m = item
				else:
					geo, bone = item
					m = material
				self.add(part, geo, m, bone)

	def build(self, arm_obj, merge=False):
		"""Create the mesh objects. merge=True joins every part except "Weapon" into ONE skinned object
		named "Body" (monsters / NPCs: one skinned MeshInstance3D, one surface per material); the
		player keeps its separate Head/Torso/Arms/Hands/Legs/Feet/Hair parts for tinting."""
		if not merge:
			return [build_object(self.parts[name], arm_obj) for name in self.parts]
		body = Part("Body")
		for name, part in self.parts.items():
			if name != "Weapon":
				body.extend(part)
		out = [build_object(body, arm_obj)]
		if "Weapon" in self.parts:
			out.append(build_object(self.parts["Weapon"], arm_obj))
		return out


def V(*a):
	return Vector(a)


def rig(s=1.0, **kw):
	"""(unit joints for modelling, armature object built with scaled joints)."""
	J = humanoid(scale=1.0, **kw)
	Js = humanoid(scale=s, **kw)
	arm = create_armature(Js)
	return J, arm


def _frame_axes(origin, xv, zv):
	z = Vector(zv).normalized()
	x = Vector(xv)
	x = (x - z * x.dot(z)).normalized()
	y = z.cross(x)
	M = Matrix.Identity(4)
	for i in range(3):
		M[i][0] = x[i]
		M[i][1] = y[i]
		M[i][2] = z[i]
		M[i][3] = origin[i]
	return M


def grip_dir(J, side):
	head, tail, _z = J["bones"]["grip_" + side]
	return (tail - head).normalized()


def fists(b, J, part, m, size=(0.09, 0.085, 0.11), thumb=True, claws=None, open_hand=False):
	"""Blocky fists around the grip point (hand_* bones). claws=(material, length)."""
	for side, sx in (("r", -1.0), ("l", 1.0)):
		wr = J["wrist_" + side]
		kn = J["knuckle_" + side]
		ax = (kn - wr).normalized()
		M = _frame_axes(wr, V(sx, 0, 0), ax)
		b.add(part, box(size, center=(0, 0, size[2] * 0.5), top=(0.92, 0.85)), m, "hand_" + side, M)
		g = grip_dir(J, side if side == "r" else "r")
		if side == "l":
			g = V(-g.x, g.y, g.z)
		if thumb:
			tp = wr + ax * (size[2] * 0.4) + g * (size[1] * 0.52)
			b.add(part, box((size[0] * 0.42, 0.034, 0.05), center=tuple(tp)), m, "hand_" + side)
		if claws:
			cm, clen = claws
			for k in (-1, 0, 1):
				base = wr + ax * size[2] * 0.85 + V(sx, 0, 0) * (k * size[0] * 0.3) + g * 0.02
				tip = base + ax * clen * 0.8 + g * (clen * 0.55)
				b.add(part, cyl(base, tip, 0.016, 0.0, n=4), cm, "hand_" + side)


def std_arms(b, J, part, m_up, m_low=None, r=(0.058, 0.049, 0.047, 0.04), pauldron=None, m_paul=None):
	m_low = m_low or m_up

	def fn(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		out = [(seg(sh, el, [(0, r[0], r[0] * 1.04), (1.0, r[1], r[1] * 1.04)], n=6), "upper_arm_" + side, m_up),
			(seg(el - d * 0.025, wr, [(0, r[2], r[2] * 1.04), (1, r[3], r[3] * 1.04)], n=6), "lower_arm_" + side, m_low)]
		if pauldron:
			rad, sc = pauldron
			out.append((sphere(rad, 8, 4, center=tuple(sh + V(sx * 0.014, 0, 0.008)), scale=sc, cut=(-0.25, 1.0)),
				"upper_arm_" + side, m_paul or m_up))
		return out
	b.both(part, fn, m_up)


def std_legs(b, J, part, m_thigh, m_shin=None, r=(0.09, 0.064, 0.062, 0.048), ankle_ext=0.1):
	m_shin = m_shin or m_thigh

	def fn(side, sx):
		hip, knee, ank = J["hip_" + side], J["knee_" + side], J["ankle_" + side]
		return [
			(seg(hip + V(0, 0, 0.05), knee, [(0, r[0], r[0] * 1.06), (0.55, r[0] * 0.86, r[0] * 0.92), (1, r[1], r[1] * 1.06)], n=6),
				"upper_leg_" + side, m_thigh),
			(seg(knee + V(0, 0, 0.02), ank + V(0, 0, ankle_ext), [(0, r[2], r[2] * 1.06), (0.45, r[2] * 0.95, r[2] * 1.02), (1, r[3], r[3] * 1.05)], n=6),
				"lower_leg_" + side, m_shin),
		]
	b.both(part, fn, m_thigh)


def std_boots(b, J, part, m, w=0.11, l=0.24, h=0.1, shaft=0.2, r=0.062, cuff=None):
	def fn(side, sx):
		ank = J["ankle_" + side]
		out = [(box((w, l, h), center=(ank.x, -0.035 - (l - 0.23) * 0.4, h * 0.5), top=(0.92, 0.72), shift=(0, 0.03)), "foot_" + side, m)]
		if shaft > 0:
			out.append((seg(ank - V(0, 0, 0.03), ank + V(0, 0, shaft), [(0, r, r * 1.08), (0.8, r * 1.02, r * 1.1), (1, r * 1.1, r * 1.18)], n=6),
				"lower_leg_" + side, cuff or m))
		return out
	b.both(part, fn, m)


def head_loft(hz, w=0.112, d=0.122, h=0.29, cy=0.006, n=8, chin=0.62, jaw=0.9):
	"""Rounded blocky head from the head bone head (hz) up; the face is flat at -Y."""
	k = h / 0.27
	rings = [
		(hz + 0.01 * k, w * chin * 0.95, d * chin, 0, cy - 0.014),
		(hz + 0.05 * k, w * jaw, d * 0.9, 0, cy - 0.006),
		(hz + 0.12 * k, w * 1.03, d * 1.02, 0, cy),
		(hz + 0.19 * k, w, d, 0, cy + 0.004),
		(hz + 0.245 * k, w * 0.7, d * 0.72, 0, cy + 0.006),
		(hz + h, 0, 0, 0, cy + 0.006),
	]
	return loft(rings, n=n)


def eyes(b, part, hz, m, y=-0.118, z=0.135, x=0.044, size=(0.026, 0.014, 0.03), bone="head"):
	for sx in (-1, 1):
		b.add(part, box(size, center=(sx * x, y, hz + z)), m, bone)


# =================================================================================== skeleton

def build_skeleton():
	J, arm = rig(shoulder_x=0.19, hip_x=0.095)
	b = Body(J)
	hz = J["head_z"]
	bone = mat("tint_bone", hexc("ddd3b6"), rough=0.75)
	dark = mat("void", hexc("141010"), rough=0.9)
	eye = glow("eye_skeleton", hexc("6fe8ff"), 7.0)
	rust = mat("rust_iron", hexc("7a5b45"), rough=0.6, metal=0.3)
	cloth = mat("rag_red", hexc("6a2a22"), rough=0.95)
	leather = mat("leather_old", hexc("4a3322"), rough=0.9)

	# ---- Head: skull + jaw + glowing eyes
	b.add("Head", loft([(hz + 0.07, 0.085, 0.1, 0, 0.0), (hz + 0.12, 0.11, 0.12, 0, 0.008), (hz + 0.2, 0.108, 0.118, 0, 0.012),
		(hz + 0.26, 0.075, 0.085, 0, 0.012), (hz + 0.285, 0.0, 0.0, 0, 0.012)], n=8), bone, "head")
	b.add("Head", box((0.13, 0.1, 0.06), center=(0, -0.045, hz + 0.05), top=(1.05, 1.0)), bone, "head")
	b.add("Head", box((0.1, 0.012, 0.03), center=(0, -0.097, hz + 0.055)), dark, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.045, 0.02, 0.045), center=(sx * 0.045, -0.112, hz + 0.14)), dark, "head")
		b.add("Head", box((0.026, 0.01, 0.024), center=(sx * 0.045, -0.123, hz + 0.14)), eye, "head")
	b.add("Head", box((0.022, 0.02, 0.03), center=(0, -0.12, hz + 0.1), top=(0.4, 1.0)), dark, "head")
	for k in range(4):
		b.add("Head", box((0.05, 0.04, 0.03), center=(0, 0.0, J["neck_z"] + 0.02 * k)), bone, "neck")

	# ---- Torso: spine, ribs, sternum, pelvis, loincloth
	for k in range(5):
		z = 1.04 + k * 0.045
		b.add("Torso", box((0.05, 0.045, 0.035), center=(0, 0.03, z)), bone, "spine")
	for k, (z, rx, ry) in enumerate([(1.26, 0.15, 0.1), (1.31, 0.165, 0.108), (1.36, 0.165, 0.106), (1.41, 0.145, 0.095)]):
		ring = torus(1.0, 0.1, 12, 4)
		b.add("Torso", ring, bone, "chest", T(0, 0.01, z) @ S(rx, ry, 0.13))
	b.add("Torso", box((0.035, 0.03, 0.2), center=(0, -0.105, 1.33)), bone, "chest")
	b.add("Torso", box((0.05, 0.04, 0.2), center=(0, 0.1, 1.34)), bone, "chest")
	b.add("Torso", loft([(1.25, 0.12, 0.07, 0, 0.02), (1.44, 0.12, 0.07, 0, 0.02)], n=6), dark, "chest")
	b.add("Torso", box((0.36, 0.06, 0.05), center=(0, 0.02, 1.44), top=(0.8, 1.0)), bone, "chest")
	b.add("Torso", box((0.26, 0.12, 0.1), center=(0, 0.01, 0.96), top=(1.25, 1.0)), bone, "hips")
	b.add("Torso", box((0.2, 0.03, 0.2), center=(0, -0.07, 0.86), top=(1.1, 1.0)), cloth, "hips")
	b.add("Torso", box((0.2, 0.03, 0.18), center=(0, 0.08, 0.87), top=(1.1, 1.0)), cloth, "hips")
	b.add("Torso", loft([(0.97, 0.155, 0.08), (1.01, 0.155, 0.08)], n=8), leather, "hips")

	# ---- Arms: thin bones with knobby joints, rusty pauldron on the left shoulder
	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		out = [(cyl(sh, el, 0.03, 0.026, n=5), "upper_arm_" + side, bone),
			(octa(0.04, center=tuple(sh)), "upper_arm_" + side, bone),
			(octa(0.034, center=tuple(el)), "lower_arm_" + side, bone),
			(cyl(el, wr, 0.024, 0.021, n=5), "lower_arm_" + side, bone),
			(cyl(el + V(0.012 * sx, 0.012, 0), wr + V(0.012 * sx, 0.012, 0), 0.016, 0.014, n=4), "lower_arm_" + side, bone)]
		if side == "l":
			out.append((sphere(0.1, 8, 4, center=tuple(sh + V(0.02, 0, 0.012)), scale=(1.1, 1.05, 0.8), cut=(-0.2, 1.0)), "upper_arm_l", rust))
			out.append((cyl(sh + V(0.02, 0, 0.09), sh + V(0.05, 0, 0.16), 0.02, 0.0, n=4), "upper_arm_l", rust))
		return out
	b.both("Arms", arm_geo, bone)
	fists(b, J, "Hands", bone, size=(0.075, 0.065, 0.095))

	# ---- Legs
	def leg_geo(side, sx):
		hip, knee, ank = J["hip_" + side], J["knee_" + side], J["ankle_" + side]
		return [(cyl(hip + V(0, 0, 0.03), knee, 0.034, 0.028, n=5), "upper_leg_" + side, bone),
			(octa(0.04, center=tuple(knee + V(0, -0.01, 0))), "lower_leg_" + side, bone),
			(cyl(knee, ank, 0.027, 0.022, n=5), "lower_leg_" + side, bone),
			(cyl(knee + V(0.014 * sx, 0.01, 0), ank + V(0.014 * sx, 0.01, 0.03), 0.016, 0.013, n=4), "lower_leg_" + side, bone)]
	b.both("Legs", leg_geo, bone)

	def foot_geo(side, sx):
		ank = J["ankle_" + side]
		return [(box((0.085, 0.2, 0.06), center=(ank.x, -0.04, 0.03), top=(0.85, 0.75)), "foot_" + side),
			(octa(0.035, center=tuple(ank)), "foot_" + side)]
	b.both("Feet", foot_geo, bone)
	b.build(arm, merge=True)
	return arm, dict(s=1.0, weapon=True, arm_swing=26, stabilize_left=True, base=pose(head=(4, 0, 0)),
		run_frames=15, duty=0.35), cc_anim.HUMANOID_ANIMS


# =================================================================================== zombie

def build_zombie():
	J, arm = rig(upper_arm=0.3, forearm=0.27, shoulder_x=0.21)
	b = Body(J)
	hz = J["head_z"]
	skin = mat("tint_skin", hexc("86a070"), rough=0.85)
	shirt = mat("rag_shirt", hexc("7a6a50"), rough=0.95)
	pants = mat("rag_pants", hexc("3f3c52"), rough=0.95)
	wound = mat("wound", hexc("5a1c1c"), rough=0.8)
	bone = mat("bone_dirty", hexc("d6cba8"), rough=0.8)
	eye = glow("eye_zombie", hexc("e8f060"), 4.0)
	dark = mat("void", hexc("141010"), rough=0.9)
	rope = mat("rope", hexc("8a7650"), rough=0.95)

	b.add("Head", head_loft(hz, 0.112, 0.12, 0.28, chin=0.72), skin, "head")
	b.add("Head", box((0.13, 0.08, 0.05), center=(0, -0.05, hz + 0.01), top=(1.1, 1.05)), skin, "head")
	b.add("Head", box((0.09, 0.02, 0.04), center=(0, -0.1, hz + 0.035)), dark, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.04, 0.016, 0.034), center=(sx * 0.045, -0.114, hz + 0.14)), dark, "head")
		b.add("Head", box((0.016, 0.01, 0.016), center=(sx * 0.045, -0.124, hz + 0.14)), eye, "head")
	b.add("Head", box((0.05, 0.03, 0.03), center=(0.05, 0.09, hz + 0.22)), wound, "head")
	b.add("Head", box((0.035, 0.04, 0.045), center=(0, -0.125, hz + 0.1), top=(0.5, 0.5)), skin, "head")
	b.add("Hair", hair_cap(hz, 0.119, 0.127, 0.28, front=0.265, back=0.07, side=0.17, top_extra=0.006, n=8), mat("hair_dead", hexc("4a4636")), "head")
	for k, (x, y) in enumerate([(-0.05, 0.02), (0.03, -0.03), (0.07, 0.05)]):
		b.add("Hair", cyl((x, y, hz + 0.26), (x * 1.6, y * 1.4 - 0.02, hz + 0.31), 0.01, 0.0, n=3), mat("hair_dead", hexc("4a4636")), "head")
	b.add("Head", cyl((0, 0.01, J["neck_z"] - 0.03), (0, 0.0, hz + 0.05), 0.055, 0.05, n=6), skin, "neck")

	b.add("Torso", loft([(0.84, 0.18, 0.13), (0.95, 0.172, 0.122), (1.08, 0.165, 0.115)], n=8), pants, "hips")
	b.add("Torso", loft([(0.97, 0.176, 0.126), (1.01, 0.174, 0.124)], n=8), rope, "hips")
	b.add("Torso", loft([(1.04, 0.16, 0.11), (1.16, 0.17, 0.115), (1.28, 0.185, 0.12)], n=8), skin, "spine")
	b.add("Torso", box((0.13, 0.02, 0.12), center=(0.02, -0.113, 1.17)), wound, "spine")
	for k in range(3):
		b.add("Torso", box((0.1, 0.018, 0.018), center=(0.02, -0.123, 1.13 + k * 0.035)), bone, "spine")
	b.add("Torso", loft([(1.24, 0.19, 0.124), (1.33, 0.212, 0.132), (1.41, 0.215, 0.128), (1.46, 0.16, 0.1)], n=8), shirt, "chest")
	b.add("Torso", box((0.2, 0.06, 0.14), center=(-0.08, 0.02, 1.2), top=(1.0, 1.0)), shirt, "spine")
	b.add("Torso", box((0.06, 0.02, 0.1), center=(0.1, -0.13, 1.2)), shirt, "spine")

	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		out = [(seg(sh, el, [(0, 0.062, 0.064), (0.5, 0.058, 0.06), (1, 0.047, 0.049)], n=6), "upper_arm_" + side, shirt if side == "l" else skin),
			(seg(el, wr, [(0, 0.045, 0.046), (1, 0.038, 0.04)], n=6), "lower_arm_" + side, skin)]
		if side == "r":
			out.append((sphere(0.07, 6, 3, center=tuple(sh + V(-0.01, 0, 0)), scale=(1.0, 1.0, 0.8)), "upper_arm_r", shirt))
			out.append((box((0.05, 0.03, 0.05), center=tuple(el + V(0, -0.03, -0.06))), "lower_arm_r", wound))
		return out
	b.both("Arms", arm_geo, skin)
	fists(b, J, "Hands", skin, size=(0.085, 0.07, 0.11), thumb=False, claws=(mat("nail_dark", hexc("2a2620")), 0.06))
	std_legs(b, J, "Legs", pants, r=(0.09, 0.064, 0.062, 0.046), ankle_ext=0.2)

	def leg_extra(side, sx):
		ank = J["ankle_" + side]
		if side == "l":
			return [(box((0.12, 0.02, 0.07), center=tuple(J["knee_l"] + V(0, -0.064, -0.06))), "lower_leg_l", wound),
				(seg(ank - V(0, 0, 0.02), ank + V(0, 0, 0.13), [(0, 0.052, 0.056), (1, 0.056, 0.06)], n=6), "lower_leg_l", mat("shoe_old", hexc("3a2c22")))]
		return [(seg(ank - V(0, 0, 0.02), ank + V(0, 0, 0.22), [(0, 0.042, 0.045), (1, 0.046, 0.048)], n=6), "lower_leg_r", skin),
			(box((0.13, 0.03, 0.06), center=tuple(ank + V(0, -0.01, 0.24))), "lower_leg_r", pants)]
	b.both("Legs", leg_extra, skin)

	def feet(side, sx):
		ank = J["ankle_" + side]
		return [(box((0.1, 0.22, 0.075), center=(ank.x, -0.04, 0.0375), top=(0.9, 0.75)), "foot_" + side,
			skin if side == "r" else mat("shoe_old", hexc("3a2c22")))]
	b.both("Feet", feet, skin)
	b.build(arm, merge=True)
	# Shuffling gait: short quick steps, always one foot on the floor, left foot dragged (limp).
	style = dict(s=1.0, weapon=False, lean=10, bounce=0.012, limp=0.8, run_arms="forward", action_base=0.6,
		run_frames=11, duty=0.52, lift=0.11, toe_off=26.0, crouch=-0.03,
		base=pose(spine=(14, 0, 0), chest=(6, 4, 0), neck=(8, 0, 0), head=(4, -14, 8)),
		loco=pose(upper_arm_r=(-72, 0, 6), upper_arm_l=(-64, 0, -2), lower_arm_s=(18, 0, 0), hand_s=(-15, 0, 0)))
	return arm, style, cc_anim.HUMANOID_ANIMS


# =================================================================================== ghoul

def build_ghoul():
	J, arm = rig(upper_arm=0.34, forearm=0.35, hand=0.12, shoulder_x=0.2, shoulder_z=1.37, arm_out=12,
		hip_z=0.92, leg_top=0.9, knee_z=0.5, knee_y=-0.04)
	b = Body(J)
	hz = J["head_z"]
	skin = mat("tint_skin", hexc("a397b8"), rough=0.8)
	dark = mat("ghoul_dark", hexc("2c2432"), rough=0.8)
	claw = mat("claw", hexc("1c1818"), rough=0.4)
	eye = glow("eye_ghoul", hexc("ff4a2a"), 6.0)
	mouth = mat("mouth_red", hexc("5a1418"), rough=0.7)
	tooth = mat("tooth", hexc("e8e0c8"), rough=0.5)
	rag = mat("rag_ghoul", hexc("4a4038"), rough=0.95)

	# Head: long skull, big jaw with teeth, pointed ears
	b.add("Head", loft([(hz + 0.02, 0.07, 0.1, 0, -0.03), (hz + 0.08, 0.1, 0.13, 0, -0.01), (hz + 0.15, 0.1, 0.13, 0, 0.01),
		(hz + 0.22, 0.075, 0.1, 0, 0.02), (hz + 0.25, 0.0, 0.0, 0, 0.02)], n=8), skin, "head")
	b.add("Head", box((0.13, 0.12, 0.05), center=(0, -0.09, hz + 0.02), top=(1.0, 1.0)), skin, "head")
	b.add("Head", box((0.11, 0.03, 0.03), center=(0, -0.145, hz + 0.045)), mouth, "head")
	for k in range(5):
		b.add("Head", box((0.012, 0.012, 0.03), center=(-0.04 + k * 0.02, -0.148, hz + 0.055)), tooth, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.036, 0.016, 0.022), center=(sx * 0.045, -0.125, hz + 0.13)), eye, "head")
		b.add("Head", cyl((sx * 0.09, 0.02, hz + 0.14), (sx * 0.19, 0.08, hz + 0.2), 0.03, 0.0, n=4), skin, "head")
	b.add("Head", cyl((0, 0.02, J["neck_z"] - 0.04), (0, -0.01, hz + 0.05), 0.045, 0.04, n=6), skin, "neck")

	# Torso: gaunt ribs, spine spikes, loin rag
	b.add("Torso", loft([(0.84, 0.15, 0.11), (0.95, 0.14, 0.1), (1.07, 0.125, 0.09)], n=8), skin, "hips")
	b.add("Torso", box((0.18, 0.03, 0.16), center=(0, -0.1, 0.83), top=(1.2, 1)), rag, "hips")
	b.add("Torso", box((0.2, 0.03, 0.14), center=(0, 0.1, 0.84), top=(1.2, 1)), rag, "hips")
	b.add("Torso", loft([(1.04, 0.12, 0.085), (1.16, 0.13, 0.09), (1.27, 0.16, 0.105)], n=8), skin, "spine")
	b.add("Torso", loft([(1.24, 0.165, 0.11), (1.32, 0.19, 0.12), (1.4, 0.19, 0.115), (1.45, 0.13, 0.09)], n=8), skin, "chest")
	for k in range(3):
		b.add("Torso", box((0.2, 0.012, 0.014), center=(0, -0.118, 1.27 + k * 0.045)), dark, "chest")
	for k, (z, bn) in enumerate([(1.12, "spine"), (1.26, "chest"), (1.36, "chest"), (1.44, "chest")]):
		b.add("Torso", cyl((0, 0.08 + k * 0.005, z), (0, 0.17 + k * 0.01, z + 0.07), 0.028, 0.0, n=4), tooth, bn)

	std_arms(b, J, "Arms", skin, r=(0.048, 0.04, 0.04, 0.032))
	fists(b, J, "Hands", skin, size=(0.1, 0.07, 0.12), thumb=False, claws=(claw, 0.13))
	std_legs(b, J, "Legs", skin, r=(0.075, 0.05, 0.05, 0.036), ankle_ext=0.02)

	def feet(side, sx):
		ank = J["ankle_" + side]
		out = [(box((0.1, 0.2, 0.06), center=(ank.x, -0.05, 0.03), top=(0.9, 0.7)), "foot_" + side, skin)]
		for k in (-1, 0, 1):
			p = V(ank.x + k * 0.03, -0.15, 0.02)
			out.append((cyl(p, p + V(0, -0.05, -0.015), 0.012, 0.0, n=4), "foot_" + side, claw))
		return out
	b.both("Feet", feet, skin)
	b.build(arm, merge=True)
	# Loping scramble (the ghoul is the fastest monster: 5.5 m/s = 1.06x playback).
	style = dict(s=1.0, weapon=False, lean=10, bounce=0.025, run_arms="claw", arm_swing=40, action_base=0.45,
		run_frames=15, duty=0.3, lift=0.24, crouch=0.0,
		base=pose(spine=(34, 0, 0), chest=(22, 0, 0), neck=(-18, 0, 0), head=(-24, 0, 0),
			upper_leg_s=(-30, 6, 0), lower_leg_s=(50, 0, 0), foot_s=(-20, -6, 0), **{"loc:hips": (0, 0.04, -0.13)}),
		loco=pose(upper_arm_s=(-25, 8, 0), lower_arm_s=(-10, 0, 0)), body_depth=1.0)
	return arm, style, cc_anim.HUMANOID_ANIMS


# =================================================================================== cultist

def front_panel(rings, frac=0.6, n=10):
	"""Curved sheet over the front of a body loft: rings (z, rx, ry, cy); frac = fraction of the half
	circumference covered on each side of the centre line. Double sided."""
	verts, faces, idx = [], [], []
	for (z, rx, ry, cy) in rings:
		row = []
		for k in range(n + 1):
			a = math.radians(-90.0 + (k / n * 2.0 - 1.0) * 90.0 * frac)
			row.append(len(verts))
			verts.append(V(rx * math.cos(a), cy + ry * math.sin(a), z))
		idx.append(row)
	for i in range(len(idx) - 1):
		a, c = idx[i], idx[i + 1]
		for k in range(n):
			faces.append([a[k], a[k + 1], c[k + 1], c[k]])
	nv = len(verts)
	verts = verts + [v.copy() for v in verts]
	faces = faces + [[i + nv for i in reversed(f)] for f in faces]
	return verts, faces


def robe_back(b, m, z_top, z_hem, y_top, y_hem, w_top, w_hem, part="Torso"):
	"""Slanted panel inside the back of a split robe skirt (fills the gap when the legs part)."""
	verts = [V(-w_hem / 2, y_hem, z_hem), V(w_hem / 2, y_hem, z_hem), V(w_top / 2, y_top, z_top), V(-w_top / 2, y_top, z_top)]
	faces = [[0, 1, 2, 3], [3, 2, 1, 0]]
	verts = verts + [v.copy() for v in verts]
	faces = [[0, 1, 2, 3], [7, 6, 5, 4]]
	b.add(part, (verts, faces), m, "hips")


def robe_skirt(b, J, m, z_top=1.02, z_hem=0.1, r_top=(0.17, 0.12), r_hem=(0.3, 0.26), part="Torso", n=5, trim=None, stole=None):
	"""Robe skirt as two halves skinned to the thighs (they swing with the legs) + a back panel."""
	for side, sx in (("r", -1.0), ("l", 1.0)):
		verts, faces = [], []
		rings = []
		for (z, rx, ry) in ((z_top, r_top[0], r_top[1]), ((z_top + z_hem) / 2, (r_top[0] + r_hem[0]) / 2 * 1.05, (r_top[1] + r_hem[1]) / 2 * 1.05), (z_hem, r_hem[0], r_hem[1])):
			ring = []
			for k in range(n + 1):
				a = math.radians(-90 + 180.0 * k / n)   # half circle on this side, from front (-Y) to back (+Y)
				x = sx * rx * math.cos(a) * 1.0
				y = ry * math.sin(a)
				ring.append(len(verts))
				verts.append(V(x, y, z))
			rings.append(ring)
		for i in range(len(rings) - 1):
			a, c = rings[i], rings[i + 1]
			for k in range(n):
				f = [a[k], a[k + 1], c[k + 1], c[k]]
				faces.append(f if sx > 0 else list(reversed(f)))
		# inner faces so the open halves have no holes when seen from inside
		inner = [list(reversed(f)) for f in faces]
		nv = len(verts)
		verts2 = verts + [v.copy() for v in verts]
		faces2 = faces + [[i + nv for i in f] for f in inner]
		b.add(part, (verts2, faces2), m, "upper_leg_" + side)
		if trim is not None:
			hem = []
			hv = []
			for k in range(n + 1):
				a = math.radians(-90 + 180.0 * k / n)
				for dz, sc in ((0.0, 1.015), (0.05, 1.012)):
					hv.append(V(sx * r_hem[0] * sc * math.cos(a), r_hem[1] * sc * math.sin(a), z_hem + dz))
			for k in range(n):
				f = [2 * k, 2 * k + 2, 2 * k + 3, 2 * k + 1]
				hem.append(f if sx > 0 else list(reversed(f)))
			b.add(part, (hv, hem), trim, "upper_leg_" + side)
		if stole is not None:
			# Strip down the front of this half (just outside the surface), 4-7 cm from the centre line.
			sv, sf = [], []
			for (z, rx, ry) in ((z_top, r_top[0], r_top[1]), (z_hem, r_hem[0], r_hem[1])):
				for u in (0.2, 0.42):
					a = math.radians(-90 + 90 * u * 0.55)
					sv.append(V(sx * rx * 1.012 * math.cos(a), ry * 1.012 * math.sin(a), z))
			f = [0, 1, 3, 2]
			sf.append(f if sx < 0 else list(reversed(f)))
			b.add(part, (sv, sf), stole, "upper_leg_" + side)


def build_cultist():
	J, arm = rig()
	b = Body(J)
	hz = J["head_z"]
	robe = mat("tint_robe", hexc("c4b8a8"), rough=0.9)
	trim = mat("robe_crimson", hexc("8e1f1f"), rough=0.85)
	void = mat("hood_void", hexc("0c0a0b"), rough=1.0)
	eye = glow("eye_cultist", hexc("ffa030"), 7.0)
	skin = mat("skin_pale", hexc("c9ad9a"), rough=0.8)
	rope = mat("rope", hexc("6a5438"), rough=0.95)
	gold = mat("gold", hexc("e8b04a"), rough=0.35, metal=0.5)

	# Hood: rounded cowl with a drooping tip, a dark face opening and glowing eyes
	b.add("Head", hair_cap(hz - 0.03, 0.142, 0.152, 0.29, front=0.04, back=-0.05, side=0.0, top_extra=0.01, n=10, cy=0.02), robe, "head")
	b.add("Head", tube([V(0, 0.1, hz + 0.24), V(0, 0.18, hz + 0.2), V(0, 0.23, hz + 0.1)], [0.06, 0.035, 0.0], n=5), robe, "head")
	b.add("Head", xf(slab([(-0.085, 0.02), (0.085, 0.02), (0.08, 0.17), (0.0, 0.24), (-0.08, 0.17)], 0.01, axis="y"), T(0, -0.14, hz)), void, "head")
	b.add("Head", xf(slab([(-0.093, 0.0), (0.093, 0.0), (0.09, 0.18), (0.0, 0.262), (-0.09, 0.18), (-0.078, 0.172), (0.0, 0.245), (0.078, 0.172), (0.082, 0.02), (-0.082, 0.02), (-0.078, 0.172), (-0.09, 0.18)], 0.01, axis="y"), T(0, -0.143, hz)), trim, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.03, 0.01, 0.014), center=(sx * 0.038, -0.148, hz + 0.13)), eye, "head")
	b.add("Head", loft([(J["neck_z"] - 0.06, 0.2, 0.15, 0, 0.01), (J["neck_z"] + 0.05, 0.13, 0.13, 0, 0.02)], n=8), robe, "chest")
	b.add("Head", cyl((0, 0.01, J["neck_z"] - 0.03), (0, 0.0, hz + 0.05), 0.05, 0.045, n=6), void, "neck")

	# Robe body
	b.add("Torso", loft([(0.95, 0.17, 0.12), (1.08, 0.165, 0.115)], n=8), robe, "hips")
	b.add("Torso", loft([(1.04, 0.16, 0.11), (1.16, 0.168, 0.114), (1.27, 0.185, 0.122)], n=8), robe, "spine")
	b.add("Torso", loft([(1.24, 0.18, 0.12), (1.32, 0.205, 0.13), (1.39, 0.215, 0.126), (1.445, 0.17, 0.1), (1.47, 0.1, 0.075)], n=8), robe, "chest")
	b.add("Torso", loft([(0.98, 0.178, 0.126), (1.03, 0.175, 0.124)], n=8), rope, "hips")
	robe_skirt(b, J, robe, z_top=1.02, z_hem=0.1, r_top=(0.178, 0.126), r_hem=(0.27, 0.24), trim=trim, stole=trim)
	robe_back(b, robe, z_top=1.0, z_hem=0.12, y_top=0.08, y_hem=0.07, w_top=0.2, w_hem=0.28)
	# Crimson stole down the front + amulet
	for sx in (-1, 1):
		b.add("Torso", box((0.05, 0.02, 0.24), center=(sx * 0.07, -0.128, 1.32)), trim, "chest")
		b.add("Torso", box((0.05, 0.02, 0.2), center=(sx * 0.07, -0.122, 1.14)), trim, "spine")
	b.add("Torso", octa(0.035, center=(0, -0.135, 1.26), scale=(1, 0.5, 1.2)), gold, "chest")

	# Wide sleeves
	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		return [(seg(sh, el, [(0, 0.065, 0.067), (1, 0.06, 0.062)], n=6), "upper_arm_" + side, robe),
			(seg(el - d * 0.03, wr + d * 0.02, [(0, 0.058, 0.06), (0.6, 0.075, 0.078), (1, 0.09, 0.094)], n=6, cap1=False), "lower_arm_" + side, robe),
			(seg(wr + d * 0.015, wr + d * 0.025, [(0, 0.091, 0.095), (1, 0.094, 0.098)], n=6), "lower_arm_" + side, trim),
			(sphere(0.08, 8, 3, center=tuple(sh + V(sx * 0.01, 0, 0.01)), scale=(1.1, 1.05, 0.8), cut=(-0.2, 1.0)), "upper_arm_" + side, robe)]
	b.both("Arms", arm_geo, robe)
	fists(b, J, "Hands", skin, size=(0.08, 0.075, 0.1))
	std_legs(b, J, "Legs", void, r=(0.075, 0.055, 0.055, 0.045))
	std_boots(b, J, "Feet", mat("boot_dark", hexc("2e2420")), w=0.1, l=0.23, h=0.085, shaft=0.1, r=0.058)
	b.build(arm, merge=True)
	# Hurried shuffle in a robe: quick short steps, feet stay low.
	style = dict(s=1.0, weapon=False, robe=True, lean=8, run_frames=12, duty=0.46, lift=0.12,
		toe_off=26.0, bounce=0.015,
		base=pose(spine=(4, 0, 0), neck=(4, 0, 0), head=(6, 0, 0)),
		loco=pose(upper_arm_s=(-16, -4, 14), lower_arm_s=(-38, 0, 0)))
	return arm, style, cc_anim.HUMANOID_ANIMS


# =================================================================================== brute

def build_brute():
	s = 1.34
	J, arm = rig(s, shoulder_x=0.27, shoulder_z=1.38, upper_arm=0.3, forearm=0.28, hand=0.12, arm_out=14, elbow=35,
		hip_x=0.13, hip_z=0.9, leg_top=0.87, knee_z=0.48, head_z=1.5, head_top=1.72, neck_z=1.42, chest_z=1.2, spine_z=1.04)
	b = Body(J, s)
	hz = J["head_z"]
	skin = mat("tint_skin", hexc("a0624a"), rough=0.8)
	leather = mat("leather_brute", hexc("3a2a22"), rough=0.9)
	iron = mat("iron_brute", hexc("5f6068"), rough=0.5, metal=0.35)
	fur = mat("fur", hexc("a08c70"), rough=1.0)
	eye = glow("eye_brute", hexc("ff5a2a"), 4.0)
	tusk = mat("tusk", hexc("efe6cc"), rough=0.5)
	dark = mat("void", hexc("141010"), rough=0.9)

	b.add("Head", head_loft(hz - 0.01, 0.1, 0.11, 0.23, chin=0.95, jaw=1.05), skin, "head")
	b.add("Head", box((0.19, 0.06, 0.035), center=(0, -0.1, hz + 0.14), top=(0.9, 1.0)), skin, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.03, 0.012, 0.016), center=(sx * 0.042, -0.11, hz + 0.115)), eye, "head")
		b.add("Head", cyl((sx * 0.05, -0.1, hz + 0.03), (sx * 0.06, -0.125, hz + 0.1), 0.014, 0.0, n=4), tusk, "head")
	b.add("Head", box((0.08, 0.012, 0.02), center=(0, -0.113, hz + 0.045)), dark, "head")
	b.add("Head", box((0.04, 0.05, 0.04), center=(0, -0.125, hz + 0.085), top=(0.6, 0.5)), skin, "head")
	b.add("Head", cyl((0, 0.02, J["neck_z"] - 0.04), (0, 0.0, hz + 0.05), 0.085, 0.075, n=6), skin, "neck")

	b.add("Torso", loft([(0.8, 0.22, 0.17), (0.9, 0.23, 0.18), (1.06, 0.24, 0.2)], n=8), leather, "hips")
	b.add("Torso", box((0.2, 0.04, 0.26), center=(0, -0.2, 0.74), top=(1.2, 1)), leather, "hips")
	b.add("Torso", loft([(0.95, 0.245, 0.205), (1.02, 0.245, 0.205)], n=8), mat("belt_black", hexc("2a201a")), "hips")
	b.add("Torso", box((0.12, 0.03, 0.1), center=(0, -0.215, 0.985)), iron, "hips")
	b.add("Torso", loft([(1.0, 0.23, 0.2, 0, -0.01), (1.1, 0.25, 0.22, 0, -0.02), (1.22, 0.26, 0.2, 0, -0.01)], n=8), skin, "spine")
	b.add("Torso", loft([(1.18, 0.26, 0.19), (1.28, 0.3, 0.19), (1.37, 0.31, 0.17), (1.44, 0.24, 0.13), (1.47, 0.12, 0.1)], n=8), skin, "chest")
	for sx in (-1, 1):
		b.add("Torso", box((0.17, 0.03, 0.1), center=(sx * 0.1, -0.18, 1.31), top=(0.9, 1)), skin, "chest")
	# Fur mantle across the shoulders
	b.add("Torso", loft([(1.36, 0.32, 0.2, 0, 0.02), (1.45, 0.28, 0.18, 0, 0.03), (1.5, 0.16, 0.12, 0, 0.03)], n=8), fur, "chest")

	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		out = [(seg(sh, el, [(0, 0.1, 0.1), (0.5, 0.095, 0.095), (1, 0.075, 0.075)], n=6), "upper_arm_" + side, skin),
			(seg(el - d * 0.03, wr, [(0, 0.075, 0.075), (0.45, 0.085, 0.085), (1, 0.065, 0.065)], n=6), "lower_arm_" + side, skin),
			(seg(wr - d * 0.1, wr + d * 0.01, [(0, 0.075, 0.075), (1, 0.08, 0.08)], n=6), "lower_arm_" + side, leather)]
		if side == "l":
			out.append((sphere(0.13, 8, 4, center=tuple(sh + V(0.02, 0, 0.02)), scale=(1.1, 1.0, 0.8), cut=(-0.25, 1.0)), "upper_arm_l", iron))
			for k in range(3):
				a = math.radians(-30 + k * 30)
				base = sh + V(0.06 + 0.04 * math.cos(a), 0.06 * math.sin(a), 0.08)
				out.append((cyl(base, base + V(0.04, 0.02 * math.sin(a), 0.1), 0.025, 0.0, n=4), "upper_arm_l", tusk))
		return out
	b.both("Arms", arm_geo, skin)
	fists(b, J, "Hands", skin, size=(0.14, 0.12, 0.14))
	std_legs(b, J, "Legs", leather, skin, r=(0.12, 0.095, 0.09, 0.07))
	std_boots(b, J, "Feet", skin, w=0.15, l=0.27, h=0.09, shaft=0.12, r=0.075, cuff=mat("wraps", hexc("8a7a60")))
	b.build(arm, merge=True)
	# Heavy stomping jog: always one foot planted.
	style = dict(s=s, weapon=False, lean=10, bounce=0.02, arm_swing=26, heavy=1.0, run_frames=12, duty=0.5, lift=0.14,
		base=pose(spine=(10, 0, 0), neck=(-6, 0, 0), head=(-6, 0, 0), upper_arm_s=(0, 10, 0), upper_leg_s=(-6, 6, 0),
			lower_leg_s=(10, 0, 0), foot_s=(-4, -6, 0)), body_depth=1.5)
	return arm, style, cc_anim.HUMANOID_ANIMS


# =================================================================================== lich (boss)

def build_lich():
	s = 1.62
	J, arm = rig(s, shoulder_x=0.21, upper_arm=0.3, forearm=0.28, hand=0.11)
	b = Body(J, s)
	hz = J["head_z"]
	robe = mat("tint_robe", hexc("4b2c6e"), rough=0.85)
	robe2 = mat("robe_dark", hexc("24163a"), rough=0.9)
	trim = mat("gold_lich", hexc("e0b048"), rough=0.35, metal=0.5)
	bone = mat("bone_lich", hexc("ddd5bd"), rough=0.7)
	void = mat("void", hexc("100c12"), rough=1.0)
	eye = glow("eye_lich", hexc("6affd4"), 7.0)
	rune = glow("rune_lich", hexc("46d8b4"), 2.0)
	gem = glow("gem_lich", hexc("ff3a6a"), 6.0)
	wood = mat("staff_lich", hexc("3a2a22"), rough=0.8)
	orb = glow("orb_lich", hexc("7affe0"), 7.0)

	# Skull + crown
	b.add("Head", loft([(hz + 0.06, 0.08, 0.095, 0, -0.005), (hz + 0.12, 0.105, 0.118, 0, 0.005), (hz + 0.2, 0.104, 0.116, 0, 0.01),
		(hz + 0.25, 0.075, 0.085, 0, 0.012), (hz + 0.275, 0, 0, 0, 0.012)], n=8), bone, "head")
	b.add("Head", box((0.12, 0.1, 0.06), center=(0, -0.045, hz + 0.045), top=(1.05, 1.0)), bone, "head")
	b.add("Head", box((0.09, 0.012, 0.025), center=(0, -0.096, hz + 0.05)), void, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.045, 0.02, 0.045), center=(sx * 0.045, -0.108, hz + 0.135)), void, "head")
		b.add("Head", box((0.022, 0.012, 0.02), center=(sx * 0.045, -0.12, hz + 0.135)), eye, "head")
	crown = loft([(hz + 0.17, 0.118, 0.128, 0, 0.01), (hz + 0.215, 0.12, 0.13, 0, 0.01)], n=10, cap0=False, cap1=False)
	cv, cf = crown
	b.add("Details", (cv + [v.copy() for v in cv], cf + [[i + len(cv) for i in reversed(f)] for f in cf]), trim, "head")
	for k in range(10):
		a = 2 * math.pi * k / 10 + math.pi / 10
		x, y = math.cos(a) * 0.12, math.sin(a) * 0.13 + 0.01
		h = 0.13 if k in (7, 8) else (0.09 if k % 2 == 0 else 0.06)
		b.add("Details", cyl((x, y, hz + 0.21), (x * 1.08, y * 1.08, hz + 0.21 + h), 0.022, 0.0, n=4), trim, "head")
	b.add("Details", octa(0.028, center=(0, -0.138, hz + 0.2), scale=(1, 0.6, 1.3)), gem, "head")
	b.add("Head", cyl((0, 0.01, J["neck_z"] - 0.03), (0, 0.0, hz + 0.06), 0.035, 0.03, n=5), bone, "neck")

	# Robes: upper body, high spiked mantle, long skirt, runes
	b.add("Torso", loft([(0.92, 0.18, 0.13), (1.08, 0.165, 0.115)], n=8), robe, "hips")
	b.add("Torso", loft([(1.04, 0.15, 0.1), (1.16, 0.16, 0.106), (1.27, 0.18, 0.116)], n=8), robe, "spine")
	b.add("Torso", loft([(1.24, 0.18, 0.118), (1.33, 0.2, 0.126), (1.4, 0.2, 0.12), (1.46, 0.14, 0.09)], n=8), robe, "chest")
	b.add("Torso", loft([(1.36, 0.28, 0.2, 0, 0.02), (1.44, 0.26, 0.19, 0, 0.03), (1.5, 0.15, 0.13, 0, 0.04), (1.62, 0.16, 0.12, 0, 0.07)],
		n=8, cap1=False), robe2, "chest")
	for k in range(5):
		a = math.radians(200 + k * 35)
		base = V(math.cos(a) * 0.22, math.sin(a) * 0.16 + 0.03, 1.44)
		b.add("Torso", cyl(base, base + V(math.cos(a) * 0.1, math.sin(a) * 0.08 + 0.02, 0.16), 0.03, 0.0, n=4), bone, "chest")
	robe_skirt(b, J, robe, z_top=1.0, z_hem=0.0, r_top=(0.19, 0.14), r_hem=(0.34, 0.3), n=6, trim=trim, stole=rune)
	robe_back(b, robe2, z_top=0.98, z_hem=0.03, y_top=0.08, y_hem=0.06, w_top=0.22, w_hem=0.32)
	b.add("Torso", loft([(0.97, 0.188, 0.134), (1.02, 0.186, 0.132)], n=8), trim, "hips")
	for k in range(3):
		b.add("Torso", box((0.05, 0.02, 0.05), center=(0, -0.13, 1.1 + k * 0.1)), rune, "spine" if k < 2 else "chest")

	# Sleeves + bony clawed hands
	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		return [(seg(sh, el, [(0, 0.06, 0.062), (1, 0.055, 0.057)], n=6), "upper_arm_" + side, robe),
			(seg(el - d * 0.03, wr, [(0, 0.055, 0.057), (0.7, 0.08, 0.082), (1, 0.1, 0.1)], n=6, cap1=False), "lower_arm_" + side, robe),
			(seg(wr, wr + d * 0.012, [(0, 0.1, 0.1), (1, 0.102, 0.102)], n=6), "lower_arm_" + side, trim)]
	b.both("Arms", arm_geo, robe)
	fists(b, J, "Hands", bone, size=(0.075, 0.06, 0.1), claws=(void, 0.09))
	# Built-in staff in the left hand (skinned to hand_l): gnarled shaft + orb in a claw.
	gl = J["bones"]["grip_l"][0]
	base = gl + V(0, 0, -0.75)
	pts = [base, gl + V(0.0, -0.01, -0.2), gl + V(0.01, 0.0, 0.35), gl + V(-0.01, 0.01, 0.8), gl + V(0.0, 0.0, 1.0)]
	b.add("Weapon", tube(pts, [0.02, 0.024, 0.024, 0.026, 0.03], n=6), wood, "hand_l")
	top = gl + V(0, 0, 1.08)
	b.add("Weapon", icosphere(0.075, center=tuple(top)), orb, "hand_l")
	for k in range(4):
		a = 2 * math.pi * k / 4
		d = V(math.cos(a), math.sin(a), 0)
		b.add("Weapon", tube([gl + V(0, 0, 0.98) + d * 0.02, top + d * 0.09 + V(0, 0, -0.02), top + d * 0.05 + V(0, 0, 0.09)],
			[0.014, 0.012, 0.0], n=4), bone, "hand_l")
	b.build(arm, merge=True)
	style = dict(s=s, weapon=False, hover=0.28, run_arms="still", lean=16, robe=True,
		base=pose(neck=(4, 0, 0), head=(4, 0, 0)), loco=pose(upper_arm_r=(-6, 12, 0), lower_arm_r=(-25, 0, 0)),
		hold_left=pose(upper_arm_l=(-12, -10, 0), lower_arm_l=(-8, 0, 0)),
		# corpse: the staff lies flat on the floor beside the body (found with a pose search)
		die_pose=pose(upper_arm_l=(40, -45, 0), lower_arm_l=(0, 0, 0), hand_l=(-30, 55, -15)))
	return arm, style, cc_anim.BOSS_ANIMS


# =================================================================================== gravebreaker (boss)

def build_gravebreaker():
	s = 1.55
	J, arm = rig(s, shoulder_x=0.25, shoulder_z=1.38, upper_arm=0.29, forearm=0.27, hand=0.12, arm_out=14, elbow=40,
		hip_x=0.12, grip_up=45)
	b = Body(J, s)
	hz = J["head_z"]
	plate = mat("tint_armor", hexc("5d616c"), rough=0.45, metal=0.4)
	plate_dark = mat("armor_dark", hexc("33353c"), rough=0.5, metal=0.35)
	horn = mat("horn", hexc("d9ccae"), rough=0.6)
	glow_o = glow("ember", hexc("ff7a22"), 7.0)
	leather = mat("leather_gb", hexc("3a2a20"), rough=0.9)
	stone = mat("gravestone", hexc("8c8a86"), rough=0.95)
	skin = mat("skin_dead", hexc("6c727c"), rough=0.8)
	void = mat("void", hexc("100c0c"), rough=1.0)

	# Horned helm with glowing slit
	b.add("Head", loft([(hz + 0.0, 0.12, 0.13, 0, 0.0), (hz + 0.1, 0.13, 0.14, 0, 0.0), (hz + 0.2, 0.125, 0.135, 0, 0.005),
		(hz + 0.27, 0.085, 0.095, 0, 0.01), (hz + 0.3, 0.0, 0.0, 0, 0.01)], n=8), plate, "head")
	b.add("Head", box((0.18, 0.02, 0.03), center=(0, -0.137, hz + 0.14)), void, "head")
	for sx in (-1, 1):
		b.add("Head", box((0.05, 0.012, 0.018), center=(sx * 0.045, -0.145, hz + 0.14)), glow_o, "head")
		pts = [V(sx * 0.11, -0.01, hz + 0.2), V(sx * 0.22, 0.0, hz + 0.26), V(sx * 0.3, -0.04, hz + 0.37), V(sx * 0.3, -0.1, hz + 0.47)]
		b.add("Head", tube(pts, [0.05, 0.04, 0.026, 0.0], n=6), horn, "head")
	b.add("Head", box((0.03, 0.2, 0.08), center=(0, 0.0, hz + 0.29)), plate_dark, "head")
	b.add("Head", cyl((0, 0.0, J["neck_z"] - 0.03), (0, 0.0, hz + 0.05), 0.08, 0.075, n=6), plate_dark, "neck")

	# Plated body
	b.add("Torso", loft([(0.82, 0.21, 0.15), (0.95, 0.2, 0.145), (1.08, 0.2, 0.14)], n=8), leather, "hips")
	for sx in (-1, 1):
		b.add("Torso", box((0.17, 0.035, 0.22), center=(sx * 0.1, -0.15, 0.78), top=(1.1, 1.0)), plate, "upper_leg_" + ("r" if sx < 0 else "l"))
	b.add("Torso", box((0.36, 0.035, 0.2), center=(0, 0.16, 0.8), top=(1.1, 1.0)), plate, "hips")
	b.add("Torso", loft([(0.95, 0.21, 0.152), (1.03, 0.21, 0.152)], n=8), plate_dark, "hips")
	b.add("Torso", box((0.1, 0.03, 0.09), center=(0, -0.16, 0.99)), glow_o, "hips")
	b.add("Torso", loft([(1.02, 0.2, 0.14), (1.15, 0.21, 0.145), (1.27, 0.24, 0.155)], n=8), plate_dark, "spine")
	b.add("Torso", loft([(1.22, 0.24, 0.155), (1.3, 0.28, 0.17), (1.38, 0.29, 0.165), (1.45, 0.22, 0.13), (1.48, 0.12, 0.09)], n=8), plate, "chest")
	b.add("Torso", box((0.3, 0.04, 0.2), center=(0, -0.165, 1.33), top=(0.85, 1.0)), plate, "chest")
	b.add("Torso", xf(slab([(-0.02, 0.0), (0.03, 0.07), (0.0, 0.12), (0.04, 0.19), (0.0, 0.19), (-0.03, 0.11), (0.0, 0.07)], 0.012, axis="y"), T(0, -0.187, 1.24)), glow_o, "chest")

	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		out = [(seg(sh, el, [(0, 0.085, 0.085), (1, 0.07, 0.07)], n=6), "upper_arm_" + side, skin),
			(seg(el - d * 0.04, wr, [(0, 0.075, 0.075), (0.5, 0.085, 0.085), (1, 0.08, 0.08)], n=6), "lower_arm_" + side, plate),
			(sphere(0.14, 8, 4, center=tuple(sh + V(sx * 0.03, 0, 0.03)), scale=(1.15, 1.1, 0.85), cut=(-0.3, 1.0)), "upper_arm_" + side, plate),
			(cyl(sh + V(sx * 0.07, 0, 0.13), sh + V(sx * 0.13, 0.0, 0.27), 0.035, 0.0, n=4), "upper_arm_" + side, horn),
			(octa(0.05, center=tuple(el + V(0, 0.03, 0))), "lower_arm_" + side, plate_dark)]
		return out
	b.both("Arms", arm_geo, plate)
	fists(b, J, "Hands", plate_dark, size=(0.13, 0.12, 0.14))
	std_legs(b, J, "Legs", leather, plate, r=(0.11, 0.085, 0.085, 0.068))

	def knee(side, sx):
		k = J["knee_" + side]
		return [(box((0.13, 0.05, 0.13), center=tuple(k + V(0, -0.08, 0)), top=(0.8, 1.0)), "lower_leg_" + side, plate_dark)]
	b.both("Legs", knee, plate)
	std_boots(b, J, "Feet", plate_dark, w=0.15, l=0.28, h=0.11, shaft=0.18, r=0.085)

	# Built-in gravestone maul (skinned to hand_r): long haft + tombstone head with a glowing rune.
	g, tail, _ = J["bones"]["grip_r"]
	d = (tail - g).normalized()
	side_v = V(1, 0, 0) - d * d.x
	side_v.normalize()
	M = _frame_axes(g, side_v, d)
	b.add("Weapon", cyl((0, 0, -0.45), (0, 0, 1.0), 0.03, 0.028, n=6), leather, "hand_r", M)
	tomb = [(-0.2, 0.9), (0.2, 0.9), (0.2, 1.28), (0.17, 1.37), (0.1, 1.42), (0.0, 1.44), (-0.1, 1.42), (-0.17, 1.37), (-0.2, 1.28)]
	b.add("Weapon", slab(tomb, 0.15, axis="x"), stone, "hand_r", M)
	b.add("Weapon", slab([(-0.22, 0.86), (0.22, 0.86), (0.22, 0.92), (-0.22, 0.92)], 0.17, axis="x"), plate_dark, "hand_r", M)
	cross = [(-0.02, 1.02), (0.02, 1.02), (0.02, 1.2), (0.07, 1.2), (0.07, 1.24), (0.02, 1.24), (0.02, 1.3), (-0.02, 1.3),
		(-0.02, 1.24), (-0.07, 1.24), (-0.07, 1.2), (-0.02, 1.2)]
	for sx in (-1, 1):
		b.add("Weapon", slab(cross, 0.012, axis="x"), glow_o, "hand_r", M @ T(sx * 0.077, 0, 0))
	b.add("Weapon", cyl((0, 0, 0.8), (0, 0, 0.87), 0.045, n=6), plate_dark, "hand_r", M)
	b.build(arm, merge=True)
	# Heavy stride with a short flight; slam_floor: the tombstone rests on the floor at the slam's hit frame.
	style = dict(s=s, weapon=True, bounce=0.02, arm_swing=22, heavy=1.0, lean=10, slam_hand=58.0, slam_floor=True, slam_wind_hand=50.0,
		run_frames=16, duty=0.45, lift=0.14,
		carry=pose(upper_arm_r=(-30, 12, 0), lower_arm_r=(-92, 0, 0), hand_r=(20, 0, 0)),
		base=pose(spine=(6, 0, 0), upper_arm_s=(0, 8, 0), upper_leg_s=(-6, 7, 0), lower_leg_s=(10, 0, 0), foot_s=(-4, -7, 0)),
		body_depth=1.4,
		# corpse: the maul lies flat beside the body
		die_pose=pose(upper_arm_r=(50, 45, 0), lower_arm_r=(0, 0, 0), hand_r=(-15, -45, -70)))
	return arm, style, cc_anim.BOSS_ANIMS


# =================================================================================== merchant (NPC)

def build_merchant():
	J, arm = rig(shoulder_x=0.2, head_top=1.79)
	b = Body(J)
	hz = J["head_z"]
	skin = mat("skin", hexc("e0a784"), rough=0.8)
	beard = mat("beard", hexc("c8bdb0"), rough=0.95)
	shirt = mat("shirt_green", hexc("4f7a4a"), rough=0.9)
	apron = mat("tint_apron", hexc("9a7650"), rough=0.85)
	pants = mat("pants_brown", hexc("5a4632"), rough=0.9)
	boots = mat("boots_brown", hexc("4a3020"), rough=0.8)
	hat = mat("hat_red", hexc("8a3a2a"), rough=0.9)
	feather = mat("feather", hexc("e8d890"), rough=0.9)
	eye = mat("eye_dark", hexc("1a1412"), rough=0.5)
	belt = mat("leather_dark", hexc("3b2616"), rough=0.8)
	gold = mat("gold", hexc("e8b04a"), rough=0.35, metal=0.5)

	b.add("Head", head_loft(hz, 0.112, 0.12, 0.27, chin=0.75), skin, "head")
	b.add("Head", box((0.05, 0.05, 0.055), center=(0, -0.125, hz + 0.105), top=(0.7, 0.6)), mat("skin_nose", hexc("d88a70")), "head")
	eyes(b, "Head", hz, eye, y=-0.12, z=0.14, x=0.043, size=(0.022, 0.012, 0.024))
	for sx in (-1, 1):
		b.add("Head", box((0.022, 0.045, 0.055), center=(sx * 0.114, 0.01, hz + 0.12)), skin, "head")
		b.add("Head", box((0.045, 0.016, 0.014), center=(sx * 0.045, -0.123, hz + 0.168)), beard, "head")
	b.add("Head", loft([(hz - 0.04, 0.05, 0.04, 0, -0.1), (hz + 0.02, 0.1, 0.07, 0, -0.08), (hz + 0.085, 0.105, 0.06, 0, -0.07)], n=6), beard, "head")
	b.add("Head", box((0.1, 0.03, 0.025), center=(0, -0.125, hz + 0.08)), beard, "head")
	b.add("Head", cyl((0, 0.005, J["neck_z"] - 0.03), (0, 0.005, hz + 0.05), 0.058, 0.052, n=6), skin, "neck")
	# Hat: wide brim + crown + feather
	b.add("Hair", lathe([(0.0, 0.2), (0.19, 0.2), (0.19, 0.215), (0.0, 0.215)], n=10), hat, "head", T(0, 0.01, hz + 0.0) @ S(1.0, 1.05, 1.0))
	b.add("Hair", lathe([(0.12, 0.2), (0.115, 0.29), (0.09, 0.32), (0.0, 0.325)], n=8), hat, "head", T(0, 0.01, hz))
	b.add("Hair", loft([(hz + 0.23, 0.121, 0.121, 0, 0.01), (hz + 0.25, 0.12, 0.12, 0, 0.01)], n=8), belt, "head")
	b.add("Hair", tube([V(0.1, 0.03, hz + 0.25), V(0.15, 0.07, hz + 0.35), V(0.14, 0.14, hz + 0.43)], [0.022, 0.018, 0.0], n=4), feather, "head")

	# Portly torso, apron, belt
	b.add("Torso", loft([(0.84, 0.19, 0.14), (0.95, 0.2, 0.16, 0, -0.02), (1.08, 0.21, 0.17, 0, -0.03)], n=8), pants, "hips")
	b.add("Torso", loft([(1.04, 0.21, 0.17, 0, -0.03), (1.14, 0.225, 0.19, 0, -0.045), (1.25, 0.21, 0.16, 0, -0.03)], n=8), shirt, "spine")
	b.add("Torso", loft([(1.22, 0.2, 0.14, 0, -0.015), (1.32, 0.215, 0.135), (1.4, 0.215, 0.125), (1.45, 0.17, 0.1), (1.47, 0.1, 0.075)], n=8), shirt, "chest")
	b.add("Torso", loft([(0.98, 0.212, 0.175, 0, -0.025), (1.03, 0.214, 0.178, 0, -0.028)], n=8), belt, "hips")
	b.add("Torso", box((0.06, 0.02, 0.05), center=(0, -0.205, 1.005)), gold, "hips")
	b.add("Torso", front_panel([(1.04, 0.222, 0.182, -0.03), (1.14, 0.236, 0.2, -0.045), (1.25, 0.222, 0.172, -0.03)], 0.62), apron, "spine")
	b.add("Torso", front_panel([(1.25, 0.21, 0.15, -0.015), (1.36, 0.225, 0.142, 0.0)], 0.5), apron, "chest")
	b.add("Torso", front_panel([(0.62, 0.23, 0.17, -0.035), (0.84, 0.21, 0.16, -0.03), (0.97, 0.214, 0.18, -0.03), (1.05, 0.222, 0.184, -0.032)], 0.62), apron, "hips")
	b.add("Torso", box((0.1, 0.02, 0.07), center=(0.08, -0.22, 0.85)), mat("pocket", hexc("7a5a38")), "hips")
	b.add("Torso", box((0.07, 0.06, 0.08), center=(-0.19, -0.03, 0.93), top=(0.9, 0.9)), belt, "hips")

	def arm_geo(side, sx):
		sh, el, wr = J["shoulder_" + side], J["elbow_" + side], J["wrist_" + side]
		d = (wr - el).normalized()
		return [(seg(sh, el, [(0, 0.064, 0.066), (1, 0.056, 0.058)], n=6), "upper_arm_" + side, shirt),
			(seg(el - d * 0.02, el + d * 0.05, [(0, 0.058, 0.06), (1, 0.06, 0.062)], n=6), "lower_arm_" + side, shirt),
			(seg(el + d * 0.04, wr, [(0, 0.047, 0.048), (1, 0.041, 0.042)], n=6), "lower_arm_" + side, skin),
			(sphere(0.075, 8, 3, center=tuple(sh + V(sx * 0.01, 0, 0.0)), scale=(1.05, 1.05, 0.85), cut=(-0.2, 1.0)), "upper_arm_" + side, shirt)]
	b.both("Arms", arm_geo, shirt)
	fists(b, J, "Hands", skin, size=(0.085, 0.08, 0.1))
	std_legs(b, J, "Legs", pants, r=(0.095, 0.068, 0.066, 0.05))
	std_boots(b, J, "Feet", boots, w=0.11, l=0.24, h=0.09, shaft=0.16, r=0.064)
	b.build(arm, merge=True)
	style = dict(s=1.0, weapon=False,
		base=pose(spine=(-4, 0, 0), head=(3, 0, 0)),
		loco=pose(upper_arm_s=(-10, -4, 22), lower_arm_s=(-36, 0, 0), hand_s=(-10, 0, 0)))
	return arm, style, cc_anim.MERCHANT_ANIMS


CHARACTERS = {
	"char_skeleton": build_skeleton,
	"char_zombie": build_zombie,
	"char_ghoul": build_ghoul,
	"char_cultist": build_cultist,
	"char_brute": build_brute,
	"char_lich": build_lich,
	"char_gravebreaker": build_gravebreaker,
	"char_merchant": build_merchant,
}
