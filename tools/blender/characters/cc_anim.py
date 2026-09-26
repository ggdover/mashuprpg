"""Animation set for the humanoid rig (docs/ARCHITECTURE.md §14.3).

Every function returns a list of (time_seconds, pose) keys (see cc_rig for pose conventions).
A character `style` dict tunes the set:
  s          character scale (location offsets are multiplied by it)
  base       pose added to EVERY key (posture: hunch, bent knees, ...)
  loco       pose added to idle/run/hit/channel keys only (e.g. zombie arms raised forward)
  arm_swing  run: arm swing amplitude (deg)         lean   run: forward lean (deg)
  weapon     True = right hand carries a weapon     heavy  0..1 heavier look
  run_arms   'swing' | 'forward' (zombie) | 'claw' (ghoul) | 'still' (floating caster)
  hover      float height (m) for hovering characters (legs dangle, no stepping; run = glide)
  limp       0..1 zombie drag of the left leg        robe   True: robe skirt (legs straight in death)
  IK run (walking characters; the build adds rig = cc_ground.RigInfo, arm, skin):
  run_frames loop length in 30 fps frames (cadence at the character's real speed)
  duty       fraction of the cycle each foot is planted (> 0.5: always one foot down)
  crouch, bounce   hips height offset / bob (m, before scale; lowest at mid-stance)
  strike, toe_off  foot pitch at touchdown / lift-off (deg, + = toe down)
  lift, lift_pow, lift_skew, swing_match, stance_shift, reach_k, hip_twist, drag_pitch: swing shape
  Planted feet move backward at exactly REF_RUN_SPEED (5.2 m/s) for EVERY walking character, so
  consumers play run at speed_scale = move_speed / 5.2.
  slam_floor / slam_held / slam_hand / slam_wind_hand: attack_slam weapon on the floor at the hit
  die_pose   per-character corpse overrides (the lich lays its staff down, the gravebreaker its maul)
Durations and hit frames follow §14.3 exactly:
  idle 2.0 loop, run loop (run_frames, 0.37-0.6 s), attack_slash 0.6 (hit 0.45),
  attack_slam 0.8 (0.55), attack_stab 0.5 (0.45), shoot_bow 0.7 (0.6), shoot_crossbow 0.6 (0.4),
  cast 0.6 (0.5), cast_area 0.7 (0.55), channel 1.0 loop, hit 0.3, die 1.0, dodge 0.4, roar 1.2.
The build then bakes a per-frame vertical root correction (cc_ground.bake_ground): feet on y = 0 in
every animation except die / dodge (which stay above the floor, corpses resting on it).
"""
import math

from cc_rig import FPS, add, fk, lerp, mirror, pose, sample, scale, sym

REF_RUN_SPEED = 5.2   # m/s: planted-foot speed of every walking character's run (speed_scale = v / 5.2)

HUMANOID_ANIMS = ["idle", "run", "attack_slash", "attack_slam", "attack_stab", "shoot_bow", "shoot_crossbow",
	"cast", "cast_area", "channel", "hit", "die", "dodge"]
BOSS_ANIMS = HUMANOID_ANIMS + ["roar"]
MERCHANT_ANIMS = ["idle", "talk"]

DURATION = {"idle": 2.0, "run": 0.6, "attack_slash": 0.6, "attack_slam": 0.8, "attack_stab": 0.5,
	"shoot_bow": 0.7, "shoot_crossbow": 0.6, "cast": 0.6, "cast_area": 0.7, "channel": 1.0, "hit": 0.3,
	"die": 1.0, "dodge": 0.4, "roar": 1.2, "talk": 2.4}
HIT_FRAME = {"attack_slash": 0.45, "attack_slam": 0.55, "attack_stab": 0.45, "shoot_bow": 0.6,
	"shoot_crossbow": 0.4, "cast": 0.5, "cast_area": 0.55}

DEFAULT_STYLE = dict(s=1.0, base={}, loco={}, arm_swing=32.0, lean=12.0, bounce=0.02,
	weapon=True, run_arms="swing", hover=0.0, heavy=0.0, limp=0.0, robe=False,
	# IK run (walking characters; the build puts a cc_ground.RigInfo into style["rig"]):
	run_frames=18, duty=0.3, crouch=-0.085, reach_k=0.975, stance_shift=0.1, strike=8.0, toe_off=35.0,
	roll_start=0.55, lift=0.22, lift_pow=3.0, lift_skew=0.8, swing_match=0.7, drag_pitch=25.0, hip_twist=7.0)

TAU = 2.0 * math.pi


def _st(style):
	st = dict(DEFAULT_STYLE)
	st.update(style or {})
	return st


def _loc(st, bone, x, y, z):
	s = st["s"]
	return {"loc:" + bone: (x * s, y * s, z * s)}


ARM_L = ("upper_arm_l", "lower_arm_l", "hand_l")
ARM_R = ("upper_arm_r", "lower_arm_r", "hand_r")


def _fin(st, p, loco=False, carry=False, base_w=1.0, stabilize=True):
	"""Apply the style's base (+ loco) layers, arm holds and the hover offset.
	hold_left: pose for the left arm kept in every animation (e.g. the lich's staff hand).
	carry: pose for the right arm in idle/run (e.g. a maul resting on the shoulder)."""
	layers = [p, scale(st["base"], base_w) if base_w != 1.0 else st["base"]]
	if loco:
		layers.append(st["loco"])
	out = add(*layers)
	if st.get("hold_left"):
		for b in ARM_L:
			out[b] = add({b: st["hold_left"].get(b, (0.0, 0.0, 0.0))}, {b: p.get(b, (0.0, 0.0, 0.0))}, w=[1.0, 0.25])[b]
	if carry and st.get("carry"):
		for b in ARM_R:
			out[b] = add({b: st["carry"].get(b, (0.0, 0.0, 0.0))}, {b: p.get(b, (0.0, 0.0, 0.0))}, w=[1.0, 0.15])[b]
	if stabilize and st.get("stabilize_left"):
		# Keep grip_l (shield / focus) roughly upright: undo the forward/back tilt the spine and the
		# left arm give the hand (valid for small Y/Z rotations; skipped when the root rotates).
		tilt = sum(out.get(b, (0.0, 0.0, 0.0))[0] for b in ("hips", "spine", "chest", "upper_arm_l", "lower_arm_l"))
		h = out.get("hand_l", (0.0, 0.0, 0.0))
		out["hand_l"] = (-tilt * 0.85 + h[0] * 0.3, h[1], h[2])
	if st["hover"] > 0.0:
		out = add(out, _loc(st, "root", 0, 0, st["hover"]))
	return out


def _seq(st, keys, loco=False, stabilize_mid=True):
	"""Finish a one-shot: the first and last keys use the carry pose so idle -> action -> idle is seamless."""
	n = len(keys)
	out = []
	for i, (t, p) in enumerate(keys):
		edge = i == 0 or i == n - 1
		# action_base < 1 relaxes a strong posture (ghoul hunch) during the action's middle keys.
		out.append((t, _fin(st, p, loco=loco, carry=edge, base_w=1.0 if edge else st.get("action_base", 1.0),
			stabilize=edge or stabilize_mid)))
	return out


# ----------------------------------------------------------------------------------- stances

def stance(st):
	"""Relaxed ready stance (idle phase 0 without breathing)."""
	p = pose(upper_leg_s=(-9, 6, 0), lower_leg_s=(15, 0, 0), foot_s=(-6, -6, 0),
		spine=(4, 0, 0), chest=(0, 0, -4), neck=(0, 0, 2), head=(0, 0, 2),
		upper_arm_r=(-10, 6, 0), hand_r=(8, 0, 0), upper_arm_l=(-6, -8, 0), lower_arm_l=(-8, 0, 0))
	if st["hover"] > 0.0:
		p = pose(upper_leg_s=(-12, 3, 0), lower_leg_s=(24, 0, 0), foot_s=(18, 0, 0), spine=(4, 0, 0))
	p = add(p, _loc(st, "hips", 0, 0, -0.025 if st["hover"] <= 0 else 0.0))
	return p


def ready(st):
	return _fin(st, stance(st), loco=False)


# ----------------------------------------------------------------------------------- loops

def idle(style):
	st = _st(style)

	def fn(ph):
		b = math.sin(TAU * ph)
		c = math.cos(TAU * ph)
		p = stance(st)
		breath = pose(chest=(-1.8 * b, 0, 0), spine=(0.8 * b, 0, 0), neck=(0.8 * b, 0, 0), head=(1.2 * b, 0, 2.5 * math.sin(TAU * ph + 0.8)),
			upper_arm_r=(2.0 * math.sin(TAU * ph + 0.5), 1.5 * b, 0), upper_arm_l=(2.0 * math.sin(TAU * ph + 0.5), -1.5 * b, 0),
			lower_arm_s=(-2.0 * b, 0, 0))
		p = add(p, breath, _loc(st, "hips", 0, 0, -0.006 * (1 - c)))
		if st["hover"] > 0.0:
			p = add(p, _loc(st, "root", 0, 0, 0.06 * b), pose(upper_leg_s=(3 * c, 0, 0), lower_leg_s=(-4 * c, 0, 0)))
		return _fin(st, p, loco=True, carry=True)
	return sample(fn, DURATION["idle"], step=2)


def _run_arms(st, s1):
	"""Upper-body arm layer of the run; s1 = +1 when the right leg reaches forward (left arm forward)."""
	arm = st["arm_swing"]
	mode = st["run_arms"]
	if mode == "swing":
		ar = (arm * s1, 6, 0)
		al = (-arm * s1, -6, 0)
		lr = (-38 - 8 * s1, 0, 0)
		hr = (0, 0, 0)
		if st["weapon"]:
			ar = (-6 + 0.4 * arm * s1, 8, 0)
			lr = (-22 - 4 * s1, 0, 0)
			hr = (95, 0, 0)
		return {"upper_arm_r": ar, "upper_arm_l": al, "hand_r": hr, "lower_arm_r": lr, "lower_arm_l": (-38 + 8 * s1, 0, 0)}
	if mode == "forward":
		return pose(upper_arm_r=(-4 * s1, 0, 2 * s1), upper_arm_l=(4 * s1, 0, 2 * s1))
	if mode == "claw":
		return {"upper_arm_r": (arm * s1, 10, 0), "upper_arm_l": (-arm * s1, -10, 0),
			"lower_arm_r": (-20 - 15 * max(0, -s1), 0, 0), "lower_arm_l": (-20 - 15 * max(0, s1), 0, 0)}
	if mode == "still":
		return pose(upper_arm_s=(10, 14, 0), lower_arm_s=(-20, 0, 0))
	return {}


def _smooth(e0, e1, x):
	t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
	return t * t * (3.0 - 2.0 * t)


def _hermite(p0, p1, m0, m1, u):
	u2 = u * u
	u3 = u2 * u
	return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1


def run_length(style):
	"""Length (s) of the run loop: a whole number of frames (style run_frames, default 18 = 0.6 s)."""
	return _st(style)["run_frames"] / FPS


def _foot_track(st, q, side):
	"""Ankle (y, z) in armature space (character faces -Y), foot pitch (deg, + = toe down) and
	whether the foot is planted, for one foot at gait phase q (0 = touchdown). Stance (q < duty): the
	foot lands on its forefoot (strike > 0) or heel (strike < 0), rolls flat, then onto the toe; its
	ground contact point moves backward at exactly REF_RUN_SPEED. Swing: Hermite curve that leaves and
	lands with (swing_match x) the ground speed, lifted by a bump that is flat at both ends."""
	R = st["rig"]
	s = st["s"]
	T = st["run_frames"] / FPS
	d = st["duty"]
	D = REF_RUN_SPEED * d * T
	limp = st["limp"] if side == "l" else 0.0
	y0 = -D * 0.5 + st["stance_shift"] * s
	hs = st["strike"]
	to = st["toe_off"] * (1.0 - 0.6 * limp)
	rs = st["roll_start"]
	if q < d:
		u = q / d
		if u < 0.2:
			psi = hs * (1.0 - _smooth(0.0, 0.2, u))
		elif u > rs:
			psi = to * _smooth(rs, 1.0, u)
		else:
			psi = 0.0
		y, z = R.stance_ankle(y0 + D * u, psi)
		return y, z, psi, True
	u = (q - d) / (1.0 - d)
	m = REF_RUN_SPEED * (1.0 - d) * T * st["swing_match"]
	y1, _z1 = R.stance_ankle(y0 + D, to)
	ya, _za = R.stance_ankle(y0, hs)
	y = _hermite(y1, ya, m, m, u)
	drag = st["drag_pitch"] * limp
	psi = to + (hs - to) * _smooth(0.1, 0.9, u) + drag * math.sin(math.pi * u)
	lift = st["lift"] * s * (1.0 - 0.75 * limp)
	c = lift * math.sin(math.pi * (u ** st["lift_skew"])) ** st["lift_pow"]
	return y, c - R.lowest_rel(psi), psi, False


def _run_upper(st, ph):
	"""Run pose without legs (hips twist, lean, arms) and the two foot targets."""
	from mathutils import Vector
	R = st["rig"]
	a = TAU * ph
	c1 = math.cos(a)             # +1 at the right touchdown (right leg forward, left arm forward)
	sway = 7.0 * st["limp"] * c1
	p = pose(hips=(0, sway, st["hip_twist"] * c1), spine=(st["lean"], -sway * 0.6, -6 * c1), chest=(0, 0, -5 * c1),
		neck=(-st["lean"] * 0.35, 0, 3 * c1), head=(-st["lean"] * 0.35, 0, 2 * c1))
	p = add(p, _run_arms(st, c1))
	body = _fin(st, p, loco=True, carry=True)
	for b in ("upper_leg", "lower_leg", "foot"):
		for side in ("l", "r"):
			body.pop(b + "_" + side, None)
	targets = {}
	for side, off in (("r", 0.0), ("l", 0.5)):
		y, z, psi, planted = _foot_track(st, (ph + off) % 1.0, side)
		targets[side] = (Vector((R.ankle[side].x, y, z)), psi, planted)
	return body, targets


def _run_bob(st):
	"""Hips height offset over the cycle (table of 120 samples): the style's crouch + bounce (lowest at
	mid-stance), limited so the PLANTED legs reach their feet, then smoothed (no kinks)."""
	cache = st.get("_bob_table")
	if cache is not None:
		return cache
	R = st["rig"]
	s = st["s"]
	n = 120
	lim = []
	want = []
	for i in range(n):
		ph = i / n
		body, targets = _run_upper(st, ph)
		G0 = fk(R.arm, body)
		m = math.inf
		for side in ("l", "r"):
			t, _psi, planted = targets[side]
			if not planted:
				continue
			H = G0["hips"] @ R.hip[side]
			r = st["reach_k"] * R.leg
			h2 = r * r - (t.x - H.x) ** 2 - (t.y - H.y) ** 2
			m = min(m, t.z + math.sqrt(max(0.0, h2)) - H.z)
		lim.append(m)
		want.append((st["crouch"] - st["bounce"] * math.cos(2.0 * (TAU * ph - math.pi * st["duty"]))) * s)
	bob = [min(w, l) for w, l in zip(want, lim)]
	k = 6   # circular box blur (+-6 samples = +-5% of the cycle), 3 passes, then re-limit
	for _ in range(3):
		bob = [sum(bob[(i + j) % n] for j in range(-k, k + 1)) / (2 * k + 1) for i in range(n)]
	bob = [min(b, l) for b, l in zip(bob, lim)]
	st["_bob_table"] = bob
	return bob


def _run_ik(st, ph):
	"""One frame of the IK run (walking characters)."""
	R = st["rig"]
	table = _run_bob(st)
	n = len(table)
	x = (ph % 1.0) * n
	i = int(x)
	f = x - i
	bob = table[i % n] * (1.0 - f) + table[(i + 1) % n] * f
	body, targets = _run_upper(st, ph)
	hl = body.get("loc:hips", (0.0, 0.0, 0.0))
	body["loc:hips"] = (hl[0], hl[1], hl[2] + bob)
	G = fk(R.arm, body)
	for side in ("l", "r"):
		t, psi, _planted = targets[side]
		(al, be, ga), _err = R.solve_leg(G["hips"], side, t, psi)
		body["upper_leg_" + side] = (al, 0.0, 0.0)
		body["lower_leg_" + side] = (be, 0.0, 0.0)
		body["foot_" + side] = (ga, 0.0, 0.0)
	return body


def run(style):
	st = _st(style)
	dur = st["run_frames"] / FPS
	if st["hover"] <= 0.0 and st.get("rig") is not None:
		return sample(lambda ph: _run_ik(st, ph), dur, step=1)

	def fn(ph):
		# Hovering glide (lich): legs trail, body leans forward, gentle sway; arms per run_arms.
		a = TAU * ph
		s1 = math.sin(a)
		p = pose(upper_leg_s=(18, 3, 0), lower_leg_s=(30, 0, 0), foot_s=(30, 0, 0),
			spine=(st["lean"], 3 * s1, 4 * s1), chest=(4, 0, -3 * s1), head=(-st["lean"] * 0.6, 0, 0))
		p = add(p, _loc(st, "root", 0, 0, 0.04 * math.sin(2 * a)), _run_arms(st, s1))
		return _fin(st, p, loco=True, carry=True)
	return sample(fn, dur, step=1)


def channel(style):
	"""Arms out (whirlwind); the model is spun by code."""
	st = _st(style)

	def fn(ph):
		c = math.cos(TAU * ph)
		b = math.sin(TAU * ph)
		p = pose(upper_leg_s=(-18, 8, 0), lower_leg_s=(28, 0, 0), foot_s=(-10, -8, 0),
			spine=(10, 0, 0), chest=(-4, 0, 0), head=(-8, 0, 0),
			upper_arm_r=(-12, 78, 0), lower_arm_r=(22, 0, 0), hand_r=(55, 0, 0),
			upper_arm_l=(-12, -75, 0), lower_arm_l=(18, 0, 0), hand_l=(10, 0, 0))
		p = add(p, _loc(st, "hips", 0, 0, -0.08 + 0.02 * c), pose(upper_arm_s=(3 * b, 0, 0), chest=(0, 2 * b, 0)))
		return _fin(st, p, loco=False)
	return sample(fn, DURATION["channel"], step=2)


# ----------------------------------------------------------------------------------- attacks

def attack_slash(style):
	st = _st(style)
	r = stance(st)
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


def attack_slam(style):
	st = _st(style)
	r = stance(st)
	lift = add(r, pose(spine=(-6, 0, 0), chest=(-8, 0, 0), head=(-6, 0, 0),
		upper_arm_r=(-120, 0, 18), lower_arm_r=(-40, 0, 0), hand_r=(-10, 0, 0),
		upper_arm_l=(-120, 0, -30), lower_arm_l=(-50, 0, 0), hand_l=(0, 0, 0)), _loc(st, "hips", 0, 0.01, 0.0))
	wind = add(r, pose(spine=(-14, 0, 0), chest=(-12, 0, 0), neck=(-4, 0, 0), head=(-10, 0, 0),
		upper_arm_r=(-168, 0, 15), lower_arm_r=(-35, 0, 0), hand_r=(st.get("slam_wind_hand", -15.0), 0, 0),
		upper_arm_l=(-168, 0, -25), lower_arm_l=(-45, 0, 0),
		upper_leg_s=(-4, 4, 0), lower_leg_s=(6, 0, 0), foot_s=(8, 0, 0)), _loc(st, "hips", 0, 0.03, 0.04))
	impact = add(r, pose(spine=(28, 0, 0), chest=(14, 0, 0), neck=(-12, 0, 0), head=(-10, 0, 0),
		upper_arm_r=(-62, 0, 14), lower_arm_r=(30, 0, 0), hand_r=(st.get("slam_hand", 80.0), 0, 0),
		upper_arm_l=(-58, 0, -30), lower_arm_l=(26, 0, 0), hand_l=(40, 0, 0),
		upper_leg_r=(-40, 6, 0), lower_leg_r=(62, 0, 0), foot_r=(-22, -6, 0),
		upper_leg_l=(-10, -6, 0), lower_leg_l=(44, 0, 0), foot_l=(-34, 6, 0)), _loc(st, "hips", 0, -0.02, -0.2))
	if not st["weapon"]:
		# Unarmed (brute, ghoul...): both fists pound the ground in front.
		impact = add(r, pose(spine=(46, 0, 0), chest=(16, 0, 0), neck=(-24, 0, 0), head=(-16, 0, 0),
			upper_arm_r=(-88, 0, 20), lower_arm_r=(30, 0, 0), hand_r=(10, 0, 0),
			upper_arm_l=(-88, 0, -20), lower_arm_l=(30, 0, 0), hand_l=(10, 0, 0),
			upper_leg_r=(-44, 8, 0), lower_leg_r=(66, 0, 0), foot_r=(-22, -8, 0),
			upper_leg_l=(-16, -8, 0), lower_leg_l=(50, 0, 0), foot_l=(-34, 8, 0)), _loc(st, "hips", 0, 0.04, -0.26))
	hold = add(impact, pose(spine=(2, 0, 0), upper_arm_s=(3, 0, 0)), _loc(st, "hips", 0, 0, -0.02))
	# Impact on whole frame 13 (0.433 s): the export bakes whole frames, so the weapon is already down
	# at the 0.44 s hit frame (55%) instead of being interpolated halfway to it.
	t_hit = 13.0 / 30.0
	keys = [(0.0, r), (0.16, lift), (0.32, wind), (t_hit, impact), (0.58, hold), (0.8, r)]
	if (st.get("slam_floor") or st.get("slam_held")) and st.get("skin") is not None:
		# Built-in weapon (gravebreaker maul) or the reference held weapon (weapon_maul on grip_r): its
		# head rests on the floor from the impact (frame 13) to the end of the hold (frame 17), one
		# solved key per baked frame.
		mid = [(f / 30.0, lerp(impact, hold, _smooth(0.0, 1.0, (f - 13) / 4.0))) for f in range(14, 18)]
		keys = [(0.0, r), (0.16, lift), (0.32, wind), (t_hit, impact)] + mid + [(0.8, r)]
		out = _seq(st, keys, stabilize_mid=False)
		return [(t, _weapon_to_floor(st, p) if 12.5 / 30.0 < t < 17.5 / 30.0 else p) for t, p in out]
	return _seq(st, keys, stabilize_mid=False)  # two-handed: no shield/focus in grip_l


def _held_lowest(st, G):
	"""Lowest z of the reference held weapon (style slam_held: vertices in item space) attached to
	grip_r like Godot's BoneAttachment3D (origin at the bone head, item +Z along the bone)."""
	from mathutils import Matrix
	M = G["grip_r"] @ st["arm"].data.bones["grip_r"].matrix_local @ Matrix.Rotation(-math.pi / 2.0, 4, "X")
	return min((M @ v).z for v in st["slam_held"])


def _weapon_to_floor(st, p):
	"""Bend the right wrist (hand_r X) so the lowest vertex of the weapon (the built-in "Weapon" part,
	or style slam_held) is level with the lowest foot vertex (the ground bake puts the feet on y = 0),
	by bisection."""
	arm, skin = st["arm"], st["skin"]

	def gap(x):
		q = dict(p)
		h = q.get("hand_r", (0.0, 0.0, 0.0))
		q["hand_r"] = (x, h[1], h[2])
		G = fk(arm, q)
		w = skin.lowest(G, parts=("Weapon",)) if st.get("slam_floor") else _held_lowest(st, G)
		return w - skin.lowest(G, bones=FEET), q
	lo, hi = -80.0, p.get("hand_r", (0.0, 0.0, 0.0))[0]
	g_lo, _q = gap(lo)
	g_hi, q_hi = gap(hi)
	if g_hi >= 0.0:
		return q_hi          # already above the floor
	if g_lo < 0.0:
		return gap(lo)[1]    # cannot lift it enough: best effort
	q = q_hi
	for _ in range(30):
		mid = 0.5 * (lo + hi)
		g, q = gap(mid)
		if g > 0.0:
			lo = mid
		else:
			hi = mid
	return q


def attack_stab(style):
	st = _st(style)
	r = stance(st)
	draw = add(r, pose(spine=(-2, 0, -10), chest=(0, 0, -24), head=(0, 0, 18),
		upper_arm_r=(28, 10, 0), lower_arm_r=(-78, 0, 0), hand_r=(78, 0, 0),
		upper_arm_l=(-40, 0, 25), lower_arm_l=(-30, 0, 0),
		upper_leg_r=(6, 4, 0), upper_leg_l=(-14, -4, 0), lower_leg_l=(20, 0, 0)), _loc(st, "hips", 0, 0.04, -0.03))
	thrust = add(r, pose(spine=(16, 0, 10), chest=(4, 0, 18), head=(-10, 0, -16),
		upper_arm_r=(-84, 0, -20), lower_arm_r=(32, 0, 0), hand_r=(84, 0, 0),
		upper_arm_l=(22, 0, 12), lower_arm_l=(-40, 0, 0),
		upper_leg_r=(-40, 4, 0), lower_leg_r=(40, 0, 0), foot_r=(2, 0, 0),
		upper_leg_l=(22, -4, 0), lower_leg_l=(14, 0, 0), foot_l=(-10, 0, 0)), _loc(st, "hips", 0, -0.14, -0.09))
	keys = [(0.0, r), (0.13, draw), (0.225, thrust), (0.31, lerp(thrust, r, 0.12)), (0.5, r)]
	return _seq(st, keys)


def shoot_bow(style):
	st = _st(style)
	r = stance(st)
	body = pose(spine=(2, 0, 20), chest=(-2, 0, 28), neck=(0, 0, -24), head=(0, 0, -22),
		upper_leg_r=(-10, 6, 0), upper_leg_l=(8, -8, 0), lower_leg_s=(10, 0, 0))
	raise_ = add(r, body, pose(upper_arm_r=(-82, 0, -40), lower_arm_r=(30, 0, 0), hand_r=(6, 0, 0),
		upper_arm_l=(-80, 0, -52), lower_arm_l=(-30, 0, 0), hand_l=(0, 0, 0)))
	draw = add(r, body, pose(upper_arm_r=(-88, 0, -46), lower_arm_r=(36, 0, 0), hand_r=(4, 0, 0),
		upper_arm_l=(-86, 0, 30), lower_arm_l=(-135, 0, 0), hand_l=(10, 0, 0), chest=(-3, 0, 4)))
	release = add(r, body, pose(upper_arm_r=(-86, 0, -44), lower_arm_r=(36, 0, 0), hand_r=(4, 0, 0),
		upper_arm_l=(-78, 0, 60), lower_arm_l=(-100, 0, 0), hand_l=(-20, 0, 0), chest=(-5, 0, 8)))
	keys = [(0.0, r), (0.16, raise_), (0.38, draw), (0.42, draw), (0.47, release), (0.58, lerp(release, r, 0.25)), (0.7, r)]
	return _seq(st, keys, stabilize_mid=False)  # two-handed: no shield/focus in grip_l


def shoot_crossbow(style):
	st = _st(style)
	r = stance(st)
	aim = add(r, pose(spine=(4, 0, -15), chest=(0, 0, -20), neck=(4, 0, 18), head=(6, 0, 16),
		upper_arm_r=(-36, 0, 21), lower_arm_r=(-16, 0, 14), hand_r=(90, 0, 0),
		upper_arm_l=(-58, 0, -26), lower_arm_l=(40, 0, 0), hand_l=(30, 0, 0),
		upper_leg_r=(6, 5, 0), upper_leg_l=(-14, -5, 0), lower_leg_l=(18, 0, 0)))
	kick = add(aim, pose(spine=(-6, 0, 0), chest=(-4, 0, 0), head=(-4, 0, 0), upper_arm_r=(14, 0, 0), upper_arm_l=(12, 0, 0),
		hand_r=(-10, 0, 0)), _loc(st, "hips", 0, 0.04, 0.0))
	keys = [(0.0, r), (0.14, aim), (0.22, aim), (0.26, kick), (0.36, aim), (0.6, r)]
	return _seq(st, keys, stabilize_mid=False)  # two-handed: no shield/focus in grip_l


def cast(style):
	st = _st(style)
	r = stance(st)
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


def cast_area(style):
	st = _st(style)
	r = stance(st)
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


# ----------------------------------------------------------------------------------- reactions

def hit(style):
	st = _st(style)
	r = stance(st)
	fl = add(r, pose(spine=(-14, 4, -6), chest=(-10, 0, 0), neck=(-6, 0, 0), head=(-14, 6, 0),
		upper_arm_r=(18, 12, 0), upper_arm_l=(14, -16, 0), lower_arm_s=(-20, 0, 0),
		upper_leg_s=(-10, 0, 0), lower_leg_s=(16, 0, 0)), _loc(st, "hips", 0, 0.06, -0.03))
	keys = [(0.0, r), (0.07, fl), (0.16, lerp(fl, r, 0.45)), (0.3, r)]
	return _seq(st, keys, loco=True)


FEET = ("foot_l", "foot_r")


def _shift_root(p, dz):
	q = dict(p)
	lr = q.get("loc:root", (0.0, 0.0, 0.0))
	q["loc:root"] = (lr[0], lr[1], lr[2] + dz)
	return q


def _floor_keys(st, keys, feet_until, rest_from, lift=None, upright_only=False):
	"""Vertical root offsets per key for the animations the ground bake skips (die, dodge):
	keys with t <= feet_until put the feet on the floor (walking characters; with upright_only only
	keys without root rotation), every key stays above the floor, and keys with t >= rest_from rest
	their lowest vertex on it (+ lift[t]). Needs style["skin"] (set by the build)."""
	skin = st.get("skin")
	if skin is None:
		return keys
	arm = st["arm"]
	walker = st["hover"] <= 0.0 and any(True for _ in skin.select(bones=FEET))
	out = []
	for t, p in keys:
		G = fk(arm, p)
		low = skin.lowest(G)
		dz = max(0.0, -low)
		upright = not any(abs(a) > 1e-6 for a in p.get("root", (0.0, 0.0, 0.0)))
		if walker and t <= feet_until + 1e-6 and (upright or not upright_only):
			dz = max(-skin.lowest(G, bones=FEET), -low)
		if t >= rest_from - 1e-6:
			dz = -low + (lift or {}).get(round(t, 3), 0.0)
		out.append((t, _shift_root(p, dz) if abs(dz) > 1e-7 else p))
	return out


def die(style):
	st = _st(style)
	r = stance(st)
	s = st["s"]
	fl = add(r, pose(spine=(-16, 0, -8), chest=(-10, 0, 0), head=(-20, 0, 0),
		upper_arm_r=(20, 20, 0), upper_arm_l=(15, -25, 0), lower_arm_s=(-25, 0, 0)), _loc(st, "hips", 0, 0.05, -0.02))
	buckle = add(r, pose(spine=(24, 0, 6), chest=(10, 0, 0), neck=(12, 0, 0), head=(18, 8, 0),
		upper_arm_r=(-10, 18, 0), upper_arm_l=(-5, -14, 0), lower_arm_s=(-20, 0, 0), hand_s=(20, 0, 0),
		upper_leg_s=(-50, 8, 0), lower_leg_s=(85, 0, 0), foot_s=(-30, 0, 0)), _loc(st, "hips", 0, 0.08, -0.36))
	lying_body = pose(spine=(-4, 0, 0), chest=(-4, 0, 0), neck=(-6, 0, 0), head=(-10, 0, 35),
		upper_arm_r=(16, 74, 0), lower_arm_r=(38, 0, 0), upper_arm_l=(18, -62, 0), lower_arm_l=(36, 0, 0),
		upper_leg_r=(-35, 12, 0), lower_leg_r=(55, 0, 0), foot_r=(20, 0, 0),
		upper_leg_l=(-8, -8, 0), lower_leg_l=(12, 0, 0), foot_l=(25, 0, 0))
	# Limp wrists for characters holding items: a weapon on grip_r lies flat pointing away from the
	# body, a shield / focus on grip_l lies face up beside the arm.
	if st["weapon"]:
		lying_body["hand_r"] = (90, 0, -15)
	if st.get("stabilize_left"):
		lying_body["hand_l"] = (-60, 0, -60)
	if st["robe"]:
		# Robe skirt halves follow the thighs: keep the legs nearly straight so the skirt lies flat.
		lying_body.update(pose(upper_leg_r=(-6, 6, 0), lower_leg_r=(10, 0, 0), foot_r=(20, 0, 0),
			upper_leg_l=(-3, -5, 0), lower_leg_l=(6, 0, 0), foot_l=(24, 0, 0)))
	thick = 0.13 * st.get("body_depth", 1.0)
	fall = add(lying_body, {"root": (-90, 0, 0), "loc:root": (0, 0.05 * s, thick * s)}, _loc(st, "hips", 0, 0.0, 0.0))
	bounce = add(fall, {"root": (8, 0, 0), "loc:root": (0, 0, 0.02 * s)}, pose(head=(8, 0, 0), upper_arm_s=(10, 0, 0)))
	mid = add(lerp(buckle, lying_body, 0.4), {"root": (-45, 0, 0), "loc:root": (0, 0.0, 0.04 * s)})
	keys = [(0.0, r), (0.1, fl), (0.3, buckle), (0.48, mid), (0.64, fall), (0.74, bounce), (0.86, fall), (1.0, fall)]
	out = []
	for t, p in keys:
		if t == 0.0:
			q = _fin(st, p, carry=True)
		else:
			q = add(p, st["base"]) if t < 0.5 else add(p, scale(st["base"], 0.2))
			if st["hover"] > 0.0 and t < 0.5:
				q = add(q, _loc(st, "root", 0, 0, st["hover"] * (1.0 - t / 0.5)))
			if t >= 0.48 and st.get("die_pose"):
				# Character-specific corpse (e.g. the lich lays its staff flat beside the body).
				dp = st["die_pose"] if t >= 0.64 else scale(st["die_pose"], 0.5)
				for b, v in dp.items():
					q[b] = add({b: q.get(b, (0.0, 0.0, 0.0))}, {b: v})[b] if t < 0.64 else v
		out.append((t, q))
	# Floor: standing keys keep their feet on it, nothing ever sinks below it, the corpse rests on it.
	return _floor_keys(st, out, feet_until=0.3, rest_from=0.64, lift={0.74: 0.02 * s})


def dodge(style):
	"""Forward roll in place (the code moves the actor 6 m in 0.35 s)."""
	st = _st(style)
	r = stance(st)
	s = st["s"]
	curl = pose(spine=(55, 0, 0), chest=(25, 0, 0), neck=(25, 0, 0), head=(20, 0, 0),
		upper_arm_s=(-60, 10, 0), lower_arm_s=(-70, 0, 0),
		upper_leg_s=(-105, 6, 0), lower_leg_s=(125, 0, 0), foot_s=(20, 0, 0))
	pivot = 0.56 * s
	from mathutils import Euler, Vector

	def rolled(deg, drop):
		rot = Euler((math.radians(deg), 0, 0), "XYZ").to_matrix()
		c = Vector((0, 0, pivot))
		off = c - rot @ c
		return add(curl, {"root": (deg, 0, 0), "loc:root": (off.x, off.y, off.z)}, _loc(st, "hips", 0, 0, drop))
	crouch = add(r, pose(spine=(35, 0, 0), chest=(10, 0, 0), head=(10, 0, 0), upper_arm_s=(-50, 8, 0), lower_arm_s=(-40, 0, 0),
		upper_leg_s=(-60, 6, 0), lower_leg_s=(90, 0, 0), foot_s=(-30, 0, 0)), _loc(st, "hips", 0, 0, -0.32))
	keys = [(0.0, r), (0.05, crouch), (0.1, rolled(60, -0.3)), (0.155, rolled(150, -0.3)), (0.21, rolled(240, -0.3)),
		(0.265, rolled(320, -0.3)), (0.31, add(crouch, pose(spine=(-10, 0, 0)))), (0.4, r)]
	keys = _seq(st, keys, stabilize_mid=False)
	# Feet on the floor when upright (crouch / stand), never below it while rolling.
	return _floor_keys(st, keys, feet_until=0.4, rest_from=9.0, upright_only=True)


def roar(style):
	st = _st(style)
	r = stance(st)
	inhale = add(r, pose(spine=(-12, 0, 0), chest=(-12, 0, 0), neck=(-8, 0, 0), head=(-22, 0, 0),
		upper_arm_r=(-60, 55, 0), lower_arm_r=(-60, 0, 0), upper_arm_l=(-60, -55, 0), lower_arm_l=(-60, 0, 0)),
		_loc(st, "hips", 0, 0.03, 0.03))
	bellow = add(r, pose(spine=(16, 0, 0), chest=(14, 0, 0), neck=(4, 0, 0), head=(6, 0, 0),
		upper_arm_r=(-25, 70, 0), lower_arm_r=(-75, 0, 0), hand_r=(30, 0, 0),
		upper_arm_l=(-25, -70, 0), lower_arm_l=(-75, 0, 0), hand_l=(30, 0, 0),
		upper_leg_s=(-24, 10, 0), lower_leg_s=(40, 0, 0), foot_s=(-16, -10, 0)), _loc(st, "hips", 0, -0.03, -0.12))
	sh1 = add(bellow, pose(chest=(0, 4, 3), head=(2, -5, 0), upper_arm_s=(3, 4, 0)))
	sh2 = add(bellow, pose(chest=(0, -4, -3), head=(-2, 5, 0), upper_arm_s=(-3, -2, 0)))
	keys = [(0.0, r), (0.32, inhale), (0.5, bellow), (0.6, sh1), (0.7, sh2), (0.8, sh1), (0.9, bellow), (1.2, r)]
	return _seq(st, keys)


def talk(style):
	st = _st(style)
	r = stance(st)
	# Open-handed gestures (the loco layer holds the hands on the belly; these offsets swing the
	# right arm out and forward, palm up).
	g1 = add(r, pose(upper_arm_r=(-28, 24, -34), lower_arm_r=(-4, 0, 0), hand_r=(-30, 0, 0), head=(6, 0, -8), neck=(0, 0, -4)))
	g2 = add(r, pose(upper_arm_r=(-20, 38, -30), lower_arm_r=(-14, 0, 0), hand_r=(-40, 0, 0), head=(-4, 0, 6), chest=(0, 0, 4),
		upper_arm_l=(-10, -24, 22), lower_arm_l=(-6, 0, 0)))
	nod = add(g1, pose(head=(12, 0, 0)))
	keys = [(0.0, r), (0.4, g1), (0.8, g2), (1.1, nod), (1.4, g2), (1.8, g1), (2.4, r)]
	return _seq(st, keys, loco=True)


BUILDERS = {"idle": idle, "run": run, "attack_slash": attack_slash, "attack_slam": attack_slam,
	"attack_stab": attack_stab, "shoot_bow": shoot_bow, "shoot_crossbow": shoot_crossbow, "cast": cast,
	"cast_area": cast_area, "channel": channel, "hit": hit, "die": die, "dodge": dodge, "roar": roar, "talk": talk}
