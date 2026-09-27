"""Act II — The Gilded Sands (desert): Qarth-like sandstone city pieces, Egyptian monuments, Nile
bank farms and river props, the Snake Isles, the Anubis necropolis and the temple court. Model ids
are prefixed "desert_", materials "ds_".

Blender axes: Z up, fronts face -Y (= Godot +Z, toward the camera). Origin at the base centre.
Built with envlib.MeshBuilder (closed shells; exported with backface culling).
Run: blender --background --factory-startup --python tools/blender/acts/build_all.py -- --only desert --check
OWNER: acts-desert.
"""

import math
import random

import bmesh
from mathutils import Matrix, Vector

import envlib as L
from envlib import MeshBuilder

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

DS_PALETTE = {
    "ds_sand": dict(hex="#d9bf8f", rough=0.95),
    "ds_sandstone": dict(hex="#caa46c", rough=0.93),
    "ds_sandstone_b": dict(hex="#bf975f", rough=0.93),
    "ds_sandstone_light": dict(hex="#e3cb98", rough=0.92),
    "ds_sandstone_dark": dict(hex="#9f7c4e", rough=0.95),
    "ds_sandstone_top": dict(hex="#b89565", rough=0.97),
    "ds_cream": dict(hex="#ecdfc3", rough=0.9),
    "ds_plaster": dict(hex="#e2cda5", rough=0.95),
    "ds_plaster_b": dict(hex="#d8b98a", rough=0.95),
    "ds_stripe": dict(hex="#3d3631", rough=0.9),
    "ds_opening": dict(hex="#2b221c", rough=1.0),
    "ds_wood": dict(hex="#6f4a2b", rough=0.88),
    "ds_wood_dark": dict(hex="#47301d", rough=0.9),
    "ds_bronze": dict(hex="#a47436", rough=0.45, metal=0.55),
    "ds_gold": dict(hex="#d8a93e", rough=0.35, metal=0.65),
    "ds_gold_glow": dict(hex="#f2c35a", emit="#ffc64d", strength=2.2, rough=0.4),
    "ds_lapis": dict(hex="#2d4f9c", rough=0.6),
    "ds_turquoise": dict(hex="#3aa39c", rough=0.55),
    "ds_red_paint": dict(hex="#a8412e", rough=0.8),
    "ds_palm_trunk": dict(hex="#7b5b3b", rough=0.95),
    "ds_palm_trunk_dark": dict(hex="#5b4229", rough=0.95),
    "ds_palm_leaf": dict(hex="#4f7f33", rough=0.85),
    "ds_palm_leaf_dark": dict(hex="#3a6429", rough=0.85),
    "ds_palm_leaf_light": dict(hex="#77a043", rough=0.85),
    "ds_palm_leaf_dry": dict(hex="#a08a4a", rough=0.9),
    "ds_date": dict(hex="#c0702a", rough=0.7),
    "ds_reed": dict(hex="#6d8f37", rough=0.85),
    "ds_reed_dark": dict(hex="#4e6e2b", rough=0.85),
    "ds_reed_head": dict(hex="#a7b35a", rough=0.85),
    "ds_shrub": dict(hex="#5f7f35", rough=0.9),
    "ds_shrub_dark": dict(hex="#44602b", rough=0.9),
    "ds_cloth_red": dict(hex="#a8392b", rough=0.9),
    "ds_cloth_cream": dict(hex="#eadfc4", rough=0.9),
    "ds_cloth_blue": dict(hex="#2f5e8e", rough=0.9),
    "ds_cloth_saffron": dict(hex="#d8982b", rough=0.9),
    "ds_cloth_teal": dict(hex="#2f7f78", rough=0.9),
    "ds_cloth_purple": dict(hex="#6a3a6e", rough=0.9),
    "ds_pot": dict(hex="#b8693b", rough=0.8),
    "ds_pot_dark": dict(hex="#8c4d2b", rough=0.85),
    "ds_pot_light": dict(hex="#d19a67", rough=0.8),
    "ds_water": dict(hex="#3f8fa6", rough=0.06, emit="#1d5a6e", strength=0.25),
    "ds_water_jet": dict(hex="#bfe8f2", emit="#8fd8ee", strength=0.8, rough=0.1),
    "ds_rock": dict(hex="#b88f5d", rough=0.97),
    "ds_rock_b": dict(hex="#a47d50", rough=0.97),
    "ds_rock_c": dict(hex="#cfa874", rough=0.97),
    "ds_hull": dict(hex="#5f4128", rough=0.85),
    "ds_hull_light": dict(hex="#8a623b", rough=0.85),
    "ds_sail": dict(hex="#efe6d0", rough=0.9),
    "ds_rope": dict(hex="#a88a5a", rough=0.95),
    "ds_iron": dict(hex="#3c3a38", rough=0.6, metal=0.3),
    "ds_fire": dict(hex="#ff9a30", emit="#ff8a20", strength=6.0, rough=1.0),
    "ds_fire_core": dict(hex="#ffd66a", emit="#ffcc55", strength=8.0, rough=1.0),
    # Act II outdoor zones
    "ds_basalt": dict(hex="#2b2825", rough=0.5),
    "ds_basalt_b": dict(hex="#3d3833", rough=0.75),
    "ds_mud": dict(hex="#9b7651", rough=0.97),
    "ds_mud_light": dict(hex="#bb976b", rough=0.97),
    "ds_mud_dark": dict(hex="#6d5136", rough=0.97),
    "ds_soil": dict(hex="#4c3b2a", rough=1.0),
    "ds_whitewash": dict(hex="#e9e0cc", rough=0.95),
    "ds_crop_green": dict(hex="#71a03a", rough=0.85),
    "ds_crop_dark": dict(hex="#4c7a2b", rough=0.85),
    "ds_crop_gold": dict(hex="#d2a84c", rough=0.85),
    "ds_crop_gold_b": dict(hex="#b58c3b", rough=0.85),
    "ds_verdigris": dict(hex="#4f8c77", rough=0.5, metal=0.35),
    "ds_verdigris_dark": dict(hex="#2f5d51", rough=0.55, metal=0.3),
    "ds_lotus_pad": dict(hex="#4e8541", rough=0.6),
    "ds_lotus_pad_b": dict(hex="#3b6a34", rough=0.6),
    "ds_lotus_white": dict(hex="#f4e9ef", rough=0.7),
    "ds_lotus_blue": dict(hex="#7494df", rough=0.7),
    "ds_plank": dict(hex="#8b6b46", rough=0.9),
    "ds_camel": dict(hex="#bb8f5c", rough=0.95),
    "ds_camel_dark": dict(hex="#8e6842", rough=0.95),
    "ds_fern": dict(hex="#3f8a3a", rough=0.8),
    "ds_fern_light": dict(hex="#6aae48", rough=0.8),
    "ds_grass_green": dict(hex="#5e9a3c", rough=0.85),
    "ds_eye_red": dict(hex="#d8402a", emit="#ff4a20", strength=1.5, rough=0.5),
}
L.PALETTE.update(DS_PALETTE)


# ----------------------------------------------------------------------------------- helpers

def hull(mb, points, mat):
    """Convex hull like MeshBuilder.hull, tolerant of coplanar input (bmesh can report a vertex
    as both interior and unused)."""
    verts = [mb.bm.verts.new(Vector(p)) for p in points]
    res = bmesh.ops.convex_hull(mb.bm, input=verts)
    unused = list(dict.fromkeys(g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)))
    if unused:
        bmesh.ops.delete(mb.bm, geom=unused, context="VERTS")
    verts = [v for v in verts if v.is_valid]
    faces = list(mb._faces_of(verts))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    mb._assign(verts, mat)
    return verts


def ribbon(mb, pts, widths, ups, thick, mat):
    """Closed thin strip (leaf, frond, cloth) along pts with per-point widths and up vectors."""
    bm = mb.bm
    n = len(pts)
    rows = []
    for i in range(n):
        p = Vector(pts[i])
        t = (Vector(pts[min(i + 1, n - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        up = Vector(ups[i]) if isinstance(ups, list) else Vector(ups)
        side = t.cross(up)
        if side.length < 1e-6:
            side = t.cross(X)
        side.normalize()
        up2 = side.cross(t).normalized()
        w = max(widths[i], 0.012) / 2
        h = thick / 2
        rows.append([bm.verts.new(p + side * w + up2 * h), bm.verts.new(p - side * w + up2 * h),
                     bm.verts.new(p - side * w - up2 * h), bm.verts.new(p + side * w - up2 * h)])
    faces = []
    for i in range(n - 1):
        a, b = rows[i], rows[i + 1]
        for k in range(4):
            faces.append(bm.faces.new([a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]]))
    faces.append(bm.faces.new(list(reversed(rows[0]))))
    faces.append(bm.faces.new(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    verts = [v for r in rows for v in r]
    mb._assign(verts, mat)
    return verts


def band(mb, cx, cy, w, d, z0, z1, mat, grow=0.03):
    """A horizontal course slightly proud of a w x d block (stripe bands, cornices)."""
    return mb.box((cx, cy, (z0 + z1) / 2), (w + 2 * grow, d + 2 * grow, z1 - z0), mat)


def merlons_x(mb, x0, x1, y, z, depth, count, mat, w=0.62, h=0.7, stepped=False):
    """Merlons along X (centred between x0 and x1) at the line y, standing on z."""
    for k in range(count):
        x = x0 + (k + 0.5) * (x1 - x0) / count
        mb.box((x, y, z + h / 2), (w, depth, h), mat)
        if stepped:
            mb.box((x, y, z + h + 0.12), (w * 0.55, depth * 0.9, 0.24), mat)


def merlons_ring(mb, w, d, z, mat, per_side=4, thick=0.4, mw=0.55, mh=0.65, stepped=False):
    """Merlons around a w x d rectangle top edge."""
    for s in (-1, 1):
        merlons_x(mb, -w / 2, w / 2, s * (d / 2 - thick / 2), z, thick, per_side, mat, w=mw, h=mh, stepped=stepped)
    for s in (-1, 1):
        for k in range(per_side):
            yy = -d / 2 + (k + 0.5) * d / per_side
            if abs(abs(yy) - d / 2) < mw:
                continue
            mb.box((s * (w / 2 - thick / 2), yy, z + mh / 2), (thick, mw, mh), mat)
            if stepped:
                mb.box((s * (w / 2 - thick / 2), yy, z + mh + 0.12), (thick * 0.9, mw * 0.55, 0.24), mat)


def pointed_arch(cx, z_spring, half, n=6, ratio=1.4):
    """Points of a pointed arch from the left spring point over the apex to the right spring
    point (left to right)."""
    r = ratio * half
    th = math.acos((half - r) / r)
    left = []
    for i in range(n + 1):
        a = math.pi - (math.pi - th) * i / n
        left.append((cx - half + r + r * math.cos(a), z_spring + r * math.sin(a)))
    right = [(2 * cx - x, z) for (x, z) in reversed(left[:-1])]
    return left + right


def round_arch(cx, z_spring, half, n=8):
    return [(cx - half * math.cos(math.pi * i / n), z_spring + half * math.sin(math.pi * i / n)) for i in range(n + 1)]


def front_frame(y, sign=-1):
    """Frame for a face at depth y facing sign*Y: (origin, u, v, n) with u x v = n."""
    if sign < 0:
        return (Vector((0, y, 0)), X, Z, -Y)
    return (Vector((0, y, 0)), -X, Z, Y)


def arch_opening(mb, cx, z0, half, z_spring, y, depth, mat, pointed=True, sign=-1):
    """A dark recessed arched opening (door / window void) on a front face at depth y."""
    top = pointed_arch(cx, z_spring, half) if pointed else round_arch(cx, z_spring, half)
    poly = [(cx - half, z0)] + top + [(cx + half, z0)]
    poly = [(p[0], p[1]) for p in poly]
    # prism with u = X (sign -1) needs CCW in (x, z): bottom-left -> bottom-right -> up -> over
    ccw = [(cx - half, z0), (cx + half, z0)] + [p for p in reversed(top)]
    if sign > 0:
        ccw = [(-p[0], p[1]) for p in ccw]
        ccw = [ccw[0], ccw[1]] + ccw[2:]
        ccw = list(reversed(ccw))
    fr = front_frame(y, sign)
    mb.prism(ccw, -depth, 0.02, mat, frame=fr)


def voussoirs(mb, cx, z_spring, half, y, mats, count=11, width=0.45, proud=0.1, pointed=True, sign=-1):
    """Alternating coloured wedge stones around an arch (the Qarth striped arch)."""
    inner = pointed_arch(cx, z_spring, half, n=count) if pointed else round_arch(cx, z_spring, half, n=count)
    outer = pointed_arch(cx, z_spring, half + width, n=count) if pointed else round_arch(cx, z_spring, half + width, n=count)
    # both lists run left -> right over the apex with 2*count+1 points (pointed) or count+1 (round)
    fr = front_frame(y, sign)
    for i in range(len(inner) - 1):
        a, b = inner[i], inner[i + 1]
        c, d = outer[i + 1], outer[i]
        quad = [a, b, c, d]
        # orientation: inner runs left->right (clockwise over the top when seen from the front);
        # make it CCW for the prism
        area = 0.0
        for k in range(4):
            x1, y1 = quad[k]
            x2, y2 = quad[(k + 1) % 4]
            area += x1 * y2 - x2 * y1
        if sign > 0:
            quad = [(-p[0], p[1]) for p in quad]
            area = -area
        if area < 0:
            quad = list(reversed(quad))
        mb.prism(quad, -0.05, proud, mats[i % len(mats)], frame=fr)


def lathe_pot(mb, x, y, z, h, r, mat, lid=None, neck=0.45, segs=8, handles=False):
    prof = [(0.0, 0.0), (r * 0.55, 0.0), (r, h * 0.35), (r * 0.92, h * 0.62), (r * neck, h * 0.85),
            (r * (neck + 0.12), h), (0.0, h)]
    mb.lathe(prof, mat, segs=segs, center=(x, y, z))
    if lid:
        mb.cyl((x, y, z + h + 0.03), r * (neck + 0.1), r * 0.2, 0.08, lid, segs=segs)
    if handles:
        for s in (-1, 1):
            mb.box((x + s * r * 0.8, y, z + h * 0.72), (0.05, 0.05, h * 0.3), mat)


def stone_blocks(mb, rng, x0, x1, z0, z1, y, mat, count, sign=-1, size=(0.9, 0.45)):
    """Random slightly proud ashlar blocks on a front face (texture)."""
    for _ in range(count):
        w = size[0] * rng.uniform(0.7, 1.3)
        h = size[1]
        x = rng.uniform(x0 + w / 2, x1 - w / 2)
        z = z0 + h * (0.5 + int(rng.uniform(0, max(1, (z1 - z0) / h - 1))))
        if z + h / 2 > z1:
            continue
        mb.box((x, y + sign * 0.012, z), (w, 0.04, h - 0.04), mat)


# ----------------------------------------------------------------------------------- city pieces

def build_desert_wall():
    """City wall segment: 4 m along X (tiles end to end), 1.8 m thick, 5 m to the walkway,
    stepped merlons on both edges, a plinth, a dark course band and ashlar texture."""
    mb = MeshBuilder()
    rng = random.Random(101)
    W, D, H = 4.0, 1.8, 5.0
    mb.box((0, 0, H / 2), (W, D, H), "ds_sandstone")
    mb.box((0, 0, 0.35), (W, D + 0.3, 0.7), "ds_sandstone_dark")
    band(mb, 0, 0, W - 0.06, D, 3.35, 3.6, "ds_sandstone_b", grow=0.04)
    mb.box((0, 0, H + 0.04), (W, D - 0.9, 0.08), "ds_sandstone_top")
    for s in (-1, 1):
        mb.box((0, s * (D / 2 - 0.22), H + 0.12), (W, 0.44, 0.24), "ds_sandstone_b")
        merlons_x(mb, -W / 2, W / 2, s * (D / 2 - 0.22), H + 0.24, 0.44, 3, "ds_sandstone", w=0.8, h=0.62, stepped=True)
    for sgn in (-1, 1):
        stone_blocks(mb, rng, -W / 2 + 0.05, W / 2 - 0.05, 0.8, 3.3, sgn * D / 2, "ds_sandstone_b", 5, sign=sgn)
        stone_blocks(mb, rng, -W / 2 + 0.05, W / 2 - 0.05, 3.7, 4.9, sgn * D / 2, "ds_sandstone_light", 2, sign=sgn)
    mb.finish("desert_wall")


def build_desert_tower():
    """Square wall tower (3.8 m, 9 m) with dark stripe bands at the foot, arrow slits, a
    projecting parapet and stepped merlons."""
    mb = MeshBuilder()
    rng = random.Random(103)
    W, H = 3.8, 8.6
    mb.box((0, 0, H / 2), (W, W, H), "ds_sandstone", taper=(0.94, 0.94))
    mb.box((0, 0, 0.4), (W + 0.4, W + 0.4, 0.8), "ds_sandstone_dark")
    for k, z in enumerate((1.1, 1.8, 2.5)):
        band(mb, 0, 0, W * (1 - 0.06 * z / H) - 0.02, W * (1 - 0.06 * z / H) - 0.02, z, z + 0.32,
             "ds_stripe" if k % 2 == 0 else "ds_cream", grow=0.035)
    band(mb, 0, 0, W * 0.94, W * 0.94, 5.6, 5.9, "ds_stripe", grow=0.035)
    # parapet box
    Wp = W * 0.96 + 0.3
    mb.box((0, 0, H + 0.2), (Wp, Wp, 0.4), "ds_sandstone_b")
    for k in range(5):
        mb.box((-Wp / 2 + 0.4 + k * (Wp - 0.8) / 4, 0, H - 0.1), (0.22, Wp - 0.1, 0.25), "ds_sandstone_dark")
    mb.box((0, 0, H + 0.42), (Wp - 0.8, Wp - 0.8, 0.06), "ds_sandstone_top")
    merlons_ring(mb, Wp, Wp, H + 0.4, "ds_sandstone", per_side=4, thick=0.4, mw=0.6, mh=0.6, stepped=True)
    # arrow slits and a window on every side
    for (sign, frame_axis) in ((-1, "y"), (1, "y"), (-1, "x"), (1, "x")):
        for z in (3.6, 6.6):
            half = 0.16 if z < 5 else 0.3
            ws = W * (1 - 0.06 * z / H) / 2
            if frame_axis == "y":
                arch_opening(mb, 0.0, z - 0.7, half, z, sign * ws, 0.1, "ds_opening", sign=sign)
            else:
                # rotate a y-facing opening onto the x faces
                verts_before = len(mb.bm.verts)
                arch_opening(mb, 0.0, z - 0.7, half, z, -ws, 0.1, "ds_opening", sign=-1)
                mb.bm.verts.ensure_lookup_table()
                new = [mb.bm.verts[i] for i in range(verts_before, len(mb.bm.verts))]
                mb.transform(new, Matrix.Rotation(sign * math.pi / 2, 4, "Z"))
    stone_blocks(mb, rng, -1.6, 1.6, 3.0, 5.4, -W * 0.965 / 2, "ds_sandstone_b", 5)
    mb.finish("desert_tower")


def build_desert_tower_dome():
    """Ornate Qarth tower (~14 m): square shaft with stripe bands, an arcaded lantern storey and
    a gilded dome with a finial — the city's landmark."""
    mb = MeshBuilder()
    W = 4.4
    mb.box((0, 0, 0.45), (W + 0.6, W + 0.6, 0.9), "ds_sandstone_dark")
    mb.box((0, 0, 4.5), (W, W, 8.0), "ds_sandstone")
    for k, z in enumerate((1.3, 2.0, 2.7, 3.4)):
        band(mb, 0, 0, W - 0.02, W - 0.02, z, z + 0.3, "ds_stripe" if k % 2 == 0 else "ds_cream", grow=0.035)
    for sign in (-1, 1):
        arch_opening(mb, 0, 0.9, 0.6, 2.6, sign * W / 2, 0.3, "ds_opening", sign=sign)
        voussoirs(mb, 0, 2.6, 0.6, sign * W / 2, ["ds_stripe", "ds_cream"], count=5, width=0.32, sign=sign)
        arch_opening(mb, 0, 5.2, 0.35, 6.3, sign * W / 2, 0.2, "ds_opening", sign=sign)
    band(mb, 0, 0, W, W, 8.3, 8.7, "ds_sandstone_light", grow=0.18)
    # arcaded lantern storey: an arched slab on every side around a dark core
    Wl = 3.6
    mb.box((0, 0, 8.72), (Wl + 0.2, Wl + 0.2, 0.1), "ds_sandstone_top")
    mb.box((0, 0, 9.9), (Wl - 0.9, Wl - 0.9, 2.4), "ds_opening")
    outline = [(-Wl / 2, 8.75), (-0.95, 8.75)] + pointed_arch(0, 10.0, 0.95, n=5) + [(0.95, 8.75), (Wl / 2, 8.75), (Wl / 2, 11.12), (-Wl / 2, 11.12)]
    for k in range(4):
        before = len(mb.bm.verts)
        mb.prism(outline, -0.3, 0.0, "ds_sandstone_light", frame=front_frame(-Wl / 2, -1))
        mb.bm.verts.ensure_lookup_table()
        mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))], Matrix.Rotation(k * math.pi / 2, 4, "Z"))
    mb.box((0, 0, 11.25), (Wl + 0.3, Wl + 0.3, 0.3), "ds_sandstone_b")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.cyl((sx * (Wl / 2), sy * (Wl / 2), 11.75), 0.22, 0.0, 0.9, "ds_gold", segs=6)
    # drum and dome
    mb.cyl((0, 0, 11.7), 1.45, 1.45, 0.6, "ds_sandstone_light", segs=12)
    prof = [(0.0, 0.0)] + [(1.55 * math.cos(math.pi / 2 * i / 6) * (1.0 + 0.08 * math.sin(math.pi * i / 6)),
                           1.9 * math.sin(math.pi / 2 * i / 6)) for i in range(6)] + [(0.0, 1.9)]
    mb.lathe(prof, "ds_gold", segs=12, center=(0, 0, 12.0))
    mb.cyl((0, 0, 14.05), 0.12, 0.04, 0.5, "ds_gold", segs=6)
    mb.ico((0, 0, 14.4), 0.14, "ds_gold_glow", subdiv=1)
    mb.finish("desert_tower_dome")


def build_desert_gate():
    """The great gate: a 10 m wide, 3.6 m deep gatehouse with a pointed arch whose voussoirs
    alternate black and cream (Qarth), dark stripe bands on the piers, open studded doors (the
    way out to the river) and stepped merlons."""
    mb = MeshBuilder()
    rng = random.Random(107)
    W, D, H = 10.0, 3.6, 9.6
    half, spring = 1.9, 4.6
    arch = pointed_arch(0, spring, half, n=8)
    outline = [(-W / 2, 0.0), (-half, 0.0)] + arch + [(half, 0.0), (W / 2, 0.0), (W / 2, H), (-W / 2, H)]
    # outline goes: bottom-left, left jamb foot, up the arch (left->right), right jamb foot,
    # bottom-right, top-right, top-left = CCW seen from the front (u = X, v = Z)
    mb.prism(outline, -D / 2, D / 2, "ds_sandstone", frame=(Vector((0, 0, 0)), X, Z, -Y))
    # plinth on both piers
    for s in (-1, 1):
        mb.box((s * (W / 2 + half) / 2, 0, 0.4), ((W / 2 - half) + 0.2, D + 0.3, 0.8), "ds_sandstone_dark")
        for k, z in enumerate((1.2, 1.9, 2.6, 3.3)):
            mb.box((s * (W / 2 + half) / 2, 0, z + 0.16), ((W / 2 - half) + 0.06, D + 0.07, 0.32),
                   "ds_stripe" if k % 2 == 0 else "ds_cream")
    # striped voussoirs, front and back
    for sign in (-1, 1):
        voussoirs(mb, 0, spring, half, sign * D / 2, ["ds_stripe", "ds_cream"], count=6, width=0.7, proud=0.12, sign=sign)
    # the doors stand open: two studded leaves swung back against the passage walls
    for s in (-1, 1):
        lx = s * (half - 0.15)
        mb.box((lx, -0.55, 2.2), (0.2, 1.75, 4.4), "ds_wood_dark")
        for k in range(5):
            mb.box((lx - s * 0.11, -0.55, 0.6 + k * 0.85), (0.03, 1.6, 0.1), "ds_bronze")
        mb.cyl_between((lx - s * 0.1, -1.2, 2.3), (lx - s * 0.26, -1.2, 2.3), 0.1, 0.1, "ds_bronze", segs=8)
    # a dark threshold of worn paving under the arch
    mb.box((0, 0, 0.02), (2 * half - 0.1, D - 0.1, 0.04), "ds_sandstone_dark")
    # upper storey band, cornice, parapet with stepped merlons and two small windows
    band(mb, 0, 0, W, D, 7.0, 7.35, "ds_stripe", grow=0.04)
    band(mb, 0, 0, W, D, 8.9, 9.2, "ds_sandstone_light", grow=0.12)
    for s in (-1, 1):
        for sign in (-1, 1):
            arch_opening(mb, s * 3.3, 7.7, 0.28, 8.35, sign * D / 2, 0.2, "ds_opening", sign=sign)
    mb.box((0, 0, H + 0.05), (W - 0.6, D - 0.6, 0.1), "ds_sandstone_top")
    merlons_ring(mb, W + 0.24, D + 0.24, H, "ds_sandstone", per_side=7, thick=0.42, mw=0.72, mh=0.62, stepped=True)
    stone_blocks(mb, rng, -W / 2 + 0.1, -half - 0.8, 3.8, 6.8, -D / 2, "ds_sandstone_b", 4)
    stone_blocks(mb, rng, half + 0.8, W / 2 - 0.1, 3.8, 6.8, -D / 2, "ds_sandstone_b", 4)
    # banners on the front piers
    for s in (-1, 1):
        mb.box((s * 3.4, -D / 2 - 0.06, 5.6), (1.0, 0.06, 2.6), "ds_cloth_red")
        mb.box((s * 3.4, -D / 2 - 0.1, 5.6), (0.3, 0.04, 2.3), "ds_gold")
        mb.box((s * 3.4, -D / 2 - 0.08, 6.95), (1.2, 0.12, 0.1), "ds_wood_dark")
    mb.finish("desert_gate")


def _house_door(mb, x, y, half=0.55, spring=1.7, sign=-1, stripes=False):
    arch_opening(mb, x, 0.0, half, spring, y, 0.25, "ds_opening", sign=sign)
    if stripes:
        voussoirs(mb, x, spring, half, y, ["ds_stripe", "ds_cream"], count=4, width=0.28, proud=0.07, sign=sign)
    else:
        voussoirs(mb, x, spring, half, y, ["ds_sandstone_light"], count=4, width=0.2, proud=0.06, sign=sign)
    mb.box((x, y + sign * 0.3, 0.07), (2 * half + 0.6, 0.6, 0.14), "ds_sandstone_dark")


def _window(mb, x, z, y, sign=-1, w=0.34, grille=True):
    arch_opening(mb, x, z - 0.45, w, z + 0.1, y, 0.12, "ds_opening", sign=sign)
    if grille:
        mb.box((x, y + sign * 0.03, z - 0.2), (2 * w - 0.06, 0.04, 0.05), "ds_wood_dark")
        mb.box((x, y + sign * 0.03, z - 0.15), (0.05, 0.04, 0.6), "ds_wood_dark")
    mb.box((x, y + sign * 0.06, z - 0.5), (2 * w + 0.2, 0.14, 0.08), "ds_sandstone_light")


def build_desert_house_a():
    """Flat-roofed sandstone house (6 x 6 m, 4.4 m) with an arched door, grilled windows, a
    parapet, a roof pergola with a saffron cloth, and water jars on the roof."""
    mb = MeshBuilder()
    rng = random.Random(111)
    W, D, H = 6.0, 6.0, 4.2
    mb.box((0, 0, H / 2), (W, D, H), "ds_plaster")
    mb.box((0, 0, 0.2), (W + 0.12, D + 0.12, 0.4), "ds_sandstone_dark")
    band(mb, 0, 0, W, D, H - 0.25, H, "ds_sandstone_b", grow=0.08)
    # parapet ring
    for s in (-1, 1):
        mb.box((0, s * (D / 2 - 0.12), H + 0.3), (W + 0.16, 0.3, 0.6), "ds_plaster_b")
        mb.box((s * (W / 2 - 0.12), 0, H + 0.3), (0.3, D - 0.2, 0.6), "ds_plaster_b")
    mb.box((0, 0, H + 0.02), (W - 0.3, D - 0.3, 0.06), "ds_sandstone_top")
    for k in range(7):
        x = -W / 2 + 0.45 + k * (W - 0.9) / 6
        mb.box((x, -D / 2 - 0.02, H + 0.66), (0.3, 0.3, 0.14), "ds_plaster")
    _house_door(mb, -1.2, -D / 2, sign=-1)
    _window(mb, 1.3, 2.4, -D / 2)
    _window(mb, 1.3, 2.4, D / 2, sign=1)
    _window(mb, -1.3, 2.4, D / 2, sign=1)
    # side windows (rotate a front window onto the x faces)
    for s in (-1, 1):
        before = len(mb.bm.verts)
        _window(mb, 0.0, 2.4, -D / 2)
        mb.bm.verts.ensure_lookup_table()
        mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))], Matrix.Rotation(s * math.pi / 2, 4, "Z"))
    # roof pergola in the back-left corner
    px, py = -1.3, 1.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((px + sx * 1.2, py + sy * 1.1, H + 1.1), (0.14, 0.14, 2.2), "ds_wood")
    for sy in (-1, 1):
        mb.box((px, py + sy * 1.1, H + 2.25), (2.7, 0.12, 0.12), "ds_wood_dark")
    for k in range(4):
        mb.box((px, py - 1.1 + k * 0.73, H + 2.33), (2.4, 0.5, 0.04), "ds_cloth_saffron" if k % 2 == 0 else "ds_cloth_cream")
    # roof clutter: jars and a rolled carpet
    for (x, y, h) in ((1.8, 1.7, 0.7), (2.2, 1.2, 0.55), (1.5, 2.2, 0.5)):
        lathe_pot(mb, x, y, H + 0.05, h, 0.26, "ds_pot" if rng.random() < 0.6 else "ds_pot_dark")
    mb.cyl_between((0.6, -1.6, H + 0.2), (2.4, -1.6, H + 0.2), 0.17, 0.17, "ds_cloth_red", segs=8)
    # outside: a bench and a pot by the door
    mb.box((1.6, -D / 2 - 0.35, 0.25), (1.6, 0.5, 0.5), "ds_sandstone_b")
    lathe_pot(mb, -2.4, -D / 2 - 0.4, 0.0, 0.8, 0.3, "ds_pot", handles=True)
    stone_blocks(mb, rng, -W / 2 + 0.1, W / 2 - 0.1, 0.5, 3.8, -D / 2, "ds_plaster_b", 3)
    mb.finish("desert_house_a")


def build_desert_house_b():
    """Two-storey house (6 x 5 m): the upper floor set back with a roof terrace, a wooden
    screened balcony, a striped awning over the door and a stripe course."""
    mb = MeshBuilder()
    rng = random.Random(113)
    W, D = 6.0, 5.0
    H1, H2 = 3.6, 3.0
    mb.box((0, 0, H1 / 2), (W, D, H1), "ds_sandstone_light")
    mb.box((0, 0, 0.2), (W + 0.12, D + 0.12, 0.4), "ds_sandstone_dark")
    band(mb, 0, 0, W, D, H1 - 0.3, H1, "ds_stripe", grow=0.05)
    # upper storey set back to the rear
    uw, ud = 4.2, 3.2
    uy = D / 2 - ud / 2 - 0.1
    mb.box((0.6, uy, H1 + H2 / 2), (uw, ud, H2), "ds_plaster")
    band(mb, 0.6, uy, uw, ud, H1 + H2 - 0.25, H1 + H2, "ds_sandstone_b", grow=0.07)
    # parapets
    mb.box((0, -D / 2 + 0.12, H1 + 0.35), (W + 0.1, 0.24, 0.7), "ds_sandstone_light")
    for s in (-1, 1):
        mb.box((s * (W / 2 - 0.12), 0, H1 + 0.35), (0.24, D, 0.7), "ds_sandstone_light")
    mb.box((0, 0, H1 + 0.02), (W - 0.3, D - 0.3, 0.06), "ds_sandstone_top")
    for s in (-1, 1):
        mb.box((0.6, uy + s * (ud / 2 - 0.1), H1 + H2 + 0.25), (uw + 0.1, 0.2, 0.5), "ds_plaster_b")
        mb.box((0.6 + s * (uw / 2 - 0.1), uy, H1 + H2 + 0.25), (0.2, ud, 0.5), "ds_plaster_b")
    mb.box((0.6, uy, H1 + H2 + 0.02), (uw - 0.3, ud - 0.3, 0.06), "ds_sandstone_top")
    # door with striped awning
    _house_door(mb, -1.5, -D / 2, sign=-1, stripes=True)
    ang = math.radians(22)
    for k in range(5):
        x = -2.5 + k * 0.5 + 0.25
        mb.box((x, -D / 2 - 0.55, 2.55), (0.5, 1.2, 0.04), "ds_cloth_red" if k % 2 == 0 else "ds_cloth_cream", rot=(ang, 0, 0))
    for s in (-1, 1):
        mb.cyl_between((-1.5 + s * 1.2, -D / 2 - 1.05, 0.0), (-1.5 + s * 1.2, -D / 2 - 1.05, 2.35), 0.04, 0.04, "ds_wood_dark", segs=5)
    _window(mb, 1.5, 2.3, -D / 2)
    # upper floor: screened wooden balcony (mashrabiya) on the front of the upper storey
    by = uy - ud / 2
    mb.box((0.6, by - 0.35, H1 + 1.2), (1.8, 0.7, 1.6), "ds_wood_dark")
    for k in range(5):
        mb.box((0.6 - 0.72 + k * 0.36, by - 0.71, H1 + 1.2), (0.06, 0.03, 1.4), "ds_wood")
    for k in range(4):
        mb.box((0.6, by - 0.71, H1 + 0.62 + k * 0.38), (1.7, 0.03, 0.05), "ds_wood")
    mb.box((0.6, by - 0.35, H1 + 2.08), (2.0, 0.9, 0.12), "ds_wood")
    _window(mb, 2.1, H1 + 1.8, by, w=0.3)
    # terrace clutter: potted plant, cushions, jars
    lathe_pot(mb, -2.2, -1.5, H1 + 0.05, 0.55, 0.3, "ds_pot")
    mb.ico((-2.2, -1.5, H1 + 0.95), 0.45, "ds_shrub", subdiv=1, jitter=0.06, rng=rng, scale=(1, 1, 0.8))
    mb.box((-1.0, -1.7, H1 + 0.15), (1.2, 0.8, 0.2), "ds_cloth_blue")
    mb.box((-1.0, -1.35, H1 + 0.35), (1.2, 0.2, 0.3), "ds_cloth_teal")
    for s in (-1, 1):
        before = len(mb.bm.verts)
        _window(mb, 0.0, 2.3, -W / 2)
        mb.bm.verts.ensure_lookup_table()
        mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))], Matrix.Rotation(s * math.pi / 2, 4, "Z"))
    stone_blocks(mb, rng, -W / 2 + 0.1, W / 2 - 0.1, 0.5, 3.2, -D / 2, "ds_sandstone", 3)
    mb.finish("desert_house_b")


def build_desert_house_c():
    """Domed house (5 x 5 m): a cube with a stripe band, an octagonal drum and a cream dome with a
    gilded finial, corner pinnacles and a striped arched door."""
    mb = MeshBuilder()
    rng = random.Random(117)
    W, H = 5.0, 4.4
    mb.box((0, 0, H / 2), (W, W, H), "ds_sandstone_light")
    mb.box((0, 0, 0.2), (W + 0.14, W + 0.14, 0.4), "ds_sandstone_dark")
    for k, z in enumerate((2.9, 3.2)):
        band(mb, 0, 0, W, W, z, z + 0.3, "ds_stripe" if k == 0 else "ds_cream", grow=0.04)
    band(mb, 0, 0, W, W, H - 0.2, H, "ds_sandstone_b", grow=0.1)
    mb.box((0, 0, H + 0.02), (W - 0.2, W - 0.2, 0.06), "ds_sandstone_top")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (W / 2 - 0.25), sy * (W / 2 - 0.25), H + 0.35), (0.5, 0.5, 0.7), "ds_sandstone_light")
            mb.cyl((sx * (W / 2 - 0.25), sy * (W / 2 - 0.25), H + 0.95), 0.22, 0.0, 0.6, "ds_sandstone_b", segs=4, twist=math.pi / 4)
    mb.cyl((0, 0, H + 0.45), 1.75, 1.75, 0.9, "ds_sandstone_light", segs=8, twist=math.pi / 8)
    prof = [(0.0, 0.0)] + [(1.9 * math.cos(math.pi / 2 * i / 6), 1.95 * math.sin(math.pi / 2 * i / 6)) for i in range(6)] + [(0.0, 1.95)]
    mb.lathe(prof, "ds_cream", segs=12, center=(0, 0, H + 0.9))
    top = H + 0.9 + 1.95
    mb.cyl((0, 0, top + 0.2), 0.1, 0.03, 0.45, "ds_gold", segs=6)
    mb.ico((0, 0, top + 0.5), 0.12, "ds_gold", subdiv=1)
    _house_door(mb, 0.0, -W / 2, half=0.65, spring=1.9, sign=-1, stripes=True)
    for x in (-1.6, 1.6):
        _window(mb, x, 2.2, -W / 2, w=0.28)
    for s in (-1, 1):
        before = len(mb.bm.verts)
        _window(mb, 0.0, 2.2, -W / 2, w=0.3)
        mb.bm.verts.ensure_lookup_table()
        mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))], Matrix.Rotation(s * math.pi / 2, 4, "Z"))
    _window(mb, 0.0, 2.2, W / 2, sign=1, w=0.3)
    lathe_pot(mb, 1.2, -W / 2 - 0.4, 0.0, 0.7, 0.28, "ds_pot", handles=True)
    lathe_pot(mb, 1.7, -W / 2 - 0.35, 0.0, 0.5, 0.22, "ds_pot_dark")
    stone_blocks(mb, rng, -W / 2 + 0.1, W / 2 - 0.1, 0.5, 2.8, -W / 2, "ds_sandstone", 3)
    mb.finish("desert_house_c")


def build_desert_colonnade():
    """Arcade segment 6 m along X (tiles end to end: columns every 3 m), 1.3 m deep: sandstone
    columns with gilded capitals carrying pointed arches and a cornice."""
    mb = MeshBuilder()
    D = 1.3
    top_z, spring = 5.4, 3.0
    for x in (-1.5, 1.5):
        mb.box((x, 0, 0.18), (0.8, 0.8, 0.36), "ds_sandstone_dark")
        mb.cyl((x, 0, 1.68), 0.28, 0.25, 2.64, "ds_sandstone_light", segs=8)
        mb.cyl((x, 0, 3.1), 0.3, 0.42, 0.2, "ds_gold", segs=8)
        mb.box((x, 0, 3.26), (0.9, 0.9, 0.14), "ds_sandstone")
    # arcade wall: arch between the columns + half arches at the ends
    a = pointed_arch(0.0, spring + 0.33, 1.2, n=6)
    left_half = pointed_arch(-3.0, spring + 0.33, 1.2, n=6)[6:]
    right_half = pointed_arch(3.0, spring + 0.33, 1.2, n=6)[:7]
    # outline (CCW in x/z): top edge right -> left, down the left end, along the bottom over the
    # arches left -> right, up the right end
    pts = [(3.0, top_z), (-3.0, top_z)] + left_half + a + right_half
    # pts: top-right, top-left, left apex -> x=-1.8 spring, (-1.2 spring), arch left->right, (1.2 spring), 1.8 -> right apex
    # remove duplicates at the springs
    clean = []
    for p in pts:
        if not clean or (abs(clean[-1][0] - p[0]) > 1e-6 or abs(clean[-1][1] - p[1]) > 1e-6):
            clean.append(p)
    mb.prism(clean, -D / 2 + 0.15, D / 2 - 0.15, "ds_sandstone", frame=(Vector((0, 0, 0)), X, Z, -Y))
    # stripe voussoirs on the front and a cornice
    voussoirs(mb, 0.0, spring + 0.33, 1.2, -D / 2 + 0.15, ["ds_stripe", "ds_cream"], count=4, width=0.3, proud=0.06)
    mb.box((0, 0, top_z + 0.12), (6.0, D, 0.24), "ds_sandstone_light")
    mb.box((0, 0, top_z + 0.3), (6.0, D - 0.3, 0.12), "ds_sandstone_top")
    merlons_x(mb, -3.0, 3.0, -D / 2 + 0.12, top_z + 0.24, 0.24, 6, "ds_sandstone_light", w=0.5, h=0.4)
    mb.finish("desert_colonnade")


# ----------------------------------------------------------------------------------- monuments

def build_desert_obelisk():
    """Obelisk on a stepped plinth (~7.2 m) with carved glyph bands and a glowing gilded
    pyramidion — the Qadesh waystone."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.2), (2.4, 2.4, 0.4), "ds_sandstone_dark")
    mb.box((0, 0, 0.6), (1.8, 1.8, 0.4), "ds_sandstone")
    mb.box((0, 0, 0.88), (1.3, 1.3, 0.16), "ds_sandstone_light")
    h = 5.6
    mb.box((0, 0, 0.96 + h / 2), (0.92, 0.92, h), "ds_sandstone_light", taper=(0.62, 0.62))
    top = 0.96 + h
    tw = 0.92 * 0.62
    hull(mb, [(tw / 2, tw / 2, top), (-tw / 2, tw / 2, top), (tw / 2, -tw / 2, top), (-tw / 2, -tw / 2, top),
             (0, 0, top + 0.62)], "ds_gold_glow")
    # glyph columns: small dark marks on all four faces
    rng = random.Random(121)
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 4, "Z")
        for i in range(9):
            z = 1.4 + i * 0.52
            w_here = 0.92 * (1 - 0.38 * (z - 0.96) / h) / 2
            for dx in (-0.13, 0.13):
                if rng.random() < 0.8:
                    sx = rng.choice((0.1, 0.06, 0.14))
                    sz = rng.choice((0.1, 0.18, 0.06))
                    before = len(mb.bm.verts)
                    mb.box((dx * (w_here / 0.46), -w_here - 0.005, z), (sx, 0.03, sz), "ds_stripe" if i % 3 else "ds_lapis")
                    mb.bm.verts.ensure_lookup_table()
                    mb.transform([mb.bm.verts[j] for j in range(before, len(mb.bm.verts))], rot)
    # offering bowls glowing on the plinth
    for s in (-1, 1):
        mb.lathe([(0.0, 0.0), (0.12, 0.0), (0.22, 0.14), (0.2, 0.16), (0.0, 0.1)], "ds_bronze", segs=8, center=(s * 0.72, -0.72, 0.8))
        mb.ico((s * 0.72, -0.72, 0.98), 0.1, "ds_fire_core", subdiv=0)
    mb.finish("desert_obelisk")


def build_desert_obelisk_fallen():
    """A toppled obelisk broken in three pieces, half sunk in the sand (~8 x 2 m)."""
    mb = MeshBuilder()
    rng = random.Random(123)
    pieces = [((-2.6, 0.0), 2.6, 0.9, 0.82, 0.08), ((0.4, 0.25), 2.4, 0.8, 0.72, -0.12), ((2.9, -0.2), 1.6, 0.7, 0.62, 0.3)]
    for (x, y), ln, w0, w1, yaw in pieces:
        before = len(mb.bm.verts)
        mb.box((0, 0, 0), (ln, w0, w0), "ds_sandstone_light", taper=None)
        mb.bm.verts.ensure_lookup_table()
        new = [mb.bm.verts[i] for i in range(before, len(mb.bm.verts))]
        for v in new:
            k = (v.co.x + ln / 2) / ln
            sc = (w0 + (w1 - w0) * k) / w0
            v.co.y *= sc
            v.co.z *= sc
            v.co.x += rng.uniform(-0.05, 0.05) if abs(v.co.x) > ln / 2 - 0.01 else 0.0
        mb.transform(new, Matrix.Translation((x, y, w0 * 0.22)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(0.12, 4, "X"))
        mb.ico((x, y + 0.3, 0.0), 1.0, "ds_sand", subdiv=1, scale=(ln * 0.5, 1.1, 0.42), flatten_below=0.0)
        for i in range(3):
            gx = x - ln / 2 + (i + 0.5) * ln / 3
            mb.box((gx, y - w0 / 2 + 0.02, w0 * 0.55), (0.14, 0.05, 0.12), "ds_stripe")
    hull(mb, [(4.1, -0.7, 0.0), (4.8, -0.9, 0.0), (4.6, -0.2, 0.0), (4.4, -0.55, 0.55)], "ds_gold")
    for i in range(5):
        hull(mb, L.rock_points((rng.uniform(-3, 3.5), rng.uniform(-1.2, 1.2), 0.0), (0.25, 0.2, 0.18), rng, n=8), "ds_sandstone")
    mb.clamp_floor()
    mb.finish("desert_obelisk_fallen")


def build_desert_pyramid():
    """A great pyramid (40 m base, ~26 m): stepped courses of dressed stone (reads as the Giza
    slope from afar, as blocks close up) with a gilded capstone and a dark entrance."""
    mb = MeshBuilder()
    B = 40.0
    steps = 26
    hstep = 1.0
    for k in range(steps):
        half = B / 2 - k * (B / 2 - 1.3) / steps
        mat = "ds_sandstone_light" if k % 2 == 0 else "ds_sandstone"
        mb.box((0, 0, k * hstep + hstep / 2), (2 * half, 2 * half, hstep), mat)
    top = steps * hstep
    hull(mb, [(1.3, 1.3, top), (-1.3, 1.3, top), (1.3, -1.3, top), (-1.3, -1.3, top), (0, 0, top + 2.2)], "ds_gold_glow")
    # entrance on the north... front (-Y) face, a few courses up
    z = 5.0
    half_at = B / 2 - int(z) * (B / 2 - 1.3) / steps
    mb.box((0, -half_at + 0.9, z + 1.2), (2.4, 2.0, 2.4), "ds_sandstone_b")
    hull(mb, [(-1.3, -half_at - 0.1, z + 2.4), (1.3, -half_at - 0.1, z + 2.4), (0, -half_at - 0.1, z + 3.3),
             (-1.3, -half_at + 1.5, z + 2.4), (1.3, -half_at + 1.5, z + 2.4), (0, -half_at + 1.5, z + 3.3)], "ds_sandstone_light")
    mb.box((0, -half_at - 0.1 + 0.05, z + 1.1), (1.3, 0.1, 1.9), "ds_opening")
    mb.finish("desert_pyramid")


def build_desert_statue():
    """Seated colossus of a pharaoh (~8 m) on a plinth, hands on knees, nemes headdress in blue
    and gold, facing the front (-Y)."""
    mb = MeshBuilder()
    stone = "ds_sandstone"
    mb.box((0, 0.2, 0.6), (3.4, 5.0, 1.2), "ds_sandstone_dark")
    mb.box((0, 0.2, 1.28), (3.1, 4.7, 0.16), "ds_sandstone_b")
    # throne
    mb.box((0, 1.1, 2.9), (2.6, 2.2, 3.1), "ds_sandstone_b")
    mb.box((0, 1.95, 4.6), (2.4, 0.5, 3.4), "ds_sandstone_b")
    for s in (-1, 1):
        mb.box((s * 1.33, 1.1, 3.0), (0.06, 1.9, 2.4), "ds_lapis")
    # legs (shins) and feet
    for s in (-1, 1):
        mb.box((s * 0.55, -0.55, 2.4), (0.8, 0.9, 2.2), stone, taper=(0.9, 0.95))
        mb.box((s * 0.55, -0.85, 1.52), (0.8, 1.2, 0.32), stone)
        # thighs
        mb.box((s * 0.55, 0.35, 3.75), (0.86, 2.0, 0.8), stone)
    # kilt front
    mb.box((0, -0.05, 3.3), (1.0, 0.25, 1.1), "ds_cream", taper=(1.3, 1.0))
    # torso
    mb.box((0, 0.95, 5.3), (1.9, 1.2, 2.4), stone, taper=(1.15, 0.9))
    mb.box((0, 0.35, 5.9), (1.2, 0.08, 0.5), "ds_lapis")
    mb.box((0, 0.33, 5.9), (1.3, 0.06, 0.2), "ds_gold")
    # arms resting on the thighs
    for s in (-1, 1):
        mb.cyl_between((s * 1.05, 1.0, 6.1), (s * 1.0, 0.9, 4.5), 0.32, 0.28, stone, segs=6)
        mb.cyl_between((s * 0.95, 0.9, 4.35), (s * 0.7, -0.4, 4.35), 0.26, 0.22, stone, segs=6)
        mb.box((s * 0.65, -0.55, 4.3), (0.45, 0.5, 0.3), stone)
    # head with nemes headdress (blue / gold stripes) and a false beard
    mb.box((0, 0.95, 6.75), (0.62, 0.7, 0.8), stone)
    hull(mb, [(-0.95, 1.3, 6.2), (0.95, 1.3, 6.2), (-0.55, 0.65, 6.2), (0.55, 0.65, 6.2),
             (-0.5, 1.15, 7.45), (0.5, 1.15, 7.45), (-0.4, 0.8, 7.3), (0.4, 0.8, 7.3)], "ds_gold")
    for k in range(3):
        mb.box((0, 0.76, 6.45 + k * 0.33), (1.0 - k * 0.12, 0.08, 0.1), "ds_lapis")
    mb.box((0, 0.58, 6.72), (0.5, 0.1, 0.55), stone)
    mb.box((0, 0.6, 6.25), (0.2, 0.18, 0.4), "ds_lapis")
    mb.cyl((0, 0.95, 7.7), 0.32, 0.2, 0.6, "ds_cream", segs=8)
    mb.ico((0, 0.95, 8.05), 0.18, "ds_gold", subdiv=1)
    for s in (-1, 1):
        mb.box((s * 0.17, 0.57, 6.87), (0.12, 0.04, 0.06), "ds_stripe")
    mb.finish("desert_statue")


def build_desert_sphinx():
    """Recumbent sphinx (~12 m long, 6 m tall) on a plinth, paws forward toward the front (-Y)."""
    mb = MeshBuilder()
    rng = random.Random(127)
    stone = "ds_sandstone"
    mb.box((0, 0.5, 0.45), (5.4, 12.6, 0.9), "ds_sandstone_dark")
    # body (lying lion)
    hull(mb, [(-2.0, 5.2, 0.9), (2.0, 5.2, 0.9), (-2.2, -1.5, 0.9), (2.2, -1.5, 0.9),
             (-1.7, 5.4, 3.0), (1.7, 5.4, 3.0), (-1.9, 1.0, 3.5), (1.9, 1.0, 3.5),
             (-1.8, -1.2, 3.2), (1.8, -1.2, 3.2), (0, 5.8, 2.4)], stone)
    # haunches
    for s in (-1, 1):
        mb.ico((s * 1.7, 4.0, 1.9), 1.2, stone, subdiv=1, scale=(0.6, 1.3, 0.9), flatten_below=0.9)
    # forepaws
    for s in (-1, 1):
        mb.box((s * 1.2, -3.6, 1.35), (1.0, 4.4, 0.9), stone, bevel=0.08)
        for k in range(3):
            mb.box((s * 1.2 - 0.3 + k * 0.3, -5.82, 1.2), (0.22, 0.1, 0.5), "ds_sandstone_b")
    # chest and neck
    hull(mb, [(-1.6, -1.8, 0.9), (1.6, -1.8, 0.9), (-1.4, -1.6, 4.6), (1.4, -1.6, 4.6),
             (-1.5, 0.2, 3.6), (1.5, 0.2, 3.6)], stone)
    # head with nemes
    mb.box((0, -1.9, 5.05), (1.2, 1.1, 1.3), stone)
    hull(mb, [(-1.5, -1.0, 4.3), (1.5, -1.0, 4.3), (-0.95, -2.0, 4.4), (0.95, -2.0, 4.4),
             (-0.75, -1.3, 6.1), (0.75, -1.3, 6.1), (-0.6, -2.0, 5.9), (0.6, -2.0, 5.9)], "ds_sandstone_light")
    for k in range(4):
        mb.box((0, -1.02 - 0.0, 4.55 + k * 0.38), (2.2 - k * 0.25, 0.1, 0.12), "ds_sandstone_b")
    mb.box((0, -2.48, 5.0), (0.9, 0.12, 0.9), stone)
    mb.box((0, -2.56, 5.05), (0.18, 0.12, 0.3), "ds_sandstone_b")
    mb.box((0, -2.4, 4.3), (0.3, 0.2, 0.55), "ds_sandstone_b")
    for s in (-1, 1):
        mb.box((s * 0.24, -2.56, 5.3), (0.18, 0.04, 0.07), "ds_stripe")
    # tail curled along the side
    mb.cyl_between((1.9, 5.5, 1.1), (2.35, 2.5, 1.0), 0.16, 0.12, stone, segs=5)
    for i in range(6):
        hull(mb, L.rock_points((rng.uniform(-3.2, 3.2), rng.uniform(-6.5, 6.5), 0.0), (0.3, 0.25, 0.2), rng, n=8), "ds_sandstone_b")
    mb.clamp_floor()
    mb.finish("desert_sphinx")


def build_desert_head():
    """A giant broken statue head (nemes headdress) half buried in the sand (~4 m)."""
    mb = MeshBuilder()
    stone = "ds_sandstone"
    rot = Matrix.Rotation(-0.35, 4, "Y") @ Matrix.Rotation(0.15, 4, "X")
    before = len(mb.bm.verts)
    mb.box((0, 0, 1.4), (1.8, 2.0, 2.4), stone)
    hull(mb, [(-2.3, 0.9, 0.3), (2.3, 0.9, 0.3), (-1.5, -0.8, 0.4), (1.5, -0.8, 0.4),
             (-1.2, 0.6, 3.4), (1.2, 0.6, 3.4), (-0.9, -0.7, 3.2), (0.9, -0.7, 3.2)], "ds_sandstone_light")
    for k in range(4):
        mb.box((0, -0.82, 0.8 + k * 0.6), (3.0 - k * 0.45, 0.12, 0.18), "ds_sandstone_b")
    mb.box((0, -1.08, 1.5), (1.4, 0.25, 1.5), stone)
    mb.box((0, -1.25, 1.55), (0.3, 0.2, 0.5), "ds_sandstone_b")
    mb.box((0, -1.2, 0.8), (0.8, 0.14, 0.18), "ds_sandstone_dark")
    for s in (-1, 1):
        mb.box((s * 0.38, -1.22, 1.95), (0.34, 0.06, 0.1), "ds_stripe")
        mb.box((s * 0.38, -1.21, 2.1), (0.4, 0.05, 0.06), "ds_sandstone_dark")
    mb.bm.verts.ensure_lookup_table()
    mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))], rot)
    rng = random.Random(129)
    for i in range(5):
        hull(mb, L.rock_points((rng.uniform(-2.5, 2.5), rng.uniform(-2, 2), 0.0), (0.35, 0.3, 0.2), rng, n=8), "ds_sandstone_b")
    mb.box((0, 0, 0.1), (5.0, 3.6, 0.2), "ds_sandstone_b")
    mb.clamp_floor()
    mb.finish("desert_head")


def build_desert_column():
    """Egyptian papyrus column (~6.2 m): painted bands, an open bell capital and an abacus."""
    mb = MeshBuilder()
    mb.cyl((0, 0, 0.2), 0.85, 0.8, 0.4, "ds_sandstone_dark", segs=10)
    mb.lathe([(0.0, 0.0), (0.56, 0.0), (0.6, 0.6), (0.58, 2.8), (0.5, 4.3), (0.42, 4.5), (0.0, 4.5)],
             "ds_sandstone_light", segs=10, center=(0, 0, 0.4))
    for z, m in ((1.2, "ds_lapis"), (1.35, "ds_red_paint"), (3.9, "ds_lapis"), (4.05, "ds_red_paint"), (4.2, "ds_turquoise")):
        r = 0.595 if z < 3 else 0.5
        mb.cyl((0, 0, z), r, r * 0.995, 0.12, m, segs=10)
    # bell capital
    mb.lathe([(0.0, 0.0), (0.42, 0.0), (0.62, 0.45), (0.95, 1.0), (1.0, 1.1), (0.0, 1.1)],
             "ds_sandstone_light", segs=12, center=(0, 0, 4.85))
    for i in range(6):
        a = 2 * math.pi * i / 6
        mb.box((0.78 * math.cos(a), 0.78 * math.sin(a), 5.55), (0.1, 0.06, 0.7), "ds_turquoise", rot=(0, 0, a + math.pi / 2))
    mb.box((0, 0, 6.05), (1.3, 1.3, 0.22), "ds_sandstone")
    mb.finish("desert_column")


def build_desert_column_broken():
    """A broken column stump with its fallen drums beside it (~3 x 3 m)."""
    mb = MeshBuilder()
    rng = random.Random(131)
    mb.cyl((0, 0, 0.2), 0.85, 0.8, 0.4, "ds_sandstone_dark", segs=10)
    mb.cyl((0, 0, 1.3), 0.58, 0.58, 1.8, "ds_sandstone_light", segs=10)
    mb.cyl((0, 0, 1.35), 0.595, 0.595, 0.12, "ds_lapis", segs=10)
    hull(mb, [(0.58 * math.cos(a), 0.58 * math.sin(a), 2.2 + rng.uniform(-0.1, 0.5)) for a in
             [2 * math.pi * i / 10 for i in range(10)]] + [(0.3, 0.1, 2.2), (-0.2, 0.2, 2.2)], "ds_sandstone_light")
    for (x, y, yaw) in ((1.5, -0.6, 0.3), (-1.3, 1.1, 1.3)):
        before = len(mb.bm.verts)
        mb.cyl((0, 0, 0), 0.56, 0.56, 1.1, "ds_sandstone_light", segs=10, rot=(math.pi / 2, 0, 0))
        mb.bm.verts.ensure_lookup_table()
        mb.transform([mb.bm.verts[i] for i in range(before, len(mb.bm.verts))],
                     Matrix.Translation((x, y, 0.5)) @ Matrix.Rotation(yaw, 4, "Z"))
    for i in range(4):
        hull(mb, L.rock_points((rng.uniform(-1.6, 1.6), rng.uniform(-1.6, 1.6), 0.0), (0.2, 0.18, 0.15), rng, n=7), "ds_sandstone")
    mb.clamp_floor()
    mb.finish("desert_column_broken")


def build_desert_pylon():
    """Temple pylon gateway (18 m wide, 11 m): two battered towers with painted reliefs, a
    cornice, flagpoles with banners and a dark gate between them — the boss forecourt backdrop."""
    mb = MeshBuilder()
    rng = random.Random(137)
    for s in (-1, 1):
        cx = s * 5.0
        mb.box((cx, 0, 5.25), (7.0, 4.0, 10.5), "ds_sandstone", taper=(0.8, 0.8))
        band(mb, cx, 0, 7.0 * 0.8, 4.0 * 0.8, 10.2, 10.6, "ds_sandstone_light", grow=0.25)
        mb.box((cx, 0, 10.7), (6.0, 3.6, 0.2), "ds_sandstone_top")
        # relief panel: pharaoh smiting, as coloured blocks
        yface = -2.0 + 0.2 * (4.2 / 10.5)
        mb.box((cx, -1.9, 4.5), (4.4, 0.1, 5.4), "ds_sandstone_b")
        mb.box((cx - s * 0.8, -1.97, 4.3), (0.8, 0.06, 2.6), "ds_lapis")
        mb.box((cx - s * 0.8, -1.97, 5.95), (0.5, 0.06, 0.6), "ds_gold")
        mb.box((cx + s * 0.8, -1.97, 3.9), (0.6, 0.06, 1.8), "ds_red_paint")
        for k in range(6):
            mb.box((cx + rng.uniform(-1.8, 1.8), -1.97, rng.uniform(2.2, 6.8)), (0.2, 0.05, 0.3), "ds_stripe")
        # flagpole slots with banners
        for dx in (-1.6, 1.6):
            x = cx + dx
            mb.box((x, -2.25, 7.0), (0.22, 0.22, 11.5), "ds_wood_dark")
            mb.box((x + 0.35, -2.3, 11.5), (0.6, 0.05, 1.8), "ds_cloth_red" if dx < 0 else "ds_cloth_saffron")
    # gate between the towers
    mb.box((0, 0, 3.6), (3.4, 3.4, 7.2), "ds_sandstone_b")
    band(mb, 0, 0, 3.4, 3.4, 6.7, 7.2, "ds_sandstone_light", grow=0.15)
    mb.box((0, -1.72, 2.6), (1.8, 0.1, 5.2), "ds_opening")
    hull(mb, [(-0.7, -1.9, 6.1), (0.7, -1.9, 6.1), (0.0, -1.9, 6.5), (-0.7, -1.75, 6.1), (0.7, -1.75, 6.1), (0.0, -1.75, 6.5)], "ds_gold")
    for s in (-1, 1):
        mb.box((s * 1.2, -1.95, 3.0), (0.3, 0.4, 6.0), "ds_sandstone_light")
    mb.finish("desert_pylon")


def build_desert_tomb():
    """Mastaba tomb (8 x 6 m, 4 m): a battered flat-topped block with a dark doorway, stairs down,
    a false door stela and offering jars."""
    mb = MeshBuilder()
    mb.box((0, 0.4, 2.0), (8.0, 6.0, 4.0), "ds_sandstone", taper=(0.86, 0.84))
    band(mb, 0, 0.4, 8.0 * 0.86, 6.0 * 0.84, 3.75, 4.05, "ds_sandstone_light", grow=0.1)
    mb.box((0, 0.4, 4.08), (6.4, 4.6, 0.08), "ds_sandstone_top")
    # entrance porch
    mb.box((0, -2.75, 1.5), (3.0, 1.2, 3.0), "ds_sandstone_b")
    mb.box((0, -3.2, 3.1), (3.4, 0.6, 0.3), "ds_sandstone_light")
    mb.box((0, -3.36, 1.1), (1.3, 0.1, 2.2), "ds_opening")
    for s in (-1, 1):
        mb.box((s * 0.85, -3.4, 1.2), (0.3, 0.15, 2.4), "ds_sandstone_light")
        mb.box((s * 2.4, -2.62, 1.4), (0.7, 0.1, 2.0), "ds_sandstone_light")
        mb.box((s * 2.4, -2.68, 1.6), (0.35, 0.05, 1.2), "ds_opening")
    for k in range(3):
        mb.box((0, -3.6 - k * 0.3, 0.3 - k * 0.1), (1.8, 0.3, 0.2), "ds_sandstone_dark")
    lathe_pot(mb, -1.4, -3.7, 0.0, 0.7, 0.28, "ds_pot", handles=True)
    lathe_pot(mb, 1.5, -3.6, 0.0, 0.5, 0.24, "ds_pot_dark", lid="ds_pot_light")
    mb.finish("desert_tomb")


# ----------------------------------------------------------------------------------- plants

def _palm(mb, rng, base, height, lean, lean_dir, fronds=9, frond_len=3.0, trunk_r=0.26, dates=True, dry=0):
    """A date palm: segmented curved trunk and a crown of drooping fronds with leaflet notches."""
    bx, by = base
    ld = Vector((math.cos(lean_dir), math.sin(lean_dir), 0.0))
    segs = 9
    pts = []
    for i in range(segs + 1):
        t = i / segs
        off = ld * (lean * t * t)
        pts.append(Vector((bx, by, 0.0)) + off + Z * (height * t))
    for i in range(segs):
        r0 = trunk_r * (1.12 - 0.3 * i / segs)
        r1 = r0 * 0.82
        mb.cyl_between(pts[i] - Z * 0.02 if i else pts[i], pts[i + 1] + (pts[i + 1] - pts[i]).normalized() * 0.05,
                       r0, r1, "ds_palm_trunk" if i % 2 == 0 else "ds_palm_trunk_dark", segs=6)
    mb.cyl((bx, by, 0.12), trunk_r * 1.5, trunk_r * 1.1, 0.24, "ds_palm_trunk_dark", segs=6)
    top = pts[-1]
    mb.ico(top + Z * 0.1, trunk_r * 1.5, "ds_palm_trunk_dark", subdiv=1, scale=(1, 1, 0.9))
    pattern = [0.1, 0.55, 0.32, 0.62, 0.36, 0.58, 0.32, 0.46, 0.18, 0.04]
    for f in range(fronds):
        a = 2 * math.pi * f / fronds + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        ln = frond_len * rng.uniform(0.85, 1.1)
        rise = rng.uniform(0.5, 1.1)
        droop = rng.uniform(1.4, 2.2)
        n = len(pattern)
        fp = []
        for i in range(n):
            s = i / (n - 1)
            fp.append(top + d * (0.15 + ln * s) + Z * (0.2 + rise * s * ln * 0.45 - droop * s * s * ln * 0.45))
        side = d.cross(Z)
        up = (Z * 0.9 + side * rng.uniform(-0.3, 0.3)).normalized()
        mat = "ds_palm_leaf_dry" if f < dry else ("ds_palm_leaf" if f % 3 else ("ds_palm_leaf_dark" if f % 2 else "ds_palm_leaf_light"))
        ribbon(mb, fp, [w * ln / 3.0 for w in pattern], up, 0.05, mat)
    # a few upright young fronds
    for f in range(3):
        a = 2 * math.pi * f / 3 + 0.5
        d = Vector((math.cos(a), math.sin(a), 0.0))
        fp = [top + Z * 0.2 + d * (0.3 * s) + Z * (1.2 * s) for s in (0.0, 0.3, 0.6, 1.0)]
        ribbon(mb, fp, [0.1, 0.3, 0.25, 0.03], d.cross(Z).normalized(), 0.05, "ds_palm_leaf_light")
    if dates:
        for k in range(3):
            a = 2 * math.pi * k / 3 + 1.0
            c = top + Vector((math.cos(a), math.sin(a), 0)) * trunk_r * 1.6 - Z * 0.35
            mb.ico(c, 0.2, "ds_date", subdiv=1, scale=(1, 1, 1.4), jitter=0.02, rng=rng)


def build_desert_palm_a():
    """Tall date palm (~8 m) with a gentle lean and a full crown."""
    mb = MeshBuilder()
    rng = random.Random(141)
    _palm(mb, rng, (0.0, 0.0), 7.6, 0.9, 0.6, fronds=10, frond_len=3.2, dry=1)
    mb.finish("desert_palm_a")


def build_desert_palm_b():
    """A clump of two shorter palms (~5 m and ~6.2 m) with a shrubby base."""
    mb = MeshBuilder()
    rng = random.Random(143)
    _palm(mb, rng, (-0.35, 0.1), 5.0, 1.1, 2.6, fronds=8, frond_len=2.6, trunk_r=0.22, dates=False)
    _palm(mb, rng, (0.35, -0.1), 6.2, 0.9, -0.4, fronds=9, frond_len=2.9, trunk_r=0.24, dry=2)
    for k in range(5):
        a = 2 * math.pi * k / 5
        mb.ico((0.7 * math.cos(a), 0.7 * math.sin(a), 0.2), 0.42, "ds_shrub" if k % 2 else "ds_shrub_dark",
               subdiv=1, jitter=0.06, rng=rng, scale=(1, 1, 0.7), flatten_below=0.0)
    mb.clamp_floor()
    mb.finish("desert_palm_b")


def build_desert_reeds():
    """Papyrus clump (~2.4 m, 1.4 m across): thin stalks with starburst umbels."""
    mb = MeshBuilder()
    rng = random.Random(149)
    for k in range(13):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.6)
        base = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        h = rng.uniform(1.4, 2.5)
        tip = base + Vector((math.cos(a) * r * 0.5 + rng.uniform(-0.15, 0.15), math.sin(a) * r * 0.5 + rng.uniform(-0.15, 0.15), h))
        mb.cyl_between(base, tip, 0.035, 0.02, "ds_reed" if k % 3 else "ds_reed_dark", segs=4)
        mb.cyl(tip + Z * 0.08, 0.04, 0.3, 0.2, "ds_reed_head", segs=6)
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        base = Vector((0.45 * math.cos(a), 0.45 * math.sin(a), 0.0))
        tip = base + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, rng.uniform(0.5, 0.9)))
        ribbon(mb, [base, (base + tip) / 2 + Z * 0.1, tip], [0.12, 0.1, 0.02], Vector((math.cos(a), math.sin(a), 0.2)).cross(Z).normalized() if False else Vector((-math.sin(a), math.cos(a), 0.0)), 0.03, "ds_reed_dark")
    mb.finish("desert_reeds")


def build_desert_shrub():
    """Low green river-bank shrub (~1.8 m across)."""
    mb = MeshBuilder()
    rng = random.Random(151)
    for k in range(6):
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.3, 0.6)
        mb.ico((r * math.cos(a), r * math.sin(a), 0.35), rng.uniform(0.38, 0.55), "ds_shrub" if k % 2 else "ds_shrub_dark",
               subdiv=1, jitter=0.07, rng=rng, scale=(1, 1, 0.8))
    mb.ico((0, 0, 0.75), 0.5, "ds_palm_leaf_light", subdiv=1, jitter=0.06, rng=rng, scale=(1, 1, 0.8))
    mb.clamp_floor()
    mb.finish("desert_shrub")


# ----------------------------------------------------------------------------------- props

def build_desert_awning():
    """Market awning (3.8 x 3.2 m): four poles, a striped red/cream canopy sloping to the back,
    carpets, cushions, a low table of goods, baskets and hanging lamps. The merchant stands in
    front of it (Blender -Y)."""
    mb = MeshBuilder()
    rng = random.Random(153)
    W, D = 3.8, 3.2
    for sx in (-1, 1):
        mb.cyl_between((sx * W / 2, -D / 2, 0), (sx * W / 2, -D / 2, 2.7), 0.06, 0.06, "ds_wood_dark", segs=6)
        mb.cyl_between((sx * W / 2, D / 2, 0), (sx * W / 2, D / 2, 3.1), 0.06, 0.06, "ds_wood_dark", segs=6)
    ang = math.atan2(0.4, D)
    ln = math.hypot(D, 0.4) + 0.3
    n = 7
    for k in range(n):
        x = -W / 2 - 0.1 + (k + 0.5) * (W + 0.2) / n
        m = "ds_cloth_red" if k % 2 == 0 else "ds_cloth_cream"
        mb.box((x, 0, 2.95), ((W + 0.2) / n + 0.004, ln, 0.05), m, rot=(-ang, 0, 0))
        mb.box((x, -D / 2 - 0.12, 2.62), ((W + 0.2) / n - 0.02, 0.04, 0.3), m)
    # carpets
    mb.box((0, 0.2, 0.02), (3.4, 2.6, 0.04), "ds_cloth_red")
    mb.box((0, 0.2, 0.045), (2.8, 2.0, 0.02), "ds_cloth_blue")
    mb.box((0, 0.2, 0.06), (1.6, 1.0, 0.015), "ds_cloth_saffron")
    # back rack with hanging rugs
    mb.box((0, D / 2 - 0.1, 2.1), (W - 0.2, 0.08, 0.08), "ds_wood")
    for k, m in enumerate(("ds_cloth_teal", "ds_cloth_purple", "ds_cloth_saffron")):
        mb.box((-1.1 + k * 1.1, D / 2 - 0.12, 1.35), (0.95, 0.04, 1.5), m)
        mb.box((-1.1 + k * 1.1, D / 2 - 0.15, 1.35), (0.6, 0.03, 1.1), "ds_cloth_cream" if k != 1 else "ds_gold")
    # low table with goods
    mb.box((0, 0.1, 0.35), (1.8, 0.9, 0.08), "ds_wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 0.8, 0.1 + sy * 0.35, 0.16), (0.08, 0.08, 0.32), "ds_wood_dark")
    for k in range(4):
        lathe_pot(mb, -0.6 + k * 0.4, 0.1, 0.39, 0.3, 0.12, ["ds_bronze", "ds_pot", "ds_gold", "ds_pot_light"][k], segs=6)
    # cushions and baskets
    for (x, y, m) in ((-1.3, 0.9, "ds_cloth_teal"), (1.3, 0.9, "ds_cloth_saffron"), (1.35, 0.3, "ds_cloth_purple")):
        mb.box((x, y, 0.15), (0.7, 0.7, 0.22), m, bevel=0.05)
    for (x, y) in ((-1.55, -1.1), (1.6, -1.2)):
        mb.cyl((x, y, 0.25), 0.3, 0.36, 0.5, "ds_rope", segs=8)
        mb.ico((x, y, 0.5), 0.26, "ds_date" if x < 0 else "ds_palm_leaf_light", subdiv=1, scale=(1, 1, 0.5))
    # hanging brass lamps
    for x in (-1.0, 1.0):
        mb.cyl_between((x, 0.0, 2.9), (x, 0.0, 2.3), 0.01, 0.01, "ds_iron", segs=3)
        mb.ico((x, 0.0, 2.2), 0.13, "ds_fire_core", subdiv=1, scale=(1, 1, 1.3))
        mb.cyl((x, 0.0, 2.36), 0.12, 0.04, 0.12, "ds_bronze", segs=6)
    lathe_pot(mb, 2.2, -0.9, 0.0, 0.9, 0.32, "ds_pot", handles=True)
    lathe_pot(mb, 2.3, -0.3, 0.0, 0.6, 0.26, "ds_pot_dark", lid="ds_pot_light")
    mb.finish("desert_awning")


def build_desert_fountain():
    """Square pool (4.8 m) with a raised sandstone rim, blue water, a central fluted basin with a
    glinting jet and turquoise tile inlays."""
    mb = MeshBuilder()
    S = 4.8
    t = 0.4
    for s in (-1, 1):
        mb.box((0, s * (S / 2 - t / 2), 0.3), (S, t, 0.6), "ds_sandstone_light", bevel=0.03)
        mb.box((s * (S / 2 - t / 2), 0, 0.3), (t, S - 2 * t + 0.02, 0.6), "ds_sandstone_light", bevel=0.03)
        mb.box((0, s * (S / 2 + 0.005), 0.25), (S * 0.8, 0.02, 0.12), "ds_turquoise")
        mb.box((s * (S / 2 + 0.005), 0, 0.25), (0.02, S * 0.8, 0.12), "ds_turquoise")
    mb.box((0, 0, 0.2), (S - 2 * t + 0.02, S - 2 * t + 0.02, 0.4), "ds_water")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (S / 2 - 0.2), sy * (S / 2 - 0.2), 0.68), (0.5, 0.5, 0.2), "ds_sandstone")
            mb.lathe([(0.0, 0.0), (0.13, 0.0), (0.2, 0.2), (0.12, 0.4), (0.16, 0.5), (0.0, 0.5)], "ds_pot",
                     segs=6, center=(sx * (S / 2 - 0.2), sy * (S / 2 - 0.2), 0.78))
    mb.cyl((0, 0, 0.6), 0.35, 0.28, 0.5, "ds_sandstone", segs=8)
    mb.lathe([(0.0, 0.0), (0.3, 0.0), (0.95, 0.28), (1.0, 0.36), (0.0, 0.32)], "ds_sandstone_light", segs=10, center=(0, 0, 0.85))
    mb.cyl((0, 0, 1.19), 0.85, 0.85, 0.04, "ds_water", segs=10)
    mb.cyl((0, 0, 1.45), 0.12, 0.1, 0.5, "ds_sandstone", segs=6)
    mb.cyl((0, 0, 1.95), 0.07, 0.02, 0.6, "ds_water_jet", segs=5)
    mb.ico((0, 0, 1.75), 0.12, "ds_gold", subdiv=1)
    mb.finish("desert_fountain")


def build_desert_pots():
    """A cluster of amphorae and storage jars (~1.4 m across)."""
    mb = MeshBuilder()
    lathe_pot(mb, 0.0, 0.15, 0.0, 1.0, 0.32, "ds_pot", handles=True)
    lathe_pot(mb, -0.52, -0.2, 0.0, 0.7, 0.28, "ds_pot_dark", lid="ds_pot_light")
    lathe_pot(mb, 0.5, -0.25, 0.0, 0.55, 0.3, "ds_pot_light", neck=0.6)
    lathe_pot(mb, 0.25, 0.6, 0.0, 0.45, 0.22, "ds_pot")
    mb.cyl((-0.45, 0.45, 0.13), 0.3, 0.34, 0.26, "ds_rope", segs=8)
    mb.ico((-0.45, 0.45, 0.28), 0.26, "ds_date", subdiv=1, scale=(1, 1, 0.45))
    mb.finish("desert_pots")


def build_desert_carpet():
    """A patterned rug (2.2 x 1.4 m) lying on the ground."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.012), (2.2, 1.4, 0.024), "ds_cloth_red")
    mb.box((0, 0, 0.026), (1.8, 1.0, 0.012), "ds_cloth_blue")
    mb.box((0, 0, 0.034), (1.2, 0.5, 0.01), "ds_cloth_saffron")
    for s in (-1, 1):
        mb.box((s * 1.14, 0, 0.01), (0.1, 1.3, 0.016), "ds_cloth_cream")
    mb.finish("desert_carpet")


def build_desert_boat():
    """Felucca (~8 m) floating at the waterline (origin): upswept hull, a mast and a big cream
    lateen sail on a slanted yard."""
    mb = MeshBuilder()
    L_ = 7.6
    pts = []
    for i in range(9):
        t = i / 8
        y = -L_ / 2 + L_ * t
        w = 1.05 * math.sin(math.pi * (0.08 + 0.84 * t)) ** 0.7
        zt = 0.55 + 0.9 * (abs(t - 0.5) * 2) ** 3
        pts += [(w, y, zt), (-w, y, zt), (w * 0.5, y, -0.45), (-w * 0.5, y, -0.45)]
    pts += [(0, -L_ / 2 - 0.35, 1.5), (0, L_ / 2 + 0.3, 1.35)]
    hull(mb, pts, "ds_hull")
    mb.box((0, 0, 0.62), (1.6, 5.4, 0.08), "ds_hull_light")
    for k in range(4):
        mb.box((0, -2.0 + k * 1.3, 0.72), (1.7, 0.18, 0.12), "ds_wood_dark")
    mb.cyl_between((0, -1.2, 0.6), (0, -1.0, 6.5), 0.09, 0.06, "ds_wood_dark", segs=6)
    a = Vector((0, -4.2, 1.6))
    b = Vector((0, 2.6, 7.6))
    mb.cyl_between(a, b, 0.06, 0.05, "ds_wood", segs=5)
    sail = [a + (b - a) * 0.02, b - (b - a) * 0.02, Vector((0, 2.4, 1.3))]
    # the sail: a thin triangular prism in the YZ plane, slightly bellied
    mid = (sail[0] + sail[1] + sail[2]) / 3 + X * 0.35
    for tri in ((sail[0], sail[1], mid), (sail[1], sail[2], mid), (sail[2], sail[0], mid)):
        pass
    hull(mb, [sail[0] + X * 0.03, sail[1] + X * 0.03, sail[2] + X * 0.03, mid,
             sail[0] - X * 0.03, sail[1] - X * 0.03, sail[2] - X * 0.03], "ds_sail")
    mb.cyl_between(Vector((0, 2.4, 1.3)), Vector((0, 3.4, 0.7)), 0.015, 0.015, "ds_rope", segs=3)
    mb.box((0.0, 3.0, 0.8), (0.6, 0.6, 0.3), "ds_pot")
    mb.ico((0.2, -2.7, 0.85), 0.25, "ds_cloth_blue", subdiv=1, scale=(1.2, 1, 0.6))
    mb.finish("desert_boat")


def build_desert_rock():
    """Layered sandstone outcrop (~3 m): stacked wind-worn strata."""
    mb = MeshBuilder()
    rng = random.Random(157)
    hull(mb, L.rock_points((0, 0, 0), (1.6, 1.2, 0.9), rng, n=16), "ds_rock")
    hull(mb, L.rock_points((0.2, -0.1, 0.8), (1.25, 0.95, 0.6), rng, n=14, flat_bottom=False), "ds_rock_c")
    hull(mb, L.rock_points((0.35, 0.05, 1.35), (0.85, 0.7, 0.45), rng, n=12, flat_bottom=False), "ds_rock_b")
    hull(mb, L.rock_points((-1.4, 0.8, 0), (0.5, 0.4, 0.35), rng, n=10), "ds_rock_b")
    mb.clamp_floor()
    mb.finish("desert_rock")


def _tile_slabs(mb, rects, mats, rng):
    # grout bed under the slabs, top a little below the slab tops
    mb.box((0, 0, -0.07), (2.0, 2.0, 0.1), "ds_sandstone_dark")
    for k, (x0, y0, x1, y1) in enumerate(rects):
        g = 0.035
        h = rng.uniform(0.0, 0.012)
        mb.box(((x0 + x1) / 2, (y0 + y1) / 2, -0.05 + h / 2), (x1 - x0 - g, y1 - y0 - g, 0.1 + h), mats[k % len(mats)], bevel=0.018)


def build_desert_tile_a():
    """2 x 2 m cream paving: four square slabs (top at z = 0)."""
    mb = MeshBuilder()
    rng = random.Random(161)
    _tile_slabs(mb, [(-1, -1, 0, 0), (0, -1, 1, 0), (-1, 0, 0, 1), (0, 0, 1, 1)],
                ["ds_cream", "ds_sandstone_light", "ds_sandstone_light", "ds_cream"], rng)
    mb.finish("desert_tile_a")


def build_desert_tile_b():
    """2 x 2 m paving variant: long and short slabs."""
    mb = MeshBuilder()
    rng = random.Random(163)
    _tile_slabs(mb, [(-1, -1, 0.3, -0.35), (0.3, -1, 1, -0.35), (-1, -0.35, -0.2, 0.35), (-0.2, -0.35, 1, 0.35),
                     (-1, 0.35, 0.5, 1), (0.5, 0.35, 1, 1)],
                ["ds_sandstone_light", "ds_cream", "ds_cream", "ds_sandstone_light", "ds_sandstone_light", "ds_plaster"], rng)
    mb.finish("desert_tile_b")


def build_desert_brazier():
    """Bronze fire bowl on a sandstone pedestal (~1.6 m)."""
    mb = MeshBuilder()
    rng = random.Random(167)
    mb.box((0, 0, 0.2), (0.8, 0.8, 0.4), "ds_sandstone_dark")
    mb.cyl((0, 0, 0.8), 0.22, 0.18, 0.8, "ds_sandstone", segs=8)
    mb.lathe([(0.0, 0.0), (0.2, 0.0), (0.55, 0.3), (0.6, 0.38), (0.0, 0.3)], "ds_bronze", segs=10, center=(0, 0, 1.2))
    for k in range(5):
        a = 2 * math.pi * k / 5
        hull(mb, [(0.2 * math.cos(a), 0.2 * math.sin(a), 1.5), (0.2 * math.cos(a + 0.9), 0.2 * math.sin(a + 0.9), 1.5),
                  (0.05 * math.cos(a + 0.45), 0.05 * math.sin(a + 0.45), 1.45),
                  (0.08 * math.cos(a + 0.4), 0.08 * math.sin(a + 0.4), 1.95 + rng.uniform(0, 0.3))], "ds_fire")
    mb.cyl((0, 0, 1.6), 0.14, 0.02, 0.5, "ds_fire_core", segs=5)
    mb.finish("desert_brazier")


def build_desert_planter():
    """Raised square palm bed (1.8 m, 0.55 m) of sandstone with a cream rim, dark soil and small
    plants (a palm prop stands in its middle)."""
    mb = MeshBuilder()
    rng = random.Random(171)
    S, t = 1.8, 0.22
    for s in (-1, 1):
        mb.box((0, s * (S / 2 - t / 2), 0.26), (S, t, 0.52), "ds_sandstone_light")
        mb.box((s * (S / 2 - t / 2), 0, 0.26), (t, S - 2 * t + 0.02, 0.52), "ds_sandstone_light")
        mb.box((0, s * (S / 2 - t / 2), 0.55), (S + 0.06, t + 0.06, 0.06), "ds_cream")
        mb.box((s * (S / 2 - t / 2), 0, 0.55), (t + 0.06, S - 2 * t, 0.06), "ds_cream")
    mb.box((0, 0, 0.22), (S - 2 * t + 0.02, S - 2 * t + 0.02, 0.44), "ds_palm_trunk_dark")
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.6
        mb.ico((0.45 * math.cos(a), 0.45 * math.sin(a), 0.5), 0.2, "ds_shrub" if k % 2 else "ds_palm_leaf_light",
               subdiv=1, jitter=0.03, rng=rng, scale=(1, 1, 0.8))
    mb.box((0, -S / 2 - 0.01, 0.28), (S * 0.6, 0.02, 0.1), "ds_turquoise")
    mb.finish("desert_planter")


def build_desert_sphinx_small():
    """Avenue sphinx (ram-headed criosphinx) on a plinth (~1.6 x 3.6 m, 2.4 m), facing -Y."""
    mb = MeshBuilder()
    stone = "ds_sandstone_light"
    mb.box((0, 0.1, 0.35), (1.6, 3.6, 0.7), "ds_sandstone_b")
    mb.box((0, 0.1, 0.72), (1.45, 3.45, 0.06), "ds_sandstone")
    hull(mb, [(-0.55, 1.5, 0.75), (0.55, 1.5, 0.75), (-0.6, -0.3, 0.75), (0.6, -0.3, 0.75),
              (-0.45, 1.5, 1.55), (0.45, 1.5, 1.55), (-0.5, -0.1, 1.75), (0.5, -0.1, 1.75)], stone)
    for s in (-1, 1):
        mb.box((s * 0.33, -0.95, 0.9), (0.3, 1.3, 0.3), stone)
    hull(mb, [(-0.45, -0.2, 0.75), (0.45, -0.2, 0.75), (-0.4, -0.55, 1.9), (0.4, -0.55, 1.9), (0, 0.2, 1.7)], stone)
    mb.box((0, -0.8, 2.05), (0.5, 0.75, 0.5), stone)
    mb.box((0, -1.2, 1.95), (0.3, 0.3, 0.3), stone)
    for s in (-1, 1):
        mb.lathe([(0.0, -0.08), (0.12, -0.08), (0.12, 0.08), (0.0, 0.08)], "ds_sandstone_b", segs=6,
                 center=(s * 0.33, -0.7, 2.05), matrix=Matrix.Rotation(math.pi / 2, 4, "Y"))
        mb.box((s * 0.35, -0.9, 1.9), (0.08, 0.25, 0.25), "ds_sandstone_b")
    mb.box((0, -1.0, 1.35), (0.45, 0.15, 0.6), "ds_lapis")
    mb.finish("desert_sphinx_small")


def build_desert_ruin():
    """Crumbling mud-brick ruin (~6 x 3 m): an L of broken walls, a surviving arch and fallen bricks."""
    mb = MeshBuilder()
    rng = random.Random(173)
    brick = "ds_sandstone_b"
    # long wall with a jagged top
    for k in range(6):
        x = -2.5 + k * 1.0
        h = [2.8, 3.3, 2.2, 1.4, 2.6, 1.0][k]
        mb.box((x, 0.8, h / 2), (1.02, 0.7, h), brick if k % 2 else "ds_sandstone")
        mb.box((x + rng.uniform(-0.2, 0.2), 0.8, h + 0.12), (0.5, 0.6, 0.24), "ds_sandstone_dark")
    # short return wall
    for k in range(3):
        y = 0.1 - k * 0.9
        h = [2.4, 1.6, 0.8][k]
        mb.box((-2.65, y, h / 2), (0.7, 0.92, h), "ds_sandstone")
    # the arch: two piers and a round arch
    for s in (-1, 1):
        mb.box((1.2 + s * 0.85, -0.6, 1.2), (0.45, 0.6, 2.4), brick)
    arch = round_arch(1.2, 2.4, 0.85, n=6)
    outer = round_arch(1.2, 2.4, 1.3, n=6)
    poly = [(outer[0][0], 2.4)] + outer[1:-1] + [(outer[-1][0], 2.4)] + list(reversed(arch))
    poly = list(reversed(poly)) if sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))) < 0 else poly
    mb.prism(poly, -0.3, 0.3, "ds_sandstone_light", frame=(Vector((0, -0.6, 0)), X, Z, -Y))
    # sand drift and fallen bricks
    mb.ico((0.0, 0.2, 0.0), 1.8, "ds_sand", subdiv=1, scale=(1.8, 0.9, 0.35), flatten_below=0.0)
    for i in range(9):
        mb.box((rng.uniform(-3, 3), rng.uniform(-1.6, -0.4), 0.12), (0.45, 0.25, 0.22), "ds_sandstone_b" if i % 2 else "ds_sandstone",
               rot=(0, 0, rng.uniform(0, 3)))
    mb.clamp_floor()
    mb.finish("desert_ruin")


def build_desert_tent():
    """Nomad tent (~4.4 x 3.4 m): a striped cloth roof on poles over rugs, open at the front."""
    mb = MeshBuilder()
    rng = random.Random(179)
    W, D = 4.4, 3.4
    for x in (-W / 2, 0.0, W / 2):
        mb.cyl_between((x, -D / 2, 0), (x, -D / 2, 1.9), 0.05, 0.05, "ds_wood_dark", segs=5)
        mb.cyl_between((x, D / 2, 0), (x, D / 2, 1.5), 0.05, 0.05, "ds_wood_dark", segs=5)
        mb.cyl_between((x, 0.0, 0), (x, 0.0, 2.4), 0.06, 0.06, "ds_wood_dark", segs=5)
    # roof: two slopes, striped cream / brown / dark
    for side, (y0, z0, y1, z1) in (("front", (-D / 2 - 0.2, 1.85, 0.0, 2.45)), ("back", (0.0, 2.45, D / 2 + 0.2, 1.45))):
        ln = math.hypot(y1 - y0, z1 - z0)
        ang = math.atan2(z1 - z0, y1 - y0)
        for k in range(6):
            x = -W / 2 - 0.2 + (k + 0.5) * (W + 0.4) / 6
            mb.box((x, (y0 + y1) / 2, (z0 + z1) / 2), ((W + 0.4) / 6 + 0.004, ln, 0.05),
                   ["ds_cloth_cream", "ds_hull_light", "ds_stripe"][k % 3], rot=(ang, 0, 0))
    # back and side walls of cloth
    mb.box((0, D / 2 + 0.05, 0.75), (W, 0.05, 1.5), "ds_hull_light")
    for s in (-1, 1):
        mb.box((s * (W / 2 + 0.03), 0.4, 0.8), (0.05, D - 0.6, 1.6), "ds_cloth_cream")
    mb.box((0, 0.1, 0.02), (W - 0.4, D - 0.5, 0.04), "ds_cloth_red")
    mb.box((0, 0.1, 0.045), (W - 1.2, D - 1.2, 0.02), "ds_cloth_blue")
    for (x, m) in ((-1.4, "ds_cloth_saffron"), (1.3, "ds_cloth_teal")):
        mb.box((x, 1.0, 0.18), (0.8, 0.6, 0.26), m, bevel=0.05)
    lathe_pot(mb, 1.7, -0.9, 0.0, 0.6, 0.24, "ds_pot", handles=True)
    mb.cyl((-1.8, -1.3, 0.15), 0.25, 0.3, 0.3, "ds_rope", segs=7)
    # cold fire pit in front
    for k in range(7):
        a = 2 * math.pi * k / 7
        mb.box((0.9 * math.cos(a), -2.6 + 0.9 * math.sin(a), 0.1), (0.3, 0.25, 0.2), "ds_rock_b", rot=(0, 0, a))
    for k in range(3):
        a = k * 1.1
        mb.cyl_between((0.4 * math.cos(a), -2.6 + 0.4 * math.sin(a), 0.08), (-0.4 * math.cos(a), -2.6 - 0.4 * math.sin(a), 0.1),
                       0.06, 0.05, "ds_wood_dark", segs=5)
    mb.finish("desert_tent")


def build_desert_grass():
    """Dry desert grass tufts (~1.6 m across, 0.7 m)."""
    mb = MeshBuilder()
    rng = random.Random(181)
    for t in range(3):
        cx, cy = rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5)
        for k in range(7):
            a = 2 * math.pi * k / 7 + rng.uniform(-0.3, 0.3)
            base = Vector((cx, cy, 0.0))
            tip = base + Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, rng.uniform(0.4, 0.75)))
            mid = (base + tip) / 2 + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.05))
            ribbon(mb, [base, mid, tip], [0.09, 0.06, 0.012], Vector((-math.sin(a), math.cos(a), 0.0)), 0.025,
                   "ds_palm_leaf_dry" if k % 3 else ("ds_reed_head" if t % 2 else "ds_rock_c"))
    mb.finish("desert_grass")


def build_desert_pebbles():
    """A scatter of flat stones half sunk in the sand (~2 m across)."""
    mb = MeshBuilder()
    rng = random.Random(183)
    for i in range(9):
        c = (rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9), 0.0)
        r = rng.uniform(0.12, 0.32)
        hull(mb, L.rock_points(c, (r, r * rng.uniform(0.6, 1.0), r * 0.45), rng, n=8), ["ds_rock", "ds_rock_b", "ds_rock_c"][i % 3])
    mb.clamp_floor()
    mb.finish("desert_pebbles")



# ----------------------------------------------------------------------------------- border ruins

def _ruin_wall(model_id, seed, heights, rubble_front=1, rubble_back=3):
    """A 2 m run of ruined ashlar wall along X (x in [-1, 1]), 0.7 m thick, for lining the edges
    of the walkable map. heights: course count per 0.5 m column (broken, uneven top). Fallen
    blocks lie mostly behind it (+Y, away from the walkable side)."""
    mb = MeshBuilder()
    rng = random.Random(seed)
    course = 0.34
    thick = 0.7
    mb.box((0, 0, 0.1), (2.08, thick + 0.16, 0.2), "ds_sandstone_dark")
    cols = len(heights)
    cw = 2.0 / cols
    for ci, n in enumerate(heights):
        x0 = -1.0 + ci * cw
        for k in range(n):
            z = 0.2 + course * (k + 0.5)
            # alternate joints per course: split some columns into two blocks
            split = (k + ci) % 2 == 1 and n > 1
            parts = [(x0 + cw * 0.25, cw * 0.5), (x0 + cw * 0.75, cw * 0.5)] if split else [(x0 + cw * 0.5, cw)]
            for (cx, w) in parts:
                shrink = 0.02 + (0.05 if k == n - 1 else 0.0)
                mat = "ds_sandstone" if (k + ci) % 3 else ("ds_sandstone_b" if k % 2 else "ds_sandstone_light")
                verts = mb.box((cx + rng.uniform(-0.02, 0.02), rng.uniform(-0.03, 0.03), z),
                               (w - shrink, thick - rng.uniform(0.0, 0.06), course - 0.03), mat)
                if k == n - 1:
                    # the broken top course: knock the corners about
                    for v in verts:
                        if v.co.z > z:
                            v.co.z -= rng.uniform(0.0, 0.12)
                            v.co.x += rng.uniform(-0.04, 0.04)
    for i in range(rubble_back + rubble_front):
        side = 1 if i < rubble_back else -1
        c = (rng.uniform(-0.85, 0.85), side * rng.uniform(0.55, 0.95), 0.0)
        r = rng.uniform(0.14, 0.26)
        hull(mb, L.rock_points(c, (r * 1.4, r, r * 0.8), rng, n=8), ["ds_sandstone", "ds_sandstone_b", "ds_rock_c"][i % 3])
    mb.clamp_floor()
    mb.finish(model_id)


def build_desert_ruinwall_a():
    """Low ruined wall run (0.9-1.2 m)."""
    _ruin_wall("desert_ruinwall_a", 1201, [3, 3, 2, 3])


def build_desert_ruinwall_b():
    """Mid-height ruined wall run with a broken end (0.9-1.6 m)."""
    _ruin_wall("desert_ruinwall_b", 1202, [4, 4, 3, 2])


def build_desert_ruinwall_c():
    """Almost razed wall run: a course or two and scattered blocks (0.5-0.9 m)."""
    _ruin_wall("desert_ruinwall_c", 1203, [2, 1, 2, 2], rubble_front=1, rubble_back=4)


def build_desert_ruinwall_pier():
    """Square pier stub (0.95 m, ~1.9 m) with a dark stripe band, marking joints of the ruin line."""
    mb = MeshBuilder()
    rng = random.Random(1204)
    mb.box((0, 0, 0.15), (1.15, 1.15, 0.3), "ds_sandstone_dark")
    for k in range(5):
        z = 0.3 + 0.32 * (k + 0.5)
        mat = "ds_stripe" if k == 2 else ("ds_sandstone" if k % 2 else "ds_sandstone_b")
        verts = mb.box((rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), z), (0.95 - 0.02 * k, 0.95 - 0.02 * k, 0.3), mat)
        if k == 4:
            for v in verts:
                if v.co.z > z:
                    v.co.z -= rng.uniform(0.0, 0.18)
    mb.clamp_floor()
    mb.finish("desert_ruinwall_pier")


# ----------------------------------------------------------------------------------- Act II zones
# The river banks, the oasis, the Snake Isles, the Anubis necropolis and the temple court.

def _since(mb, before):
    """The BMVerts added since `before` = set(mb.bm.verts) was taken (bmesh reuses the slots of
    deleted verts, so new verts are not always at the end of the sequence)."""
    return [v for v in mb.bm.verts if v not in before]


def _jackal_head(mb, c, s=1.0, ear_h=0.95, mat="ds_basalt", yaw=0.0):
    """A jackal head (Anubis): skull centred on c, long snout toward -Y, tall pointed ears with
    gilded insides, gold eyes. s scales it."""
    before = set(mb.bm.verts)
    hull(mb, [(-0.3, 0.25, -0.25), (0.3, 0.25, -0.25), (-0.33, -0.2, -0.25), (0.33, -0.2, -0.25),
              (-0.28, 0.2, 0.25), (0.28, 0.2, 0.25), (-0.3, -0.25, 0.2), (0.3, -0.25, 0.2), (0.0, 0.35, 0.0)], mat)
    hull(mb, [(-0.2, -0.15, -0.22), (0.2, -0.15, -0.22), (-0.22, -0.15, 0.12), (0.22, -0.15, 0.12),
              (-0.08, -0.95, -0.17), (0.08, -0.95, -0.17), (-0.07, -0.93, -0.03), (0.07, -0.93, -0.03)], mat)
    mb.ico((0.0, -0.95, -0.1), 0.075, "ds_stripe", subdiv=0)
    for sx in (-1, 1):
        hull(mb, [(sx * 0.07, 0.03, 0.15), (sx * 0.31, 0.03, 0.15), (sx * 0.2, 0.17, 0.17), (sx * 0.19, -0.07, 0.15),
                  (sx * 0.24, 0.06, 0.15 + ear_h)], mat)
        hull(mb, [(sx * 0.12, -0.085, 0.24), (sx * 0.26, -0.085, 0.24), (sx * 0.232, -0.01, 0.15 + ear_h * 0.8),
                  (sx * 0.13, -0.04, 0.26), (sx * 0.25, -0.04, 0.26), (sx * 0.228, 0.02, 0.15 + ear_h * 0.74)], "ds_gold")
        mb.box((sx * 0.21, -0.27, 0.07), (0.13, 0.05, 0.05), "ds_gold", rot=(0, 0, -sx * 0.45))
    mb.transform(_since(mb, before), Matrix.Translation(Vector(c)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Scale(s, 4))


def _relief_anubis(mb, x, y, z0, h, sign=-1, lean=0.0, mat="ds_basalt"):
    """A standing jackal-headed god in low relief (about h m tall, feet at z0) on a wall face at
    depth y facing sign*Y; lean = how far the (battered) face leans back (radians)."""
    before = set(mb.bm.verts)
    s = h / 4.0
    t = 0.07
    f = -sign   # the figure faces along +x on the front, mirrored on the back
    parts = [(-0.22, 0.78, 0.22, 1.56, mat), (0.22, 0.78, 0.22, 1.56, mat), (0.0, 1.78, 0.9, 0.62, "ds_gold"),
             (0.0, 1.56, 0.94, 0.1, "ds_lapis"), (0.0, 2.55, 0.78, 1.0, mat), (0.0, 3.08, 0.96, 0.16, "ds_lapis"),
             (0.0, 3.2, 0.9, 0.08, "ds_gold"), (0.5, 2.62, 0.2, 0.95, mat), (-0.5, 2.4, 0.2, 1.05, mat),
             (0.0, 3.42, 0.36, 0.42, mat), (0.36, 3.38, 0.46, 0.15, mat), (-0.08, 3.84, 0.11, 0.5, mat),
             (0.08, 3.84, 0.11, 0.5, mat), (0.82, 1.95, 0.07, 3.7, "ds_gold"), (0.82, 3.82, 0.32, 0.09, "ds_gold"),
             (-0.62, 1.85, 0.2, 0.2, "ds_gold"), (-0.62, 1.62, 0.07, 0.3, "ds_gold")]
    for (cx, cz, w, hh, m) in parts:
        mb.box((x + f * cx * s, y + sign * t / 2, z0 + cz * s), (w * s, t, hh * s), m)
    if lean:
        piv = Vector((x, y, z0))
        mb.transform(_since(mb, before), Matrix.Translation(piv) @ Matrix.Rotation(sign * lean, 4, "X") @ Matrix.Translation(-piv))


def _winged_disc(mb, y, z, span, sign=-1):
    """A winged sun disc (glowing gold disc, rows of lapis / gold / turquoise feathers) on a face
    at depth y facing sign*Y, centred on x = 0 at height z."""
    mb.cyl((0, y + sign * 0.08, z), 0.62, 0.62, 0.16, "ds_gold_glow", segs=12, rot=(math.pi / 2, 0, 0))
    for s in (-1, 1):
        for k, (m, dz, ln) in enumerate((("ds_lapis", -0.22, 1.0), ("ds_gold", 0.08, 0.86), ("ds_turquoise", 0.34, 0.7))):
            L_ = span * ln
            mb.box((s * (0.58 + L_ / 2), y + sign * 0.05, z + dz + L_ * 0.04), (L_, 0.1, 0.3), m, rot=(0, -s * 0.08, 0))


def _papyrus_column(mb, x, y, z0, h, r=0.5):
    """Papyrus column from z0 to z0 + h: base disc, painted shaft, open bell capital, abacus."""
    mb.cyl((x, y, z0 + 0.15), r * 1.55, r * 1.5, 0.3, "ds_sandstone_dark", segs=10)
    sh = h * 0.7
    zs = z0 + 0.3
    prof = [(0.0, 0.0), (r * 1.05, 0.0), (r * 1.1, sh * 0.12), (r * 1.02, sh * 0.62), (r * 0.86, sh * 0.97), (r * 0.76, sh), (0.0, sh)]
    mb.lathe(prof, "ds_sandstone_light", segs=10, center=(x, y, zs))

    def rad(fz):
        for (r0, z0_), (r1, z1_) in zip(prof[1:-1], prof[2:-1]):
            if z0_ <= fz <= z1_:
                return r0 + (r1 - r0) * (fz - z0_) / max(z1_ - z0_, 1e-6)
        return r
    for fz, m in ((0.2, "ds_lapis"), (0.24, "ds_red_paint"), (0.86, "ds_lapis"), (0.9, "ds_red_paint"), (0.94, "ds_turquoise")):
        rr = rad(sh * fz) + 0.02
        mb.cyl((x, y, zs + sh * fz), rr, rr, sh * 0.035, m, segs=10)
    cz = zs + sh
    ch = h - 0.3 - sh - 0.25
    mb.lathe([(0.0, 0.0), (r * 0.76, 0.0), (r * 1.1, ch * 0.4), (r * 1.7, ch * 0.92), (r * 1.78, ch), (0.0, ch)],
             "ds_sandstone_light", segs=12, center=(x, y, cz))
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.26
        mb.box((x + r * 1.35 * math.cos(a), y + r * 1.35 * math.sin(a), cz + ch * 0.62), (0.12, 0.06, ch * 0.6),
               "ds_turquoise" if i % 2 else "ds_crop_dark", rot=(0, 0, a + math.pi / 2))
    mb.box((x, y, z0 + h - 0.125), (r * 2.6, r * 2.6, 0.25), "ds_sandstone")


def build_desert_anubis_statue():
    """Colossal standing Anubis (~9.8 m): a black jackal-headed god striding on a plinth, with a
    gilded was-sceptre and ankh, a lapis-striped wig, a broad collar and a gold-trimmed kilt,
    against a back pillar. Faces -Y."""
    mb = MeshBuilder()
    P = 1.2
    mb.box((0, 0.1, 0.5), (3.4, 3.4, 1.0), "ds_sandstone_dark")
    band(mb, 0, 0.1, 3.4, 3.4, 0.62, 0.8, "ds_lapis", grow=0.012)
    mb.box((0, 0.1, 1.1), (3.1, 3.1, 0.2), "ds_sandstone")
    for k in range(8):
        mb.box((-1.23 + k * 0.35, -1.615, 0.34), (0.15, 0.04, 0.2), "ds_gold" if k % 3 == 1 else "ds_stripe")
    mb.box((0, 0.8, P + 3.2), (1.15, 0.5, 6.4), "ds_basalt_b")
    st = "ds_basalt"
    # striding legs, left foot forward
    mb.box((-0.36, -0.72, P + 0.14), (0.42, 1.0, 0.28), st)
    mb.box((0.36, 0.12, P + 0.14), (0.42, 1.0, 0.28), st)
    mb.cyl_between((-0.36, -0.55, P + 0.2), (-0.37, -0.32, P + 2.1), 0.17, 0.24, st, segs=7)
    mb.cyl_between((-0.37, -0.32, P + 2.0), (-0.35, -0.02, P + 3.7), 0.24, 0.33, st, segs=7)
    mb.cyl_between((0.36, 0.28, P + 0.2), (0.37, 0.22, P + 2.1), 0.17, 0.24, st, segs=7)
    mb.cyl_between((0.37, 0.22, P + 2.0), (0.35, 0.08, P + 3.7), 0.24, 0.33, st, segs=7)
    for (x, y) in ((-0.361, -0.527), (0.361, 0.274)):
        mb.cyl((x, y, P + 0.42), 0.205, 0.2, 0.12, "ds_gold", segs=7)
    # kilt with a gold front panel and belt
    hull(mb, [(-0.62, -0.34, P + 4.25), (0.62, -0.34, P + 4.25), (-0.62, 0.36, P + 4.25), (0.62, 0.36, P + 4.25),
              (-0.8, -0.62, P + 2.85), (0.8, -0.5, P + 2.85), (-0.78, 0.45, P + 2.85), (0.78, 0.48, P + 2.85)], "ds_cream")
    hull(mb, [(-0.22, -0.39, P + 4.2), (0.22, -0.39, P + 4.2), (-0.3, -0.66, P + 2.9), (0.3, -0.6, P + 2.9),
              (-0.22, -0.3, P + 4.2), (0.22, -0.3, P + 4.2), (-0.3, -0.52, P + 2.9), (0.3, -0.48, P + 2.9)], "ds_gold")
    mb.box((0, 0.01, P + 4.3), (1.34, 0.8, 0.18), "ds_gold")
    # torso
    hull(mb, [(-0.58, -0.3, P + 4.35), (0.58, -0.3, P + 4.35), (-0.58, 0.32, P + 4.35), (0.58, 0.32, P + 4.35),
              (-1.02, -0.36, P + 5.85), (1.02, -0.36, P + 5.85), (-1.02, 0.38, P + 5.85), (1.02, 0.38, P + 5.85),
              (-0.82, -0.3, P + 6.15), (0.82, -0.3, P + 6.15), (-0.82, 0.3, P + 6.15), (0.82, 0.3, P + 6.15)], st)
    mb.cyl_between((0, 0.0, P + 6.0), (0, -0.04, P + 7.0), 0.3, 0.26, st, segs=8)
    # broad collar
    for k, (r, m) in enumerate(((1.0, "ds_gold"), (0.86, "ds_lapis"), (0.72, "ds_turquoise"), (0.56, "ds_gold"))):
        mb.lathe([(0.0, 0.0), (r, 0.0), (r, 0.09), (0.0, 0.09)], m, segs=14, center=(0, -0.02, P + 5.9 + k * 0.075),
                 scale_xy=(1.0, 0.52))
    # left arm forward, holding the was-sceptre
    sl, el, fl = Vector((-0.98, 0.0, P + 5.85)), Vector((-1.08, -0.12, P + 4.75)), Vector((-1.02, -0.8, P + 4.6))
    mb.cyl_between(sl, el, 0.27, 0.22, st, segs=7)
    mb.cyl_between(el, fl, 0.21, 0.17, st, segs=7)
    mb.ico(fl, 0.2, st, subdiv=1)
    mb.cyl_between(sl + (el - sl) * 0.25 - Z * 0.0, sl + (el - sl) * 0.4, 0.29, 0.27, "ds_gold", segs=7)
    mb.cyl_between(el + (fl - el) * 0.72, el + (fl - el) * 0.86, 0.19, 0.19, "ds_gold", segs=7)
    mb.cyl((fl.x, fl.y, P + 3.45), 0.06, 0.06, 6.9, "ds_gold", segs=6)
    for s in (-1, 1):
        mb.box((fl.x + s * 0.07, fl.y, P + 0.16), (0.06, 0.06, 0.32), "ds_gold", rot=(0, s * 0.45, 0))
    mb.box((fl.x, fl.y - 0.16, P + 6.93), (0.13, 0.5, 0.15), "ds_gold", rot=(0.45, 0, 0))
    mb.box((fl.x, fl.y + 0.05, P + 7.08), (0.08, 0.1, 0.18), "ds_gold")
    # right arm down, holding an ankh
    sr, er, fr_ = Vector((0.98, 0.02, P + 5.85)), Vector((1.1, 0.08, P + 4.75)), Vector((1.06, -0.12, P + 3.75))
    mb.cyl_between(sr, er, 0.27, 0.22, st, segs=7)
    mb.cyl_between(er, fr_, 0.21, 0.17, st, segs=7)
    mb.ico(fr_, 0.2, st, subdiv=1)
    mb.cyl_between(sr + (er - sr) * 0.25, sr + (er - sr) * 0.4, 0.29, 0.27, "ds_gold", segs=7)
    mb.cyl_between(er + (fr_ - er) * 0.72, er + (fr_ - er) * 0.86, 0.19, 0.19, "ds_gold", segs=7)
    ay = fr_.y - 0.16
    mb.lathe([(0.1, -0.035), (0.15, -0.035), (0.15, 0.035), (0.1, 0.035)], "ds_gold", segs=8, closed=True,
             center=(fr_.x, ay, fr_.z - 0.02), matrix=Matrix.Rotation(math.pi / 2, 4, "X"))
    mb.box((fr_.x, ay, fr_.z - 0.2), (0.44, 0.07, 0.07), "ds_gold")
    mb.box((fr_.x, ay, fr_.z - 0.47), (0.08, 0.07, 0.5), "ds_gold")
    # striped wig: back mass and lappets over the shoulders
    hull(mb, [(-0.44, 0.02, P + 7.4), (0.44, 0.02, P + 7.4), (-0.5, 0.45, P + 7.25), (0.5, 0.45, P + 7.25),
              (-0.52, 0.4, P + 6.15), (0.52, 0.4, P + 6.15), (-0.42, 0.06, P + 6.2), (0.42, 0.06, P + 6.2)], "ds_lapis")
    for sx in (-1, 1):
        hull(mb, [(sx * 0.22, -0.12, P + 7.2), (sx * 0.5, -0.12, P + 7.2), (sx * 0.22, 0.05, P + 7.2), (sx * 0.5, 0.05, P + 7.2),
                  (sx * 0.3, -0.34, P + 6.1), (sx * 0.6, -0.34, P + 6.1), (sx * 0.3, -0.17, P + 6.1), (sx * 0.6, -0.17, P + 6.1)], "ds_lapis")
        for k in range(3):
            t = 0.2 + 0.3 * k
            zz = P + 7.2 - 1.1 * t
            yy = -0.12 - 0.22 * t
            mb.box((sx * (0.36 + 0.08 * t), yy - 0.015, zz), (0.3, 0.05, 0.08), "ds_gold", rot=(0.2, 0, 0))
    _jackal_head(mb, (0.0, 0.02, P + 7.25), s=1.2, ear_h=1.0)
    mb.finish("desert_anubis_statue")


def build_desert_jackal_statue():
    """Recumbent jackal of Anubis (~3.5 m tall, 3.7 m long) lying on a gilded shrine chest, head
    raised toward -Y."""
    mb = MeshBuilder()
    mb.box((0, 0.1, 0.06), (1.9, 3.7, 0.12), "ds_sandstone_dark")
    mb.box((0, 0.1, 0.72), (1.5, 3.3, 1.2), "ds_basalt_b")
    for s in (-1, 1):
        mb.box((s * 0.765, 0.1, 0.72), (0.04, 2.9, 0.82), "ds_lapis")
        for k in range(3):
            mb.box((s * 0.78, -0.9 + k * 1.0, 0.72), (0.03, 0.5, 0.5), "ds_gold")
    mb.box((0, -1.565, 0.72), (1.1, 0.04, 0.8), "ds_lapis")
    mb.box((0, -1.58, 0.72), (0.5, 0.03, 0.5), "ds_gold")
    mb.box((0, 0.1, 1.29), (1.6, 3.4, 0.1), "ds_gold")
    mb.box((0, 0.1, 1.43), (1.6, 3.4, 0.2), "ds_basalt_b", taper=(1.07, 1.03))
    top = 1.53
    j = "ds_basalt"
    hull(mb, [(-0.42, 1.25, top), (0.42, 1.25, top), (-0.45, -0.55, top), (0.45, -0.55, top),
              (-0.3, 1.2, top + 0.62), (0.3, 1.2, top + 0.62), (-0.32, -0.35, top + 0.78), (0.32, -0.35, top + 0.78),
              (0.0, 1.38, top + 0.3)], j)
    for s in (-1, 1):
        mb.ico((s * 0.33, 0.95, top + 0.3), 0.36, j, subdiv=1, scale=(0.7, 1.3, 1.0), flatten_below=top)
        mb.box((s * 0.22, -0.95, top + 0.1), (0.2, 1.0, 0.2), j)
        mb.box((s * 0.22, -1.48, top + 0.07), (0.24, 0.2, 0.14), j)
    hull(mb, [(-0.34, -0.7, top), (0.34, -0.7, top), (-0.3, -0.3, top + 0.8), (0.3, -0.3, top + 0.8),
              (-0.2, -0.75, top + 1.15), (0.2, -0.75, top + 1.15), (-0.22, -0.45, top + 1.2), (0.22, -0.45, top + 1.2)], j)
    mb.cyl((0, -0.6, top + 0.98), 0.29, 0.26, 0.1, "ds_gold", segs=8, rot=(0.5, 0, 0))
    mb.cyl_between((0.28, 1.3, top + 0.12), (0.5, 0.35, top + 0.07), 0.08, 0.06, j, segs=5)
    _jackal_head(mb, (0.0, -0.58, top + 1.36), s=0.62, ear_h=0.85)
    mb.finish("desert_jackal_statue")


def build_desert_serpent_statue():
    """A rearing cobra (~5.3 m) of green bronze on a plinth: a coiled body, a spread hood with a
    gilded rim and lapis bands, red eyes — the serpent gods of the Snake Isles. Faces -Y."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.35), (2.5, 2.5, 0.7), "ds_sandstone_dark")
    mb.box((0, 0, 0.78), (2.2, 2.2, 0.16), "ds_sandstone_b")
    for s in (-1, 1):
        mb.box((s * 0.7, -1.26, 0.38), (0.5, 0.04, 0.3), "ds_verdigris_dark")
    base = 0.86
    b = "ds_verdigris"
    pts = []
    n = 26
    for i in range(n + 1):
        t = i / n
        a = t * 2.3 * 2 * math.pi
        r = 0.72 - 0.4 * t
        pts.append(Vector((r * math.cos(a), r * math.sin(a), base + 0.25 + 0.95 * t)))
    for i in range(n):
        rr = 0.29 - 0.09 * i / n
        mb.cyl_between(pts[i], pts[i + 1] + (pts[i + 1] - pts[i]).normalized() * 0.05, rr, rr * 0.97,
                       b if i % 4 else "ds_verdigris_dark", segs=6)
    neck = [pts[-1], Vector((0.12, 0.12, base + 1.75)), Vector((-0.04, 0.02, base + 2.35)), Vector((0.0, -0.1, base + 2.95))]
    for i in range(3):
        mb.cyl_between(neck[i], neck[i + 1] + (neck[i + 1] - neck[i]).normalized() * 0.06, 0.27 - 0.02 * i, 0.26 - 0.02 * i, b, segs=7)
    hz = base + 2.85

    def hood(dy, grow, mat, t):
        pts_ = [(sx * (w + grow), -0.18 + dy + yy, hz + z) for sx in (-1, 1)
                for (w, z) in ((0.42, -0.3), (0.86, 0.35), (0.8, 0.95), (0.42, 1.4)) for yy in (-t, t)]
        hull(mb, pts_ + [(0.0, -0.18 + dy, hz + 1.55 + grow)], mat)
    hood(0.08, 0.09, "ds_gold", 0.07)
    hood(0.0, 0.0, b, 0.11)
    for k, (z, w) in enumerate(((0.05, 0.72), (0.45, 1.3), (0.85, 1.15))):
        mb.box((0, -0.3, hz + z), (w, 0.04, 0.13), "ds_lapis" if k != 1 else "ds_gold")
    for sx in (-1, 1):
        mb.cyl((sx * 0.36, -0.305, hz + 0.65), 0.14, 0.14, 0.04, "ds_gold", segs=8, rot=(math.pi / 2, 0, 0))
    hull(mb, [(-0.27, -0.08, hz + 1.28), (0.27, -0.08, hz + 1.28), (-0.24, -0.08, hz + 1.66), (0.24, -0.08, hz + 1.66),
              (-0.13, -0.92, hz + 1.33), (0.13, -0.92, hz + 1.33), (-0.1, -0.86, hz + 1.52), (0.1, -0.86, hz + 1.52)], b)
    for sx in (-1, 1):
        mb.box((sx * 0.19, -0.5, hz + 1.6), (0.09, 0.12, 0.06), "ds_eye_red")
        mb.box((sx * 0.035, -1.05, hz + 1.34), (0.025, 0.28, 0.025), "ds_red_paint", rot=(0, 0, sx * 0.2))
    mb.finish("desert_serpent_statue")


def build_desert_stele():
    """Round-topped tomb stela (~2.1 m) on a low base: a winged sun disc, a jackal-headed god and
    rows of glyphs on its face."""
    mb = MeshBuilder()
    rng = random.Random(281)
    mb.box((0, 0, 0.12), (1.3, 0.62, 0.24), "ds_sandstone_dark")
    w, top, t = 0.5, 1.62, 0.16
    arc = [(w * math.cos(a), top + w * math.sin(a)) for a in [math.pi * i / 8 for i in range(9)]]
    mb.prism([(-w, 0.24), (w, 0.24)] + arc, -t, t, "ds_sandstone_light", frame=(Vector((0, 0, 0)), X, Z, -Y))
    y = -t - 0.012
    mb.cyl((0, y, top + 0.2), 0.08, 0.08, 0.03, "ds_gold", segs=8, rot=(math.pi / 2, 0, 0))
    for s in (-1, 1):
        mb.box((s * 0.22, y, top + 0.21), (0.26, 0.03, 0.06), "ds_lapis", rot=(0, -s * 0.12, 0))
    for (cx, cz, bw, bh) in ((-0.14, 0.95, 0.13, 0.5), (-0.14, 1.28, 0.16, 0.2), (-0.14, 1.44, 0.1, 0.12),
                             (-0.2, 1.44, 0.1, 0.05), (-0.11, 1.55, 0.03, 0.12), (-0.17, 1.55, 0.03, 0.12)):
        mb.box((cx, y, cz), (bw, 0.03, bh), "ds_stripe")
    mb.box((-0.02, y, 1.1), (0.03, 0.03, 0.75), "ds_gold")
    for row in range(3):
        for k in range(4):
            if rng.random() < 0.85:
                mb.box((0.1 + k * 0.1, y, 1.42 - row * 0.2), (0.06, 0.03, 0.1), "ds_stripe" if rng.random() < 0.8 else "ds_red_paint")
    for k in range(6):
        mb.box((-0.36 + k * 0.145, y, 0.5), (0.08, 0.03, 0.12), "ds_stripe")
    mb.finish("desert_stele")


def build_desert_sarcophagus():
    """A stone sarcophagus (2.4 x 1.0 m) with painted bands and glyphs; its gabled lid pushed
    askew, the dark inside showing."""
    mb = MeshBuilder()
    rng = random.Random(283)
    L_, W, H = 2.4, 1.0, 0.85
    mb.box((0, 0, H / 2), (W, L_, H), "ds_sandstone_light", bevel=0.03)
    mb.box((0, 0, H - 0.02), (W - 0.2, L_ - 0.2, 0.06), "ds_opening")
    for s in (-1, 1):
        mb.box((s * (W / 2 + 0.005), 0, H * 0.72), (0.02, L_ - 0.2, 0.1), "ds_lapis")
        mb.box((s * (W / 2 + 0.005), 0, H * 0.58), (0.02, L_ - 0.2, 0.05), "ds_gold")
        for k in range(5):
            mb.box((s * (W / 2 + 0.006), -0.9 + k * 0.45, H * 0.32), (0.02, 0.18, 0.2), "ds_stripe")
    before = set(mb.bm.verts)
    mb.prism([(-0.56, 0.0), (0.56, 0.0), (0.56, 0.12), (0.0, 0.3), (-0.56, 0.12)], -1.25, 1.25, "ds_sandstone",
             frame=(Vector((0, 0, 0)), X, Z, -Y))
    mb.box((0, -0.95, 0.24), (0.5, 0.3, 0.14), "ds_gold")
    mb.box((0, 0.0, 0.25), (0.1, 1.8, 0.12), "ds_lapis")
    mb.transform(_since(mb, before), Matrix.Translation((0.42, 0.08, H)) @ Matrix.Rotation(0.32, 4, "Z"))
    for i in range(4):
        hull(mb, L.rock_points((rng.uniform(-1.0, 1.0), rng.uniform(-1.4, 1.4), 0.0), (0.16, 0.13, 0.1), rng, n=7), "ds_sandstone_b")
    mb.clamp_floor()
    mb.finish("desert_sarcophagus")


def build_desert_tomb_pyr():
    """Small tomb chapel with a steep white pyramid roof and a gilded capstone (~4.6 x 6 m, 6.5 m):
    a dark doorway, a stela by the door and a low walled forecourt (front -Y)."""
    mb = MeshBuilder()
    cy = 1.0
    mb.box((0, cy, 1.3), (4.4, 3.8, 2.6), "ds_mud_light", taper=(0.95, 0.95))
    band(mb, 0, cy, 4.4 * 0.95, 3.8 * 0.95, 2.45, 2.7, "ds_sandstone_light", grow=0.08)
    top = 2.7
    hull(mb, [(-1.8, cy - 1.75, top), (1.8, cy - 1.75, top), (-1.8, cy + 1.75, top), (1.8, cy + 1.75, top), (0, cy, top + 3.4)], "ds_whitewash")
    k = 0.155
    hull(mb, [(-1.8 * k - 0.03, cy - 1.75 * k - 0.03, top + 3.4 * (1 - k)), (1.8 * k + 0.03, cy - 1.75 * k - 0.03, top + 3.4 * (1 - k)),
              (-1.8 * k - 0.03, cy + 1.75 * k + 0.03, top + 3.4 * (1 - k)), (1.8 * k + 0.03, cy + 1.75 * k + 0.03, top + 3.4 * (1 - k)),
              (0, cy, top + 3.47)], "ds_gold")
    yf = cy - 1.9 * 0.97
    mb.box((0, yf - 0.04, 0.9), (0.9, 0.12, 1.8), "ds_opening")
    for s in (-1, 1):
        mb.box((s * 0.58, yf - 0.06, 0.95), (0.24, 0.14, 1.9), "ds_sandstone_light")
    mb.box((0, yf - 0.07, 1.98), (1.45, 0.16, 0.24), "ds_sandstone_light")
    mb.box((1.35, yf - 0.1, 0.75), (0.6, 0.18, 1.1), "ds_sandstone")
    mb.box((1.35, yf - 0.2, 0.85), (0.4, 0.04, 0.6), "ds_stripe")
    # low forecourt walls with an opening in front
    fy = cy - 1.9 - 2.4
    for s in (-1, 1):
        mb.box((s * 2.0, (yf + fy) / 2, 0.38), (0.36, yf - fy, 0.76), "ds_mud")
        mb.box((s * 1.45, fy, 0.38), (1.46, 0.36, 0.76), "ds_mud")
        mb.box((s * 2.0, fy, 0.45), (0.5, 0.5, 0.9), "ds_mud_light")
    lathe_pot(mb, -1.3, fy + 0.7, 0.0, 0.55, 0.22, "ds_pot", handles=True)
    mb.finish("desert_tomb_pyr")


def build_desert_mudhouse():
    """Nile farmhouse (~8 x 4.6 m): a mud-brick house with a roof parapet and palm-trunk beam ends,
    stairs to the roof, and a walled side yard with a beehive granary and a palm-frond shade."""
    mb = MeshBuilder()
    rng = random.Random(287)
    cx = -1.4
    mb.box((cx, 0.0, 1.45), (5.0, 4.4, 2.9), "ds_mud", taper=(0.97, 0.96))
    mb.box((cx, 0.0, 2.95), (4.8, 4.2, 0.12), "ds_mud_dark")
    for s in (-1, 1):
        mb.box((cx, s * 2.02, 3.14), (4.86, 0.18, 0.38), "ds_mud_light")
        mb.box((cx + s * 2.34, 0.0, 3.14), (0.18, 3.86, 0.38), "ds_mud_light")
    mb.box((cx, -2.1, 0.3), (5.04, 0.06, 0.6), "ds_whitewash")
    for k in range(7):
        mb.cyl((cx - 2.1 + k * 0.7, -2.1, 2.72), 0.07, 0.07, 0.3, "ds_palm_trunk_dark", segs=5, rot=(math.pi / 2, 0, 0))
    mb.box((cx + 0.7, -2.1, 0.95), (0.95, 0.12, 1.9), "ds_opening")
    mb.box((cx + 0.7, -2.14, 1.98), (1.3, 0.14, 0.16), "ds_palm_trunk_dark")
    for x in (cx - 1.45, cx - 0.45):
        mb.box((x, -2.1, 1.95), (0.42, 0.12, 0.42), "ds_opening")
        mb.box((x, -2.14, 1.72), (0.56, 0.1, 0.06), "ds_palm_trunk_dark")
    # stairs up the west side
    for k in range(6):
        hk = 0.48 * (k + 1)
        mb.box((cx - 2.85, 1.35 - k * 0.55, hk / 2), (0.7, 0.55, hk), "ds_mud_light")
    # side yard: low walls, granary dome, shade roof
    x0, x1 = cx + 2.5, cx + 5.4
    mb.box(((x0 + x1) / 2, 2.0, 0.65), (x1 - x0, 0.3, 1.3), "ds_mud")
    mb.box((x1 - 0.15, 0.2, 0.65), (0.3, 3.9, 1.3), "ds_mud")
    mb.box(((x0 + x1) / 2 + 0.55, -1.75, 0.65), (x1 - x0 - 1.1, 0.3, 1.3), "ds_mud")
    for x in (x0 + 0.1, x1 - 0.15):
        mb.box((x, -1.75, 0.8), (0.4, 0.4, 1.6), "ds_mud_light")
    mb.ico((x0 + 1.9, 1.0, 0.0), 1.0, "ds_mud_light", subdiv=2, scale=(0.9, 0.9, 1.7), flatten_below=0.0)
    mb.box((x0 + 1.9, 0.3, 0.6), (0.4, 0.2, 0.4), "ds_opening")
    for (px, py) in ((x0 + 0.5, -0.9), (x0 + 0.5, 0.6)):
        mb.cyl_between((px, py, 0.0), (px, py, 2.2), 0.06, 0.05, "ds_wood_dark", segs=5)
    mb.box((x0 + 0.1, -0.15, 2.25), (1.3, 2.3, 0.08), "ds_palm_leaf_dry", rot=(0.0, 0.1, 0.0))
    for k in range(5):
        mb.box((x0 + 0.1 + rng.uniform(-0.3, 0.3), -1.1 + k * 0.48, 2.3), (1.5, 0.12, 0.05), "ds_palm_leaf" if k % 2 else "ds_palm_leaf_dry")
    lathe_pot(mb, cx + 1.55, -2.55, 0.0, 0.8, 0.3, "ds_pot", handles=True)
    lathe_pot(mb, cx + 2.1, -2.45, 0.0, 0.55, 0.24, "ds_pot_dark", lid="ds_pot_light")
    mb.cyl((cx - 1.0, -2.6, 0.13), 0.3, 0.34, 0.26, "ds_rope", segs=8)
    mb.clamp_floor()
    mb.finish("desert_mudhouse")


def build_desert_mudhouse_b():
    """A dovecote farm (~7 x 4 m): a small flat-roofed mud-brick house beside a tapering pigeon
    tower (6.8 m) studded with clay pots and perches, whitewashed pinnacles on top."""
    mb = MeshBuilder()
    rng = random.Random(289)
    hx = -1.6
    mb.box((hx, 0.1, 1.25), (3.8, 3.6, 2.5), "ds_mud", taper=(0.97, 0.96))
    mb.box((hx, 0.1, 2.55), (3.6, 3.4, 0.1), "ds_mud_dark")
    for s in (-1, 1):
        mb.box((hx, 0.1 + s * 1.66, 2.72), (3.66, 0.16, 0.34), "ds_mud_light")
        mb.box((hx + s * 1.76, 0.1, 2.72), (0.16, 3.2, 0.34), "ds_mud_light")
    mb.box((hx - 0.6, -1.65, 0.9), (0.9, 0.12, 1.8), "ds_opening")
    mb.box((hx - 0.6, -1.69, 1.88), (1.2, 0.12, 0.14), "ds_palm_trunk_dark")
    mb.box((hx + 0.8, -1.65, 1.7), (0.4, 0.12, 0.4), "ds_opening")
    mb.box((hx, -1.72, 0.28), (3.84, 0.06, 0.56), "ds_whitewash")
    tx = 1.9
    H = 5.4
    mb.box((tx, 0.1, H / 2), (2.8, 2.8, H), "ds_mud_light", taper=(0.72, 0.72))
    mb.box((tx, 0.1, H + 0.15), (2.2, 2.2, 0.3), "ds_whitewash")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((tx + sx * 0.85, 0.1 + sy * 0.85, H + 0.75), (0.34, 0.34, 0.9), "ds_whitewash", taper=(0.4, 0.4))
    mb.ico((tx, 0.1, H + 0.3), 0.75, "ds_whitewash", subdiv=1, scale=(1, 1, 0.9), flatten_below=H + 0.3)
    for k in range(4):
        z = 1.6 + k * 0.9
        half = 1.4 * (1 - 0.28 * z / H)
        mb.box((tx, 0.1 - half - 0.05, z - 0.3), (2.0 * half, 0.1, 0.07), "ds_palm_trunk_dark")
        for i in range(5):
            if rng.random() < 0.85:
                x = tx - half + 0.35 + i * (2 * half - 0.7) / 4
                mb.cyl((x, 0.1 - half + 0.02, z), 0.1, 0.1, 0.16, "ds_pot", segs=6, rot=(math.pi / 2, 0, 0))
                mb.cyl((x, 0.1 - half - 0.045, z), 0.055, 0.055, 0.03, "ds_opening", segs=6, rot=(math.pi / 2, 0, 0))
        for i in range(4):
            if rng.random() < 0.7:
                x = tx + half + 0.02
                y = 0.1 - half + 0.4 + i * (2 * half - 0.8) / 3
                mb.cyl((x, y, z), 0.1, 0.1, 0.16, "ds_pot", segs=6, rot=(0, math.pi / 2, 0))
    lathe_pot(mb, hx + 1.4, -2.2, 0.0, 0.7, 0.28, "ds_pot", handles=True)
    mb.finish("desert_mudhouse_b")


def _crops(model_id, seed, mats, heights, width=0.62):
    """A 6 x 4 m field patch: five rows of plant clumps on low ridges over dark irrigated soil."""
    mb = MeshBuilder()
    rng = random.Random(seed)
    mb.box((0, 0, 0.02), (6.0, 4.0, 0.04), "ds_soil")
    for r in range(5):
        y = -1.6 + r * 0.8
        mb.box((0, y, 0.07), (5.8, 0.36, 0.1), "ds_mud_dark", taper=(1.0, 0.6))
        for k in range(9):
            x = -2.6 + k * 0.65 + rng.uniform(-0.08, 0.08)
            h = rng.uniform(*heights)
            m = mats[rng.randrange(len(mats) - 1)] if rng.random() < 0.85 else mats[-1]
            mb.box((x, y + rng.uniform(-0.04, 0.04), 0.1 + h / 2), (width, 0.34, h), m, taper=(0.75, 0.5))
    mb.finish(model_id)


def build_desert_crops_a():
    """Green field patch (6 x 4 m): rows of young crops."""
    _crops("desert_crops_a", 291, ["ds_crop_green", "ds_crop_dark", "ds_crop_green", "ds_crop_gold"], (0.3, 0.55))


def build_desert_crops_b():
    """Ripe wheat patch (6 x 4 m): rows of golden grain."""
    _crops("desert_crops_b", 293, ["ds_crop_gold", "ds_crop_gold_b", "ds_crop_gold", "ds_crop_green"], (0.55, 0.85), width=0.6)


def build_desert_bridge():
    """Stone bridge over the Iteru (6 x 32 m along Y, deck at ground level): parapets with coping,
    rounded refuges over pointed cutwaters standing in the river, obelisk finials at the ends."""
    mb = MeshBuilder()
    Lh = 16.0
    W = 5.6
    mb.box((0, 0, -0.26), (W, 2 * Lh, 0.6), "ds_sandstone_light")
    for k in range(15):
        mb.box((0, -Lh + 2.0 + k * 2.0, 0.046), (W - 1.0, 0.07, 0.012), "ds_sandstone_b")
    for s in (-1, 1):
        x = s * (W / 2 - 0.25)
        mb.box((x, 0, 0.35), (0.5, 2 * Lh, 0.7), "ds_sandstone")
        mb.box((x, 0, 0.76), (0.62, 2 * Lh + 0.1, 0.12), "ds_sandstone_light")
        mb.box((s * (W / 2 - 0.1), 0, -1.6), (0.3, 2 * Lh, 2.4), "ds_sandstone_b")
        for py in (-9.6, -3.2, 3.2, 9.6):
            hull(mb, [(s * (W / 2 - 0.2), py - 1.0, -2.4), (s * (W / 2 - 0.2), py + 1.0, -2.4), (s * (W / 2 + 1.5), py, -2.4),
                      (s * (W / 2 - 0.2), py - 1.0, 0.5), (s * (W / 2 - 0.2), py + 1.0, 0.5), (s * (W / 2 + 1.5), py, 0.5)], "ds_sandstone_b")
            mb.cyl((s * (W / 2 + 0.25), py, 0.35), 0.95, 0.95, 0.7, "ds_sandstone", segs=10)
            mb.cyl((s * (W / 2 + 0.25), py, 0.76), 1.02, 1.02, 0.12, "ds_sandstone_light", segs=10)
        for ey in (-Lh + 0.45, Lh - 0.45):
            mb.box((x, ey, 0.7), (0.9, 0.9, 1.4), "ds_sandstone")
            mb.box((x, ey, 2.15), (0.56, 0.56, 1.5), "ds_sandstone_light", taper=(0.6, 0.6))
            hull(mb, [(x - 0.17, ey - 0.17, 2.9), (x + 0.17, ey - 0.17, 2.9), (x - 0.17, ey + 0.17, 2.9), (x + 0.17, ey + 0.17, 2.9),
                      (x, ey, 3.25)], "ds_gold")
            mb.box((x, ey, 1.25), (0.94, 0.94, 0.14), "ds_lapis")
    mb.finish("desert_bridge")


def build_desert_footbridge():
    """A plank footbridge (3.2 x 14 m along Y) over a marsh channel: deck at ground level, posts
    down into the water and rope rails — the Snake Isles' crossings."""
    mb = MeshBuilder()
    rng = random.Random(297)
    Lh = 7.0
    n = 26
    for k in range(n):
        y = -Lh + (k + 0.5) * (2 * Lh / n)
        mb.box((rng.uniform(-0.05, 0.05), y, -0.025), (2.6 + rng.uniform(-0.12, 0.12), 2 * Lh / n - 0.05, 0.1),
               "ds_plank" if k % 4 else "ds_wood", rot=(0, 0, rng.uniform(-0.035, 0.035)))
    for s in (-1, 1):
        mb.box((s * 1.1, 0, -0.16), (0.2, 2 * Lh, 0.16), "ds_wood_dark")
        posts = (-6.6, -3.3, 0.0, 3.3, 6.6)
        for py in posts:
            mb.cyl((s * 1.45, py, -0.6), 0.1, 0.09, 2.6, "ds_wood_dark", segs=6)
        for a, b in zip(posts[:-1], posts[1:]):
            mb.cyl_between((s * 1.45, a, 0.62), (s * 1.45, b, 0.62), 0.03, 0.03, "ds_rope", segs=4)
    mb.finish("desert_footbridge")


def build_desert_well():
    """Village well (~2.6 m): a round stone rim with dark water, a timber frame with a pulley, rope
    and bucket, a stone trough and water jars."""
    mb = MeshBuilder()
    mb.lathe([(0.78, 0.0), (1.12, 0.0), (1.12, 0.78), (1.03, 0.88), (0.86, 0.88), (0.78, 0.78)], "ds_sandstone", segs=14, closed=True)
    mb.lathe([(1.12, 0.3), (1.15, 0.3), (1.15, 0.4), (1.12, 0.4)], "ds_sandstone_b", segs=14, closed=True)
    mb.cyl((0, 0, 0.46), 0.8, 0.8, 0.04, "ds_water", segs=14)
    for s in (-1, 1):
        mb.cyl_between((s * 0.98, 0, 0.0), (s * 0.98, 0, 2.45), 0.08, 0.07, "ds_wood_dark", segs=6)
    mb.cyl_between((-1.12, 0, 2.38), (1.12, 0, 2.38), 0.07, 0.07, "ds_wood", segs=6)
    mb.cyl((0, 0, 2.25), 0.16, 0.16, 0.1, "ds_wood_dark", segs=8, rot=(0, math.pi / 2, 0))
    mb.cyl_between((0, 0.15, 2.25), (0, 0.15, 1.32), 0.015, 0.015, "ds_rope", segs=4)
    lathe_pot(mb, 0.0, 0.15, 0.95, 0.38, 0.16, "ds_wood", neck=0.9, segs=7)
    mb.box((1.9, 0.6, 0.23), (1.5, 0.56, 0.46), "ds_sandstone_b")
    mb.box((1.9, 0.6, 0.455), (1.3, 0.36, 0.02), "ds_water")
    lathe_pot(mb, -1.55, -0.75, 0.0, 0.8, 0.3, "ds_pot", handles=True)
    lathe_pot(mb, -1.2, -1.2, 0.0, 0.55, 0.24, "ds_pot_light")
    mb.finish("desert_well")


def build_desert_jetty():
    """Wooden landing stage (2.6 x 9 m) on posts, planked, with a mooring post and a coil of rope;
    the land end at +Y, reaching out over the water toward -Y."""
    mb = MeshBuilder()
    for k in range(18):
        mb.box((0, -4.25 + k * 0.5, 0.3), (2.6, 0.44, 0.07), "ds_plank" if k % 3 else "ds_wood")
    for s in (-1, 1):
        mb.box((s * 1.0, 0, 0.19), (0.18, 9.0, 0.16), "ds_wood_dark")
        for py in (-4.2, -1.4, 1.4, 4.2):
            mb.cyl((s * 1.15, py, -0.72), 0.12, 0.12, 2.3, "ds_wood_dark", segs=6)
    mb.cyl((1.0, -4.1, 0.75), 0.14, 0.12, 0.9, "ds_wood_dark", segs=6)
    mb.cyl((-0.7, -3.2, 0.41), 0.3, 0.3, 0.14, "ds_rope", segs=8)
    lathe_pot(mb, 0.6, 2.9, 0.335, 0.6, 0.24, "ds_pot", handles=True)
    mb.finish("desert_jetty")


def build_desert_shaduf():
    """Shaduf (~4.4 m): two mud-brick pillars, a crossbeam, a long sweep pole with a mud
    counterweight and a bucket on a rope reaching out over the water (-Y), a small basin behind."""
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.box((s * 0.55, 0.0, 1.1), (0.45, 0.5, 2.2), "ds_mud", taper=(0.85, 0.85))
    mb.cyl_between((-0.8, 0, 2.25), (0.8, 0, 2.25), 0.08, 0.08, "ds_wood_dark", segs=6)
    piv = Vector((0, 0, 2.35))
    d = Vector((0, -1, -0.25)).normalized()
    a, b = piv - d * 1.9, piv + d * 3.6
    mb.cyl_between(a, b, 0.07, 0.05, "ds_wood", segs=6)
    mb.ico(a + Vector((0, 0.05, -0.1)), 0.42, "ds_mud_dark", subdiv=1, scale=(1, 1, 0.8))
    mb.cyl_between(b, Vector((b.x, b.y, 0.72)), 0.015, 0.015, "ds_rope", segs=4)
    lathe_pot(mb, b.x, b.y, 0.36, 0.36, 0.17, "ds_pot_dark", neck=0.8, segs=7)
    mb.box((0, 1.25, 0.15), (1.4, 1.1, 0.3), "ds_mud_light")
    mb.box((0, 1.25, 0.305), (1.1, 0.8, 0.02), "ds_water")
    mb.finish("desert_shaduf")


def build_desert_canal():
    """Irrigation ditch segment (2.2 x 8 m along Y): a strip of water between low mud banks with a
    few tufts; laid end to end beside the fields."""
    mb = MeshBuilder()
    rng = random.Random(301)
    mb.box((0, 0, 0.02), (1.1, 8.0, 0.04), "ds_water")
    for s in (-1, 1):
        hull(mb, [(s * 0.5, -4.0, 0.0), (s * 1.1, -4.0, 0.0), (s * 0.62, -4.0, 0.14), (s * 0.92, -4.0, 0.14),
                  (s * 0.5, 4.0, 0.0), (s * 1.1, 4.0, 0.0), (s * 0.62, 4.0, 0.14), (s * 0.92, 4.0, 0.14)], "ds_mud_dark")
        for k in range(3):
            y = rng.uniform(-3.4, 3.4)
            for i in range(4):
                a = rng.uniform(0, 2 * math.pi)
                base = Vector((s * 0.78, y, 0.1))
                tip = base + Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, rng.uniform(0.35, 0.6)))
                ribbon(mb, [base, (base + tip) / 2, tip], [0.07, 0.05, 0.01], Vector((-math.sin(a), math.cos(a), 0.0)), 0.02,
                       "ds_grass_green" if i % 2 else "ds_reed")
    mb.finish("desert_canal")


def build_desert_lotus():
    """Floating lotus pads with white and blue flowers (~3 m across); origin at the water surface."""
    mb = MeshBuilder()
    rng = random.Random(303)
    for k in range(8):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.2, 1.3)
        rad = rng.uniform(0.28, 0.5)
        z = 0.012 + k * 0.006
        mb.cyl((r * math.cos(a), r * math.sin(a), z), rad, rad, 0.02, "ds_lotus_pad" if k % 2 else "ds_lotus_pad_b", segs=9)
    for k, m in enumerate(("ds_lotus_white", "ds_lotus_white", "ds_lotus_blue")):
        a = k * 2.1 + 0.4
        r = 0.6 + 0.2 * k
        c = Vector((r * math.cos(a), r * math.sin(a), 0.03))
        mb.cyl_between(c, c + Z * 0.18, 0.02, 0.02, "ds_reed", segs=4)
        for p in range(6):
            pa = p * math.pi / 3
            d = Vector((math.cos(pa), math.sin(pa), 0.0))
            side = d.cross(Z)
            hull(mb, [c + Z * 0.15, c + Z * 0.16 + d * 0.06 + side * 0.05, c + Z * 0.16 + d * 0.06 - side * 0.05,
                      c + Z * 0.34 + d * 0.13], m)
        mb.ico(c + Z * 0.22, 0.05, "ds_gold", subdiv=0)
    mb.finish("desert_lotus")


def build_desert_tile_c():
    """Cheap 2 x 2 m court paving (four plain slabs over a grout bed) for the big temple court."""
    mb = MeshBuilder()
    rng = random.Random(307)
    mb.box((0, 0, -0.07), (2.0, 2.0, 0.1), "ds_sandstone_dark")
    mats = ["ds_sandstone_light", "ds_cream", "ds_cream", "ds_sandstone_light"]
    for k, (x, y) in enumerate(((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5))):
        h = rng.uniform(0.0, 0.012)
        mb.box((x, y, -0.05 + h / 2), (0.965, 0.965, 0.1 + h), mats[k])
    mb.finish("desert_tile_c")


def build_desert_mesa():
    """A wind-carved sandstone butte (~13 x 9 m, 7 m): stacked strata, a flat cap and talus."""
    mb = MeshBuilder()
    rng = random.Random(311)
    hull(mb, L.rock_points((0, 0, 0), (6.5, 4.6, 2.8), rng, n=22, rough=0.12), "ds_rock")
    hull(mb, L.rock_points((0.3, -0.2, 2.3), (5.2, 3.7, 2.1), rng, n=20, flat_bottom=False, rough=0.1), "ds_rock_c")
    hull(mb, L.rock_points((0.5, 0.1, 4.4), (4.2, 3.0, 1.7), rng, n=18, flat_bottom=False, rough=0.1), "ds_rock_b")
    hull(mb, [(x, y, z) for (x, y) in L.jitter_pts(L.circle_pts(3.3, 9, 0.3, 0.6, 0.1), 0.4, rng) for z in (5.6, 6.8)], "ds_rock_c")
    for i in range(10):
        a = rng.uniform(0, 2 * math.pi)
        c = (math.cos(a) * rng.uniform(5.5, 7.2), math.sin(a) * rng.uniform(4.0, 5.2), 0.0)
        r = rng.uniform(0.4, 1.0)
        hull(mb, L.rock_points(c, (r * 1.3, r, r * 0.8), rng, n=9), ["ds_rock", "ds_rock_b", "ds_rock_c"][i % 3])
    mb.clamp_floor()
    mb.finish("desert_mesa")


def build_desert_portico():
    """A colonnade section of the temple court (12.4 x 2.9 m, 7.6 m): four papyrus columns on a
    stylobate under a painted architrave and cavetto cornice, before a wall carved with jackal
    gods (front -Y)."""
    mb = MeshBuilder()
    Lx = 12.4
    mb.box((0, 0.25, 0.2), (Lx, 2.9, 0.4), "ds_sandstone_dark")
    mb.box((0, 1.35, 3.7), (Lx, 0.5, 6.6), "ds_sandstone")
    for x in (-3.0, 0.0, 3.0):
        _relief_anubis(mb, x, 1.1, 1.0, 3.6)
    for x in (-4.5, -1.5, 1.5, 4.5):
        _papyrus_column(mb, x, -0.35, 0.4, 6.1, r=0.42)
    mb.box((0, 0.5, 6.95), (Lx, 2.4, 0.9), "ds_sandstone_light")
    for k, (m, z) in enumerate((("ds_lapis", 6.72), ("ds_red_paint", 6.9), ("ds_gold", 7.08))):
        mb.box((0, -0.71, z), (Lx - 0.2, 0.03, 0.12), m)
    mb.box((0, 0.5, 7.55), (Lx, 2.4, 0.3), "ds_sandstone", taper=(1.02, 1.14))
    mb.box((0, 0.5, 7.74), (Lx * 1.02 + 0.05, 2.4 * 1.14 + 0.05, 0.08), "ds_sandstone_top")
    mb.finish("desert_portico")


def build_desert_temple_gate():
    """The Anubis temple front (39 x 7.6 m, 12.8 m; masts 14.6 m): two battered pylon towers with
    colossal jackal god reliefs and glyph columns, cavetto cornices, black-and-gold banners on
    masts, and between them the gate block with a winged sun disc; the door itself
    (desert_temple_door) stands in front of the gate block (its front at y = -2.1). Kept below the
    game camera's height (~15.6 m over the player), so the camera is never inside it; the temple
    hall (desert_temple_hall) stands behind it (+Y)."""
    mb = MeshBuilder()
    rng = random.Random(313)
    H = 11.6
    W, D, TX, TY = 15.0, 7.0, 0.84, 0.8
    lean = math.atan(D / 2 * (1 - TY) / H)
    for s in (-1, 1):
        cx = s * 12.0
        mb.box((cx, 0.4, H / 2), (W, D, H), "ds_sandstone", taper=(TX, TY))
        tw, td = W * TX, D * TY
        band(mb, cx, 0.4, tw, td, H - 0.55, H - 0.15, "ds_sandstone_b", grow=0.12)
        mb.box((cx, 0.4, H + 0.5), (tw + 0.2, td + 0.2, 1.0), "ds_sandstone_light", taper=(1.1, 1.22))
        mb.box((cx, 0.4, H + 1.1), ((tw + 0.2) * 1.1 + 0.1, (td + 0.2) * 1.22 + 0.1, 0.2), "ds_sandstone_top")
        z0 = 1.2
        yf = 0.4 - D / 2 * (1 - (1 - TY) * z0 / H)
        _relief_anubis(mb, cx + s * 0.6, yf, z0, 7.8, sign=-1, lean=lean)
        for col in range(3):
            gx = cx - s * (3.6 + col * 0.8)
            for k in range(10):
                z = 1.6 + k * 0.85
                if rng.random() < 0.15:
                    continue
                yz = 0.4 - D / 2 * (1 - (1 - TY) * z / H)
                mb.box((gx + rng.uniform(-0.08, 0.08), yz - 0.02, z), (0.36, 0.08, 0.42),
                       "ds_stripe" if rng.random() < 0.72 else ("ds_lapis" if rng.random() < 0.6 else "ds_red_paint"), rot=(-lean, 0, 0))
        for dx in (-5.0, 5.0):
            x = cx + dx
            yb = 0.4 - D / 2 - 0.25
            mb.box((x, yb, 7.0), (0.3, 0.3, 14.0), "ds_wood_dark")
            for zc in (4.0, 9.5):
                yc = 0.4 - D / 2 * (1 - (1 - TY) * zc / H)
                mb.box((x, (yb + yc) / 2, zc), (0.22, yc - yb + 0.1, 0.22), "ds_bronze")
            mb.box((x + 0.62, yb - 0.04, 11.9), (0.95, 0.06, 3.8), "ds_basalt")
            mb.box((x + 0.62, yb - 0.08, 11.9), (0.3, 0.04, 3.4), "ds_gold")
            hull(mb, [(x - 0.2, yb - 0.2, 14.0), (x + 0.2, yb - 0.2, 14.0), (x - 0.2, yb + 0.2, 14.0), (x + 0.2, yb + 0.2, 14.0),
                      (x, yb, 14.6)], "ds_gold")
    # the gate block between the towers
    gb = 0.6
    mb.box((0, gb, 4.5), (9.4, 5.2, 9.0), "ds_sandstone_b")
    band(mb, 0, gb, 9.4, 5.2, 8.3, 8.7, "ds_sandstone", grow=0.1)
    mb.box((0, gb, 9.3), (9.8, 5.6, 0.8), "ds_sandstone_light", taper=(1.06, 1.12))
    mb.box((0, gb, 9.78), (9.8 * 1.06 + 0.1, 5.6 * 1.12 + 0.1, 0.18), "ds_sandstone_top")
    _winged_disc(mb, gb - 2.6, 7.95, 3.2)
    for s in (-1, 1):
        mb.box((s * 3.6, gb - 2.62, 3.6), (1.0, 0.06, 6.4), "ds_lapis")
        mb.box((s * 3.6, gb - 2.66, 3.6), (0.6, 0.04, 5.9), "ds_gold")
    mb.finish("desert_temple_gate")


def build_desert_temple_hall():
    """The Anubis temple's hall behind its pylon (34 x 34 m, 12 m): a battered flat-roofed hypostyle
    block with a cavetto cornice, a raised clerestory nave with dark light-slots, jackal gods and
    glyph bands carved along its sides, and a lower sanctuary at the back. Its front (-Y) meets the
    back of desert_temple_gate; like the pylon it stays below the game camera's height."""
    mb = MeshBuilder()
    rng = random.Random(331)
    W, D, H = 34.0, 26.0, 9.0
    yc = -4.0
    mb.box((0, yc, H / 2), (W, D, H), "ds_sandstone", taper=(0.95, 0.97))
    band(mb, 0, yc, W * 0.95, D * 0.97, H - 0.6, H - 0.2, "ds_sandstone_b", grow=0.12)
    mb.box((0, yc, H + 0.4), (W * 0.95 + 0.2, D * 0.97 + 0.2, 0.8), "ds_sandstone_light", taper=(1.06, 1.08))
    mb.box((0, yc, H + 0.9), ((W * 0.95 + 0.2) * 1.06 + 0.1, (D * 0.97 + 0.2) * 1.08 + 0.1, 0.2), "ds_sandstone_top")
    # the clerestory: a raised nave down the middle, with dark light-slots on its sides
    mb.box((0, yc, H + 2.0), (10.0, D - 2.0, 2.2), "ds_sandstone_b")
    mb.box((0, yc, H + 3.2), (10.8, D - 1.4, 0.3), "ds_sandstone_light")
    for s in (-1, 1):
        for k in range(7):
            mb.box((s * 5.02, yc - (D - 2.0) / 2 + 2.0 + k * 3.35, H + 2.0), (0.06, 1.4, 1.0), "ds_opening")
    # jackal gods and glyph bands along both sides (carved facing -Y, then turned to face +-X)
    for s in (-1, 1):
        for k in range(4):
            before = set(mb.bm.verts)
            y0 = yc - D / 2 + 4.0 + k * 6.0
            _relief_anubis(mb, 0.0, 0.0, 0.9, 5.6, sign=-1)
            for g in range(6):
                if rng.random() < 0.85:
                    mb.box((-1.9 + g * 0.75, -0.035, 6.9), (0.36, 0.07, 0.36), "ds_stripe" if g % 3 else "ds_lapis")
            xf = W / 2 * (1 - 0.05 * 0.1)
            M = Matrix.Translation((s * (xf - 0.2), y0, 0.0)) @ Matrix.Rotation(-s * math.pi / 2, 4, "Z")
            mb.transform(_since(mb, before), M)
    # the sanctuary at the back
    mb.box((0, yc + D / 2 + 4.0, 3.8), (20.0, 8.0, 7.6), "ds_sandstone", taper=(0.96, 0.96))
    mb.box((0, yc + D / 2 + 4.0, 7.9), (20.4, 8.4, 0.6), "ds_sandstone_light", taper=(1.05, 1.08))
    # offering stands on the roof corners
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = sx * (W * 0.95 / 2 - 1.2)
            y = yc + sy * (D * 0.97 / 2 - 1.2)
            mb.box((x, y, H + 1.4), (0.9, 0.9, 0.8), "ds_sandstone_b")
            mb.ico((x, y, H + 2.0), 0.35, "ds_gold", subdiv=1)
    mb.finish("desert_temple_hall")


def build_desert_temple_door():
    """The doorway of the Anubis temple (6.4 x 1.8 m, 7.4 m): gilded jambs with jackal reliefs on
    black panels, a lintel with a winged sun, bronze-studded black doors thrown open on the dark,
    a threshold and a pair of offering braziers — the entrance to the act's dungeon (front -Y)."""
    mb = MeshBuilder()
    mb.box((0, 0.0, 0.07), (6.4, 1.8, 0.14), "ds_sandstone_dark")
    for s in (-1, 1):
        mb.box((s * 2.4, 0.15, 3.3), (1.4, 1.5, 6.6), "ds_sandstone_light")
        mb.box((s * 2.4, -0.62, 3.2), (0.9, 0.06, 5.2), "ds_basalt")
        _relief_anubis(mb, s * 2.4, -0.65, 0.9, 4.4, sign=-1, mat="ds_gold")
        mb.box((s * 2.4, -0.64, 6.05), (1.2, 0.06, 0.14), "ds_gold")
        mb.box((s * 1.78, -0.6, 3.3), (0.1, 0.06, 6.6), "ds_gold")
    mb.box((0, 0.15, 6.95), (6.4, 1.5, 0.9), "ds_sandstone_light")
    mb.box((0, 0.15, 7.52), (6.6, 1.7, 0.26), "ds_sandstone", taper=(1.04, 1.12))
    _winged_disc(mb, -0.6, 6.95, 1.6)
    mb.box((0, 0.65, 3.3), (3.3, 0.5, 6.6), "ds_opening")
    mb.box((0, 0.3, 0.16), (3.3, 1.1, 0.04), "ds_opening")
    for s in (-1, 1):
        before = set(mb.bm.verts)
        mb.box((s * 0.8, 0.0, 3.1), (1.6, 0.14, 6.2), "ds_basalt")
        for k in range(4):
            for i in range(2):
                mb.box((s * (0.45 + i * 0.7), -0.08, 1.0 + k * 1.4), (0.1, 0.04, 0.1), "ds_bronze")
        mb.transform(_since(mb, before), Matrix.Translation((s * 1.62, 0.02, 0.0)) @ Matrix.Rotation(-s * 1.2, 4, "Z") @ Matrix.Translation((-s * 1.6, 0.0, 0.0)))
    mb.finish("desert_temple_door")


def build_desert_gateway():
    """Monumental gateway (26 x 4.6 m, ~11 m): two battered pylon towers with jackal reliefs on
    both faces and a lintel with winged sun discs spanning a 12 m passage (along Y) between them."""
    mb = MeshBuilder()
    H = 10.0
    W, D, TX, TY = 6.4, 4.6, 0.82, 0.8
    lean = math.atan(D / 2 * (1 - TY) / H)
    for s in (-1, 1):
        cx = s * 9.3
        mb.box((cx, 0, H / 2), (W, D, H), "ds_sandstone", taper=(TX, TY))
        tw, td = W * TX, D * TY
        band(mb, cx, 0, tw, td, H - 0.5, H - 0.15, "ds_sandstone_b", grow=0.1)
        mb.box((cx, 0, H + 0.4), (tw + 0.2, td + 0.2, 0.8), "ds_sandstone_light", taper=(1.1, 1.22))
        mb.box((cx, 0, H + 0.88), ((tw + 0.2) * 1.1 + 0.1, (td + 0.2) * 1.22 + 0.1, 0.16), "ds_sandstone_top")
        for sg in (-1, 1):
            z0 = 1.2
            yf = sg * D / 2 * (1 - (1 - TY) * z0 / H)
            _relief_anubis(mb, cx, yf, z0, 6.4, sign=sg, lean=lean)
    mb.box((0, 0, 9.2), (14.2, 3.0, 1.6), "ds_sandstone_light")
    mb.box((0, 0, 10.2), (14.6, 3.2, 0.4), "ds_sandstone", taper=(1.02, 1.15))
    for sg in (-1, 1):
        _winged_disc(mb, sg * 1.5, 9.2, 2.4, sign=sg)
    mb.finish("desert_gateway")


def build_desert_camel():
    """A standing dromedary (~2.3 m, 2.9 m long) with a red-and-blue saddle blanket and bags, head
    toward -Y."""
    mb = MeshBuilder()
    rng = random.Random(317)
    c = "ds_camel"
    hull(mb, L.rock_points((0, 0.2, 1.45), (0.42, 0.95, 0.38), rng, n=18, flat_bottom=False, rough=0.05), c)
    mb.ico((0, 0.28, 1.82), 0.42, c, subdiv=1, scale=(0.8, 1.15, 0.95))
    mb.cyl_between((0, -0.62, 1.5), (0, -1.12, 1.98), 0.2, 0.14, c, segs=7)
    mb.cyl_between((0, -1.12, 1.95), (0, -1.2, 2.2), 0.14, 0.13, c, segs=7)
    hull(mb, [(-0.13, -1.05, 2.32), (0.13, -1.05, 2.32), (-0.14, -1.1, 2.1), (0.14, -1.1, 2.1),
              (-0.09, -1.62, 2.18), (0.09, -1.62, 2.18), (-0.08, -1.6, 2.04), (0.08, -1.6, 2.04)], c)
    for s in (-1, 1):
        mb.box((s * 0.12, -1.08, 2.38), (0.05, 0.06, 0.1), "ds_camel_dark")
        mb.box((s * 0.1, -1.3, 2.26), (0.03, 0.05, 0.03), "ds_stripe")
    for (x, y) in ((-0.2, -0.5), (0.2, -0.5), (-0.2, 0.85), (0.2, 0.85)):
        knee = Vector((x * 1.05, y + (0.05 if y < 0 else -0.08), 0.68))
        mb.cyl_between((x, y, 1.3), knee, 0.1, 0.075, c, segs=6)
        mb.cyl_between(knee, (x * 1.05, y + 0.02, 0.06), 0.07, 0.055, "ds_camel_dark", segs=6)
        mb.box((x * 1.05, y - 0.03, 0.04), (0.16, 0.2, 0.08), "ds_camel_dark")
    mb.cyl_between((0, 1.12, 1.5), (0, 1.22, 0.95), 0.04, 0.03, "ds_camel_dark", segs=5)
    mb.ico((0, 0.28, 1.86), 0.47, "ds_cloth_red", subdiv=1, scale=(0.95, 1.1, 0.72))
    for s in (-1, 1):
        mb.box((s * 0.45, 0.28, 1.66), (0.05, 0.8, 0.44), "ds_cloth_red")
        mb.box((s * 0.47, 0.28, 1.44), (0.04, 0.8, 0.07), "ds_cloth_blue")
        mb.ico((s * 0.58, 0.0, 1.45), 0.22, "ds_cloth_saffron", subdiv=1, scale=(0.7, 1.0, 1.1))
        mb.ico((s * 0.56, 0.62, 1.5), 0.2, "ds_rope", subdiv=1, scale=(0.7, 1.0, 1.1))
    mb.finish("desert_camel")


def build_desert_fern():
    """A lush broad-leaved oasis plant (~1.4 m, 2.4 m across): arching ribbon leaves."""
    mb = MeshBuilder()
    rng = random.Random(319)
    for k in range(9):
        a = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        ln = rng.uniform(0.9, 1.3)
        pts = [Vector((0, 0, 0.05)) + d * (ln * s) + Z * ((1.3 * s - 1.05 * s * s) * ln) for s in (0.0, 0.25, 0.5, 0.75, 1.0)]
        ribbon(mb, pts, [0.05, 0.3, 0.36, 0.26, 0.02], (Z * 0.9 + d.cross(Z) * 0.1).normalized(), 0.03,
               "ds_fern" if k % 3 else "ds_fern_light")
    mb.ico((0, 0, 0.15), 0.18, "ds_crop_dark", subdiv=1)
    mb.clamp_floor()
    mb.finish("desert_fern")


def build_desert_grass_green():
    """Lush green grass tufts (~1.5 m across, 0.6 m) for the oasis, the fields and the river banks."""
    mb = MeshBuilder()
    rng = random.Random(323)
    for t in range(3):
        cx, cy = rng.uniform(-0.45, 0.45), rng.uniform(-0.45, 0.45)
        for k in range(7):
            a = 2 * math.pi * k / 7 + rng.uniform(-0.3, 0.3)
            base = Vector((cx, cy, 0.0))
            tip = base + Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, rng.uniform(0.35, 0.65)))
            mid = (base + tip) / 2 + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.05))
            ribbon(mb, [base, mid, tip], [0.09, 0.06, 0.012], Vector((-math.sin(a), math.cos(a), 0.0)), 0.025,
                   "ds_grass_green" if k % 3 else ("ds_fern_light" if t % 2 else "ds_crop_dark"))
    mb.finish("desert_grass_green")


BUILDERS = {
    "desert_sphinx_small": build_desert_sphinx_small,
    "desert_ruin": build_desert_ruin,
    "desert_tent": build_desert_tent,
    "desert_grass": build_desert_grass,
    "desert_pebbles": build_desert_pebbles,
    "desert_planter": build_desert_planter,
    "desert_wall": build_desert_wall,
    "desert_tower": build_desert_tower,
    "desert_tower_dome": build_desert_tower_dome,
    "desert_gate": build_desert_gate,
    "desert_house_a": build_desert_house_a,
    "desert_house_b": build_desert_house_b,
    "desert_house_c": build_desert_house_c,
    "desert_colonnade": build_desert_colonnade,
    "desert_obelisk": build_desert_obelisk,
    "desert_obelisk_fallen": build_desert_obelisk_fallen,
    "desert_pyramid": build_desert_pyramid,
    "desert_statue": build_desert_statue,
    "desert_sphinx": build_desert_sphinx,
    "desert_head": build_desert_head,
    "desert_column": build_desert_column,
    "desert_column_broken": build_desert_column_broken,
    "desert_pylon": build_desert_pylon,
    "desert_tomb": build_desert_tomb,
    "desert_palm_a": build_desert_palm_a,
    "desert_palm_b": build_desert_palm_b,
    "desert_reeds": build_desert_reeds,
    "desert_shrub": build_desert_shrub,
    "desert_awning": build_desert_awning,
    "desert_fountain": build_desert_fountain,
    "desert_pots": build_desert_pots,
    "desert_carpet": build_desert_carpet,
    "desert_boat": build_desert_boat,
    "desert_rock": build_desert_rock,
    "desert_tile_a": build_desert_tile_a,
    "desert_tile_b": build_desert_tile_b,
    "desert_brazier": build_desert_brazier,
    "desert_ruinwall_a": build_desert_ruinwall_a,
    "desert_ruinwall_b": build_desert_ruinwall_b,
    "desert_ruinwall_c": build_desert_ruinwall_c,
    "desert_ruinwall_pier": build_desert_ruinwall_pier,
    "desert_anubis_statue": build_desert_anubis_statue,
    "desert_jackal_statue": build_desert_jackal_statue,
    "desert_serpent_statue": build_desert_serpent_statue,
    "desert_stele": build_desert_stele,
    "desert_sarcophagus": build_desert_sarcophagus,
    "desert_tomb_pyr": build_desert_tomb_pyr,
    "desert_mudhouse": build_desert_mudhouse,
    "desert_mudhouse_b": build_desert_mudhouse_b,
    "desert_crops_a": build_desert_crops_a,
    "desert_crops_b": build_desert_crops_b,
    "desert_bridge": build_desert_bridge,
    "desert_footbridge": build_desert_footbridge,
    "desert_well": build_desert_well,
    "desert_jetty": build_desert_jetty,
    "desert_shaduf": build_desert_shaduf,
    "desert_canal": build_desert_canal,
    "desert_lotus": build_desert_lotus,
    "desert_tile_c": build_desert_tile_c,
    "desert_mesa": build_desert_mesa,
    "desert_portico": build_desert_portico,
    "desert_temple_gate": build_desert_temple_gate,
    "desert_temple_hall": build_desert_temple_hall,
    "desert_temple_door": build_desert_temple_door,
    "desert_gateway": build_desert_gateway,
    "desert_camel": build_desert_camel,
    "desert_fern": build_desert_fern,
    "desert_grass_green": build_desert_grass_green,
}
