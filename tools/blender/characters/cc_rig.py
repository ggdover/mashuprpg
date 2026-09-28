"""Humanoid rig (docs/ARCHITECTURE.md §14.2) and pose/keyframe helpers.

Rig: bones root, hips, spine, chest, neck, head, upper_arm_l/r, lower_arm_l/r, hand_l/r, grip_l/r
(non-deforming), upper_leg_l/r, lower_leg_l/r, foot_l/r. Characters face -Y (Blender), right side on -X.

Poses are authored as Euler angles in DEGREES about the ARMATURE axes (X = character's left,
Y = back, Z = up), applied X then Y then Z, relative to the parent bone as if the parent were in
its rest orientation ("FK in rest axes"). Conventions that follow from that:
  * upward bones (spine, chest, neck, head, hips): +X bends forward, +Z twists to the character's
    left, +Y side-bends toward the character's left;
  * hanging arms: -X swings forward/up (-90 = horizontal forward, -170 = overhead), +X swings
    back; right arm +Y (left arm -Y) raises it sideways; Z (after X) sweeps a raised arm
    horizontally (+Z toward the character's left);
  * lower_arm -X bends the elbow further, hand -X flexes the wrist forward/up;
  * legs: -X hip flexion (leg forward), lower_leg +X bends the knee, foot +X points the toe down.
Author the right side, `mirror()` gives the left side ((x, y, z) -> (x, -y, -z)).
Locations: key "loc:<bone>" = offset (metres) of that bone in its parent's frame, expressed in armature
axes as if the parent were at rest (root: plain armature space).
"""
import math

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

BONES = [
	# name, parent, deform
	("root", None, True),
	("hips", "root", True),
	("spine", "hips", True),
	("chest", "spine", True),
	("neck", "chest", True),
	("head", "neck", True),
	("upper_arm_l", "chest", True),
	("lower_arm_l", "upper_arm_l", True),
	("hand_l", "lower_arm_l", True),
	("grip_l", "hand_l", False),
	("upper_arm_r", "chest", True),
	("lower_arm_r", "upper_arm_r", True),
	("hand_r", "lower_arm_r", True),
	("grip_r", "hand_r", False),
	("upper_leg_l", "hips", True),
	("lower_leg_l", "upper_leg_l", True),
	("foot_l", "lower_leg_l", True),
	("upper_leg_r", "hips", True),
	("lower_leg_r", "upper_leg_r", True),
	("foot_r", "lower_leg_r", True),
]
BONE_NAMES = [b[0] for b in BONES]
PARENT = {b[0]: b[1] for b in BONES}

# Armatures built with another bone list (the player's rig, tools/blender/player/pl_rig.py) store it
# as JSON in the custom property "rig_bones"; every helper below iterates bones_of(arm_obj).
_BONES_BY_ARM = {}


def bones_of(arm_obj):
	"""The (name, parent, deform) list of an armature: its "rig_bones" property, else BONES."""
	key = arm_obj.name_full + ":%d" % arm_obj.as_pointer()
	got = _BONES_BY_ARM.get(key)
	if got is not None:
		return got
	raw = arm_obj.get("rig_bones") if hasattr(arm_obj, "get") else None
	if raw:
		import json
		got = [tuple(b) for b in json.loads(raw)]
	else:
		got = BONES
	_BONES_BY_ARM[key] = got
	return got

FPS = 30


def _n(v):
	v = Vector(v)
	v.normalize()
	return v


def humanoid(**kw):
	"""Rest-pose joints. Returns dict with 'bones': name -> (head, tail, z_axis) and named points.
	All lengths in metres for a 1.8 m human, multiplied by `scale`."""
	p = dict(
		scale=1.0,
		hip_z=0.96, hip_x=0.1, spine_z=1.08, chest_z=1.24, neck_z=1.44, head_z=1.53, head_top=1.80,
		shoulder_x=0.2, shoulder_z=1.39, upper_arm=0.28, forearm=0.25, hand=0.1,
		arm_out=8.0, elbow=40.0,
		leg_top=0.93, knee_z=0.52, ankle_z=0.09, foot_len=0.15, toe_z=0.025, knee_y=-0.015,
		grip_up=50.0, grip_out=8.0, shield_face=35.0,
	)
	p.update(kw)
	s = p["scale"]
	J = {"params": p}
	bones = {}
	up = Vector((0, 0, 1))
	front = Vector((0, -1, 0))

	def P(x, y, z):
		return Vector((x * s, y * s, z * s))

	J["root"] = P(0, 0, 0)
	bones["root"] = (P(0, 0, 0), P(0, 0, 0.25), front)
	bones["hips"] = (P(0, 0, p["hip_z"]), P(0, 0, p["spine_z"]), front)
	bones["spine"] = (P(0, 0, p["spine_z"]), P(0, 0, p["chest_z"]), front)
	bones["chest"] = (P(0, 0, p["chest_z"]), P(0, 0, p["neck_z"]), front)
	bones["neck"] = (P(0, 0, p["neck_z"]), P(0, 0, p["head_z"]), front)
	bones["head"] = (P(0, 0, p["head_z"]), P(0, 0, p["head_top"]), front)
	for side, sx in (("r", -1.0), ("l", 1.0)):
		sh = P(sx * p["shoulder_x"], 0.0, p["shoulder_z"])
		a = math.radians(p["arm_out"])
		d_ua = _n((sx * math.sin(a), 0.02, -math.cos(a)))
		el = sh + d_ua * (p["upper_arm"] * s)
		e = math.radians(p["elbow"])
		d_fa = _n((sx * math.sin(a) * 0.4, -math.sin(e), -math.cos(e)))
		wr = el + d_fa * (p["forearm"] * s)
		kn = wr + d_fa * (p["hand"] * s)
		fist = wr + d_fa * (p["hand"] * s * 0.55)
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
		toe = P(sx * p["hip_x"], 0.02 - p["foot_len"], p["toe_z"])
		bones["upper_leg_" + side] = (hip, knee, front)
		bones["lower_leg_" + side] = (knee, ankle, front)
		bones["foot_" + side] = (ankle, toe, up)
		J["shoulder_" + side] = sh
		J["elbow_" + side] = el
		J["wrist_" + side] = wr
		J["knuckle_" + side] = kn
		J["fist_" + side] = fist
		J["hip_" + side] = hip
		J["knee_" + side] = knee
		J["ankle_" + side] = ankle
		J["toe_" + side] = toe
		J["forearm_dir_" + side] = d_fa
	J["bones"] = bones
	for k in ("hip_z", "spine_z", "chest_z", "neck_z", "head_z", "head_top", "shoulder_z"):
		J[k] = p[k] * s
	J["s"] = s
	return J


_REST = {}   # rest matrices per armature (see rest_cache); cleared by create_armature


def create_armature(J, bones=None):
	"""Create the 'Armature' object (identity transform) with the §14.2 bones (or `bones`, a list of
	(name, parent, deform), stored on the object as "rig_bones")."""
	_REST.clear()   # a new armature may reuse a freed one's address (cache key): never reuse old rests
	_BONES_BY_ARM.clear()
	arm = bpy.data.armatures.new("Armature")
	ob = bpy.data.objects.new("Armature", arm)
	bpy.context.scene.collection.objects.link(ob)
	bpy.context.view_layer.objects.active = ob
	ob.select_set(True)
	if bones is not None:
		import json
		ob["rig_bones"] = json.dumps([list(b) for b in bones])
	bpy.ops.object.mode_set(mode="EDIT")
	for name, parent, deform in (bones or BONES):
		head, tail, zax = J["bones"][name]
		eb = arm.edit_bones.new(name)
		eb.head = head
		eb.tail = tail
		eb.align_roll(Vector(zax))
		eb.use_deform = deform
		if parent:
			eb.parent = arm.edit_bones[parent]
			eb.use_connect = False
	bpy.ops.object.mode_set(mode="OBJECT")
	for pb in ob.pose.bones:
		pb.rotation_mode = "QUATERNION"
	ob.animation_data_create()
	return ob


# ----------------------------------------------------------------------------------- poses

def mirror(v):
	return (v[0], -v[1], -v[2])


def pose(**bones):
	"""pose(upper_arm_r=(x,y,z), ...). Keys ending in '_s' are applied to both sides (right as
	given, left mirrored), e.g. upper_leg_s=(-10, 0, 0) bends both legs forward."""
	out = {}
	for k, v in bones.items():
		if k.endswith("_s"):
			base = k[:-2]
			out[base + "_r"] = tuple(v)
			out[base + "_l"] = mirror(v)
		else:
			out[k] = tuple(v)
	return out


def sym(d):
	"""Given right-side entries ('*_r'), add mirrored left entries for missing '*_l'."""
	out = dict(d)
	for k, v in d.items():
		if k.endswith("_r") and not k.startswith("loc:"):
			lk = k[:-2] + "_l"
			if lk not in out:
				out[lk] = mirror(v)
	return out


def swap_sides(d):
	"""Mirror a whole pose left<->right (for mirrored animations)."""
	out = {}
	for k, v in d.items():
		if k.startswith("loc:"):
			out[k] = (-v[0], v[1], v[2])
			continue
		if k.endswith("_r"):
			nk = k[:-2] + "_l"
		elif k.endswith("_l"):
			nk = k[:-2] + "_r"
		else:
			nk = k
		out[nk] = mirror(v)
	return out


def add(*poses, w=None):
	"""Sum poses (Euler degrees and locations add up). w: optional weights."""
	out = {}
	for i, p in enumerate(poses):
		if not p:
			continue
		k = 1.0 if w is None else w[i]
		for bone, v in p.items():
			cur = out.get(bone, (0.0, 0.0, 0.0))
			out[bone] = (cur[0] + v[0] * k, cur[1] + v[1] * k, cur[2] + v[2] * k)
	return out


def scale(p, k):
	return {b: (v[0] * k, v[1] * k, v[2] * k) for b, v in p.items()}


def lerp(a, b, t):
	keys = set(a) | set(b)
	out = {}
	for k in keys:
		va = a.get(k, (0.0, 0.0, 0.0))
		vb = b.get(k, (0.0, 0.0, 0.0))
		out[k] = tuple(va[i] + (vb[i] - va[i]) * t for i in range(3))
	return out


def solve(arm_obj, p):
	"""Pose dict -> ({bone: Quaternion basis}, {bone: Vector local location})."""
	rots, locs = {}, {}
	D = {}
	for name, parent, _deform in bones_of(arm_obj):
		bone = arm_obj.data.bones[name]
		rest = bone.matrix_local.to_3x3()
		e = p.get(name, (0.0, 0.0, 0.0))
		L = Euler((math.radians(e[0]), math.radians(e[1]), math.radians(e[2])), "XYZ").to_matrix()
		Dp = D[parent] if parent else Matrix.Identity(3)
		D[name] = Dp @ L
		q = (rest.inverted() @ L @ rest).to_quaternion()
		rots[name] = q
		lk = "loc:" + name
		if lk in p:
			# Offset in the parent's frame (armature axes as if the parent were at rest), so e.g. a
			# hips crouch stays relative to a rotating root.
			t = Vector(p[lk])
			locs[name] = rest.inverted() @ t
		else:
			locs[name] = Vector((0.0, 0.0, 0.0))
	return rots, locs


class _RestCache:
	"""Per-armature rest matrices (bone.matrix_local and friends never change after creation)."""

	def __init__(self, arm_obj):
		self.local = {}
		self.local_inv = {}
		self.rel = {}
		for name, parent, _deform in bones_of(arm_obj):
			b = arm_obj.data.bones[name]
			self.local[name] = b.matrix_local.copy()
			self.local_inv[name] = b.matrix_local.inverted()
			if parent:
				self.rel[name] = arm_obj.data.bones[parent].matrix_local.inverted() @ b.matrix_local


def rest_cache(arm_obj):
	key = arm_obj.name_full + ":%d" % arm_obj.as_pointer()
	rc = _REST.get(key)
	if rc is None:
		rc = _RestCache(arm_obj)
		_REST[key] = rc
	return rc


def fk_basis(arm_obj, rots, locs):
	"""Deformation matrices (armature space, rest -> posed) per bone from bone-local rotations and
	locations (what pose_bone.rotation_quaternion / .location hold), exactly like Blender's pose
	evaluation: pose = parent_pose @ (parent_rest^-1 @ rest) @ T(loc) @ R(q)."""
	rc = rest_cache(arm_obj)
	G = {}
	P = {}
	for name, parent, _deform in bones_of(arm_obj):
		q = rots.get(name)
		R = q.normalized().to_matrix().to_4x4() if q is not None else Matrix.Identity(4)
		loc = locs.get(name)
		basis = Matrix.Translation(loc) @ R if loc is not None else R
		if parent:
			pm = P[parent] @ rc.rel[name] @ basis
		else:
			pm = rc.local[name] @ basis
		P[name] = pm
		G[name] = pm @ rc.local_inv[name]
	return G


def fk(arm_obj, p):
	"""Deformation matrices for a pose dict (see solve)."""
	rots, locs = solve(arm_obj, p)
	return fk_basis(arm_obj, rots, locs)


def key_action(arm_obj, name, keys, interp="BEZIER"):
	"""Create action `name` from [(time_s, pose), ...]. Every bone gets rotation + location keys at
	every key time (tracks of bones that never move are dropped by the exporter)."""
	act = bpy.data.actions.new(name)
	act.use_fake_user = True
	arm_obj.animation_data.action = act
	prev = {}
	for t, p in keys:
		f = t * FPS
		rots, locs = solve(arm_obj, p)
		for pb in arm_obj.pose.bones:
			q = rots[pb.name]
			pq = prev.get(pb.name)
			if pq is not None and pq.dot(q) < 0:
				q = -q
			prev[pb.name] = q
			pb.rotation_quaternion = q
			pb.location = locs[pb.name]
			pb.keyframe_insert("rotation_quaternion", frame=f)
			pb.keyframe_insert("location", frame=f)
	if interp != "BEZIER":
		from bpy_extras import anim_utils
		slot = arm_obj.animation_data.action_slot
		cb = anim_utils.action_ensure_channelbag_for_slot(act, slot)
		for fc in cb.fcurves:
			for kp in fc.keyframe_points:
				kp.interpolation = interp
	return act


def sample(fn, duration, step=1):
	"""Keys for a procedural (looping) animation: fn(phase 0..1) -> pose, one key per `step` frames."""
	frames = int(round(duration * FPS))
	keys = []
	for f in range(0, frames + 1, step):
		keys.append((f / FPS, fn(f / frames)))
	if keys[-1][0] < duration - 1e-6:
		keys.append((duration, fn(1.0)))
	return keys


def reset_pose(arm_obj):
	for pb in arm_obj.pose.bones:
		pb.rotation_quaternion = Quaternion()
		pb.location = Vector()
		pb.scale = Vector((1, 1, 1))
