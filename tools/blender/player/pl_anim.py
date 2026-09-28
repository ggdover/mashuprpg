"""The player's animations (tools/blender/player) on the player rig (pl_rig). Names, lengths and hit
frames follow the game's contract (SkillDB.ANIM_HIT_FRAMES, PlayerVisuals, PlayerLegs):

  idle 2.0 loop        run 0.6 loop (planted feet at 5.2 m/s)      walk 0.933 loop (1.82 m/s)
  walk_back 0.733 / walk_left 0.4 / walk_right 0.4 loops (1.82 m/s; the right foot touches down at
  phase 0 in every walk, so PlayerLegs can blend neighbours at one phase)
  attack_slash 0.6 (hit 0.45)  attack_slam 0.8 (0.55)  attack_stab 0.5 (0.5)  shoot_bow 0.7 (0.6)
  shoot_crossbow 0.6 (0.4)     cast 0.6 (0.5)          cast_area 0.7 (0.55)   channel 1.0 loop
  hit 0.3   die 1.0 (lying on the floor)   dodge 0.55 (fast tumble, slow rise)   parry 0.55
  parry_hold 1.0 loop
(hit = share of the length, like SkillDB.ANIM_HIT_FRAMES).

Poses use cc_rig's conventions (Euler degrees about the armature axes, relative to the parent's rest
orientation; right side authored, mirror() for the left). The gaits reuse cc_anim's IK machinery
(cc_ground.RigInfo feet tracks, gait styles) with the planted feet kept level and pointing forward
(no twist with the hips), a toe-down foot rolling about the ball joint (the toes stay put) and the
female exile's pelvis swaying over the standing leg; idle, channel and the parry guard plant their
feet with IK too, so breathing bends the knees. The one-shots are cc_anim's (the old player's) key
poses on the player's ready stance, re-timed to SkillDB's hit frames.
Every key is then finished for the player rig's extra bones (finish()):
  clavicle_*  shrug / reach with the arm; the upper arm is counter-rotated so the arm keeps its
              direction and only the shoulder moves;
  skirt_*     the four hem panels hang with gravity and are pushed by the legs: the front panel stays
              ahead of the forward-most leg, the back panel behind the backward-most one (each drags
              the other 60% along), the sides outside their leg and swinging with it (skirts, tunic
              hems, coats and robes);
  toe_*       bend up when the foot rolls onto its ball on the ground (the toes stay flat);
  hair_*, cape_*  stay at rest (runtime spring bones in Godot).
Then each action is ground baked on the exact skin (pl_rig.WSkin, the base parts only): the lowest
foot / toe vertex on the floor every frame (die / dodge: nothing below it, the corpse resting on it).
No root motion (the root only moves vertically, and rotates in die / dodge).

build_actions(arm, L) -> action names; preview(arm, L, out_dir) -> <look>_anim_<name>.png sheets.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

import cc_anim
import cc_ground
import cc_rig
import pl_rig
from cc_anim import TAU, _fin, _floor_keys, _hermite, _loc, _seq, _smooth
from cc_rig import FPS, add, fk, lerp, mirror, pose, sample

ANIMS = ["idle", "run", "walk", "walk_back", "walk_left", "walk_right", "attack_slash", "attack_slam",
	"attack_stab", "shoot_bow", "shoot_crossbow", "cast", "cast_area", "channel", "hit", "die", "dodge",
	"parry", "parry_hold"]
LOOPS = ("idle", "run", "walk", "walk_back", "walk_left", "walk_right", "channel", "parry_hold")
GAITS = ("run", "walk", "walk_back", "walk_left", "walk_right")
NO_GROUND = ("die", "dodge")
DURATION = {"idle": 2.0, "attack_slash": 0.6, "attack_slam": 0.8, "attack_stab": 0.5, "shoot_bow": 0.7,
	"shoot_crossbow": 0.6, "cast": 0.6, "cast_area": 0.7, "channel": 1.0, "hit": 0.3, "die": 1.0,
	"dodge": 0.55, "parry": 0.55, "parry_hold": 1.0}
# SkillDB.ANIM_HIT_FRAMES: the hit as a share of the animation's length.
HIT_FRAME = {"attack_slash": 0.45, "attack_slam": 0.55, "attack_stab": 0.5, "shoot_bow": 0.6,
	"shoot_crossbow": 0.4, "cast": 0.5, "cast_area": 0.55}
RUN_SPEED = cc_anim.REF_RUN_SPEED
WALK_SPEED = cc_anim.WALK_SPEED
FEET = ("foot_l", "foot_r")
FEET_TOES = ("foot_l", "foot_r", "toe_l", "toe_r")
LEG_KEYS = ("upper_leg_", "lower_leg_", "foot_")
# Gear parts (pl_gear) are left out of the ground contact skin: every boot keeps the default sole.
GEAR_PREFIXES = ("Helm_", "Chest_", "Gloves_", "Boots_")
# Directions of travel (armature ground plane: forward = (0, -1), the character's left = (+1, 0)).
WALK_DIRS = {"run": (0.0, -1.0), "walk": (0.0, -1.0), "walk_back": (0.0, 1.0), "walk_left": (1.0, 0.0),
	"walk_right": (-1.0, 0.0)}
# Held items of the previews (like tools/blender/characters/build_all.py).
PREVIEW_HELD = {
	"shoot_bow": ("weapon_bow", "offhand_quiver"),
	"shoot_crossbow": ("weapon_crossbow", "offhand_quiver"),
	"cast": ("weapon_wand", "offhand_focus"),
	"cast_area": ("weapon_staff", None),
	"attack_slam": ("weapon_maul", None),
	"attack_stab": ("weapon_dagger", "offhand_shield"),
	"channel": ("weapon_greatsword", None),
}


# ----------------------------------------------------------------------------------- skin / style

class Skin:
	"""pl_rig.WSkin (exact linear blend skinning) with the interface cc_ground / cc_anim use. A vertex
	belongs to a bone selection when its main bone is in it or it has >= 35% weight on one of its
	bones (smooth skins split heels and soles between bones)."""

	def __init__(self, arm, parts):
		self.w = pl_rig.WSkin(arm, parts)
		self.parts = sorted(parts)

	def select(self, bones=None, parts=None, exclude_parts=()):
		for part, ws, co in self.w.items:
			if parts is not None and part not in parts:
				continue
			if bones is not None:
				main = max(ws, key=lambda e: e[1])[0]
				if main not in bones and not any(b in bones and x >= 0.35 for b, x in ws):
					continue
			yield ws, co

	def lowest(self, G, bones=None, parts=None, exclude_parts=()):
		m = math.inf
		for ws, co in self.select(bones, parts):
			h = self.w.posed_z(G, ws, co)
			if h < m:
				m = h
		return m

	def posed(self, G, bones=None, parts=None, exclude_parts=()):
		out = []
		for ws, co in self.select(bones, parts):
			v = Vector(co)
			acc = Vector((0.0, 0.0, 0.0))
			for b, x in ws:
				acc += (G[b] @ v) * x
			out.append(acc)
		return out

	def rest(self, bones=None, parts=None):
		return [Vector(co) for _ws, co in self.select(bones, parts)]


class _FootProfile:
	"""The right foot's rigid profile for cc_ground.RigInfo: the vertices below the ankle that follow
	the foot (>= 30% foot weight, not toe-dominant), plus the sole point under the ball joint (so a
	toe-down foot's lowest point is right even when the forefoot is skinned to the toes)."""

	def __init__(self, arm, skin):
		b = arm.data.bones
		A = b["foot_r"].head_local
		ball = b["toe_r"].head_local
		pts = []
		for _part, ws, co in skin.w.items:
			w = dict(ws)
			main = max(ws, key=lambda e: e[1])[0]
			if w.get("foot_r", 0.0) >= 0.3 and main != "toe_r" and co[2] <= A.z + 0.02:
				pts.append(Vector(co))
		zmin = min(p.z for p in pts) if pts else 0.0
		pts.append(Vector((ball.x, ball.y, zmin)))
		self.pts = pts

	def rest(self, bones=None, parts=None):
		return self.pts


def base_parts(L):
	return [n for n in L.parts if not n.startswith(GEAR_PREFIXES)]


def make_style(arm, L, skin):
	"""Gait / posture parameters of one look (cc_anim style keys + the player's extras)."""
	f = L.look == "f"
	st = cc_anim._st(dict(s=L.J["s"], weapon=True, stabilize_left=True, run_frames=18, duty=0.3,
		arm_swing=19.0 if f else 26.0, lean=10.0 if f else 12.5, hip_twist=9.0 if f else 7.0,
		bounce=0.018 if f else 0.022, crouch=-0.08 if f else -0.09, robe=f))
	st.update(arm=arm, skin=skin, rig=cc_ground.RigInfo(arm, _FootProfile(arm, skin)), look=L.look, female=f, J=L.J,
		sway=4.0 if f else 1.5, sway_shift=0.012 if f else 0.004, walk_dir=(0.0, -1.0), ground_speed=RUN_SPEED,
		arms="run")
	st["slam_held"] = _item_vertices("weapon_maul")
	b = arm.data.bones
	ball = b["toe_r"].head_local - b["foot_r"].head_local
	st["_ball"] = (ball.y, ball.z)
	_rest_data(st)
	return st


def _item_vertices(iid):
	"""Vertices (item space) of an item model, built temporarily and removed again (the reference
	maul whose head attack_slam puts on the floor, like build_all.py does for the monsters)."""
	import cc_items
	before_obs = set(bpy.data.objects)
	before_me = set(bpy.data.meshes)
	before_ma = set(bpy.data.materials)
	cc_items.ITEMS[iid]()
	verts = []
	for o in set(bpy.data.objects) - before_obs:
		if o.type == "MESH":
			verts.extend(o.matrix_world @ v.co for v in o.data.vertices)
		bpy.data.objects.remove(o)
	for m in set(bpy.data.meshes) - before_me:
		bpy.data.meshes.remove(m)
	for m in set(bpy.data.materials) - before_ma:
		bpy.data.materials.remove(m)
	return verts


def _rest_data(st):
	"""Rest geometry finish() needs: the upper arm's direction, the hem panels, leg sample points
	(bone, rest point, radius, importance) and the toes."""
	b = st["arm"].data.bones
	s = st["s"]
	rd = {"ua_dir": (b["upper_arm_r"].tail_local - b["upper_arm_r"].head_local).normalized()}
	for k in ("skirt_f", "skirt_b", "skirt_r", "skirt_l"):
		rd[k] = b[k].head_local.copy()
	legs = {}
	for side in ("l", "r"):
		hip = b["upper_leg_" + side].head_local
		knee = b["lower_leg_" + side].head_local
		ank = b["foot_" + side].head_local
		ball = b["toe_" + side].head_local
		tip = b["toe_" + side].tail_local
		heel = Vector(st["J"]["heel_" + side]) * s
		u, lo, ft, to = "upper_leg_" + side, "lower_leg_" + side, "foot_" + side, "toe_" + side
		# (the upper thigh is left out: close to the hinges its clearance angle explodes, and the
		# cloth drapes over it anyway)
		legs[side] = [(u, hip.lerp(knee, 0.7), 0.075 * s, 1.0), (lo, knee.copy(), 0.066 * s, 1.0), (lo, knee.lerp(ank, 0.35), 0.06 * s, 0.7),
			(lo, knee.lerp(ank, 0.7), 0.055 * s, 0.45), (ft, ank.copy(), 0.05 * s, 0.35),
			(ft, heel + Vector((0, 0, 0.03 * s)), 0.035 * s, 0.3), (to, ball.lerp(tip, 0.6), 0.03 * s, 0.25)]
	rd["legs"] = legs
	rd["toe"] = {side: (b["toe_" + side].head_local.copy(), b["toe_" + side].tail_local.copy()) for side in ("l", "r")}
	st["_rest"] = rd
	# the rest configuration of the skirt constraints (finish keeps the rest clearance)
	G0 = {n: Matrix.Identity(4) for n in pl_rig.BONE_NAMES}
	rd["skirt_rest"] = _skirt_angles(st, G0)


def _euler_m(e):
	return Euler((math.radians(e[0]), math.radians(e[1]), math.radians(e[2])), "XYZ").to_matrix()


def _deg(e):
	return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


# ----------------------------------------------------------------------------------- finishing

def finish(st, p, ground=None):
	"""Add the player rig's extra bones to a pose (see the module doc). ground: floor height for the
	toe rule (None = the lowest foot vertex of this pose, i.e. where the ground bake will put it)."""
	q = dict(p)
	_clavicles(st, q)
	G = fk(st["arm"], q)
	_skirts(st, q, G)
	_toes(st, q, G, ground)
	return q


def _clavicles(st, q):
	"""Shrug with a raised arm (from ~50 deg, full at 165), pull the shoulder forward with a reach
	and back with a pull; the upper arm keeps its direction in the chest's frame."""
	d0 = st["_rest"]["ua_dir"]
	for side in ("r", "l"):
		e = q.get("upper_arm_" + side, (0.0, 0.0, 0.0))
		c0 = q.get("clavicle_" + side, (0.0, 0.0, 0.0))
		if side == "l":
			e, c0 = mirror(e), mirror(c0)
		M = _euler_m(c0) @ _euler_m(e)     # the arm's orientation in the chest's frame
		d = M @ d0
		elev = math.degrees(math.acos(max(-1.0, min(1.0, -d.z))))
		fwd = -d.y
		shrug = 17.0 * _smooth(50.0, 165.0, elev)
		reach = 10.0 * max(0.0, fwd) * _smooth(25.0, 95.0, elev) - 6.0 * max(0.0, -fwd) * _smooth(15.0, 60.0, elev)
		c = (c0[0], c0[1] + shrug, c0[2] + reach)
		ua = _deg((_euler_m(c).inverted() @ M).to_euler("XYZ"))
		if side == "l":
			c, ua = mirror(c), mirror(ua)
		q["clavicle_" + side] = c
		q["upper_arm_" + side] = ua


def _skirt_angles(st, G):
	"""Constraint angles (degrees) of the hem panels for deformation matrices G, in the hips' rest
	frame: per leg sample the sagittal angle about the front / back hinges (minus / plus its
	clearance) and the lateral angle about its side hinge (plus clearance), the knees' sagittal
	angles about the side hinges, and the gravity angles."""
	rd = st["_rest"]
	s = st["s"]
	gap = 0.02 * s
	Hi = G["hips"].inverted()
	out = {"f": [], "b": [], "r": [], "l": [], "knee_r": 0.0, "knee_l": 0.0}
	Hf, Hb = rd["skirt_f"], rd["skirt_b"]
	for side in ("l", "r"):
		sx = 1.0 if side == "r" else -1.0
		Hs = rd["skirt_" + side]
		Hs_m = Vector((Hs.x * sx, Hs.y, Hs.z))
		for i, (bone, co, r, _w) in enumerate(rd["legs"][side]):
			Q = Hi @ (G[bone] @ co)
			for key, H, sign in (("f", Hf, -1.0), ("b", Hb, 1.0)):
				v = Q - H
				d = max(1e-4, math.hypot(v.y, v.z))
				a = math.degrees(math.atan2(v.y, -v.z))
				m = min(20.0, math.degrees(math.asin(min(1.0, (r + gap) / d))))
				out[key].append(a + sign * m)
			Qm = Vector((Q.x * sx, Q.y, Q.z))
			v = Qm - Hs_m
			d = max(1e-4, math.hypot(v.x, v.z))
			a = math.degrees(math.atan2(-v.x, -v.z))
			m = min(20.0, math.degrees(math.asin(min(1.0, (r + gap) / d))))
			out[side].append(a + m)
			if i == 1:
				vk = Q - Hs
				out["knee_" + side] = math.degrees(math.atan2(vk.y, -vk.z))
	g = Hi.to_3x3() @ Vector((0.0, 0.0, -1.0))
	g.normalize()
	out["g_sag"] = math.degrees(math.atan2(g.y, -g.z))
	out["g_lat"] = math.degrees(math.atan2(-g.x, -g.z))     # + = toward the character's right (-X)
	out["g_tilt"] = math.degrees(math.acos(max(-1.0, min(1.0, -g.z))))
	return out


def _skirts(st, q, G):
	"""The hem panels: gravity (60%, fading out when lying / rolling) and the legs' push, relative
	to the rest pose (the modelled cloth clears the legs at rest; keep that clearance)."""
	rd = st["_rest"]
	now = _skirt_angles(st, G)
	rest = rd["skirt_rest"]
	k = 0.6 * (1.0 - _smooth(40.0, 75.0, now["g_tilt"]))
	g_sag = k * max(-35.0, min(35.0, now["g_sag"]))
	g_lat = k * max(-30.0, min(30.0, now["g_lat"]))
	w = [e[3] for e in rd["legs"]["l"]] + [e[3] for e in rd["legs"]["r"]]
	# pushes: the front panel ahead of every leg sample (the min), the back panel behind them (the
	# max), weighted by the sample's importance; the cloth between them drags each panel 60% of the
	# way after the other one (a deep crouch or a curled roll closes the skirt around the thighs)
	pushes_f = [(a - a0) * wi for a, a0, wi in zip(now["f"], rest["f"], w)]
	pushes_b = [(a - a0) * wi for a, a0, wi in zip(now["b"], rest["b"], w)]
	pf, pb = min(pushes_f), max(pushes_b)
	xf = min(g_sag + 0.6 * max(0.0, pb), pf)
	xb = max(g_sag + 0.6 * min(0.0, pf), pb)
	xf = max(-85.0, min(35.0, xf))
	xb = max(-70.0, min(50.0, xb))
	q["skirt_f"] = (xf, 0.0, 0.0)
	q["skirt_b"] = (xb, 0.0, 0.0)
	ws = [e[3] for e in rd["legs"]["r"]]
	for side in ("r", "l"):
		sx = 1.0 if side == "r" else -1.0
		y = max([g_lat * sx] + [(a - a0) * wi for a, a0, wi in zip(now[side], rest[side], ws)])
		y = max(-25.0, min(60.0, y))
		x = 0.8 * (now["knee_" + side] - rest["knee_" + side]) + 0.2 * g_sag
		x = max(xf, min(xb, x))
		e = (x, y, 0.0)
		q["skirt_" + side] = e if side == "r" else mirror(e)


def _toes(st, q, G, ground):
	"""Toes bend up by as much as the foot pitches them below their rest slope while the ball is on
	(or within a few cm of) the ground; in the air, and while the body rolls, they follow the foot."""
	rd = st["_rest"]
	s = st["s"]
	root = q.get("root", (0.0, 0.0, 0.0))
	upright = all(abs(a) < 1e-3 for a in root)
	if upright and ground is None:
		ground = st["skin"].lowest(G, bones=FEET)
	for side in ("l", "r"):
		h0, t0 = rd["toe"][side]
		if not upright:
			q["toe_" + side] = (0.0, 0.0, 0.0)
			continue
		ball = G["foot_" + side] @ h0
		tip = G["foot_" + side] @ t0
		d = tip - ball
		pitch = math.degrees(math.atan2(-d.z, math.hypot(d.x, d.y)))
		r = t0 - h0
		pitch0 = math.degrees(math.atan2(-r.z, math.hypot(r.x, r.y)))
		lift = ball.z - h0.z - ground
		k = 1.0 - _smooth(0.012 * s, 0.06 * s, lift)
		q["toe_" + side] = (-max(0.0, pitch - pitch0) * k, 0.0, 0.0)


# ----------------------------------------------------------------------------------- feet / IK

def _chain_m(p, bones):
	M = Matrix.Identity(3)
	for b in bones:
		M = M @ _euler_m(p.get(b, (0.0, 0.0, 0.0)))
	return M


def _level_foot(p, side, psi):
	"""Foot rotation so the foot ends level in the world, pitched by psi (deg, + = toe down), pointing
	straight forward whatever the hips do."""
	D = _chain_m(p, ("root", "hips", "upper_leg_" + side, "lower_leg_" + side))
	W = Matrix.Rotation(math.radians(psi), 3, "X")
	p["foot_" + side] = _deg((D.inverted() @ W).to_euler("XYZ"))


def _ik_legs(st, body, targets, psi):
	"""Solve both legs of `body` (a pose without legs) to the ankle targets, feet level (pitch psi)."""
	G = fk(st["arm"], body)
	for side in ("l", "r"):
		(up, kn, _ft), _err = st["rig"].solve_leg_3d(G["hips"], side, targets[side], psi[side])
		body["upper_leg_" + side] = up
		body["lower_leg_" + side] = kn
		_level_foot(body, side, psi[side])
	return body


def _no_legs(p):
	return {k: v for k, v in p.items() if not k.startswith(LEG_KEYS)}


def _plant_targets(st, p, psi):
	"""Ankle targets that keep a pose's feet where they are, both soles on one floor."""
	G = fk(st["arm"], p)
	R = st["rig"]
	A = {side: G["foot_" + side] @ st["arm"].data.bones["foot_" + side].head_local for side in ("l", "r")}
	floor = min(A[side].z + R.lowest_rel(psi[side]) for side in ("l", "r"))
	for side in ("l", "r"):
		A[side].z = floor - R.lowest_rel(psi[side])
	return A


def _planted_loop(st, base, psi, layer, duration, step=2):
	"""A loop whose feet stay planted where `base` puts them: layer(phase) -> pose offsets (hips
	location included) added to base; the legs are solved every key."""
	targets = _plant_targets(st, base, psi)

	def fn(ph):
		p = _fin(st, add(base, layer(ph)), loco=True, carry=True)
		return _ik_legs(st, _no_legs(p), targets, psi)
	return sample(fn, duration, step=step)


def _stance_ankle(g, y_flat, psi):
	"""Ankle (y, z) of a planted foot whose flat-foot ankle is at y_flat, pitched by psi (deg): rolled
	about the heel's ground point (psi < 0) or about the ball JOINT (psi > 0: the toes stay put on
	the floor while the heel rises - no sliding of the toes)."""
	R = g["rig"]
	if psi <= 0.0:
		return R.stance_ankle(y_flat, psi)
	by, bz = g["_ball"]
	zf = -R.sole_z
	c, s = math.cos(math.radians(psi)), math.sin(math.radians(psi))
	return (y_flat + by - (by * c - bz * s), zf + bz - (by * s + bz * c))


def _foot(g, q, side):
	"""Ankle target, pitch and planted flag of one foot at gait phase q (0 = touchdown) - cc_anim's
	directional foot track, with the heel / toe pivot offset blended across the swing (no jump at
	lift-off and touchdown)."""
	R = g["rig"]
	s = g["s"]
	T = g["run_frames"] / FPS
	d = g["duty"]
	v = g["ground_speed"]
	D = v * d * T
	mx, my = g["walk_dir"]
	out = -1.0 if side == "r" else 1.0
	cx = R.ankle[side].x + out * g.get("stance_width", 0.0) * s
	shift = g["stance_shift"] * s
	hs, to, rs = g["strike"], g["toe_off"], g["roll_start"]
	if q < d:
		u = q / d
		off = D * (0.5 - u) - shift
		if u < 0.2:
			psi = hs * (1.0 - _smooth(0.0, 0.2, u))
		elif u > rs:
			psi = to * _smooth(rs, 1.0, u)
		else:
			psi = 0.0
		y, z = _stance_ankle(g, my * off, psi)
		return Vector((cx + mx * off, y, z)), psi, True
	u = (q - d) / (1.0 - d)
	mt = -v * (1.0 - d) * T * g["swing_match"]
	off = _hermite(-D * 0.5 - shift, D * 0.5 - shift, mt, mt, u)
	psi = to + (hs - to) * _smooth(0.1, 0.9, u)
	# the stance ends / starts pivoted (heel or ball): blend that offset in and out across the swing
	e0, e1 = _smooth(0.0, 0.4, u), _smooth(0.6, 1.0, u)
	y0, z0 = _stance_ankle(g, 0.0, to)
	y1, z1 = _stance_ankle(g, 0.0, hs)
	cy = y0 * (1.0 - e0) + y1 * e1
	cz = (z0 + R.lowest_rel(to)) * (1.0 - e0) + (z1 + R.lowest_rel(hs)) * e1
	lift = g["lift"] * s
	c = lift * math.sin(math.pi * (u ** g["lift_skew"])) ** g["lift_pow"]
	return Vector((cx + mx * off, my * off + cy, c - R.lowest_rel(psi) + cz)), psi, False


def _arms(g, s1):
	"""Arm layer of a gait: s1 = +1 when the right leg reaches forward (the left arm forward). The
	right hand carries the weapon (a small swing); running arms bend at the elbows."""
	sw = g["arm_swing"]
	f = g["female"]
	if g["arms"] == "run":
		return {"upper_arm_r": (-6 + 0.4 * sw * s1, 5 if f else 8, 0), "lower_arm_r": (-22 - 4 * s1, 0, 0),
			"hand_r": (95, 0, 0), "upper_arm_l": (-sw * s1, -4 if f else -6, 0), "lower_arm_l": (-38 + 8 * s1, 0, 0)}
	return {"upper_arm_r": (-10 + 0.3 * sw * s1, 5 if f else 6, 0), "lower_arm_r": (-6, 0, 0), "hand_r": (10, 0, 0),
		"upper_arm_l": (-sw * s1, -4 if f else -6, 0), "lower_arm_l": (-10 + 5 * s1, 0, 0)}


def _gait_upper(g, ph):
	"""Gait pose without legs (pelvis sway and twist, lean, counter-rotation, arms) and the two foot
	targets."""
	a = TAU * ph
	c1 = math.cos(a)
	mx, my = g["walk_dir"]
	run = g["arms"] == "run"
	fwd = abs(my)
	cs = math.cos(a - math.pi * g["duty"])     # +1 at the right foot's mid-stance
	sw = g["sway"] * cs
	tw = g["hip_twist"] * c1 * (-1.0 if my > 0.5 else 1.0)
	lean = g["lean"]
	p = pose(hips=(0, sw, tw), spine=(lean, -0.6 * sw, -(6.0 if run else 3.0) * c1 * fwd),
		chest=(0, -0.25 * sw, -(5.0 if run else 1.5) * c1 * fwd),
		neck=(-lean * 0.35, 0, (3.0 if run else 1.0) * c1 * fwd), head=(-lean * 0.35, 0.3 * sw, (2.0 if run else 1.0) * c1 * fwd))
	p = add(p, _loc(g, "hips", -g["sway_shift"] * cs, 0, 0))
	if abs(mx) > 0.5:
		# side steps: lean a little into the movement, a small sway toward the planted foot
		p = add(p, pose(spine=(0, -3.0 * mx, 0), hips=(0, 2.0 * mx * c1, 0)))
	p = add(p, _arms(g, c1 * fwd + 0.25 * c1 * abs(mx)))
	body = _fin(g, p, loco=True, carry=True)
	targets = {}
	for side, off in (("r", 0.0), ("l", 0.5)):
		targets[side] = _foot(g, (ph + off) % 1.0, side)
	return body, targets


def _bob_table(g):
	"""Hips height over the cycle (120 samples): crouch + bounce (lowest at mid-stance), limited so
	the planted legs reach their feet, smoothed (cc_anim._dir_bob for this gait)."""
	if g.get("_bob") is not None:
		return g["_bob"]
	R = g["rig"]
	s = g["s"]
	n = 120
	lim = []
	want = []
	for i in range(n):
		ph = i / n
		body, targets = _gait_upper(g, ph)
		G0 = fk(g["arm"], body)
		m = math.inf
		for side in ("l", "r"):
			t, _psi, planted = targets[side]
			if not planted:
				continue
			H = G0["hips"] @ R.hip[side]
			r = g["reach_k"] * R.leg
			h2 = r * r - (t.x - H.x) ** 2 - (t.y - H.y) ** 2
			m = min(m, t.z + math.sqrt(max(0.0, h2)) - H.z)
		lim.append(m)
		want.append((g["crouch"] - g["bounce"] * math.cos(2.0 * (TAU * ph - math.pi * g["duty"]))) * s)
	bob = [min(w, l) for w, l in zip(want, lim)]
	k = 6
	for _ in range(3):
		bob = [sum(bob[(i + j) % n] for j in range(-k, k + 1)) / (2 * k + 1) for i in range(n)]
	bob = [min(b, l) for b, l in zip(bob, lim)]
	g["_bob"] = bob
	return bob


def _gait_frame(g, ph):
	table = _bob_table(g)
	n = len(table)
	x = (ph % 1.0) * n
	i = int(x)
	fr = x - i
	bob = table[i % n] * (1.0 - fr) + table[(i + 1) % n] * fr
	body, targets = _gait_upper(g, ph)
	hl = body.get("loc:hips", (0.0, 0.0, 0.0))
	body["loc:hips"] = (hl[0], hl[1], hl[2] + bob)
	return _ik_legs(g, body, {k: v[0] for k, v in targets.items()}, {k: v[1] for k, v in targets.items()})


def _gait_style(st, name):
	g = dict(st)
	g["_bob"] = None
	f = st["female"]
	if name == "run":
		g.update(walk_dir=WALK_DIRS["run"], ground_speed=RUN_SPEED, arms="run")
		return g
	extra = {"walk": cc_anim.WALK_STYLE, "walk_back": cc_anim.WALK_BACK_STYLE,
		"walk_left": cc_anim.WALK_SIDE_STYLE, "walk_right": cc_anim.WALK_SIDE_STYLE}[name]
	g.update(extra)
	g.update(walk_dir=WALK_DIRS[name], ground_speed=WALK_SPEED, arms="walk")
	if f:
		g.update(arm_swing=g["arm_swing"] * 0.8, sway=3.0 if name == "walk" else 1.5, sway_shift=0.01)
	else:
		g.update(sway=1.2, sway_shift=0.004)
	return g


def gait(st, name):
	g = _gait_style(st, name)
	return sample(lambda ph: _gait_frame(g, ph), g["run_frames"] / FPS, step=1)


# ----------------------------------------------------------------------------------- stances / loops

def ready(st):
	"""The combat-ready stance every one-shot starts and ends in: feet apart, soft knees, the weapon
	hand low and forward, the off hand ready."""
	if st["female"]:
		return pose(upper_leg_s=(-7, 4.5, 0), lower_leg_s=(12, 0, 0), foot_s=(-5, -4.5, 0),
			spine=(3, 0, 0), chest=(0, 0, -4), neck=(0, 0, 2), head=(-1, 0, 2),
			upper_arm_r=(-10, 4, 0), hand_r=(8, 0, 0), upper_arm_l=(-5, -6, 0), lower_arm_l=(-6, 0, 0))
	return pose(upper_leg_s=(-9, 6, 0), lower_leg_s=(15, 0, 0), foot_s=(-6, -6, 0),
		spine=(4, 0, 0), chest=(0, 0, -4), neck=(0, 0, 2), head=(0, 0, 2),
		upper_arm_r=(-10, 6, 0), hand_r=(8, 0, 0), upper_arm_l=(-6, -8, 0), lower_arm_l=(-8, 0, 0))


def idle(st):
	"""Breathing (2 s). The warriors stand ready and grounded; the female exile rests her weight on the
	right leg (contrapposto: right hip up, left knee soft, heel lifted) and shifts it a little."""
	f = st["female"]
	if f:
		base = pose(hips=(0, 3, 2), spine=(1, -2, -1), chest=(0, -1.5, -2), neck=(0, 0, 1), head=(-2, 2, 3),
			upper_leg_r=(-3, 1.5, 0), lower_leg_r=(5, 0, 0), upper_leg_l=(-8, -5, 0), lower_leg_l=(12, 0, 0),
			upper_arm_r=(-8, 3, 0), lower_arm_r=(-2, 0, 0), hand_r=(8, 0, 0),
			upper_arm_l=(1, -4, 6), lower_arm_l=(12, 0, 0), hand_l=(6, 0, -5))
		psi = {"r": 0.0, "l": 6.0}
	else:
		base = ready(st)
		psi = {"r": 0.0, "l": 0.0}

	def layer(ph):
		b = math.sin(TAU * ph)
		c = math.cos(TAU * ph)
		p = pose(chest=(-1.8 * b, 0, 0), spine=(0.8 * b, 0, 0), neck=(0.8 * b, 0, 0), head=(1.2 * b, 0, 2.5 * math.sin(TAU * ph + 0.8)),
			upper_arm_r=(2.0 * math.sin(TAU * ph + 0.5), 1.5 * b, 0), upper_arm_l=(2.0 * math.sin(TAU * ph + 0.5), -1.5 * b, 0),
			lower_arm_s=(-2.0 * b, 0, 0))
		p = add(p, _loc(st, "hips", 0, 0, -0.009 * (1 - c)))
		if f:
			# weight settles further onto the right leg and back
			p = add(p, pose(hips=(0, 0.8 * (1 - c), 0), spine=(0, -0.5 * (1 - c), 0), head=(0, 0.4 * (1 - c), 0)),
				_loc(st, "hips", -0.006 * (1 - c), 0, 0))
		return p
	return _planted_loop(st, base, psi, layer, DURATION["idle"], step=2)


def channel(st):
	"""Arms out wide, low wide stance (whirlwind); the model is spun by code."""
	base = pose(upper_leg_s=(-18, 8, 0), lower_leg_s=(28, 0, 0), foot_s=(-10, -8, 0),
		spine=(10, 0, 0), chest=(-4, 0, 0), head=(-8, 0, 0),
		upper_arm_r=(-12, 78, 0), lower_arm_r=(22, 0, 0), hand_r=(55, 0, 0),
		upper_arm_l=(-12, -75, 0), lower_arm_l=(18, 0, 0), hand_l=(10, 0, 0))

	def layer(ph):
		c = math.cos(TAU * ph)
		b = math.sin(TAU * ph)
		return add(_loc(st, "hips", 0, 0, -0.015 + 0.015 * c), pose(upper_arm_s=(3 * b, 0, 0), chest=(0, 2 * b, 0)))
	st2 = dict(st, stabilize_left=False)
	return _planted_loop(st2, base, {"r": 0.0, "l": 0.0}, layer, DURATION["channel"], step=2)


GUARD_ARM_R = (-30, 0, 45)
GUARD_FOREARM_R = (-50, 0, 0)
GUARD_HAND_R = (60, -15, 30)


def _guard(st, r):
	"""The parry guard: a low stance, the blade raised diagonally across the body, the off hand forward."""
	return add(r, pose(spine=(10, 0, -10), chest=(-2, 0, -12), neck=(0, 0, 8), head=(-4, 0, 10),
		upper_arm_r=GUARD_ARM_R, lower_arm_r=GUARD_FOREARM_R, hand_r=GUARD_HAND_R,
		upper_arm_l=(-55, 0, 30), lower_arm_l=(-55, 0, 0),
		upper_leg_r=(-24, 6, 0), lower_leg_r=(36, 0, 0), foot_r=(-8, 0, 0),
		upper_leg_l=(-4, -6, 0), lower_leg_l=(26, 0, 0), foot_l=(-14, 0, 0)), _loc(st, "hips", 0, 0.02, -0.09))


def parry_hold(st):
	"""The guard held (loop, 1.0 s): breathing and shifting its weight a little, feet planted."""
	g = _guard(st, ready(st))

	def layer(ph):
		b = math.sin(TAU * ph)
		c = math.cos(TAU * ph)
		return add(pose(chest=(1.2 * b, 0, -1.0 * b), spine=(0.6 * b, 0, 0), upper_arm_r=(1.5 * b, 0, 0),
			upper_arm_l=(1.2 * c, 0, 0), head=(0.8 * b, 0, 0)), _loc(st, "hips", 0, 0, -0.008 * (1.0 - c)))
	return _planted_loop(st, g, {"r": 0.0, "l": 0.0}, layer, DURATION["parry_hold"], step=2)


# ----------------------------------------------------------------------------------- one-shots

def attack_slash(st):
	r = ready(st)
	wind = add(r, pose(spine=(-4, 0, -12), chest=(-4, 3, -30), neck=(0, 0, 14), head=(6, 0, 10),
		upper_arm_r=(-105, 0, -55), lower_arm_r=(-55, 0, 0), hand_r=(-10, 0, 0),
		upper_arm_l=(-35, 0, 30), lower_arm_l=(-35, 0, 0),
		upper_leg_r=(8, 4, 0), lower_leg_r=(14, 0, 0), upper_leg_l=(-14, -4, 0), lower_leg_l=(18, 0, 0)),
		_loc(st, "hips", 0, 0.03, -0.02))
	hitp = add(r, pose(spine=(12, 0, 8), chest=(6, -3, 22), neck=(0, 0, -10), head=(-4, 0, -8),
		upper_arm_r=(-78, 0, 28), lower_arm_r=(22, 0, 0), hand_r=(85, 0, 0),
		upper_arm_l=(10, 0, 10), lower_arm_l=(-45, 0, 0),
		upper_leg_r=(-26, 4, 0), lower_leg_r=(22, 0, 0), foot_r=(4, 0, 0), upper_leg_l=(14, -4, 0), lower_leg_l=(20, 0, 0)),
		_loc(st, "hips", 0, -0.06, -0.07))
	follow = add(r, pose(spine=(16, 0, 12), chest=(6, -4, 34), neck=(0, 0, -14), head=(-4, 0, -10),
		upper_arm_r=(-50, 0, 72), lower_arm_r=(-5, 0, 0), hand_r=(100, 0, 0),
		upper_arm_l=(22, 0, 8), lower_arm_l=(-50, 0, 0),
		upper_leg_r=(-28, 4, 0), lower_leg_r=(24, 0, 0), foot_r=(4, 0, 0), upper_leg_l=(16, -4, 0), lower_leg_l=(22, 0, 0)),
		_loc(st, "hips", 0, -0.07, -0.08))
	keys = [(0.0, r), (0.17, wind), (0.27, hitp), (0.36, follow), (0.46, lerp(follow, r, 0.45)), (0.6, r)]
	return _seq(st, keys)


# the slam's impact on whole frame 13 (0.433 s): the export bakes whole frames, so the weapon is
# already down at the 0.44 s hit frame
SLAM_IMPACT_FRAME = 13


def attack_slam(st):
	r = ready(st)
	lift = add(r, pose(spine=(-6, 0, 0), chest=(-8, 0, 0), head=(-6, 0, 0),
		upper_arm_r=(-120, 0, 18), lower_arm_r=(-40, 0, 0), hand_r=(-10, 0, 0),
		upper_arm_l=(-120, 0, -30), lower_arm_l=(-50, 0, 0), hand_l=(0, 0, 0)), _loc(st, "hips", 0, 0.01, 0.0))
	wind = add(r, pose(spine=(-14, 0, 0), chest=(-12, 0, 0), neck=(-4, 0, 0), head=(-10, 0, 0),
		upper_arm_r=(-168, 0, 15), lower_arm_r=(-35, 0, 0), hand_r=(-15, 0, 0),
		upper_arm_l=(-168, 0, -25), lower_arm_l=(-45, 0, 0),
		upper_leg_s=(-4, 4, 0), lower_leg_s=(6, 0, 0), foot_s=(8, 0, 0)), _loc(st, "hips", 0, 0.03, 0.04))
	impact = add(r, pose(spine=(28, 0, 0), chest=(14, 0, 0), neck=(-12, 0, 0), head=(-10, 0, 0),
		upper_arm_r=(-62, 0, 14), lower_arm_r=(30, 0, 0), hand_r=(80, 0, 0),
		upper_arm_l=(-58, 0, -30), lower_arm_l=(26, 0, 0), hand_l=(40, 0, 0),
		upper_leg_r=(-40, 6, 0), lower_leg_r=(62, 0, 0), foot_r=(-22, -6, 0),
		upper_leg_l=(-10, -6, 0), lower_leg_l=(44, 0, 0), foot_l=(-34, 6, 0)), _loc(st, "hips", 0, -0.02, -0.2))
	hold = add(impact, pose(spine=(2, 0, 0), upper_arm_s=(3, 0, 0)), _loc(st, "hips", 0, 0, -0.02))
	t_hit = SLAM_IMPACT_FRAME / FPS
	mid = [(f / FPS, lerp(impact, hold, _smooth(0.0, 1.0, (f - SLAM_IMPACT_FRAME) / 4.0))) for f in range(SLAM_IMPACT_FRAME + 1, SLAM_IMPACT_FRAME + 5)]
	keys = [(0.0, r), (0.16, lift), (0.32, wind), (t_hit, impact)] + mid + [(0.8, r)]
	return _seq(st, keys, stabilize_mid=False)   # two-handed: nothing in grip_l


def _maul_to_floor(st, p):
	"""Bend the right wrist (hand_r X) so the held reference maul's lowest point is level with the
	lowest foot vertex (the ground bake puts the feet on the floor): lifted when it would sink,
	lowered (up to 40 deg more) when it would hover."""
	arm, skin = st["arm"], st["skin"]
	h0 = p.get("hand_r", (0.0, 0.0, 0.0))

	def gap(x):
		q = dict(p)
		q["hand_r"] = (x, h0[1], h0[2])
		G = fk(arm, q)
		return cc_anim._held_lowest(st, G) - skin.lowest(G, bones=FEET_TOES), q
	g0, q0 = gap(h0[0])
	if abs(g0) < 1e-4:
		return q0
	# sinking: lift by straightening the wrist (lower X); hovering: flex it further (higher X)
	far = h0[0] - 120.0 if g0 < 0.0 else h0[0] + 40.0
	g1, q1 = gap(far)
	if (g1 < 0.0) == (g0 < 0.0):
		return q1          # cannot reach the floor: best effort
	a, b = h0[0], far
	q = q0
	for _ in range(30):
		mid = 0.5 * (a + b)
		g, q = gap(mid)
		if (g < 0.0) == (g0 < 0.0):
			a = mid
		else:
			b = mid
	return q


def _slam_floor(st, keys):
	"""The held maul's head rests on the floor from the impact to the end of the hold."""
	lo, hi = (SLAM_IMPACT_FRAME - 0.5) / FPS, (SLAM_IMPACT_FRAME + 4.5) / FPS
	return [(t, _maul_to_floor(st, p) if lo < t < hi else p) for t, p in keys]


def attack_stab(st):
	r = ready(st)
	draw = add(r, pose(spine=(-2, 0, -10), chest=(0, 0, -24), head=(0, 0, 18),
		upper_arm_r=(28, 10, 0), lower_arm_r=(-78, 0, 0), hand_r=(78, 0, 0),
		upper_arm_l=(-40, 0, 25), lower_arm_l=(-30, 0, 0),
		upper_leg_r=(6, 4, 0), upper_leg_l=(-14, -4, 0), lower_leg_l=(20, 0, 0)), _loc(st, "hips", 0, 0.04, -0.03))
	thrust = add(r, pose(spine=(16, 0, 10), chest=(4, 0, 18), head=(-10, 0, -16),
		upper_arm_r=(-84, 0, -20), lower_arm_r=(32, 0, 0), hand_r=(84, 0, 0),
		upper_arm_l=(22, 0, 12), lower_arm_l=(-40, 0, 0),
		upper_leg_r=(-40, 4, 0), lower_leg_r=(40, 0, 0), foot_r=(2, 0, 0),
		upper_leg_l=(22, -4, 0), lower_leg_l=(14, 0, 0), foot_l=(-10, 0, 0)), _loc(st, "hips", 0, -0.14, -0.09))
	reach = add(thrust, pose(spine=(2, 0, 2), chest=(1, 0, 3), upper_arm_r=(-3, 0, -2), lower_arm_r=(4, 0, 0)))
	# the blade is fully out at the hit (0.25 s = 50%)
	keys = [(0.0, r), (0.13, draw), (0.23, thrust), (0.27, reach), (0.34, lerp(thrust, r, 0.15)), (0.5, r)]
	return _seq(st, keys)


def shoot_bow(st):
	r = ready(st)
	body = pose(spine=(2, 0, 20), chest=(-2, 0, 28), neck=(0, 0, -24), head=(0, 0, -22),
		upper_leg_r=(-10, 6, 0), upper_leg_l=(8, -8, 0), lower_leg_s=(10, 0, 0))
	raise_ = add(r, body, pose(upper_arm_r=(-82, 0, -40), lower_arm_r=(30, 0, 0), hand_r=(6, 0, 0),
		upper_arm_l=(-80, 0, -52), lower_arm_l=(-30, 0, 0), hand_l=(0, 0, 0)))
	draw = add(r, body, pose(upper_arm_r=(-88, 0, -46), lower_arm_r=(36, 0, 0), hand_r=(4, 0, 0),
		upper_arm_l=(-86, 0, 30), lower_arm_l=(-135, 0, 0), hand_l=(10, 0, 0), chest=(-3, 0, 4)))
	release = add(r, body, pose(upper_arm_r=(-86, 0, -44), lower_arm_r=(36, 0, 0), hand_r=(4, 0, 0),
		upper_arm_l=(-78, 0, 60), lower_arm_l=(-100, 0, 0), hand_l=(-20, 0, 0), chest=(-5, 0, 8)))
	# loose at the hit (0.42 s = 60%)
	keys = [(0.0, r), (0.15, raise_), (0.34, draw), (0.4, draw), (0.435, release), (0.56, lerp(release, r, 0.25)), (0.7, r)]
	return _seq(st, keys, stabilize_mid=False)   # two-handed: nothing in grip_l


def shoot_crossbow(st):
	r = ready(st)
	aim = add(r, pose(spine=(4, 0, -15), chest=(0, 0, -20), neck=(4, 0, 18), head=(6, 0, 16),
		upper_arm_r=(-36, 0, 21), lower_arm_r=(-16, 0, 14), hand_r=(90, 0, 0),
		upper_arm_l=(-58, 0, -26), lower_arm_l=(40, 0, 0), hand_l=(30, 0, 0),
		upper_leg_r=(6, 5, 0), upper_leg_l=(-14, -5, 0), lower_leg_l=(18, 0, 0)))
	kick = add(aim, pose(spine=(-6, 0, 0), chest=(-4, 0, 0), head=(-4, 0, 0), upper_arm_r=(14, 0, 0), upper_arm_l=(12, 0, 0),
		hand_r=(-10, 0, 0)), _loc(st, "hips", 0, 0.04, 0.0))
	# the bolt leaves at the hit (0.24 s = 40%)
	keys = [(0.0, r), (0.13, aim), (0.215, aim), (0.25, kick), (0.35, aim), (0.6, r)]
	return _seq(st, keys, stabilize_mid=False)   # two-handed: nothing in grip_l


def cast(st):
	r = ready(st)
	gather = add(r, pose(spine=(-3, 0, -10), chest=(-4, 0, -18), head=(0, 0, 12),
		upper_arm_r=(-20, 25, 0), lower_arm_r=(-85, 0, 0), hand_r=(-15, 0, 0),
		upper_arm_l=(-45, 0, 25), lower_arm_l=(-50, 0, 0),
		upper_leg_r=(6, 4, 0), upper_leg_l=(-12, -4, 0), lower_leg_l=(16, 0, 0)), _loc(st, "hips", 0, 0.03, -0.01))
	push = add(r, pose(spine=(12, 0, 8), chest=(4, 0, 14), head=(-8, 0, -10),
		upper_arm_r=(-84, 0, -14), lower_arm_r=(30, 0, 0), hand_r=(70, 0, 0),
		upper_arm_l=(25, 0, 15), lower_arm_l=(-35, 0, 0),
		upper_leg_r=(-24, 4, 0), lower_leg_r=(20, 0, 0), upper_leg_l=(14, -4, 0), lower_leg_l=(16, 0, 0)),
		_loc(st, "hips", 0, -0.06, -0.05))
	keys = [(0.0, r), (0.18, gather), (0.3, push), (0.4, lerp(push, r, 0.1)), (0.6, r)]
	return _seq(st, keys)


def cast_area(st):
	r = ready(st)
	up = add(r, pose(spine=(-12, 0, 0), chest=(-8, 0, 0), neck=(-8, 0, 0), head=(-14, 0, 0),
		upper_arm_r=(-150, 22, 0), lower_arm_r=(-10, 0, 0), hand_r=(100, 0, 0),
		upper_arm_l=(-150, -22, 0), lower_arm_l=(-10, 0, 0),
		upper_leg_s=(-2, 4, 0), foot_s=(10, 0, 0)), _loc(st, "hips", 0, 0.02, 0.04))
	down = add(r, pose(spine=(22, 0, 0), chest=(8, 0, 0), neck=(-10, 0, 0), head=(-8, 0, 0),
		upper_arm_r=(-28, 48, 0), lower_arm_r=(22, 0, 0), hand_r=(30, 0, 0),
		upper_arm_l=(-28, -48, 0), lower_arm_l=(22, 0, 0), hand_l=(10, 0, 0),
		upper_leg_s=(-34, 10, 0), lower_leg_s=(58, 0, 0), foot_s=(-24, -10, 0)), _loc(st, "hips", 0, -0.02, -0.18))
	keys = [(0.0, r), (0.24, up), (0.385, down), (0.5, add(down, pose(spine=(2, 0, 0)))), (0.7, r)]
	return _seq(st, keys)


def hit(st):
	r = ready(st)
	fl = add(r, pose(spine=(-14, 4, -6), chest=(-10, 0, 0), neck=(-6, 0, 0), head=(-14, 6, 0),
		upper_arm_r=(18, 12, 0), upper_arm_l=(14, -16, 0), lower_arm_s=(-20, 0, 0),
		upper_leg_s=(-10, 0, 0), lower_leg_s=(16, 0, 0)), _loc(st, "hips", 0, 0.06, -0.03))
	keys = [(0.0, r), (0.07, fl), (0.16, lerp(fl, r, 0.45)), (0.3, r)]
	return _seq(st, keys, loco=True)


def parry(st):
	"""Guard (0.55 s): snap into a low stance with the blade raised across the body and the off hand
	forward, hold it (a slight tremble), settle back."""
	r = ready(st)
	guard = _guard(st, r)
	hold = add(guard, pose(chest=(1.5, 0, -1.5), upper_arm_r=(2, 0, 0), upper_arm_l=(2, 0, 0)))
	keys = [(0.0, r), (0.07, guard), (0.25, hold), (0.42, guard), (0.55, r)]
	return _seq(st, keys)


def die(st):
	"""Hit, buckle at the knees, fall on the back (1.0 s); the corpse rests on the floor."""
	r = ready(st)
	s = st["s"]
	fl = add(r, pose(spine=(-16, 0, -8), chest=(-10, 0, 0), head=(-20, 0, 0),
		upper_arm_r=(20, 20, 0), upper_arm_l=(15, -25, 0), lower_arm_s=(-25, 0, 0)), _loc(st, "hips", 0, 0.05, -0.02))
	buckle = add(r, pose(spine=(24, 0, 6), chest=(10, 0, 0), neck=(12, 0, 0), head=(18, 8, 0),
		upper_arm_r=(-10, 18, 0), upper_arm_l=(-5, -14, 0), lower_arm_s=(-20, 0, 0), hand_s=(20, 0, 0),
		upper_leg_s=(-50, 8, 0), lower_leg_s=(85, 0, 0), foot_s=(-30, 0, 0)), _loc(st, "hips", 0, 0.08, -0.36))
	lying = pose(spine=(-4, 0, 0), chest=(-4, 0, 0), neck=(-6, 0, 0), head=(-10, 0, 35),
		upper_arm_r=(16, 74, 0), lower_arm_r=(38, 0, 0), upper_arm_l=(18, -62, 0), lower_arm_l=(36, 0, 0),
		upper_leg_r=(-35, 12, 0), lower_leg_r=(55, 0, 0), foot_r=(20, 0, 0),
		upper_leg_l=(-8, -8, 0), lower_leg_l=(12, 0, 0), foot_l=(25, 0, 0))
	# the weapon on grip_r lies flat pointing away from the body, a shield / focus face up beside the arm
	lying["hand_r"] = (90, 0, -15)
	lying["hand_l"] = (-60, 0, -60)
	# nearly straight legs for every look: any look can wear a long robe / coat / tabard, whose hem
	# panels follow the thighs (a raised knee would tent a long robe up into the air)
	lying.update(pose(upper_leg_r=(-6, 6, 0), lower_leg_r=(10, 0, 0), foot_r=(20, 0, 0),
		upper_leg_l=(-3, -5, 0), lower_leg_l=(6, 0, 0), foot_l=(24, 0, 0)))
	thick = 0.13
	fall = add(lying, {"root": (-90, 0, 0), "loc:root": (0, 0.05 * s, thick * s)})
	bounce = add(fall, {"root": (8, 0, 0), "loc:root": (0, 0, 0.02 * s)}, pose(head=(8, 0, 0), upper_arm_s=(10, 0, 0)))
	mid = add(lerp(buckle, lying, 0.4), {"root": (-45, 0, 0), "loc:root": (0, 0.0, 0.04 * s)})
	keys = [(0.0, r), (0.1, fl), (0.3, buckle), (0.48, mid), (0.64, fall), (0.74, bounce), (0.86, fall), (1.0, fall)]
	return [(t, _fin(st, p, carry=True) if t == 0.0 else p) for t, p in keys]


def _die_floor(st, keys):
	return _floor_keys(st, keys, feet_until=0.3, rest_from=0.64, lift={0.74: 0.02 * st["s"]})


def dodge(st):
	"""Forward roll in place, 0.55 s: a quick tumble in the first 40% (the game moves the player fast
	and decelerates: 1 - (1 - u)^3 of the 5 m), then a slower rise back to the stance."""
	r = ready(st)
	s = st["s"]
	curl = pose(spine=(55, 0, 0), chest=(25, 0, 0), neck=(25, 0, 0), head=(20, 0, 0),
		upper_arm_s=(-60, 10, 0), lower_arm_s=(-70, 0, 0),
		upper_leg_s=(-105, 6, 0), lower_leg_s=(125, 0, 0), foot_s=(20, 0, 0))
	pivot = 0.56 * s

	def rolled(deg, drop):
		rot = Euler((math.radians(deg), 0, 0), "XYZ").to_matrix()
		c = Vector((0, 0, pivot))
		off = c - rot @ c
		return add(curl, {"root": (deg, 0, 0), "loc:root": (off.x, off.y, off.z)}, _loc(st, "hips", 0, 0, drop))
	crouch = add(r, pose(spine=(35, 0, 0), chest=(10, 0, 0), head=(10, 0, 0), upper_arm_s=(-50, 8, 0), lower_arm_s=(-40, 0, 0),
		upper_leg_s=(-60, 6, 0), lower_leg_s=(90, 0, 0), foot_s=(-30, 0, 0)), _loc(st, "hips", 0, 0, -0.32))
	rise = add(crouch, pose(spine=(-10, 0, 0)))
	keys = [(0.0, r), (0.035, crouch), (0.075, rolled(60, -0.3)), (0.12, rolled(150, -0.3)), (0.165, rolled(240, -0.3)),
		(0.215, rolled(320, -0.3)), (0.3, rise), (0.42, lerp(rise, r, 0.6)), (0.55, r)]
	return _seq(st, keys, stabilize_mid=False)


def _dodge_floor(st, keys):
	# feet on the floor when upright (crouch / stand), never below it while rolling
	return _floor_keys(st, keys, feet_until=0.55, rest_from=9.0, upright_only=True)


BUILDERS = {"idle": idle, "channel": channel, "parry_hold": parry_hold, "attack_slash": attack_slash,
	"attack_slam": attack_slam, "attack_stab": attack_stab, "shoot_bow": shoot_bow, "shoot_crossbow": shoot_crossbow,
	"cast": cast, "cast_area": cast_area, "hit": hit, "parry": parry, "die": die, "dodge": dodge}
# applied after finish(): floor contact needs the finished skirts / toes
POST = {"attack_slam": _slam_floor, "die": _die_floor, "dodge": _dodge_floor}


# ----------------------------------------------------------------------------------- build

def build_actions(arm, L):
	"""Key every action on `arm` (L = the pl_body.Look it was built for), ground baked. Returns the
	action names (ANIMS)."""
	skin = Skin(arm, base_parts(L))
	st = make_style(arm, L, skin)
	for name in ANIMS:
		if name in GAITS:
			keys = gait(st, name)
			ground = 0.0
		else:
			keys = BUILDERS[name](st)
			ground = None
		keys = [(t, finish(st, p, ground)) for t, p in keys]
		if name in POST:
			keys = POST[name](st, keys)
		act = cc_rig.key_action(arm, name, keys)
		if name in NO_GROUND:
			cc_ground.bake_ground(arm, act, skin, bones=None, lift_only=True)
		else:
			cc_ground.bake_ground(arm, act, skin, bones=FEET_TOES, loop=name in LOOPS, soft=0.06 if name in GAITS else 0.0)
	arm.animation_data.action = None
	cc_rig.reset_pose(arm)
	report(arm, L, skin)
	return list(ANIMS)


def planted_speed(arm, act, direction, rate=60):
	"""Planted-foot ground speed (m/s) along `direction` (armature ground plane, unit (x, y)): samples
	where the ankle is within 2 cm of its lowest height, mean velocity component. {side: (speed, n)}."""
	curves = cc_ground._curves(arm, act)
	n = cc_ground.frame_count(act)
	dur = n / FPS
	steps = int(round(dur * rate))
	dt = dur / steps
	dx, dy = direction
	res = {}
	for side in ("l", "r"):
		bone = "foot_" + side
		head = arm.data.bones[bone].head_local
		ank = []
		for k in range(steps + 1):
			rots, locs = cc_ground.eval_linear(arm, curves, k / steps * n)
			ank.append(cc_rig.fk_basis(arm, rots, locs)[bone] @ head)
		zmin = min(a.z for a in ank)
		tot, cnt = 0.0, 0
		for k in range(1, steps + 1):
			if ank[k].z < zmin + 0.02 and ank[k - 1].z < zmin + 0.02:
				tot += ((ank[k].x - ank[k - 1].x) * dx + (ank[k].y - ank[k - 1].y) * dy) / dt
				cnt += 1
		res[side] = (tot / max(1, cnt), cnt)
	return res


def sole_speed(arm, act, skin, side, direction, rate=60, tol=0.004):
	"""Speed (m/s) along `direction` of the sole vertices touching the floor (z < tol) at two
	consecutive samples: the true planted speed (no sliding = the ground speed)."""
	curves = cc_ground._curves(arm, act)
	n = cc_ground.frame_count(act)
	dur = n / FPS
	steps = int(round(dur * rate))
	dt = dur / steps
	dx, dy = direction
	bones = ("foot_" + side, "toe_" + side)
	prev = None
	tot, cnt = 0.0, 0
	for k in range(steps + 1):
		rots, locs = cc_ground.eval_linear(arm, curves, k / steps * n)
		cur = skin.posed(cc_rig.fk_basis(arm, rots, locs), bones=bones)
		if prev is not None:
			for a, b in zip(prev, cur):
				if a.z < tol and b.z < tol:
					tot += ((b.x - a.x) * dx + (b.y - a.y) * dy) / dt
					cnt += 1
		prev = cur
	return tot / max(1, cnt), cnt


def report(arm, L, skin):
	"""Print length / hit frame per action, planted-foot speeds of the gaits, floor contact."""
	for name in ANIMS:
		act = bpy.data.actions[name]
		n = cc_ground.frame_count(act)
		d = n / FPS
		msg = "[anim] %s %-14s %.3fs %2d frames%s" % (L.look, name, d, n, " loop" if name in LOOPS else "")
		if name in HIT_FRAME:
			msg += "  hit %.3fs (%.0f%%)" % (HIT_FRAME[name] * d, HIT_FRAME[name] * 100)
		if name in GAITS:
			mx, my = WALK_DIRS[name]
			sp = planted_speed(arm, act, (-mx, -my))
			so = [sole_speed(arm, act, skin, side, (-mx, -my)) for side in ("r", "l")]
			msg += "  planted (ankle) r %.2f l %.2f, sole r %.2f l %.2f m/s (ref %.2f)" % (sp["r"][0], sp["l"][0], so[0][0], so[1][0],
				RUN_SPEED if name == "run" else WALK_SPEED)
		if name not in NO_GROUND:
			lo, hi = cc_ground.contact_range(arm, act, skin, bones=FEET_TOES)
			msg += "  feet %.3f..%.3f" % (lo, hi)
		print(msg)
	act = bpy.data.actions["die"]
	G = cc_ground.action_G(arm, act, cc_ground.frame_count(act) / FPS)
	print("[anim] %s die end: lowest %.3f core %.3f" % (L.look, skin.lowest(G), skin.lowest(G, bones=cc_ground.CORE)))
	act = bpy.data.actions["attack_slam"]
	st = {"arm": arm, "slam_held": _item_vertices("weapon_maul")}
	lows = [cc_anim._held_lowest(st, cc_ground.action_G(arm, act, f / FPS)) for f in range(SLAM_IMPACT_FRAME, SLAM_IMPACT_FRAME + 6)]
	print("[anim] %s attack_slam held maul lowest, frames %d-%d: %s" % (L.look, SLAM_IMPACT_FRAME, SLAM_IMPACT_FRAME + 5,
		" ".join("%.3f" % v for v in lows)))


# ----------------------------------------------------------------------------------- previews

def preview(arm, L, out_dir):
	"""Contact sheets of every action (<look>_anim_<name>.png: six moments, first from the side, then
	from the high game camera; one-shots around the hit frame) with held items pinned like Godot's
	BoneAttachment3D (build_all.py's preview weapons); gear parts hidden. PL_ANIM_PREVIEW_SIZE sets
	the tile size (default 300 px)."""
	import cc_items
	import cc_preview
	os.makedirs(out_dir, exist_ok=True)
	hidden = []
	for ob in arm.children:
		if ob.type == "MESH" and ob.name.startswith(GEAR_PREFIXES) and not ob.hide_render:
			ob.hide_render = True
			hidden.append(ob)
	groups = {}
	for a in ANIMS:
		groups.setdefault(PREVIEW_HELD.get(a, ("weapon_sword", "offhand_shield")), []).append(a)
	for (main, off), group in groups.items():
		objs = []
		if main:
			objs.append(cc_preview.attach(arm, cc_items.ITEMS[main], "grip_r", "PrevMain"))
		if off:
			objs.append(cc_preview.attach(arm, cc_items.ITEMS[off], "chest" if off == "offhand_quiver" else "grip_l", "PrevOff"))
		for a in group:
			d = cc_ground.frame_count(bpy.data.actions[a]) / FPS
			if a in HIT_FRAME:
				hf = HIT_FRAME[a] * d
				ts = sorted(set([0.0, round(d * 0.25, 3), round(hf * 0.8, 3), round(hf, 3), round(hf + d * 0.12, 3), round(d * 0.8, 3)]))
			else:
				ts = [d * f for f in (0.0, 0.15, 0.3, 0.45, 0.6, 0.8)]
			# a lying / rolling body needs the wider frame
			wide = a in ("die", "dodge")
			o, z = (2.3, 0.75) if wide else (2.0, 0.9)
			frames = [(a, t, -35.0, 12.0, o, z) for t in ts] + [(a, t, -60.0, 56.0, o, z) for t in ts]
			# 3 columns: two rows of side views, two rows from the high game camera
			cc_preview.contact_sheet(arm, frames, os.path.join(out_dir, "%s_anim_%s.png" % (L.look, a)), cols=3,
				size=int(os.environ.get("PL_ANIM_PREVIEW_SIZE", "300")))
		for pair in objs:
			for o in pair or []:
				bpy.data.objects.remove(o)
	for ob in hidden:
		ob.hide_render = False
	arm.animation_data.action = None
