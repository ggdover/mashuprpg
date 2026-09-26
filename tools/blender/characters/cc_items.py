"""Weapons, off-hands, helmets and ground-only item models (docs/ARCHITECTURE.md §14.4).

Conventions (§14.1/§14.2):
  * weapons: grip (fist centre) at the origin, blade/shaft along +Z, flat of the blade facing +-X,
    the "business side" (axe edge, bow belly, shield face) toward -Y, the bow string / crossbow top
    toward +Y. Under a BoneAttachment3D on grip_r at identity they sit in the right fist.
  * offhand_shield / offhand_focus: held on grip_l (grip_l points up, its Z faces forward-left):
    shield face toward -Y, top toward +Z, handle at the origin; the focus orb floats above the hand.
  * offhand_quiver: origin at the char_player chest bone head, hanging on the back (+Y), opening
    over the right shoulder (-X).
  * armor_helmet_*: origin at the char_player head bone head (the base of the skull).
  * ground-only items (armor_body/gloves/boots, jewel_*, loot_*): origin at the base centre,
    resting on z = 0 in their natural display pose, front toward -Y.
Every model has at least one tint_* material (base colour ~0.8 grey for gear).
Each builder returns a dict with icon hints: {"icon_rot": (rx, ry, rz) degrees, "icon_tints": {...}}.
"""
import math

from mathutils import Vector

from cc_mesh import (MIRROR_X, Part, R, S, T, bevel_box, box, build_object, cyl, glow, hexc, icosphere, lathe, loft,
	mat, merge, octa, seg, slab, sphere, tint_mat, torus, tube, xf, double_sided, hair_cap)

# Representative colours for icons (tint_* materials are pale grey in the model; icons show a
# typical tier-1 look). Keys: tint material name -> sRGB colour.
WOOD_ICON = hexc("9a6a3e")
LEATHER_ICON = hexc("8a5a34")
STEEL_ICON = hexc("c8ccd4")


def _mats():
	return dict(
		metal=tint_mat("tint_metal", rough=0.32, metal=0.35),
		wood=tint_mat("tint_wood", rough=0.8),
		leather=mat("leather_grip", hexc("4b2f1c"), rough=0.85),
		wood_fixed=mat("wood_dark", hexc("6b4526"), rough=0.85),
		iron=mat("iron_dark", hexc("55565e"), rough=0.5, metal=0.35),
		gold=mat("gold_trim", hexc("e2aa45"), rough=0.35, metal=0.5),
		string=mat("bowstring", hexc("e8e0c8"), rough=0.9),
	)


def _obj(name, parts):
	"""parts: list of (geo, material). Builds one mesh object named `name`."""
	p = Part(name)
	for geo, m in parts:
		p.add(geo, m, None)
	return build_object(p)


def diamond_blade(z0, z1, w0, w1, t0, t1, tip, n_mid=None):
	"""Blade with a diamond cross-section along +Z (edges +-Y, flats +-X)."""
	rings = [(z0, t0, w0), (z0 + (z1 - z0) * 0.15, t0, w0 * 1.04)]
	if n_mid:
		rings.append((z0 + (z1 - z0) * 0.6, (t0 + t1) / 2, (w0 + w1) / 2 * 1.02))
	rings += [(z1, t1, w1), (tip, 0.0, 0.0)]
	return loft(rings, n=4, phase=0.0)


# =================================================================================== weapons

def weapon_sword():
	m = _mats()
	parts = [
		(octa(0.03, center=(0, 0, -0.112), scale=(1, 1, 1.25)), m["metal"]),
		(cyl((0, 0, -0.095), (0, 0, 0.085), 0.019, 0.017, n=6), m["leather"]),
		(box((0.045, 0.24, 0.032), center=(0, 0, 0.1), top=(0.9, 0.85)), m["metal"]),
		(octa(0.022, center=(0, -0.125, 0.1)), m["gold"]),
		(octa(0.022, center=(0, 0.125, 0.1)), m["gold"]),
		(diamond_blade(0.115, 0.72, 0.043, 0.034, 0.011, 0.009, 0.86), m["metal"]),
	]
	_obj("weapon_sword", parts)
	return {"diag": True, "icon_fat": 1.3}


def weapon_greatsword():
	m = _mats()
	parts = [
		(octa(0.042, center=(0, 0, -0.33), scale=(1, 1, 1.2)), m["metal"]),
		(cyl((0, 0, -0.3), (0, 0, 0.13), 0.022, 0.02, n=6), m["leather"]),
		(cyl((0, 0, -0.12), (0, 0, -0.09), 0.026, n=6), m["gold"]),
		(box((0.06, 0.42, 0.05), center=(0, 0, 0.16), top=(0.8, 0.9)), m["metal"]),
		(box((0.05, 0.05, 0.09), center=(0, -0.22, 0.14), top=(0.7, 0.7)), m["metal"]),
		(box((0.05, 0.05, 0.09), center=(0, 0.22, 0.14), top=(0.7, 0.7)), m["metal"]),
		(box((0.07, 0.09, 0.09), center=(0, 0, 0.21), top=(0.6, 0.8)), m["gold"]),
		(diamond_blade(0.185, 1.12, 0.066, 0.05, 0.016, 0.013, 1.3), m["metal"]),
	]
	_obj("weapon_greatsword", parts)
	return {"diag": True, "icon_fat": 1.4}


def _axe_head(z_mid, height, reach, back=0.035, thick=0.045, flip=False):
	"""Axe blade slab in the (y, z) plane, edge toward -Y (or +Y when flip)."""
	h = height / 2.0
	poly = [(back, z_mid - h * 0.45), (back, z_mid + h * 0.45), (-0.04, z_mid + h * 0.4), (-reach * 0.7, z_mid + h * 0.95),
		(-reach, z_mid + h * 1.05), (-reach * 1.06, z_mid + h * 0.35), (-reach * 1.08, z_mid - h * 0.35),
		(-reach, z_mid - h * 1.05), (-reach * 0.7, z_mid - h * 0.85), (-0.04, z_mid - h * 0.4)]

	def edge(u, v):
		t = max(0.0, min(1.0, (u + reach) / (reach * 0.9)))
		return 0.18 + 0.82 * t
	g = slab(poly, thick, axis="x", edge=edge)
	if flip:
		g = xf(g, S(1, -1, 1))
	return g


def weapon_axe():
	m = _mats()
	parts = [
		(cyl((0, 0, -0.13), (0, 0, 0.66), 0.021, 0.019, n=6), m["wood_fixed"]),
		(cyl((0, 0, -0.1), (0, 0, 0.08), 0.024, n=6), m["leather"]),
		(octa(0.026, center=(0, 0, -0.14)), m["metal"]),
		(_axe_head(0.54, 0.2, 0.2), m["metal"]),
		(box((0.05, 0.07, 0.09), center=(0, 0.005, 0.54)), m["metal"]),
		(box((0.03, 0.06, 0.035), center=(0, 0.06, 0.54), top=(0.5, 0.4), shift=(0, 0.02)), m["metal"]),
	]
	_obj("weapon_axe", parts)
	return {"diag": True, "icon_fat": 1.25}


def weapon_greataxe():
	m = _mats()
	parts = [
		(cyl((0, 0, -0.42), (0, 0, 1.02), 0.025, 0.023, n=6), m["wood_fixed"]),
		(cyl((0, 0, -0.12), (0, 0, 0.1), 0.028, n=6), m["leather"]),
		(cyl((0, 0, -0.46), (0, 0, -0.4), 0.03, n=6), m["metal"]),
		(_axe_head(0.84, 0.34, 0.3, thick=0.055), m["metal"]),
		(_axe_head(0.84, 0.3, 0.24, thick=0.055, flip=True), m["metal"]),
		(box((0.07, 0.09, 0.2), center=(0, 0, 0.84)), m["metal"]),
		(cyl((0, 0, 0.94), (0, 0, 1.12), 0.02, 0.0, n=4), m["metal"]),
	]
	_obj("weapon_greataxe", parts)
	return {"diag": True, "icon_fat": 1.3, "icon_zmin": -0.15}


def weapon_mace():
	m = _mats()
	parts = [
		(cyl((0, 0, -0.13), (0, 0, 0.52), 0.019, 0.02, n=6), m["wood_fixed"]),
		(cyl((0, 0, -0.1), (0, 0, 0.08), 0.023, n=6), m["leather"]),
		(octa(0.026, center=(0, 0, -0.14)), m["metal"]),
		(loft([(0.47, 0.03, 0.03), (0.52, 0.055, 0.055), (0.62, 0.058, 0.058), (0.68, 0.035, 0.035), (0.71, 0, 0)], n=8), m["metal"]),
	]
	for k in range(6):
		a = k * 60.0
		fl = slab([(0.03, 0.48), (0.03, 0.69), (0.082, 0.64), (0.09, 0.55)], 0.018, axis="x")
		parts.append((xf(fl, R(0, 0, a)), m["metal"]))
	_obj("weapon_mace", parts)
	return {"diag": True, "icon_fat": 1.35}


def weapon_maul():
	m = _mats()
	parts = [
		(cyl((0, 0, -0.38), (0, 0, 0.9), 0.024, 0.023, n=6), m["wood_fixed"]),
		(cyl((0, 0, -0.12), (0, 0, 0.1), 0.028, n=6), m["leather"]),
		(octa(0.034, center=(0, 0, -0.4)), m["metal"]),
		(bevel_box((0.19, 0.4, 0.2), center=(0, 0, 0.98), b=0.35), m["metal"]),
		(box((0.205, 0.05, 0.215), center=(0, -0.12, 0.98)), m["iron"]),
		(box((0.205, 0.05, 0.215), center=(0, 0.12, 0.98)), m["iron"]),
		(cyl((0, 0, 0.85), (0, 0, 0.88), 0.04, n=6), m["iron"]),
	]
	_obj("weapon_maul", parts)
	return {"diag": True, "icon_fat": 1.35, "icon_zmin": -0.15}


def weapon_dagger():
	m = _mats()
	parts = [
		(octa(0.022, center=(0, 0, -0.075)), m["gold"]),
		(cyl((0, 0, -0.065), (0, 0, 0.05), 0.016, 0.015, n=6), m["leather"]),
		(box((0.035, 0.12, 0.024), center=(0, 0, 0.062), top=(0.9, 0.7)), m["metal"]),
		(diamond_blade(0.07, 0.25, 0.03, 0.022, 0.009, 0.007, 0.35), m["metal"]),
	]
	_obj("weapon_dagger", parts)
	return {"diag": True, "icon_fat": 1.15}


def weapon_wand():
	m = _mats()
	gem = glow("gem_wand", hexc("7fd8ff"), 5.0)
	parts = [
		(cyl((0, 0, -0.11), (0, 0, 0.29), 0.017, 0.012, n=6), m["wood"]),
		(cyl((0, 0, -0.12), (0, 0, -0.1), 0.02, n=6), m["gold"]),
		(cyl((0, 0, 0.27), (0, 0, 0.31), 0.02, 0.026, n=6), m["gold"]),
		(octa(0.034, center=(0, 0, 0.35), scale=(1, 1, 1.4)), gem),
	]
	for k in range(3):
		a = math.radians(k * 120.0 + 30)
		p0 = Vector((math.cos(a) * 0.02, math.sin(a) * 0.02, 0.3))
		p1 = Vector((math.cos(a) * 0.035, math.sin(a) * 0.035, 0.37))
		parts.append((cyl(p0, p1, 0.007, 0.004, n=4), m["gold"]))
	_obj("weapon_wand", parts)
	return {"diag": True, "icon_fat": 1.8, "icon_tints": {"tint_wood": WOOD_ICON}}


def weapon_staff():
	m = _mats()
	gem = glow("gem_staff", hexc("b07bff"), 5.0)
	parts = [
		(cyl((0, 0, -0.58), (0, 0, 1.08), 0.022, 0.02, n=6), m["wood"]),
		(cyl((0, 0, -0.1), (0, 0, 0.1), 0.026, n=6), m["leather"]),
		(cyl((0, 0, -0.6), (0, 0, -0.55), 0.026, 0.02, n=6), m["metal"]),
		(cyl((0, 0, 0.45), (0, 0, 0.5), 0.026, n=6), m["metal"]),
		(cyl((0, 0, 1.02), (0, 0, 1.1), 0.03, 0.036, n=6), m["metal"]),
		(icosphere(0.065, center=(0, 0, 1.2)), gem),
	]
	for k in range(4):
		a = math.radians(k * 90.0 + 45)
		d = Vector((math.cos(a), math.sin(a), 0))
		pts = [Vector((0, 0, 1.08)) + d * 0.03, Vector((0, 0, 1.15)) + d * 0.075, Vector((0, 0, 1.26)) + d * 0.07,
			Vector((0, 0, 1.31)) + d * 0.02]
		parts.append((tube(pts, [0.013, 0.012, 0.01, 0.0], n=4), m["metal"]))
	_obj("weapon_staff", parts)
	return {"diag": True, "icon_fat": 1.8, "icon_zmin": 0.0, "icon_tints": {"tint_wood": WOOD_ICON}}


def weapon_bow():
	m = _mats()
	limb = [(0.0, 0.06), (0.03, 0.24), (0.075, 0.42), (0.12, 0.56), (0.115, 0.62), (0.095, 0.655)]
	parts = []
	for sz in (1.0, -1.0):
		pts = [Vector((0, y, z * sz)) for (y, z) in limb]
		radii = [(0.02, 0.016), (0.019, 0.014), (0.016, 0.012), (0.013, 0.01), (0.011, 0.009), (0.007, 0.007)]
		parts.append((tube(pts, radii, n=6, side=(1, 0, 0)), m["wood"]))
		parts.append((octa(0.013, center=(0, 0.1, 0.645 * sz)), m["gold"]))
	parts.append((cyl((0, 0.0, -0.085), (0, 0.0, 0.085), 0.024, n=6), m["leather"]))
	parts.append((cyl((0, 0.113, -0.625), (0, 0.113, 0.625), 0.0045, n=4), m["string"]))
	_obj("weapon_bow", parts)
	return {"diag": True, "icon_fat": 1.6, "icon_tints": {"tint_wood": WOOD_ICON}}


def weapon_crossbow():
	m = _mats()
	parts = [
		# Stock along +Z, top (bolt groove) toward +Y.
		(box((0.05, 0.06, 0.62), center=(0, 0.0, 0.2), top=(0.9, 0.9)), m["wood"]),
		(box((0.056, 0.11, 0.2), center=(0, -0.022, -0.18), top=(0.9, 0.7), shift=(0, 0.02)), m["wood"]),
		(box((0.03, 0.02, 0.5), center=(0, 0.035, 0.28)), m["iron"]),
		(box((0.018, 0.05, 0.03), center=(0, -0.05, 0.02)), m["iron"]),
		(cyl((0, 0.0, 0.5), (0, 0.0, 0.55), 0.034, n=6), m["metal"]),
	]
	# Prod (bow arms) along X at the front, tips curving back (-Z).
	prod = [Vector((x, 0.0, 0.5 - 0.1 * (abs(x) / 0.34) ** 2)) for x in (-0.34, -0.22, -0.1, 0.0, 0.1, 0.22, 0.34)]
	radii = [0.011, 0.016, 0.02, 0.022, 0.02, 0.016, 0.011]
	parts.append((tube(prod, [(r, r * 0.8) for r in radii], n=6, side=(0, 0, 1)), m["metal"]))
	for sx in (-1, 1):
		parts.append((cyl((sx * 0.33, 0.012, 0.405), (0, 0.035, 0.22), 0.004, n=4), m["string"]))
	# Loaded bolt
	parts.append((cyl((0, 0.052, 0.2), (0, 0.052, 0.6), 0.008, n=4), m["wood_fixed"]))
	parts.append((cyl((0, 0.052, 0.6), (0, 0.052, 0.66), 0.014, 0.0, n=4), m["iron"]))
	# Stirrup
	parts.append((torus(0.045, 0.008, 8, 4, center=(0, 0.0, 0.6), axis_rot=R(0, 90, 0)), m["iron"]))
	_obj("weapon_crossbow", parts)
	return {"diag": True, "diag_spin": 180.0, "icon_fat": 1.25, "icon_elev": 30.0, "icon_tints": {"tint_wood": WOOD_ICON}}


# =================================================================================== off-hands

def offhand_shield():
	m = _mats()
	face = tint_mat("tint_shield", rough=0.55, metal=0.2)
	outline = [(x * 0.88, z * 0.88) for (x, z) in [(0.27, 0.32), (0.27, 0.02), (0.22, -0.18), (0.12, -0.33), (0.0, -0.42),
		(-0.12, -0.33), (-0.22, -0.18), (-0.27, 0.02), (-0.27, 0.32), (0.0, 0.35)]]
	inner = [(x * 0.86, z * 0.86 + 0.0) for (x, z) in outline]
	back = slab(outline, 0.03, axis="y")
	front = slab(inner, 0.02, axis="y")
	parts = [
		(xf(back, T(0, -0.075, 0)), m["iron"]),
		(xf(front, T(0, -0.095, 0)), face),
		(xf(sphere(0.054, 8, 3, cut=(0.0, 1.0), scale=(1, 1, 0.55)), T(0, -0.105, 0) @ R(90, 0, 0)), m["gold"]),
		(cyl((0, 0, -0.07), (0, 0, 0.07), 0.018, n=6), m["leather"]),
		(box((0.03, 0.06, 0.02), center=(0, -0.035, 0.07)), m["iron"]),
		(box((0.03, 0.06, 0.02), center=(0, -0.035, -0.07)), m["iron"]),
	]
	# Emblem: a chevron on the face.
	chev = slab([(-0.14, 0.12), (0.0, 0.0), (0.14, 0.12), (0.14, 0.06), (0.0, -0.07), (-0.14, 0.06)], 0.012, axis="y")
	parts.append((xf(chev, T(0, -0.108, 0.02)), m["gold"]))
	_obj("offhand_shield", parts)
	return {"icon_rot": (0, 0, 20), "icon_tints": {"tint_shield": hexc("a8adb8")}}


def offhand_focus():
	m = _mats()
	ring = tint_mat("tint_focus", rough=0.35, metal=0.4)
	orb = glow("focus_orb", hexc("9b7bff"), 4.0)
	core = glow("focus_core", hexc("e8dcff"), 6.0)
	parts = [
		(icosphere(0.075, center=(0, 0, 0.19)), orb),
		(octa(0.03, center=(0, 0, 0.19)), core),
		(torus(0.105, 0.009, 16, 4, center=(0, 0, 0.19), axis_rot=R(70, 0, 20)), ring),
		(torus(0.12, 0.008, 16, 4, center=(0, 0, 0.19), axis_rot=R(-35, 60, 0)), ring),
		(octa(0.022, center=(0, 0, 0.065), scale=(1, 1, 1.6)), ring),
	]
	_obj("offhand_focus", parts)
	return {"icon_rot": (0, 0, 0), "icon_tints": {"tint_focus": hexc("e2b24a")}}


PLAYER_CHEST_Z = 1.24
PLAYER_HEAD_Z = 1.53


def offhand_quiver():
	"""Origin = char_player chest bone head (z 1.24). Hangs on the back, opening over the right shoulder."""
	m = _mats()
	body = tint_mat("tint_quiver", rough=0.8)
	feather = mat("fletching", hexc("d8d0c0"), rough=0.9)
	feather2 = mat("fletching_red", hexc("b03a2a"), rough=0.9)
	bottom = Vector((0.12, 0.2, -0.28))
	top = Vector((-0.12, 0.19, 0.3))
	ax = (top - bottom).normalized()
	parts = [
		(seg(bottom, top, [(0, 0.05, 0.045), (0.08, 0.062, 0.055), (0.9, 0.066, 0.058), (1.0, 0.07, 0.062)], n=8, side=(1, 0, 0)), body),
		(seg(bottom + ax * 0.12, bottom + ax * 0.16, [(0, 0.066, 0.059), (1, 0.066, 0.059)], n=8), m["leather"]),
		(seg(bottom + ax * 0.52, bottom + ax * 0.56, [(0, 0.069, 0.061), (1, 0.069, 0.061)], n=8), m["leather"]),
		(seg(bottom - ax * 0.012, bottom + ax * 0.01, [(0, 0.045, 0.04), (1, 0.052, 0.046)], n=8), m["gold"]),
	]
	# Strap from the quiver top over the right shoulder toward the chest (short visible part).
	parts.append((tube([top + Vector((0.02, -0.03, -0.04)), Vector((-0.14, 0.05, 0.24)), Vector((-0.12, -0.1, 0.16))],
		[(0.018, 0.006)] * 3, n=4, side=(0, 1, 0)), m["leather"]))
	# Arrows sticking out of the opening.
	for k, (dx, dy, extra) in enumerate([(0.0, 0.0, 0.0), (0.028, 0.012, -0.03), (-0.025, 0.015, -0.015),
			(0.012, -0.025, -0.04), (-0.01, 0.03, -0.05)]):
		base = top - ax * 0.05 + Vector((dx, dy, 0))
		tip = base + ax * (0.2 + extra)
		parts.append((cyl(base, tip, 0.006, n=4), m["wood_fixed"]))
		f = feather2 if k % 2 == 0 else feather
		fl0 = tip - ax * 0.09
		for a in (0.0, 120.0, 240.0):
			ang = math.radians(a + 20 * k)
			side = ax.cross(Vector((0, 0, 1))).normalized()
			up = ax.cross(side)
			d = side * math.cos(ang) + up * math.sin(ang)
			quad = ([fl0, tip - ax * 0.005, tip - ax * 0.02 + d * 0.022, fl0 + d * 0.024], [[0, 1, 2, 3]])
			parts.append((double_sided(quad), f))
	_obj("offhand_quiver", parts)
	return {"icon_rot": (0, 0, 180), "icon_tints": {"tint_quiver": LEATHER_ICON}}


# =================================================================================== helmets
# Origin at the char_player head bone head. Player skull: half width 0.105, half depth 0.115,
# height 0.27, hair up to ~0.29 with a rim of 0.118 x 0.128.

def armor_helmet_str():
	m = _mats()
	plate = tint_mat("tint_helm", rough=0.35, metal=0.35)
	c = 0.012
	dome = loft([(0.075, 0.13, 0.142, 0, c), (0.15, 0.135, 0.146, 0, c), (0.23, 0.118, 0.128, 0, c + 0.004),
		(0.285, 0.075, 0.085, 0, c + 0.006), (0.315, 0.0, 0.0, 0, c + 0.006)], n=8, phase=22.5)
	parts = [(dome, plate)]
	# Rim band
	parts.append((loft([(0.07, 0.137, 0.149, 0, c), (0.105, 0.139, 0.151, 0, c)], n=8, phase=22.5), m["iron"]))
	# Cheek guards and back plate
	for sx in (-1, 1):
		cheek = box((0.022, 0.1, 0.13), center=(sx * 0.126, -0.03, 0.06), top=(1.0, 1.1))
		parts.append((cheek, plate))
	parts.append((box((0.2, 0.03, 0.12), center=(0, 0.14, 0.06), top=(1.1, 1)), plate))
	# Nasal guard
	parts.append((box((0.026, 0.02, 0.13), center=(0, -0.152, 0.1), top=(1.0, 1.0)), m["iron"]))
	# Crest
	crest = slab([(0.13, 0.2), (0.05, 0.325), (-0.08, 0.33), (-0.15, 0.25), (-0.1, 0.24), (-0.05, 0.3), (0.06, 0.29), (0.11, 0.19)], 0.024, axis="x")
	parts.append((xf(crest, S(1, -1, 1)), m["gold"]))
	_obj("armor_helmet_str", parts)
	return {"icon_rot": (0, 0, 30), "icon_tints": {"tint_helm": STEEL_ICON}}


def armor_helmet_dex():
	"""Leather hood: open face, cowl over the nape and shoulders, drooping tip at the back."""
	m = _mats()
	hood = tint_mat("tint_hood", rough=0.9)
	inner = mat("hood_inner", hexc("1c1612"), rough=1.0)
	outer = hair_cap(0.0, 0.142, 0.152, 0.29, front=0.2, back=-0.08, side=-0.01, top_extra=0.02, n=12, cy=0.018, closed=False)
	iv, iff = hair_cap(0.0, 0.134, 0.144, 0.29, front=0.2, back=-0.08, side=-0.01, top_extra=0.012, n=12, cy=0.018, closed=False)
	parts = [(outer, hood), ((iv, [list(reversed(f)) for f in iff]), inner)]
	# Rim around the face opening (thin band following the lower edge of the shell)
	rim_v, rim_f = [], []
	n = 12
	for k in range(n):
		a = 2 * math.pi * k / n + math.pi / n
		x, y = math.cos(a), math.sin(a)
		zb = -0.01 + (0.2 + 0.01) * (-y) ** 1.5 if y < 0 else -0.01 + (-0.08 + 0.01) * (y ** 1.2)
		for (sc, dz) in ((1.035, 0.0), (1.035, 0.03)):
			rim_v.append(Vector((x * 0.142 * sc, 0.018 + y * 0.152 * sc, zb + dz)))
	for k in range(n):
		a0, a1 = 2 * k, 2 * ((k + 1) % n)
		rim_f.append([a0, a1, a1 + 1, a0 + 1])
	parts.append((double_sided((rim_v, rim_f)), m["leather"]))
	# Drooping tip and a short mantle over the shoulders
	parts.append((tube([Vector((0, 0.1, 0.27)), Vector((0, 0.19, 0.22)), Vector((0, 0.24, 0.1))], [0.055, 0.03, 0.0], n=5), hood))
	mantle = loft([(-0.12, 0.2, 0.19, 0, 0.03), (-0.04, 0.16, 0.16, 0, 0.03), (0.02, 0.14, 0.15, 0, 0.02)], n=10, cap0=False, cap1=False)
	mv, mf = mantle
	keep = [f for f in mf if sum(mv[i].y for i in f) / len(f) > -0.1]
	parts.append((double_sided((mv, keep)), hood))
	_obj("armor_helmet_dex", parts)
	return {"icon_rot": (0, 0, 30), "icon_elev": 10, "icon_tints": {"tint_hood": hexc("5f7a45")}}


def armor_helmet_int():
	m = _mats()
	band = tint_mat("tint_circlet", rough=0.3, metal=0.5)
	gem = glow("gem_circlet", hexc("5ad8ff"), 5.0)
	c = 0.01
	ring = loft([(0.15, 0.118, 0.128, 0, c), (0.19, 0.116, 0.126, 0, c), (0.2, 0.118, 0.128, 0, c)], n=12, phase=15, cap0=False, cap1=False)
	rv, rf = ring
	parts = [(double_sided((rv, rf)), band)]
	# Points around the band
	for k in range(12):
		a = math.radians(k * 30.0 + 15.0)
		x, y = math.cos(a) * 0.12, math.sin(a) * 0.13 + c
		h = 0.07 if k in (8, 9) else (0.045 if k % 2 == 0 else 0.03)
		parts.append((cyl((x, y, 0.19), (x * 1.02, y * 1.02, 0.19 + h), 0.018, 0.0, n=4), band))
	# Front jewel mount + gem
	parts.append((box((0.05, 0.02, 0.06), center=(0, -0.13, 0.18)), band))
	parts.append((octa(0.026, center=(0, -0.145, 0.19), scale=(1, 0.7, 1.3)), gem))
	_obj("armor_helmet_int", parts)
	return {"icon_rot": (0, 0, 0), "icon_elev": 25, "icon_tints": {"tint_circlet": hexc("e8b84a")}}


# =================================================================================== ground-only

def armor_body():
	m = _mats()
	arm = tint_mat("tint_armor", rough=0.45, metal=0.25)
	parts = [
		(loft([(0.0, 0.16, 0.11), (0.08, 0.15, 0.1), (0.2, 0.158, 0.106), (0.3, 0.19, 0.122), (0.37, 0.2, 0.12),
			(0.42, 0.16, 0.1), (0.44, 0.09, 0.075)], n=8), arm),
		(box((0.24, 0.03, 0.15), center=(0, -0.112, 0.31), top=(0.85, 1)), arm),
		(loft([(0.02, 0.164, 0.114), (0.07, 0.162, 0.112)], n=8), m["leather"]),
		(box((0.055, 0.02, 0.045), center=(0, -0.118, 0.045)), m["gold"]),
		(loft([(0.43, 0.09, 0.07), (0.46, 0.075, 0.062)], n=8, cap1=False), m["leather"]),
	]
	for sx in (-1, 1):
		parts.append((sphere(0.09, 8, 4, center=(sx * 0.2, 0.0, 0.37), scale=(1.1, 1.05, 0.8), cut=(-0.2, 1.0)), arm))
		parts.append((box((0.02, 0.06, 0.02), center=(sx * 0.1, -0.105, 0.2)), m["gold"]))
	_obj("armor_body", parts)
	return {"icon_rot": (0, 0, 20), "icon_tints": {"tint_armor": STEEL_ICON}}


def armor_gloves():
	m = _mats()
	gl = tint_mat("tint_gloves", rough=0.6, metal=0.15)
	parts = []
	for sx in (-1, 1):
		x = sx * 0.075
		parts.append((box((0.085, 0.1, 0.11), center=(x, -0.02, 0.055), top=(0.92, 0.9)), gl))
		parts.append((box((0.04, 0.035, 0.05), center=(x - sx * 0.05, -0.04, 0.05)), gl))
		parts.append((loft([(0.1, 0.048, 0.052, x, 0.0), (0.2, 0.06, 0.064, x, 0.02)], n=6), gl))
		parts.append((loft([(0.105, 0.05, 0.054, x, 0.002), (0.125, 0.051, 0.055, x, 0.004)], n=6), m["leather"]))
		for k in range(4):
			parts.append((box((0.018, 0.02, 0.03), center=(x - sx * 0.03 + sx * k * 0.02, -0.075, 0.1)), m["iron"]))
	_obj("armor_gloves", parts)
	return {"icon_rot": (0, 0, 25), "icon_tints": {"tint_gloves": LEATHER_ICON}}


def armor_boots():
	m = _mats()
	bt = tint_mat("tint_boots", rough=0.7)
	parts = []
	for sx in (-1, 1):
		x = sx * 0.075
		parts.append((box((0.105, 0.24, 0.09), center=(x, -0.04, 0.045), top=(0.92, 0.7), shift=(0, 0.03)), bt))
		parts.append((loft([(0.05, 0.058, 0.066, x, 0.03), (0.22, 0.06, 0.068, x, 0.035), (0.26, 0.068, 0.075, x, 0.035)], n=6), bt))
		parts.append((loft([(0.2, 0.063, 0.071, x, 0.035), (0.22, 0.064, 0.072, x, 0.035)], n=6), m["leather"]))
		parts.append((box((0.11, 0.245, 0.018), center=(x, -0.04, 0.009)), m["leather"]))
	_obj("armor_boots", parts)
	return {"icon_rot": (0, 0, 30), "icon_tints": {"tint_boots": LEATHER_ICON}}


def jewel_ring():
	band = tint_mat("tint_ring", rough=0.3, metal=0.6)
	gem = mat("gem_ruby", hexc("e0324a"), rough=0.2, emit=hexc("ff3050"), strength=1.5)
	parts = [
		(torus(0.05, 0.011, 16, 5, center=(0, 0, 0.061), axis_rot=R(90, 0, 0)), band),
		(box((0.03, 0.03, 0.02), center=(0, 0, 0.114)), band),
		(octa(0.022, center=(0, 0, 0.13), scale=(1, 1, 0.8)), gem),
	]
	_obj("jewel_ring", parts)
	return {"icon_rot": (0, 0, 30), "icon_elev": 20, "icon_tints": {"tint_ring": hexc("d8b050")}}


def jewel_amulet():
	chain = tint_mat("tint_amulet", rough=0.3, metal=0.6)
	gem = mat("gem_emerald", hexc("30c070"), rough=0.2, emit=hexc("40ff90"), strength=1.5)
	parts = []
	# Chain: a thin loop standing in the XZ plane, plus a few link beads.
	parts.append((torus(1.0, 0.035, 20, 4, axis_rot=R(90, 0, 0)), chain))
	parts[-1] = (xf(parts[-1][0], T(0, 0, 0.2) @ S(0.11, 1.0, 0.1) @ S(1.0, 0.12, 1.0)), chain)
	for k in range(8):
		a = 2 * math.pi * (k + 0.5) / 8
		parts.append((octa(0.009, center=(math.sin(a) * 0.11, 0, 0.2 + math.cos(a) * 0.1)), chain))
	parts.append((cyl((0, 0, 0.1), (0, 0, 0.075), 0.02, n=6), chain))
	parts.append((xf(lathe([(0.0, -0.012), (0.05, -0.01), (0.055, 0.0), (0.05, 0.01), (0.0, 0.012)], n=8), T(0, 0, 0.05) @ R(90, 0, 0)), chain))
	parts.append((octa(0.028, center=(0, -0.016, 0.05), scale=(1, 0.6, 1.2)), gem))
	_obj("jewel_amulet", parts)
	return {"icon_rot": (0, 0, 15), "icon_tints": {"tint_amulet": hexc("e2b24a")}}


def jewel_belt():
	"""Belt loop standing upright (ring in the XZ plane, front toward -Y) with the buckle at the bottom:
	GroundItem lays it on its back, which puts the loop flat with the buckle at the front."""
	m = _mats()
	strap = tint_mat("tint_belt", rough=0.8)
	v, f = torus(1.0, 0.13, 20, 4, axis_rot=R(90, 0, 0))
	parts = [(xf((v, f), T(0, 0, 0.141) @ S(0.16, 1.0, 0.125) @ S(1.0, 0.2, 1.0)), strap)]
	parts.append((box((0.08, 0.05, 0.05), center=(0, 0.0, 0.012)), m["gold"]))
	parts.append((box((0.035, 0.056, 0.025), center=(0, 0.0, 0.012)), m["leather"]))
	parts.append((box((0.075, 0.07, 0.08), center=(0.12, 0.0, 0.045), top=(0.9, 0.9)), m["leather"]))
	parts.append((box((0.065, 0.065, 0.075), center=(-0.135, 0.0, 0.1), top=(0.9, 0.9)), m["leather"]))
	for k in range(6):
		a = math.radians(40 + k * 56)
		parts.append((octa(0.01, center=(math.sin(a) * 0.162, -0.02, 0.125 + math.cos(a) * 0.127)), m["gold"]))
	_obj("jewel_belt", parts)
	return {"icon_rot": (-65, 0, 0), "icon_elev": 20, "icon_tints": {"tint_belt": LEATHER_ICON}}


def loot_gold():
	coin = tint_mat("tint_gold", rough=0.3, metal=0.6, grey=0.8)
	coin_col = mat("gold_coin", hexc("f0c040"), rough=0.3, metal=0.55)
	import random
	rnd = random.Random(7)
	parts = []
	# Stacked pile: rings of coins at decreasing radius.
	layers = [(0.0, 0.12, 9), (0.012, 0.09, 7), (0.024, 0.06, 5), (0.036, 0.03, 3), (0.048, 0.0, 1)]
	for li, (z, rad, cnt) in enumerate(layers):
		for k in range(cnt):
			a = 2 * math.pi * k / cnt + li * 0.5
			x, y = math.cos(a) * rad, math.sin(a) * rad
			tilt = rnd.uniform(-18, 18)
			g = xf(lathe([(0.0, 0.0), (0.034, 0.0), (0.034, 0.008), (0.0, 0.008)], n=8, cap0=False, cap1=False),
				T(x, y, z + 0.004) @ R(tilt, rnd.uniform(-12, 12), rnd.uniform(0, 90)))
			parts.append((g, coin if (li + k) % 3 else coin_col))
	# A few standing / loose coins
	for (x, y, rz) in ((0.16, 0.03, 20), (-0.14, -0.08, 70)):
		g = xf(lathe([(0.0, 0.0), (0.034, 0.0), (0.034, 0.008), (0.0, 0.008)], n=8, cap0=False, cap1=False), T(x, y, 0.034) @ R(80, 0, rz))
		parts.append((g, coin))
	_obj("loot_gold", parts)
	return {"icon_rot": (0, 0, 0), "icon_elev": 38, "icon_tints": {"tint_gold": hexc("f2c448")}}


def _potion(name, liquid_hex, glow_hex):
	glass = mat("potion_glass_" + name, hexc("d8e8f0"), rough=0.15)
	liquid = mat("potion_liquid_" + name, hexc(liquid_hex), rough=0.3, emit=hexc(glow_hex), strength=2.0)
	cork = tint_mat("tint_cork", rough=0.9)
	liq = lathe([(0.0, 0.012), (0.058, 0.016), (0.078, 0.045), (0.082, 0.08), (0.066, 0.12), (0.0, 0.12)], n=10)
	neck = lathe([(0.0, 0.118), (0.068, 0.121), (0.036, 0.15), (0.03, 0.2), (0.036, 0.212), (0.0, 0.212)], n=10)
	parts = [
		(neck, glass),
		(xf(liq, S(1.02, 1.02, 1.0)), liquid),
		(lathe([(0.0, 0.205), (0.027, 0.205), (0.031, 0.25), (0.0, 0.25)], n=8), cork),
		(lathe([(0.0, 0.2), (0.04, 0.2), (0.04, 0.214), (0.0, 0.214)], n=8), mat("potion_band", hexc("8a6a3a"))),
	]
	return parts


def loot_potion_life():
	parts = _potion("life", "c8202a", "ff2a3a")
	_obj("loot_potion_life", parts)
	return {"icon_rot": (0, 0, 0), "icon_elev": 18, "icon_tints": {"tint_cork": hexc("a07a4a")}}


def loot_potion_mana():
	parts = _potion("mana", "2040d0", "3a6aff")
	_obj("loot_potion_mana", parts)
	return {"icon_rot": (0, 0, 0), "icon_elev": 18, "icon_tints": {"tint_cork": hexc("a07a4a")}}


ITEMS = {
	"weapon_sword": weapon_sword,
	"weapon_greatsword": weapon_greatsword,
	"weapon_axe": weapon_axe,
	"weapon_greataxe": weapon_greataxe,
	"weapon_mace": weapon_mace,
	"weapon_maul": weapon_maul,
	"weapon_dagger": weapon_dagger,
	"weapon_wand": weapon_wand,
	"weapon_staff": weapon_staff,
	"weapon_bow": weapon_bow,
	"weapon_crossbow": weapon_crossbow,
	"offhand_shield": offhand_shield,
	"offhand_focus": offhand_focus,
	"offhand_quiver": offhand_quiver,
	"armor_helmet_str": armor_helmet_str,
	"armor_helmet_dex": armor_helmet_dex,
	"armor_helmet_int": armor_helmet_int,
	"armor_body": armor_body,
	"armor_gloves": armor_gloves,
	"armor_boots": armor_boots,
	"jewel_ring": jewel_ring,
	"jewel_amulet": jewel_amulet,
	"jewel_belt": jewel_belt,
	"loot_gold": loot_gold,
	"loot_potion_life": loot_potion_life,
	"loot_potion_mana": loot_potion_mana,
}
