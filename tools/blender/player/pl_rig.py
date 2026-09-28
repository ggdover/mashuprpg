"""The player's rig (tools/blender/player): bones, body proportions per look, and smooth skin weights.

Bones (name, parent, deform). The first 20 match the monsters' rig (tools/blender/characters/cc_rig.py,
same names and pose conventions), plus:
  clavicle_l/r   between the chest and the upper arms (shrugs, reaching)
  toe_l/r        the toes (foot roll: the foot pivots on the ball, the toes stay flat)
  skirt_f/b/l/r  four panels below the waist (tunic hems, skirts, robes, coats) that follow the legs
  cape_1..3      a chain down the back (capes, long coats) - driven at runtime by a spring simulator
  hair_1..2      a chain down the back of the head (long hair, braids) - spring driven too
Characters face -Y (Blender), right side on -X, Z up. Poses: see cc_rig (Euler degrees in the
parent's rest axes; right side authored, mirror() for the left). Extra conventions:
  clavicle_r  +Y raises the shoulder (shrug), +Z pulls it forward (the left side mirrors);
  toe         -X bends the toes up;
  skirt_*     like hanging legs: -X swings the panel forward, +X back; skirt_r +Y (skirt_l -Y) out.

Looks ("f", "m1", "m2"): joint proportions + the body builder's shape parameters (pl_body).
Skinning: every vertex gets up to 4 bone weights from a weight function (see w_* below) - smooth
blends across joints instead of the monsters' rigid 100% segments.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHARS = os.path.join(HERE, "..", "characters")
for p in (HERE, CHARS):
	if p not in sys.path:
		sys.path.insert(0, p)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import cc_rig  # noqa: E402

BONES = [
	("root", None, True),
	("hips", "root", True),
	("spine", "hips", True),
	("chest", "spine", True),
	("neck", "chest", True),
	("head", "neck", True),
	("hair_1", "head", True),
	("hair_2", "hair_1", True),
	("clavicle_l", "chest", True),
	("upper_arm_l", "clavicle_l", True),
	("lower_arm_l", "upper_arm_l", True),
	("hand_l", "lower_arm_l", True),
	("grip_l", "hand_l", False),
	("clavicle_r", "chest", True),
	("upper_arm_r", "clavicle_r", True),
	("lower_arm_r", "upper_arm_r", True),
	("hand_r", "lower_arm_r", True),
	("grip_r", "hand_r", False),
	("cape_1", "chest", True),
	("cape_2", "cape_1", True),
	("cape_3", "cape_2", True),
	("upper_leg_l", "hips", True),
	("lower_leg_l", "upper_leg_l", True),
	("foot_l", "lower_leg_l", True),
	("toe_l", "foot_l", True),
	("upper_leg_r", "hips", True),
	("lower_leg_r", "upper_leg_r", True),
	("foot_r", "lower_leg_r", True),
	("toe_r", "foot_r", True),
	("skirt_f", "hips", True),
	("skirt_b", "hips", True),
	("skirt_l", "hips", True),
	("skirt_r", "hips", True),
]
BONE_NAMES = [b[0] for b in BONES]
SIDE_BONES = ("clavicle", "upper_arm", "lower_arm", "hand", "grip", "upper_leg", "lower_leg", "foot", "toe")

# Joint proportions per look (metres before `scale`; the defaults are the monsters' 1.8 m human).
BASE = dict(
	scale=1.0,
	hip_z=0.96, hip_x=0.1, spine_z=1.08, chest_z=1.24, neck_z=1.44, head_z=1.515, head_top=1.785,
	shoulder_x=0.2, shoulder_z=1.39, clav_x=0.03, upper_arm=0.28, forearm=0.25, hand=0.1,
	arm_out=8.0, elbow=40.0,
	leg_top=0.93, knee_z=0.52, ankle_z=0.09, knee_y=-0.015,
	heel_y=0.055, ball_y=-0.085, toe_y=-0.145, ball_z=0.028, toe_z=0.022,
	grip_up=50.0, grip_out=8.0, shield_face=35.0,
	back_y=0.125,      # depth of the upper back (cape / quiver hang behind it)
	hair_len=0.42,     # long-hair chain length below the nape
)
LOOKS = {
	# the female exile: 1.72 m, narrower shoulders, longer legs, long hair
	"f": dict(scale=0.955, shoulder_x=0.178, clav_x=0.028, hip_x=0.098, hip_z=0.975, leg_top=0.945, knee_z=0.535,
		spine_z=1.09, chest_z=1.245, neck_z=1.45, head_z=1.525, head_top=1.78, shoulder_z=1.395,
		upper_arm=0.27, forearm=0.24, hand=0.095, arm_out=9.0, back_y=0.11, hair_len=0.46),
	# the exiled villager (male 1): lean, 1.80 m
	"m1": dict(),
	# the exile (male 2): 1.82 m, broad shouldered, heavy arms
	"m2": dict(scale=1.01, shoulder_x=0.214, clav_x=0.034, hip_x=0.104, upper_arm=0.285, forearm=0.255,
		arm_out=11.0, back_y=0.135, hair_len=0.2),
}


def params(look):
	p = dict(BASE)
	p.update(LOOKS[look])
	return p


def _n(v):
	v = Vector(v)
	v.normalize()
	return v


def joints(look):
	"""Rest joints of a look in UNIT space (scale 1) and the bone table.
	Returns J: named points (shoulder_r, elbow_r, wrist_r, knuckle_r, fist_r, hip_r, knee_r, ankle_r,
	ball_r, toe_r, heel_r, clavicle_r ... and the _l ones), J["bones"]: name -> (head, tail, z axis),
	J["p"]: the parameters, J["s"]: the scale (applied when the armature is built)."""
	p = params(look)
	J = {"p": p, "s": p["scale"], "look": look}
	bones = {}
	front = Vector((0, -1, 0))
	up = Vector((0, 0, 1))

	def P(x, y, z):
		return Vector((x, y, z))

	bones["root"] = (P(0, 0, 0), P(0, 0, 0.25), front)
	bones["hips"] = (P(0, 0, p["hip_z"]), P(0, 0, p["spine_z"]), front)
	bones["spine"] = (P(0, 0, p["spine_z"]), P(0, 0, p["chest_z"]), front)
	bones["chest"] = (P(0, 0, p["chest_z"]), P(0, 0, p["neck_z"]), front)
	bones["neck"] = (P(0, 0, p["neck_z"]), P(0, 0, p["head_z"]), front)
	bones["head"] = (P(0, 0, p["head_z"]), P(0, 0, p["head_top"]), front)
	nape = P(0, 0.095, p["head_z"] + 0.05)
	h1 = nape + P(0, 0.018, -p["hair_len"] * 0.45)
	h2 = h1 + P(0, 0.012, -p["hair_len"] * 0.55)
	bones["hair_1"] = (nape, h1, front)
	bones["hair_2"] = (h1, h2, front)
	by = p["back_y"]
	c0 = P(0, by + 0.012, p["shoulder_z"] + 0.02)
	c1 = P(0, by + 0.045, 1.0)
	c2 = P(0, by + 0.07, 0.6)
	c3 = P(0, by + 0.08, 0.2)
	bones["cape_1"] = (c0, c1, front)
	bones["cape_2"] = (c1, c2, front)
	bones["cape_3"] = (c2, c3, front)
	J["cape_top"] = c0
	for side, sx in (("r", -1.0), ("l", 1.0)):
		cl = P(sx * p["clav_x"], -0.012, p["shoulder_z"] - 0.012)
		sh = P(sx * p["shoulder_x"], 0.0, p["shoulder_z"])
		a = math.radians(p["arm_out"])
		d_ua = _n((sx * math.sin(a), 0.02, -math.cos(a)))
		el = sh + d_ua * p["upper_arm"]
		e = math.radians(p["elbow"])
		d_fa = _n((sx * math.sin(a) * 0.4, -math.sin(e), -math.cos(e)))
		wr = el + d_fa * p["forearm"]
		kn = wr + d_fa * p["hand"]
		fist = wr + d_fa * (p["hand"] * 0.55)
		bones["clavicle_" + side] = (cl, sh, front)
		bones["upper_arm_" + side] = (sh, el, front)
		bones["lower_arm_" + side] = (el, wr, front)
		bones["hand_" + side] = (wr, kn, front)
		if side == "r":
			gu, go = math.radians(p["grip_up"]), math.radians(p["grip_out"])
			g = _n((sx * math.sin(go) * math.cos(gu), -math.cos(go) * math.cos(gu), math.sin(gu)))
			x = Vector((1, 0, 0)) - g * g.x
			x.normalize()
			z = x.cross(g)
		else:
			g = Vector((0, 0, 1))
			f = math.radians(p["shield_face"])
			z = _n((math.sin(f), -math.cos(f), 0))
		bones["grip_" + side] = (fist, fist + g * 0.1, z)
		hip = P(sx * p["hip_x"], 0, p["leg_top"])
		knee = P(sx * p["hip_x"], p["knee_y"], p["knee_z"])
		ankle = P(sx * p["hip_x"], 0.02, p["ankle_z"])
		ball = P(sx * p["hip_x"], p["ball_y"], p["ball_z"])
		toe = P(sx * p["hip_x"], p["toe_y"], p["toe_z"])
		heel = P(sx * p["hip_x"], p["heel_y"], 0.03)
		bones["upper_leg_" + side] = (hip, knee, front)
		bones["lower_leg_" + side] = (knee, ankle, front)
		bones["foot_" + side] = (ankle, ball, up)
		bones["toe_" + side] = (ball, toe, up)
		for k, v in (("clavicle", cl), ("shoulder", sh), ("elbow", el), ("wrist", wr), ("knuckle", kn), ("fist", fist),
				("hip", hip), ("knee", knee), ("ankle", ankle), ("ball", ball), ("toe", toe), ("heel", heel)):
			J[k + "_" + side] = v
		J["forearm_dir_" + side] = d_fa
		J["upper_arm_dir_" + side] = d_ua
	# skirt panels: hinge just above the hip joints, hanging to the knees
	top = p["leg_top"] + 0.03
	bot = p["knee_z"] + 0.04
	bones["skirt_f"] = (P(0, -0.1, top), P(0, -0.13, bot), front)
	bones["skirt_b"] = (P(0, 0.1, top), P(0, 0.13, bot), front)
	bones["skirt_r"] = (P(-p["hip_x"] - 0.06, 0, top), P(-p["hip_x"] - 0.08, 0, bot), front)
	bones["skirt_l"] = (P(p["hip_x"] + 0.06, 0, top), P(p["hip_x"] + 0.08, 0, bot), front)
	J["bones"] = bones
	for k in ("hip_z", "spine_z", "chest_z", "neck_z", "head_z", "head_top", "shoulder_z", "leg_top", "knee_z", "ankle_z"):
		J[k] = p[k]
	return J


def scaled(J):
	"""The bone table scaled to the look's size (what the armature is built from)."""
	s = J["s"]
	M = Matrix.Diagonal((s, s, s, 1.0))
	return {"bones": {k: (M @ h, M @ t, z) for k, (h, t, z) in J["bones"].items()}}


def create_armature(J):
	arm = cc_rig.create_armature(scaled(J), bones=BONES)
	arm["look"] = J["look"]
	return arm


# ----------------------------------------------------------------------------------- weights

def smoothstep(e0, e1, x):
	if e1 == e0:
		return 1.0 if x >= e1 else 0.0
	t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
	return t * t * (3.0 - 2.0 * t)


def _proj(p, a, b):
	"""(distance, t along a->b clamped, length) of point p to segment a-b."""
	ab = b - a
	L2 = ab.length_squared
	if L2 < 1e-12:
		return (p - a).length, 0.0, 0.0
	t = max(0.0, min(1.0, (p - a).dot(ab) / L2))
	return (p - (a + ab * t)).length, t, math.sqrt(L2)


def chain(points, bones, blends):
	"""Weight function for a tube along a chain of connected segments. points: n+1 Vectors,
	bones: n bone names (segment k belongs to bones[k]), blends: n-1 half widths (m) of the blend
	around each inner joint. A vertex is projected on the nearest segment; its arc position s along
	the chain decides the mix of the two bones around the closest joint."""
	pts = [Vector(p) for p in points]
	arc = [0.0]
	for i in range(len(pts) - 1):
		arc.append(arc[-1] + (pts[i + 1] - pts[i]).length)

	def f(v):
		best = None
		for i in range(len(pts) - 1):
			d, t, L = _proj(v, pts[i], pts[i + 1])
			if best is None or d < best[0] - 1e-9:
				best = (d, i, t, L)
		_d, i, t, L = best
		s = arc[i] + t * L
		w = {}
		# bone k spans arc[k]..arc[k+1]; joints between k-1 and k at arc[k]
		for k in range(len(bones)):
			lo = 1.0 if k == 0 else smoothstep(arc[k] - blends[k - 1], arc[k] + blends[k - 1], s)
			hi = 1.0 if k == len(bones) - 1 else 1.0 - smoothstep(arc[k + 1] - blends[k], arc[k + 1] + blends[k], s)
			x = lo * hi
			if x > 1e-4:
				w[bones[k]] = w.get(bones[k], 0.0) + x
		return w
	return f


def rigid(bone):
	return lambda v: {bone: 1.0}


def mix(*fw):
	"""Blend weight functions: mix((f1, k1), (f2, k2)) with constant factors."""
	def f(v):
		out = {}
		for fn, k in fw:
			for b, w in fn(v).items():
				out[b] = out.get(b, 0.0) + w * k
		return out
	return f


def normalized(w, keep=4):
	items = sorted(w.items(), key=lambda e: -e[1])[:keep]
	tot = sum(x for _b, x in items)
	if tot <= 0:
		raise RuntimeError("empty weights")
	return {b: x / tot for b, x in items if x / tot > 0.002}


def w_torso(J):
	"""Hips -> spine -> chest -> neck by height, with the shoulders drifting onto the clavicles."""
	f = chain([Vector((0, 0, 0.55)), Vector((0, 0, J["spine_z"])), Vector((0, 0, J["chest_z"])), Vector((0, 0, J["neck_z"])),
		Vector((0, 0, J["head_z"] + 0.1))], ["hips", "spine", "chest", "neck"], [0.07, 0.09, 0.05])
	shx = J["p"]["shoulder_x"]

	def g(v):
		w = f(v)
		# upper chest near the shoulder joints follows the clavicle a little
		k = smoothstep(shx * 0.45, shx * 0.95, abs(v.x)) * smoothstep(J["shoulder_z"] - 0.16, J["shoulder_z"] - 0.02, v.z)
		if k > 0:
			side = "l" if v.x > 0 else "r"
			tot = sum(w.values())
			w = {b: x * (1.0 - 0.7 * k) for b, x in w.items()}
			w["clavicle_" + side] = 0.7 * k * tot
		return w
	return g


def w_arm(J, side):
	"""Chest -> clavicle -> upper arm -> forearm -> hand along the arm."""
	sx = -1.0 if side == "r" else 1.0
	pts = [Vector((0, 0, J["shoulder_z"])), J["clavicle_" + side], J["shoulder_" + side], J["elbow_" + side],
		J["wrist_" + side], J["knuckle_" + side] + J["forearm_dir_" + side] * 0.05]
	return chain(pts, ["chest", "clavicle_" + side, "upper_arm_" + side, "lower_arm_" + side, "hand_" + side],
		[0.03, 0.06, 0.06, 0.035])


def w_leg(J, side):
	"""Hips -> thigh -> shin -> foot -> toes along the leg (the waistband above the hip joint stays on the
	hips). Below the ankle joint (heel, sole) the shin's share moves onto the foot, so heels follow the
	foot's pitch (a heel is as near the shin's end as the foot's start)."""
	hip = J["hip_" + side]
	ank = J["ankle_" + side]
	pts = [hip + Vector((0, 0, 0.16)), hip, J["knee_" + side], ank, J["ball_" + side], J["toe_" + side]]
	f = chain(pts, ["hips", "upper_leg_" + side, "lower_leg_" + side, "foot_" + side, "toe_" + side], [0.07, 0.06, 0.035, 0.02])
	shin, foot = "lower_leg_" + side, "foot_" + side

	def g(v):
		w = f(v)
		k = 1.0 - smoothstep(ank.z - 0.05, ank.z - 0.005, v.z)
		if k > 0.0 and shin in w:
			moved = w[shin] * k
			w[shin] -= moved
			w[foot] = w.get(foot, 0.0) + moved
			if w[shin] < 1e-4:
				del w[shin]
		return w
	return g


def w_head(J):
	return chain([Vector((0, 0, J["neck_z"] - 0.05)), Vector((0, 0, J["head_z"])), Vector((0, 0, J["head_top"] + 0.1))],
		["neck", "head"], [0.04])


def w_hair(J):
	"""Head -> hair_1 -> hair_2 down the back (long hair, braids)."""
	b = J["bones"]
	return chain([Vector((0, 0.06, J["head_top"])), b["hair_1"][0], b["hair_1"][1], b["hair_2"][1] + Vector((0, 0, -0.2))],
		["head", "hair_1", "hair_2"], [0.07, 0.1])


def w_cape(J):
	"""Chest -> cape_1 -> cape_2 -> cape_3 down the back."""
	b = J["bones"]
	top = J["cape_top"]
	return chain([top + Vector((0, -0.05, 0.12)), top, b["cape_1"][1], b["cape_2"][1], b["cape_3"][1] + Vector((0, 0, -0.3))],
		["chest", "cape_1", "cape_2", "cape_3"], [0.06, 0.12, 0.12])


def w_skirt(J, waist_z=None, full=0.22):
	"""Below the waist: hips at the waistband, the four skirt panels further down (by the angle
	around the body: front / left / back / right, cos^2 lobes)."""
	wz = J["leg_top"] + 0.06 if waist_z is None else waist_z

	def f(v):
		drop = wz - v.z
		k = smoothstep(0.02, full, drop)
		w = {}
		if k < 1.0:
			w["hips"] = 1.0 - k
		if k > 0.0:
			ang = math.atan2(v.x, -v.y)    # 0 front, +90 character's left, 180 back
			for bone, a0 in (("skirt_f", 0.0), ("skirt_l", 90.0), ("skirt_b", 180.0), ("skirt_r", -90.0)):
				c = math.cos(ang - math.radians(a0))
				if c > 0:
					w[bone] = w.get(bone, 0.0) + k * c * c
		return w
	return f


def w_skirt_legs(J, share=0.35):
	"""A long hem between the legs: mostly the skirt panels, partly the thighs (so it clears them)."""
	fs = w_skirt(J)

	def f(v):
		w = fs(v)
		side = "l" if v.x > 0 else "r"
		lw = w_leg(J, side)(v)
		out = {b: x * (1.0 - share) for b, x in w.items()}
		for b, x in lw.items():
			out[b] = out.get(b, 0.0) + x * share
		return out
	return f


# ----------------------------------------------------------------------------------- skin (LBS)

class WSkin:
	"""Rest vertices with their (bone, weight) lists, for exact posed positions (linear blend skinning)."""

	def __init__(self, arm, parts=None):
		self.arm = arm
		self.items = []   # (part, [(bone, w)], (x, y, z))
		for ob in arm.children:
			if ob.type != "MESH" or (parts is not None and ob.name not in parts):
				continue
			names = {vg.index: vg.name for vg in ob.vertex_groups}
			for v in ob.data.vertices:
				ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 0.0]
				if ws:
					self.items.append((ob.name, ws, (v.co.x, v.co.y, v.co.z)))

	def select(self, bones=None, parts=None):
		for part, ws, co in self.items:
			if parts is not None and part not in parts:
				continue
			if bones is not None:
				main = max(ws, key=lambda e: e[1])[0]
				if main not in bones:
					continue
			yield ws, co

	def posed_z(self, G, ws, co):
		z = 0.0
		for b, w in ws:
			M = G[b]
			z += w * (M[2][0] * co[0] + M[2][1] * co[1] + M[2][2] * co[2] + M[2][3])
		return z

	def lowest(self, G, bones=None, parts=None):
		m = math.inf
		for ws, co in self.select(bones, parts):
			h = self.posed_z(G, ws, co)
			if h < m:
				m = h
		return m

	def posed(self, G, bones=None, parts=None):
		out = []
		for ws, co in self.select(bones, parts):
			v = Vector(co)
			acc = Vector((0.0, 0.0, 0.0))
			for b, w in ws:
				acc += (G[b] @ v) * w
			out.append(acc)
		return out


def rig_json():
	return json.dumps([list(b) for b in BONES])
