"""Ground contact, leg IK and measurements for the character build (docs/ARCHITECTURE.md §14.3).

Everything here works on the rest mesh + analytic forward kinematics (cc_rig.fk / fk_basis), so it
is exact and independent of the depsgraph:

  Skin          rest vertices of every mesh part, grouped by (part, bone) (100% rigid skinning)
  RigInfo       leg joints / foot profile of one character, planar two-bone leg IK
  bake_ground   per-frame vertical root correction so the lowest foot vertex is at z = 0
  run_speed     planted-foot speed of a run action, measured like the review did (ankle within 2 cm
                of its lowest point, mean backward speed) and at the contact vertex
Conventions: Blender armature space, character faces -Y, so "backward" is +Y.
"""
import math

from mathutils import Matrix, Quaternion, Vector

import cc_rig

REF_RUN_SPEED = 5.2          # m/s: every walking character's run has this planted-foot speed
FEET = ("foot_l", "foot_r")
CORE = ("hips", "spine", "chest", "neck", "head")


class Skin:
	"""Rest vertices per (mesh part, bone), for rigid 100% skinned characters."""

	def __init__(self, arm):
		self.arm = arm
		self.groups = {}   # (part, bone) -> [(x, y, z), ...]
		for ob in arm.children:
			if ob.type != "MESH":
				continue
			names = {vg.index: vg.name for vg in ob.vertex_groups}
			for v in ob.data.vertices:
				if not v.groups:
					continue
				g = max(v.groups, key=lambda e: e.weight)
				key = (ob.name, names[g.group])
				self.groups.setdefault(key, []).append((v.co.x, v.co.y, v.co.z))
		self.parts = sorted({k[0] for k in self.groups})

	def select(self, bones=None, parts=None, exclude_parts=()):
		for (part, bone), vs in self.groups.items():
			if bones is not None and bone not in bones:
				continue
			if parts is not None and part not in parts:
				continue
			if part in exclude_parts:
				continue
			yield bone, vs

	def lowest(self, G, bones=None, parts=None, exclude_parts=()):
		"""Lowest posed z of the selected vertices (inf when none)."""
		m = math.inf
		for bone, vs in self.select(bones, parts, exclude_parts):
			M = G[bone]
			a, b, c, d = M[2][0], M[2][1], M[2][2], M[2][3]
			for x, y, z in vs:
				h = a * x + b * y + c * z + d
				if h < m:
					m = h
		return m

	def posed(self, G, bones=None, parts=None, exclude_parts=()):
		out = []
		for bone, vs in self.select(bones, parts, exclude_parts):
			M = G[bone]
			for v in vs:
				out.append(M @ Vector(v))
		return out

	def rest(self, bones=None, parts=None):
		return [Vector(v) for _b, vs in self.select(bones, parts) for v in vs]


# ----------------------------------------------------------------------------------- leg IK

def _ang(y, z):
	return math.atan2(z, y)


class RigInfo:
	"""Leg geometry of one character for the IK run (all in armature space, rest pose)."""

	def __init__(self, arm, skin):
		self.arm = arm
		self.skin = skin
		bones = arm.data.bones
		self.hip = {}
		self.knee = {}
		self.ankle = {}
		for side in ("l", "r"):
			self.hip[side] = bones["upper_leg_" + side].head_local.copy()
			self.knee[side] = bones["lower_leg_" + side].head_local.copy()
			self.ankle[side] = bones["foot_" + side].head_local.copy()
		H, K, A = self.hip["r"], self.knee["r"], self.ankle["r"]
		self.l1 = math.hypot(K.y - H.y, K.z - H.z)
		self.l2 = math.hypot(A.y - K.y, A.z - K.z)
		self.leg = self.l1 + self.l2
		# Foot profile relative to the ankle (y, z), right foot (both feet are mirror images).
		prof = [v - A for v in skin.rest(bones=("foot_r",))]
		if not prof:
			raise RuntimeError("no foot_r vertices")
		self.foot = [(p.y, p.z) for p in prof]
		zmin = min(p[1] for p in self.foot)
		sole = [p for p in self.foot if p[1] < zmin + 0.012 * max(1.0, self.leg / 0.84)]
		self.heel = (max(p[0] for p in sole), zmin)    # back-bottom point (y > 0 is backward)
		self.toe = (min(p[0] for p in sole), zmin)     # front-bottom point
		self.sole_z = zmin                              # sole height relative to the ankle (< 0)

	def lowest_rel(self, psi):
		"""Lowest z of the foot (relative to the ankle) when pitched by psi degrees (+ = toe down)."""
		c, s = math.cos(math.radians(psi)), math.sin(math.radians(psi))
		return min(y * s + z * c for y, z in self.foot)

	def stance_ankle(self, y_flat, psi):
		"""Ankle (y, z) for a planted foot whose flat-foot ankle position is y_flat, rolled by psi about
		the heel (psi < 0) or the toe (psi > 0); the pivot stays on the ground (z = 0)."""
		P = self.heel if psi < 0 else self.toe
		c, s = math.cos(math.radians(psi)), math.sin(math.radians(psi))
		ry = P[0] * c - P[1] * s
		rz = P[0] * s + P[1] * c
		# ground pivot = (y_flat + P.y, 0); ankle = pivot - R(psi) P
		return (y_flat + P[0] - ry, -rz)

	def solve_leg(self, G_hips, side, target, psi):
		"""Planar two-bone IK in the hips' rest frame. target: armature-space ankle Vector; psi: foot
		pitch (deg, + toe down). Returns (thigh X, knee X, foot X) in degrees and the reach error."""
		Q = G_hips.inverted() @ target
		H, K, A = self.hip[side], self.knee[side], self.ankle[side]
		uy, uz = K.y - H.y, K.z - H.z
		wy, wz = A.y - K.y, A.z - K.z
		l1, l2 = self.l1, self.l2
		dy, dz = Q.y - H.y, Q.z - H.z
		d0 = math.hypot(dy, dz)
		d = min(max(d0, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.9995)
		cd = (d * d - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		delta = math.acos(max(-1.0, min(1.0, cd)))
		ce = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
		eps = math.acos(max(-1.0, min(1.0, ce)))
		phi = _ang(dy, dz)
		a1 = phi - eps
		alpha = a1 - _ang(uy, uz)
		beta = delta - (_ang(wy, wz) - _ang(uy, uz))
		al, be = math.degrees(alpha), math.degrees(beta)
		return (al, be, psi - al - be), d0 - d


# ----------------------------------------------------------------------------------- baking

def _curves(arm, act):
	from bpy_extras import anim_utils
	slot = act.slots[0] if len(act.slots) else arm.animation_data.action_slot
	cb = anim_utils.action_ensure_channelbag_for_slot(act, slot)
	out = {}
	for fc in cb.fcurves:
		dp = fc.data_path
		if not dp.startswith('pose.bones["'):
			continue
		bone = dp[len('pose.bones["'):dp.index('"]')]
		prop = dp.rsplit(".", 1)[-1]
		out[(bone, prop, fc.array_index)] = fc
	return out


def eval_frame(arm, curves, f):
	"""Bone-local (rots, locs) of the action at frame f, straight from its F-curves."""
	rots, locs = {}, {}
	for name in cc_rig.BONE_NAMES:
		qc = [curves.get((name, "rotation_quaternion", i)) for i in range(4)]
		if all(c is not None for c in qc):
			rots[name] = Quaternion([c.evaluate(f) for c in qc])
		lc = [curves.get((name, "location", i)) for i in range(3)]
		if all(c is not None for c in lc):
			locs[name] = Vector([c.evaluate(f) for c in lc])
	return rots, locs


def eval_linear(arm, curves, f):
	"""Like eval_frame, but between whole frames interpolated the way Godot plays the exported
	(per-frame baked) animation: lerp for locations, slerp for rotations."""
	f0 = math.floor(f + 1e-6)
	t = f - f0
	r0, l0 = eval_frame(arm, curves, f0)
	if t < 1e-6:
		return r0, l0
	r1, l1 = eval_frame(arm, curves, f0 + 1)
	rots = {k: r0[k].normalized().slerp(r1[k].normalized(), t) for k in r0}
	locs = {k: l0[k].lerp(l1[k], t) for k in l0}
	return rots, locs


def frame_count(act):
	return int(round(act.frame_range[1]))


def bake_ground(arm, act, skin, bones=FEET, loop=False, soft=0.0, lift_only=False):
	"""Shift the root vertically at every frame so the lowest vertex skinned to `bones` sits on z = 0.
	soft > 0 (run): a foot higher than that is left in the air (flight phase); in between the
	correction fades out smoothly (remaining float = h^2 / soft), sinking is always removed.
	lift_only (die / dodge, bones=None = every vertex): only lift frames that dip below the floor.
	Returns (min, max) of the correction applied (metres)."""
	curves = _curves(arm, act)
	n = frame_count(act)
	root_inv = cc_rig.rest_cache(arm).local_inv["root"].to_3x3()
	lc = [curves[("root", "location", i)] for i in range(3)]
	new = []
	corr = []
	for f in range(n + 1):
		rots, locs = eval_frame(arm, curves, f)
		G = cc_rig.fk_basis(arm, rots, locs)
		h = skin.lowest(G, bones=bones)
		if lift_only:
			dz = max(0.0, -h)
		elif soft > 0.0 and h > 0.0:
			dz = -h * max(0.0, 1.0 - h / soft)
		else:
			dz = -h
		corr.append(dz)
		d = root_inv @ Vector((0.0, 0.0, dz))
		new.append([lc[i].evaluate(f) + d[i] for i in range(3)])
	if loop:   # exact seam
		new[-1] = list(new[0])
	for f, vals in enumerate(new):
		for i in range(3):
			lc[i].keyframe_points.insert(f, vals[i], options={"FAST"})
	# Drop the original keys at fractional frames (they would keep their uncorrected values).
	for c in lc:
		for kp in reversed(list(c.keyframe_points)):
			if abs(kp.co[0] - round(kp.co[0])) > 1e-4:
				c.keyframe_points.remove(kp, fast=True)
		c.update()
	return min(corr), max(corr)


def action_G(arm, act, t):
	"""Deformation matrices at time t, as Godot plays the exported (per-frame baked) action."""
	curves = _curves(arm, act)
	rots, locs = eval_linear(arm, curves, t * cc_rig.FPS)
	return cc_rig.fk_basis(arm, rots, locs)


def contact_range(arm, act, skin, bones=FEET, sub=2):
	"""(lowest, highest) of the per-sample lowest foot vertex over the action (sub samples/frame)."""
	curves = _curves(arm, act)
	n = frame_count(act)
	lo, hi = math.inf, -math.inf
	for k in range(n * sub + 1):
		rots, locs = eval_linear(arm, curves, k / sub)
		G = cc_rig.fk_basis(arm, rots, locs)
		m = skin.lowest(G, bones=bones)
		lo, hi = min(lo, m), max(hi, m)
	return lo, hi


def run_speed(arm, act, rate=60):
	"""Planted-foot backward speed (m/s) of a run action, measured like the review (and the Godot
	probe): samples where the ankle (foot bone head) is within 2 cm of its lowest height over the
	cycle, mean backward (+Y) speed. Returns {side: (speed, samples)}."""
	curves = _curves(arm, act)
	n = frame_count(act)
	dur = n / cc_rig.FPS
	steps = int(round(dur * rate))
	dt = dur / steps
	res = {}
	for side in ("l", "r"):
		bone = "foot_" + side
		head = arm.data.bones[bone].head_local
		ank = []
		for k in range(steps + 1):
			rots, locs = eval_linear(arm, curves, k / steps * n)
			ank.append(cc_rig.fk_basis(arm, rots, locs)[bone] @ head)
		zmin = min(a.z for a in ank)
		tot, cnt = 0.0, 0
		for k in range(1, steps + 1):
			if ank[k].z < zmin + 0.02 and ank[k - 1].z < zmin + 0.02:
				tot += (ank[k].y - ank[k - 1].y) / dt
				cnt += 1
		res[side] = (tot / max(1, cnt), cnt)
	return res
