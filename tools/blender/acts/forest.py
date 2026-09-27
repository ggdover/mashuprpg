"""Act I — The Whispering Pines (forest_*): Swedish pine forest, a viking lake village (Birkavik),
the ruined Mattis fort, the tarn, the grey dwarves' hollows and the barrow downs: trees and tree
stands, rocks, ground-cover patches, monuments (standing / rune stones, cairns, mounds), bridges,
the wooden gate and the roundpole fences. Built by tools/blender/acts/build_all.py (--only forest).

Blender axes: Z up, fronts face -Y (= Godot +Z, towards the game camera). Origin at the base
centre, identity transforms, flat-shaded Principled colours, closed shells (backface culling).
Materials are registered in envlib.PALETTE with the "fo_" prefix.
OWNER: acts-forest.
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

L.PALETTE.update({
    # trees
    "fo_bark_grey": dict(hex="#4a3f37", rough=0.95),
    "fo_bark_red": dict(hex="#b5673b", rough=0.9),
    "fo_bark_red_dark": dict(hex="#8d4c2c", rough=0.9),
    "fo_bark_spruce": dict(hex="#453629", rough=0.95),
    "fo_pine": dict(hex="#294f26", rough=0.9),
    "fo_pine_dark": dict(hex="#1c3a1b", rough=0.9),
    "fo_pine_light": dict(hex="#3b6432", rough=0.9),
    "fo_spruce": dict(hex="#1f3d29", rough=0.9),
    "fo_spruce_dark": dict(hex="#172f20", rough=0.9),
    "fo_spruce_light": dict(hex="#2b5234", rough=0.9),
    "fo_birch_bark": dict(hex="#e4e0d3", rough=0.8),
    "fo_birch_mark": dict(hex="#2b2a28", rough=0.9),
    "fo_birch_leaf": dict(hex="#6f993c", rough=0.85),
    "fo_birch_leaf_b": dict(hex="#84aa48", rough=0.85),
    "fo_birch_leaf_c": dict(hex="#5f8f37", rough=0.85),
    "fo_grass": dict(hex="#6f9a38", rough=0.95),
    "fo_grass_light": dict(hex="#98b24a", rough=0.95),
    "fo_grass_dry": dict(hex="#b3ad62", rough=0.95),
    "fo_reed": dict(hex="#8aa246", rough=0.9),
    "fo_reed_head": dict(hex="#6b4a2c", rough=0.9),
    # ground cover
    "fo_moss": dict(hex="#6b9034", rough=1.0),
    "fo_moss_light": dict(hex="#93b245", rough=1.0),
    "fo_moss_dark": dict(hex="#4d6f29", rough=1.0),
    "fo_shrub": dict(hex="#3c6a2b", rough=0.95),
    "fo_shrub_light": dict(hex="#57863a", rough=0.95),
    "fo_shrub_dark": dict(hex="#2d5222", rough=0.95),
    "fo_berry_blue": dict(hex="#2b3d78", rough=0.5),
    "fo_berry_red": dict(hex="#c02a26", rough=0.5),
    "fo_fern": dict(hex="#5b8e35", rough=0.95),
    "fo_fern_dark": dict(hex="#44722a", rough=0.95),
    "fo_flower": dict(hex="#f4f2ea", rough=0.8),
    "fo_flower_core": dict(hex="#e8c840", rough=0.8),
    "fo_stem": dict(hex="#5f8a3a", rough=0.9),
    "fo_mush_red": dict(hex="#c4352a", rough=0.6),
    "fo_mush_dot": dict(hex="#f3efe4", rough=0.7),
    "fo_mush_stem": dict(hex="#e6dcc6", rough=0.8),
    # stone
    "fo_granite": dict(hex="#8a8d88", rough=0.95),
    "fo_granite_dark": dict(hex="#6c706c", rough=0.95),
    "fo_granite_light": dict(hex="#a2a59e", rough=0.95),
    "fo_lichen": dict(hex="#b8bf9c", rough=1.0),
    "fo_stone": dict(hex="#7b776f", rough=0.95),
    "fo_stone_dark": dict(hex="#5c5953", rough=0.95),
    "fo_stone_light": dict(hex="#96918a", rough=0.95),
    # wood / village
    "fo_log": dict(hex="#6b4b33", rough=0.95),
    "fo_log_end": dict(hex="#b98f60", rough=0.9),
    "fo_wood": dict(hex="#5b4331", rough=0.9),
    "fo_wood_dark": dict(hex="#3d2c20", rough=0.9),
    "fo_wood_light": dict(hex="#8b6b49", rough=0.88),
    "fo_wood_grey": dict(hex="#716759", rough=0.92),
    "fo_thatch": dict(hex="#a88c52", rough=0.95),
    "fo_thatch_b": dict(hex="#94794a", rough=0.95),
    "fo_thatch_dark": dict(hex="#6f5a35", rough=0.95),
    "fo_turf": dict(hex="#62853a", rough=1.0),
    "fo_turf_b": dict(hex="#557a32", rough=1.0),
    "fo_turf_dark": dict(hex="#445f2a", rough=1.0),
    "fo_wattle": dict(hex="#7c6446", rough=0.95),
    "fo_hide": dict(hex="#9b7a54", rough=0.95),
    "fo_hide_dark": dict(hex="#6f5438", rough=0.95),
    "fo_fish": dict(hex="#a9aaa2", rough=0.6),
    "fo_sail_red": dict(hex="#a8332a", rough=0.9),
    "fo_sail_white": dict(hex="#e3d8bf", rough=0.9),
    "fo_shield_red": dict(hex="#a33a2c", rough=0.8),
    "fo_shield_blue": dict(hex="#34507a", rough=0.8),
    "fo_shield_yellow": dict(hex="#c79a38", rough=0.8),
    "fo_rune_paint": dict(hex="#a3342a", rough=0.8),
    "fo_iron": dict(hex="#3c3d42", rough=0.55, metal=0.35),
    "fo_amber": dict(hex="#d9902c", emit="#ff9a2a", strength=1.2, rough=0.3),
    "fo_pot": dict(hex="#8a5e3c", rough=0.85),
    "fo_ash": dict(hex="#39342f", rough=1.0),
    "fo_water_fall": dict(hex="#d6ecf0", emit="#b8e2ee", strength=0.6, rough=0.2),
    "fo_foam": dict(hex="#eef6f6", emit="#d8eef2", strength=0.4, rough=0.3),
    # emissive
    "fo_rune_glow": dict(hex="#9fe8ff", emit="#5fd4ff", strength=4.0, rough=0.4),
    "fo_ember": dict(hex="#ff6a1a", emit="#ff5a10", strength=4.0, rough=1.0),
})


def _rng(seed):
    return random.Random(seed)


def _hull(mb, points, mat):
    """envlib.MeshBuilder.hull, robust to near-duplicate / interior points (dedupes the points and
    the delete list)."""
    uniq = []
    for p in points:
        q = Vector(p)
        if all((q - u).length > 1e-3 for u in uniq):
            uniq.append(q)
    verts = [mb.bm.verts.new(q) for q in uniq]
    res = bmesh.ops.convex_hull(mb.bm, input=verts)
    unused = []
    for g in res["geom_interior"] + res["geom_unused"]:
        if isinstance(g, bmesh.types.BMVert) and g not in unused:
            unused.append(g)
    if unused:
        bmesh.ops.delete(mb.bm, geom=unused, context="VERTS")
    verts = [v for v in verts if v.is_valid]
    faces = list(mb._faces_of(verts))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    mb._assign(verts, mat)
    return verts


def _jitter(verts, rng, amount, zfac=1.0, zmin=None):
    for v in verts:
        if zmin is not None and v.co.z <= zmin + 1e-6:
            continue
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount),
                        rng.uniform(-amount, amount) * zfac))


def _clump(mb, c, r, mat, rng, flat=0.5, subdiv=0, jitter=0.12):
    """Faceted foliage clump (flattened, jittered icosphere)."""
    return mb.ico(c, r, mat, subdiv=subdiv, jitter=jitter * r, rng=rng, scale=(1.0, 1.0, flat),
                  rot=(0, 0, rng.uniform(0, 6.28)))


def _loft(mb, sections, mat, cap_start=True, cap_end=True):
    """Quads between consecutive closed sections (lists of Vector, same count, CCW when looking
    from the section before towards the next). Caps are fans to the section centroid."""
    rings = [[mb.bm.verts.new(Vector(p)) for p in sec] for sec in sections]
    n = len(sections[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            mb.bm.faces.new([a[i], a[j], b[j], b[i]])
    extra = []
    c0 = sum((v.co for v in rings[0]), Vector()) / n
    c1 = sum((v.co for v in rings[-1]), Vector()) / n
    ax = (c1 - c0).normalized()
    # cap apexes stand off the end rings, so the fans stay valid cones for non-convex sections
    if cap_start:
        c = mb.bm.verts.new(c0 - ax * 0.2)
        extra.append(c)
        for i in range(n):
            mb.bm.faces.new([rings[0][(i + 1) % n], rings[0][i], c])
    if cap_end:
        c = mb.bm.verts.new(c1 + ax * 0.2)
        extra.append(c)
        for i in range(n):
            mb.bm.faces.new([rings[-1][i], rings[-1][(i + 1) % n], c])
    verts = [v for r in rings for v in r] + extra
    faces = mb._faces_of(verts)
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    mb._assign(verts, mat)
    return verts


# ----------------------------------------------------------------------------------- trees

def _pine(mb, rng, height, crown_mats, lean=(0.0, 0.0), crown_scale=1.0):
    """Swedish pine: tall straight trunk, grey-brown below and orange-red above, a few dead branch
    stubs, and a high irregular crown of flat foliage clouds."""
    lx, ly = lean
    top = Vector((lx, ly, height))

    def at(t):
        return Vector((lx * t * t, ly * t * t, height * t))
    r0 = 0.3 * height / 10.0
    # lower trunk (grey, flaring) and upper trunk (red)
    prof_low = [(0.0, 0.0), (r0 * 1.25, 0.0), (r0, 0.35), (r0 * 0.88, height * 0.38), (0.0, height * 0.38)]
    v = mb.lathe(prof_low, "fo_bark_grey", segs=7, cap_bottom=False, phase=rng.uniform(0, 1))
    for vv in v:
        t = vv.co.z / height
        vv.co += Vector((lx * t * t, ly * t * t, 0))
    mb.cyl_between(at(0.37), at(0.9), r0 * 0.86, r0 * 0.45, "fo_bark_red", segs=6)
    mb.cyl_between(at(0.55), at(0.72), r0 * 0.78, r0 * 0.6, "fo_bark_red_dark", segs=6)
    # dead branch stubs on the trunk
    for k in range(3):
        z = rng.uniform(0.3, 0.6)
        a = rng.uniform(0, 6.28)
        p = at(z)
        mb.cyl_between(p, p + Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, 0.25)), 0.04, 0.02, "fo_bark_grey", segs=4)
    # crown: branches to foliage clouds
    n = rng.randint(5, 7)
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.4, 0.4)
        z = rng.uniform(0.66, 0.9)
        base = at(z)
        reach = rng.uniform(1.3, 2.3) * crown_scale * (1.15 - (z - 0.66))
        tip = base + Vector((math.cos(a) * reach, math.sin(a) * reach, rng.uniform(0.3, 0.8)))
        mb.cyl_between(base, tip, 0.1, 0.05, "fo_bark_red_dark", segs=4)
        _clump(mb, tip + Vector((0, 0, 0.15)), rng.uniform(1.0, 1.35) * crown_scale,
               crown_mats[k % len(crown_mats)], rng, flat=0.42)
    _clump(mb, top + Vector((0, 0, -0.1)), 1.2 * crown_scale, crown_mats[0], rng, flat=0.55)
    _clump(mb, at(0.84) + Vector((0.3, -0.2, 0.4)), 1.35 * crown_scale, crown_mats[-1], rng, flat=0.45)


def build_forest_pine_a():
    """Tall Swedish pine (~10 m): bare red upper trunk, high flat crown."""
    mb = MeshBuilder()
    _pine(mb, _rng(301), 9.6, ["fo_pine", "fo_pine_dark", "fo_pine_light"], lean=(0.15, -0.1), crown_scale=0.95)
    mb.clamp_floor()
    mb.finish("forest_pine_a")


def build_forest_pine_b():
    """Younger pine (~8 m), fuller and a little lower crown."""
    mb = MeshBuilder()
    _pine(mb, _rng(307), 8.0, ["fo_pine_dark", "fo_pine", "fo_pine_dark"], lean=(-0.12, 0.1), crown_scale=1.0)
    mb.clamp_floor()
    mb.finish("forest_pine_b")


def build_forest_spruce():
    """Dark Norway spruce (~7 m): drooping stacked tiers down to the ground."""
    mb = MeshBuilder()
    rng = _rng(311)
    mb.lathe([(0.0, 0.0), (0.24, 0.0), (0.17, 0.4), (0.09, 5.8), (0.0, 6.0)], "fo_bark_spruce", segs=6, cap_bottom=False)
    tiers = [(0.4, 1.9, 1.5), (1.3, 1.7, 1.4), (2.15, 1.48, 1.35), (2.95, 1.25, 1.3), (3.7, 1.0, 1.28),
             (4.4, 0.78, 1.25), (5.05, 0.55, 1.25), (5.7, 0.34, 1.4)]
    mats = ["fo_spruce", "fo_spruce_dark", "fo_spruce_light", "fo_spruce_dark"]
    for k, (z, r, h) in enumerate(tiers):
        verts = mb.lathe([(0.0, 0.0), (r, -0.25), (r * 0.8, 0.12), (0.0, h)], mats[k % len(mats)],
                         segs=7, center=(0, 0, z), phase=k * 0.9)
        for vv in verts:
            if (vv.co.x ** 2 + vv.co.y ** 2) > 0.02:
                vv.co.x += rng.uniform(-0.12, 0.12)
                vv.co.y += rng.uniform(-0.12, 0.12)
                vv.co.z += rng.uniform(-0.12, 0.05)
    mb.clamp_floor()
    mb.finish("forest_spruce")


def build_forest_birch():
    """Silver birch (~7 m): two slender white trunks with black marks, light green airy crown."""
    mb = MeshBuilder()
    rng = _rng(317)
    trunks = [((0.0, 0.0), (0.35, -0.2, 6.4), 0.16), ((0.15, 0.1), (-0.6, 0.4, 5.5), 0.12)]
    for (bx, by), top, r in trunks:
        a = Vector((bx, by, 0.0))
        b = Vector(top)
        mb.cyl_between(a, b, r, r * 0.45, "fo_birch_bark", segs=6)
        for k in range(6):
            t = rng.uniform(0.08, 0.8)
            p = a.lerp(b, t)
            rr = r * (1 - 0.55 * t) + 0.012
            ang = rng.uniform(0, 6.28)
            c = p + Vector((math.cos(ang) * rr * 0.75, math.sin(ang) * rr * 0.75, 0))
            mb.box(c, (0.12 * (1 - t * 0.5), 0.12 * (1 - t * 0.5), 0.08), "fo_birch_mark", rot=(0, 0, ang))
        mb.cyl_between(a, a + Vector((0, 0, 0.5)), r * 1.3, r * 1.05, "fo_birch_mark", segs=6)
        # branches + leaf clumps
        for k in range(4):
            t = rng.uniform(0.55, 0.92)
            p = a.lerp(b, t)
            ang = rng.uniform(0, 6.28)
            q = p + Vector((math.cos(ang) * 1.2, math.sin(ang) * 1.2, 0.6))
            mb.cyl_between(p, q, 0.05, 0.025, "fo_birch_bark", segs=4)
            _clump(mb, q, rng.uniform(0.7, 0.92), rng.choice(["fo_birch_leaf", "fo_birch_leaf_b", "fo_birch_leaf_c"]),
                   rng, flat=0.7, subdiv=1, jitter=0.05)
        _clump(mb, b + Vector((0, 0, 0.2)), 0.85, "fo_birch_leaf_b", rng, flat=0.8, subdiv=1, jitter=0.05)
    mb.clamp_floor()
    mb.finish("forest_birch")


# ----------------------------------------------------------------------------------- stones & ground

def _mossy_rock(mb, rng, center, radii, n=18, rough=0.16, moss_level=0.62, moss="fo_moss", stone="fo_granite"):
    pts = L.rock_points(center, radii, rng, n=n, rough=rough)
    _hull(mb, pts, stone)
    zc = center[2]
    top = zc + radii[2] * (moss_level - 0.5) * 2.0
    moss_pts = [(center[0] + (x - center[0]) * 0.96, center[1] + (y - center[1]) * 0.96, z + 0.05) for (x, y, z) in pts if z > top]
    moss_pts += [(center[0] + (x - center[0]) * 1.0, center[1] + (y - center[1]) * 1.0, top) for (x, y, z) in pts if z > top]
    if len(moss_pts) >= 6:
        _hull(mb, moss_pts, moss)


def build_forest_boulder_a():
    """Big granite boulder (~3 m) with a thick moss cap and lichen patches."""
    mb = MeshBuilder()
    rng = _rng(331)
    _mossy_rock(mb, rng, (0, 0, 0.8), (1.55, 1.25, 1.0), n=22, rough=0.14, moss_level=0.72)
    _mossy_rock(mb, rng, (1.2, -0.7, 0.35), (0.7, 0.6, 0.45), n=12, moss_level=0.75, moss="fo_moss_light",
                stone="fo_granite_dark")
    _hull(mb, L.rock_points((-0.9, -0.95, 0.2), (0.38, 0.3, 0.26), rng, n=10), "fo_granite_light")
    for _ in range(4):
        a = rng.uniform(0, 6.28)
        p = (math.cos(a) * 1.35, math.sin(a) * 1.05, rng.uniform(0.45, 0.9))
        mb.ico(p, 0.2, "fo_lichen", subdiv=0, scale=(1, 1, 0.35))
    mb.clamp_floor()
    mb.finish("forest_boulder_a")


def build_forest_boulder_b():
    """Low rounded granite outcrop (~4.5 m wide) with moss patches and a blueberry tuft."""
    mb = MeshBuilder()
    rng = _rng(337)
    _mossy_rock(mb, rng, (0, 0, 0.3), (2.3, 1.6, 0.62), n=24, rough=0.1, moss_level=0.8, moss="fo_moss_light")
    _mossy_rock(mb, rng, (-1.5, 0.8, 0.35), (0.9, 0.75, 0.55), n=12, moss_level=0.68, stone="fo_granite_dark")
    for c in ((1.6, 0.9, 0.3), (-0.5, -1.35, 0.2)):
        _clump(mb, c, 0.45, "fo_shrub", rng, flat=0.6)
    mb.clamp_floor()
    mb.finish("forest_boulder_b")


def build_forest_log():
    """Fallen pine log (~5.5 m along X) with moss, a stump of roots and sawn-looking ends."""
    mb = MeshBuilder()
    rng = _rng(341)
    a = Vector((-2.7, 0.1, 0.32))
    b = Vector((2.6, -0.1, 0.26))
    mb.cyl_between(a, b, 0.36, 0.28, "fo_log", segs=8)
    mb.cyl_between(b - Vector((0.02, 0, 0)), b + Vector((0.02, 0, 0)), 0.27, 0.27, "fo_log_end", segs=8)
    # moss strip on top
    for k in range(5):
        t = 0.1 + k * 0.18
        p = a.lerp(b, t) + Vector((0, 0, 0.26))
        mb.ico(p, 0.42, "fo_moss" if k % 2 else "fo_moss_light", subdiv=0, scale=(1.5, 0.75, 0.35), rng=rng, jitter=0.03)
    # root plate at the start
    for k in range(7):
        ang = 2 * math.pi * k / 7
        tip = a + Vector((-0.3, math.cos(ang) * 0.9, 0.32 + math.sin(ang) * 0.75))
        tip.z = max(tip.z, 0.05)
        mb.cyl_between(a, tip, 0.14, 0.04, "fo_bark_grey", segs=4)
    mb.ico(a + Vector((-0.2, 0, 0.1)), 0.55, "fo_ash", subdiv=0, scale=(0.4, 1.0, 0.9))
    for k in range(3):
        p = a.lerp(b, 0.3 + k * 0.2) + Vector((0, 0.3, -0.05))
        mb.cyl_between(p, p + Vector((rng.uniform(-0.3, 0.3), 0.7, 0.2)), 0.06, 0.02, "fo_log", segs=4)
    mb.clamp_floor()
    mb.finish("forest_log")


def build_forest_stump():
    """Old stump with moss and a fly-agaric."""
    mb = MeshBuilder()
    rng = _rng(347)
    mb.lathe([(0.0, 0.0), (0.55, 0.0), (0.42, 0.15), (0.36, 0.55), (0.0, 0.55)], "fo_bark_grey", segs=8, cap_bottom=False)
    mb.cyl((0, 0, 0.56), 0.33, 0.33, 0.03, "fo_log_end", segs=8)
    for k in range(4):
        ang = 2 * math.pi * k / 4 + 0.4
        mb.cyl_between((0, 0, 0.2), (math.cos(ang) * 0.8, math.sin(ang) * 0.8, 0.0), 0.12, 0.05, "fo_bark_grey", segs=4)
    mb.ico((0.2, -0.28, 0.35), 0.3, "fo_moss", subdiv=0, scale=(1.1, 0.7, 0.8), rng=rng, jitter=0.03)
    _mushroom(mb, (0.62, -0.35, 0.0), 0.32, rng)
    mb.clamp_floor()
    mb.finish("forest_stump")


def _mushroom(mb, base, h, rng):
    x, y, z = base
    mb.cyl((x, y, z + h * 0.45), h * 0.12, h * 0.09, h * 0.9, "fo_mush_stem", segs=6)
    cap = mb.lathe([(0.0, h * 0.78), (h * 0.42, h * 0.8), (h * 0.36, h * 1.02), (0.0, h * 1.12)], "fo_mush_red",
                   segs=8, center=(x, y, z))
    for k in range(4):
        a = rng.uniform(0, 6.28)
        rr = rng.uniform(0.1, 0.3) * h
        mb.ico((x + math.cos(a) * rr, y + math.sin(a) * rr, z + h * 1.06), h * 0.06, "fo_mush_dot", subdiv=0)
    return cap


def build_forest_mushrooms():
    """A ring of fly agarics."""
    mb = MeshBuilder()
    rng = _rng(349)
    for k, (x, y, h) in enumerate([(0.0, 0.0, 0.34), (0.35, 0.15, 0.24), (-0.28, 0.22, 0.2), (0.12, -0.3, 0.28), (-0.35, -0.2, 0.15)]):
        _mushroom(mb, (x, y, 0.0), h, rng)
    mb.clamp_floor()
    mb.finish("forest_mushrooms")


def build_forest_shrub():
    """Blueberry / lingonberry tussock (~1.4 m wide)."""
    mb = MeshBuilder()
    rng = _rng(353)
    mats = ["fo_shrub", "fo_shrub_light", "fo_shrub_dark", "fo_shrub"]
    for k in range(6):
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.2, 0.5)
        _clump(mb, (math.cos(a) * r, math.sin(a) * r, 0.18), rng.uniform(0.32, 0.45), mats[k % 4], rng, flat=0.6)
    _clump(mb, (0, 0, 0.28), 0.4, "fo_shrub_light", rng, flat=0.7)
    for k in range(8):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.25, 0.6)
        mb.ico((math.cos(a) * r, math.sin(a) * r, rng.uniform(0.25, 0.42)), 0.045,
               "fo_berry_blue" if k % 3 else "fo_berry_red", subdiv=0)
    mb.clamp_floor()
    mb.finish("forest_shrub")


def build_forest_fern():
    """Bracken / fern clump (~1.6 m)."""
    mb = MeshBuilder()
    rng = _rng(359)
    for k in range(8):
        a = 2 * math.pi * k / 8 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        base = Vector((0, 0, 0.05))
        mid = d * 0.45 + Vector((0, 0, 0.55))
        tip = d * 0.85 + Vector((0, 0, 0.3))
        m = "fo_fern" if k % 2 else "fo_fern_dark"
        for p0, p1, w in ((base, mid, 0.26), (mid, tip, 0.2)):
            axis = (p1 - p0)
            ln = axis.length
            u = axis.normalized()
            n = u.cross(side).normalized()
            mb.obox((p0 + p1) / 2, (u, side, n), (ln, w, 0.03), m)
    mb.clamp_floor()
    mb.finish("forest_fern")


def build_forest_flowers():
    """Patch of white wood anemones (flat, ~1.6 m)."""
    mb = MeshBuilder()
    rng = _rng(367)
    for k in range(14):
        a = rng.uniform(0, 6.28)
        r = math.sqrt(rng.uniform(0, 1)) * 0.8
        x, y = math.cos(a) * r, math.sin(a) * r
        h = rng.uniform(0.12, 0.22)
        mb.ico((x, y, h * 0.5), 0.07, "fo_stem", subdiv=0, scale=(1.2, 1.2, h * 5))
        mb.ico((x, y, h), 0.08, "fo_flower", subdiv=0, scale=(1.0, 1.0, 0.3), rot=(0, 0, a))
        mb.ico((x, y, h + 0.02), 0.025, "fo_flower_core", subdiv=0)
    mb.clamp_floor()
    mb.finish("forest_flowers")


# ----------------------------------------------------------------------------------- village

def _barge_boards(mb, x_end, half_span, z_eave, z_ridge, out=1.1, mat="fo_wood_dark", carved=True):
    """Crossed gable finials: a board along each roof slope at x = x_end, running past the apex."""
    W = half_span
    H = z_ridge - z_eave
    for s in (-1, 1):
        a = Vector((x_end, s * W, z_eave))
        b = Vector((x_end, 0.0, z_ridge))
        d = (b - a).normalized()
        c = b + d * out
        start = a - d * 0.1
        mid = (start + c) / 2
        ln = (c - start).length
        n = X
        side = n.cross(d)
        if side.z < 0:
            side = -side
        mb.obox(mid + side * 0.14, (d, side, n), (ln, 0.26, 0.14), mat)
        if carved:
            # curled "dragon" tip
            tip = c + d * 0.1
            mb.cyl_between(c, tip + Vector((0, -s * 0.35, 0.18)), 0.1, 0.05, mat, segs=5)


def _plank_wall(mb, face_origin, u, length, z0, z1, n, mats, depth=0.06, step=0.42):
    """Vertical planks on a wall face (u = along the wall, n = outward normal)."""
    k = 0
    x = -length / 2 + step / 2
    while x < length / 2:
        c = face_origin + u * x + Z * ((z0 + z1) / 2) + n * (depth / 2)
        mb.obox(c, (u, Z, n), (step - 0.04, z1 - z0, depth), mats[k % len(mats)])
        x += step
        k += 1


def _longhouse(mb, name, L_, W_, roof, rng, turf=False):
    """Viking longhouse along X: stone footing, dark plank walls, steep thatch (or turf) roof with
    low eaves, crossed gable boards, a door on the front long side and a smoke hole."""
    base = 0.35
    wall_top = 2.3
    mb.box((0, 0, base / 2), (L_ + 0.5, W_ + 0.5, base), "fo_stone_dark", bevel=0.05)
    for k in range(int((L_ + 0.4) / 0.7)):
        x = -L_ / 2 - 0.1 + k * 0.7 + 0.35
        for s in (-1, 1):
            mb.ico((x, s * (W_ / 2 + 0.27), 0.2), 0.3, rng.choice(["fo_stone", "fo_stone_light", "fo_stone_dark"]), subdiv=0,
                   scale=(1.0, 0.6, 0.65), rot=(0, 0, rng.uniform(-0.3, 0.3)))
    mb.box((0, 0, (base + wall_top) / 2), (L_, W_, wall_top - base), "fo_wood_dark")
    for s in (-1, 1):
        _plank_wall(mb, Vector((0, s * W_ / 2, 0)), X, L_, base, wall_top, Vector((0, s, 0)), ["fo_wood", "fo_wood_dark", "fo_wood_grey"])
    z_eave = 1.75
    half = W_ / 2 + 1.1
    z_ridge = 6.2 if not turf else 5.2
    thick = 0.4
    # roof
    Wd = half
    poly = [(-Wd, z_eave - thick), (0.0, z_ridge - thick), (Wd, z_eave - thick), (Wd, z_eave), (0.0, z_ridge), (-Wd, z_eave)]
    length = L_ + 1.0
    mb.prism(poly, 0.0, length, roof[0], frame=(Vector((-length / 2, 0, 0)), Y, Z, X))
    # layered courses
    theta = math.atan2(z_ridge - z_eave, Wd)
    rows = 5
    slope = math.hypot(Wd, z_ridge - z_eave)
    for side in (-1, 1):
        roof_n = Vector((0.0, side * math.sin(theta), math.cos(theta)))
        down = Vector((0.0, side * math.cos(theta), -math.sin(theta)))
        for r in range(rows):
            t = (r + 0.5) / rows
            p = Vector((0.0, side * Wd * (1 - t), z_eave + (z_ridge - z_eave) * t)) + roof_n * 0.08
            seg = slope / rows * 1.15
            A = X
            B = -down
            C = A.cross(B)
            if C.dot(roof_n) < 0:
                C = -C
            mb.obox(p + down * 0.05 + roof_n * 0.04 * (rows - r), (A, B, C), (length + 0.08 - 0.12 * r, seg, 0.18), roof[r % len(roof)])
    # ridge roll
    mb.cyl_between((-length / 2 - 0.05, 0, z_ridge - 0.05), (length / 2 + 0.05, 0, z_ridge - 0.05), 0.28, 0.28,
                   roof[-1], segs=6)
    if not turf:
        # moss and grass growing on the old thatch
        for k in range(7):
            x = rng.uniform(-length / 2 + 0.8, length / 2 - 0.8)
            s2 = rng.choice((-1, 1))
            t = rng.uniform(0.15, 0.7)
            p = Vector((x, s2 * Wd * (1 - t), z_eave + (z_ridge - z_eave) * t + 0.3))
            _clump(mb, p, rng.uniform(0.4, 0.7), rng.choice(["fo_moss", "fo_moss_dark", "fo_turf_b"]), rng, flat=0.35)
    if turf:
        for k in range(18):
            x = rng.uniform(-length / 2 + 0.5, length / 2 - 0.5)
            s = rng.choice((-1, 1))
            t = rng.uniform(0.2, 0.8)
            p = Vector((x, s * Wd * (1 - t), z_eave + (z_ridge - z_eave) * t + 0.22))
            _clump(mb, p, rng.uniform(0.35, 0.55), rng.choice(["fo_turf", "fo_turf_b", "fo_moss_light"]), rng, flat=0.45)
    # gable walls (triangles above the wall, set in from the roof ends)
    inner = lambda y: z_ridge - thick - (z_ridge - z_eave) * abs(y) / Wd
    for s in (-1, 1):
        x = s * L_ / 2
        tri = [(-W_ / 2, wall_top - 0.01), (W_ / 2, wall_top - 0.01), (0.0, inner(0) + 0.02)]
        mb.prism(tri, -0.05, 0.05, "fo_wood", frame=(Vector((x, 0, 0)), Y, Z, X))
        for k in range(-3, 4):
            y = k * W_ / 8
            h0 = wall_top
            h1 = inner(y) - 0.05
            if h1 > h0 + 0.1:
                mb.box((x + s * 0.07, y, (h0 + h1) / 2), (0.05, 0.18, h1 - h0), "fo_wood_dark")
        _barge_boards(mb, s * (length / 2 + 0.05), Wd, z_eave, z_ridge, out=1.0)
    # door on the front (-Y) side with a small porch roof
    fy = -W_ / 2
    mb.box((0.4, fy - 0.03, base + 0.85), (1.0, 0.12, 1.7), "fo_wood_dark")
    for dx in (-0.12, 0.2, 0.52, 0.84):
        mb.box((dx + 0.03, fy - 0.1, base + 0.85), (0.24, 0.04, 1.6), "fo_wood")
    mb.box((0.4, fy - 0.12, base + 1.78), (1.4, 0.16, 0.14), "fo_wood_light")
    for dx in (-0.25, 1.05):
        mb.box((dx, fy - 0.12, base + 0.9), (0.14, 0.16, 1.8), "fo_wood_light")
    # smoke hole on the ridge
    mb.box((-L_ * 0.2, 0, z_ridge + 0.15), (0.9, 0.9, 0.35), "fo_wood_dark")
    mb.box((-L_ * 0.2, 0, z_ridge + 0.36), (1.1, 1.1, 0.08), roof[-1])
    # shields / tools on the front wall
    for k, m in enumerate(["fo_shield_red", "fo_shield_blue", "fo_shield_yellow"]):
        x = -L_ / 2 + 1.2 + k * 0.9
        if abs(x - 0.4) < 1.0:
            continue
        mb.cyl((x, fy - 0.1, 1.5), 0.36, 0.36, 0.06, m, segs=10, rot=(math.pi / 2, 0, 0))
        mb.cyl((x, fy - 0.15, 1.5), 0.09, 0.09, 0.06, "fo_iron", segs=6, rot=(math.pi / 2, 0, 0))


def build_forest_longhouse():
    """Big viking longhouse (~13 x 8.5 m incl. eaves): thatch roof, crossed gable boards."""
    mb = MeshBuilder()
    rng = _rng(401)
    _longhouse(mb, "forest_longhouse", 12.0, 5.8, ["fo_thatch", "fo_thatch_b", "fo_thatch", "fo_thatch_b", "fo_thatch_dark"], rng)
    # woodpile at the side
    for k in range(5):
        for j in range(2):
            y = -1.0 + k * 0.4
            mb.cyl_between((6.5, y, 0.15 + j * 0.28), (7.2, y, 0.15 + j * 0.28), 0.13, 0.13, "fo_log" if (k + j) % 2 else "fo_log_end", segs=6)
    mb.clamp_floor()
    mb.finish("forest_longhouse")


def build_forest_turfhouse():
    """Smaller house (~8 x 5 m) with a grass-covered turf roof."""
    mb = MeshBuilder()
    rng = _rng(409)
    _longhouse(mb, "forest_turfhouse", 7.0, 4.4, ["fo_turf", "fo_turf_b", "fo_turf", "fo_turf_b", "fo_turf_dark"], rng, turf=True)
    mb.clamp_floor()
    mb.finish("forest_turfhouse")


def build_forest_hut():
    """Tiny storage hut on stones with a steep thatch roof (~3.5 x 3 m)."""
    mb = MeshBuilder()
    rng = _rng(419)
    for sx in (-1, 1):
        for sy in (-1, 1):
            _hull(mb, L.rock_points((sx * 1.3, sy * 1.0, 0.18), (0.25, 0.25, 0.2), rng, n=8), "fo_stone")
    mb.box((0, 0, 1.2), (2.8, 2.2, 1.7), "fo_wood_dark")
    _plank_wall(mb, Vector((0, -1.1, 0)), X, 2.8, 0.35, 2.05, Vector((0, -1, 0)), ["fo_wood", "fo_wood_grey"])
    Wd = 1.9
    zr, ze, th = 4.3, 1.5, 0.3
    poly = [(-Wd, ze - th), (0.0, zr - th), (Wd, ze - th), (Wd, ze), (0.0, zr), (-Wd, ze)]
    mb.prism(poly, 0.0, 3.5, "fo_thatch", frame=(Vector((-1.75, 0, 0)), Y, Z, X))
    theta = math.atan2(zr - ze, Wd)
    slope = math.hypot(Wd, zr - ze)
    mats = ["fo_thatch_b", "fo_thatch", "fo_thatch_b"]
    for side in (-1, 1):
        roof_n = Vector((0.0, side * math.sin(theta), math.cos(theta)))
        down = Vector((0.0, side * math.cos(theta), -math.sin(theta)))
        for r in range(3):
            t = (r + 0.5) / 3
            p = Vector((0.0, side * Wd * (1 - t), ze + (zr - ze) * t)) + roof_n * (0.06 + 0.04 * (3 - r))
            B = -down
            C = X.cross(B)
            if C.dot(roof_n) < 0:
                C = -C
            mb.obox(p, (X, B, C), (3.55 - 0.1 * r, slope / 3 * 1.15, 0.16), mats[r])
    _clump(mb, (0.6, -0.9, 3.1), 0.45, "fo_moss", rng, flat=0.35)
    mb.cyl_between((-1.8, 0, zr - 0.04), (1.8, 0, zr - 0.04), 0.2, 0.2, "fo_thatch_dark", segs=6)
    inner = lambda y: zr - th - (zr - ze) * abs(y) / Wd
    for s in (-1, 1):
        x = s * 1.4
        mb.prism([(-1.1, 2.04), (1.1, 2.04), (0.0, inner(0))], x - 0.05, x + 0.05, "fo_wood",
                 frame=(Vector((0, 0, 0)), Y, Z, X))
        _barge_boards(mb, s * 1.8, Wd, ze, zr, out=0.7)
    mb.box((0.0, -1.14, 1.0), (0.8, 0.08, 1.3), "fo_wood_light")
    mb.clamp_floor()
    mb.finish("forest_hut")


def build_forest_longship():
    """Viking longship (~13 m along X) with curled dragon prow, shields, mast and furled sail."""
    mb = MeshBuilder()
    rng = _rng(431)
    Lh = 6.2

    def section(x):
        t = x / Lh
        w = 1.35 * (1 - t ** 4) ** 0.6 + 0.08
        rise = 0.9 * t ** 6
        keel = -0.55 + rise * 0.8
        g = 0.55 + rise
        deck = g - 0.45
        pts = []
        # outer: left gunwale -> keel -> right gunwale, then inner back
        for k in range(5):
            a = math.pi * (k / 4)
            y = -math.cos(a) * w
            z = keel + (g - keel) * (1 - math.sin(a)) ** 1.2 if k not in (0, 4) else g
            if k == 2:
                z = keel
            pts.append(Vector((x, y, z)))
        pts.append(Vector((x, w - 0.1, g)))
        pts.append(Vector((x, w * 0.8, deck)))
        pts.append(Vector((x, -w * 0.8, deck)))
        pts.append(Vector((x, -w + 0.1, g)))
        return pts
    xs = [-Lh * 0.985, -Lh * 0.9, -Lh * 0.72, -Lh * 0.45, -Lh * 0.15, Lh * 0.15, Lh * 0.45, Lh * 0.72, Lh * 0.9, Lh * 0.985]
    secs = [section(x) for x in xs]
    # sections must run CCW seen from -X: the builder recalculates normals anyway
    _loft(mb, secs, "fo_wood")
    # strakes (dark lines along the hull)
    for zoff in (0.12, -0.18):
        for s in (-1, 1):
            pts = []
            for x in xs[1:-1]:
                sec = section(x)
                p = sec[0] if s < 0 else sec[4]
                pts.append(Vector((x, p.y * 1.01, p.z + zoff)))
            for a, b in zip(pts[:-1], pts[1:]):
                mb.cyl_between(a, b, 0.05, 0.05, "fo_wood_dark", segs=4)
    # stems: curled prow (dragon neck) and stern
    for s in (-1, 1):
        base = Vector((s * Lh * 0.98, 0, 1.45))
        prev = base
        for k in range(6):
            a = k / 5.0
            p = Vector((s * (Lh + 0.35 * math.sin(a * 2.2)), 0, 1.45 + 1.4 * a))
            if k > 0:
                mb.cyl_between(prev, p, 0.16 - 0.015 * k, 0.15 - 0.015 * k, "fo_wood_dark", segs=5)
            prev = p
        if s > 0:
            head = prev + Vector((0.25, 0, 0.1))
            mb.box(head, (0.6, 0.22, 0.3), "fo_wood_dark", rot=(0, -0.3, 0))
            mb.ico(head + Vector((0.2, 0.12, 0.1)), 0.05, "fo_rune_paint", subdiv=0)
            mb.ico(head + Vector((0.2, -0.12, 0.1)), 0.05, "fo_rune_paint", subdiv=0)
        else:
            mb.cyl_between(prev, prev + Vector((0.3, 0, 0.35)), 0.08, 0.04, "fo_wood_dark", segs=5)
    # shields along both gunwales
    mats = ["fo_shield_red", "fo_shield_yellow", "fo_shield_blue", "fo_sail_white"]
    k = 0
    for x in [i * 0.78 - 3.9 for i in range(11)]:
        sec = section(x)
        for s in (-1, 1):
            p = sec[0] if s < 0 else sec[4]
            c = Vector((x, p.y + s * 0.05, p.z - 0.05))
            mb.cyl(c, 0.32, 0.32, 0.05, mats[k % 4], segs=8, rot=(math.pi / 2, 0, 0))
            mb.cyl(c + Vector((0, s * 0.04, 0)), 0.08, 0.08, 0.05, "fo_iron", segs=5, rot=(math.pi / 2, 0, 0))
            k += 1
    # mast, yard and furled striped sail
    mb.cyl((0.2, 0, 3.1), 0.12, 0.09, 5.8, "fo_wood_dark", segs=6)
    mb.cyl_between((0.2, -2.3, 5.2), (0.2, 2.3, 5.2), 0.08, 0.08, "fo_wood_dark", segs=5)
    for k in range(6):
        y0 = -2.1 + k * 0.7
        mb.cyl_between((0.2, y0, 4.98), (0.2, y0 + 0.7, 4.98), 0.2, 0.2, "fo_sail_red" if k % 2 == 0 else "fo_sail_white", segs=6)
    for s in (-1, 1):
        mb.cyl_between((0.2, 0, 5.9), (s * 5.8, 0, 1.2), 0.02, 0.02, "fo_wood_grey", segs=3)
    # oars stowed + cargo
    for k in range(3):
        mb.box((-2.5 + k * 1.1, 0.0, 0.3), (0.7, 0.6, 0.5), "fo_hide", bevel=0.03)
    mb.finish("forest_longship")


def build_forest_jetty():
    """Wooden jetty section (~10 m along -Y from the shore, 2.4 m wide), deck at z = 0.15."""
    mb = MeshBuilder()
    rng = _rng(439)
    y0, y1 = 0.6, -9.6
    n = int((y0 - y1) / 0.36)
    for k in range(n):
        y = y0 - 0.18 - k * 0.36
        mb.box((rng.uniform(-0.04, 0.04), y, 0.12), (2.4 + rng.uniform(-0.1, 0.1), 0.32, 0.08),
               rng.choice(["fo_wood_grey", "fo_wood", "fo_wood_light"]))
    for s in (-1, 1):
        mb.box((s * 1.05, (y0 + y1) / 2, 0.02), (0.18, y0 - y1, 0.14), "fo_wood_dark")
        for k in range(5):
            y = y0 - 0.4 - k * 2.4
            mb.cyl((s * 1.2, y, -0.4), 0.13, 0.13, 1.6, "fo_wood_dark", segs=6)
            mb.cyl((s * 1.2, y, 0.42), 0.14, 0.1, 0.1, "fo_wood_dark", segs=6)
    # mooring post, rope, barrel and a crate at the end
    mb.cyl((0.9, y1 + 0.5, 0.6), 0.12, 0.12, 0.9, "fo_wood_dark", segs=6)
    mb.cyl((0.9, y1 + 0.5, 0.6), 0.15, 0.15, 0.12, "rope", segs=6)
    mb.lathe([(0.0, 0.0), (0.24, 0.0), (0.28, 0.35), (0.24, 0.7), (0.0, 0.7)], "fo_wood", segs=8, center=(-0.7, y1 + 1.2, 0.16))
    mb.box((-0.6, y1 + 2.1, 0.42), (0.55, 0.55, 0.5), "fo_wood_light", bevel=0.02)
    mb.finish("forest_jetty")


def build_forest_fence():
    """Wattle fence, 2 m segment along X (posts at x = +-1), ~1.05 m tall."""
    mb = MeshBuilder()
    rng = _rng(443)
    for x in (-1.0, 0.0, 1.0):
        mb.cyl((x, 0, 0.55), 0.06, 0.05, 1.1, "fo_wood_dark", segs=5)
    for k in range(6):
        z = 0.2 + k * 0.14
        pts = []
        for i in range(5):
            x = -1.0 + i * 0.5
            y = 0.05 * (1 if (i + k) % 2 else -1)
            pts.append(Vector((x, y, z + rng.uniform(-0.02, 0.02))))
        for a, b in zip(pts[:-1], pts[1:]):
            mb.cyl_between(a, b, 0.045, 0.045, "fo_wattle", segs=4)
    mb.clamp_floor()
    mb.finish("forest_fence")


def build_forest_runestone():
    """Rune stone waystone (~2.8 m): granite slab with a red-painted serpent band of glowing runes."""
    mb = MeshBuilder()
    rng = _rng(449)
    # slab: tapered, rounded top
    prof = [(-0.75, 0.0), (0.75, 0.0), (0.68, 1.9), (0.5, 2.5), (0.2, 2.78), (-0.2, 2.8), (-0.52, 2.55), (-0.7, 1.95)]
    verts = mb.prism(prof, -0.24, 0.24, "fo_granite", frame=(Vector((0, 0, 0)), X, Z, -Y))
    _jitter(verts, rng, 0.03, zmin=0.0)
    # serpent band: arch of segments on the front face (-Y), with glowing runes
    band = []
    for k in range(13):
        a = math.pi * k / 12
        band.append(Vector((0.52 * math.cos(a), -0.27, 1.25 + 1.05 * math.sin(a) * (1.0 if k else 1.0))))
    band.insert(0, Vector((0.52, -0.27, 0.35)))
    band.append(Vector((-0.52, -0.27, 0.35)))
    for a, b in zip(band[:-1], band[1:]):
        mb.cyl_between(a, b, 0.09, 0.09, "fo_rune_paint", segs=5)
    for k, p in enumerate(band[1:-1]):
        if k % 2 == 0:
            mb.box(p + Vector((0, -0.08, 0)), (0.08, 0.04, 0.14), "fo_rune_glow")
    mb.box((0, -0.27, 1.3), (0.1, 0.04, 0.5), "fo_rune_glow")
    mb.box((0, -0.27, 1.3), (0.34, 0.04, 0.08), "fo_rune_glow")
    mb.ico((-0.52, -0.3, 0.35), 0.13, "fo_rune_paint", subdiv=0)
    # base stones + moss
    for k in range(7):
        a = 2 * math.pi * k / 7
        _hull(mb, L.rock_points((math.cos(a) * 1.0, math.sin(a) * 0.75, 0.12), (0.3, 0.25, 0.16), rng, n=8),
                rng.choice(["fo_stone", "fo_stone_dark", "fo_granite_light"]))
    mb.ico((0.45, 0.2, 0.1), 0.35, "fo_moss", subdiv=0, scale=(1, 0.8, 0.4))
    mb.clamp_floor()
    mb.finish("forest_runestone")


def build_forest_firepit():
    """Stone ring fire pit with crossed logs and flames (~1.8 m)."""
    mb = MeshBuilder()
    rng = _rng(457)
    for k in range(10):
        a = 2 * math.pi * k / 10
        _hull(mb, L.rock_points((math.cos(a) * 0.8, math.sin(a) * 0.8, 0.14), (0.2, 0.17, 0.16), rng, n=8),
                rng.choice(["fo_stone", "fo_stone_dark", "fo_stone_light"]))
    mb.cyl((0, 0, 0.03), 0.65, 0.65, 0.06, "fo_ash", segs=10)
    for k in range(4):
        a = math.pi * k / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        mb.cyl_between(-d * 0.55 + Vector((0, 0, 0.12)), d * 0.25 + Vector((0, 0, 0.45)), 0.08, 0.06, "fo_log", segs=5)
    mb.ico((0, 0, 0.15), 0.35, "fo_ember", subdiv=0, scale=(1, 1, 0.4))
    for k in range(5):
        a = 2 * math.pi * k / 5
        r = 0.22
        h = rng.uniform(0.55, 0.85)
        mb.cyl((math.cos(a) * r, math.sin(a) * r, 0.25 + h / 2), 0.13, 0.0, h, "emit_fire", segs=4, rot=(0, 0, a))
    mb.cyl((0, 0, 0.7), 0.2, 0.0, 1.0, "emit_fire_core", segs=5)
    mb.clamp_floor()
    mb.finish("forest_firepit")


def build_forest_rack():
    """Drying rack (~3 m along X) with hanging fish and a hide."""
    mb = MeshBuilder()
    rng = _rng(461)
    for s in (-1, 1):
        x = s * 1.5
        mb.cyl_between((x, -0.5, 0.0), (x, 0.0, 1.9), 0.06, 0.05, "fo_wood_grey", segs=5)
        mb.cyl_between((x, 0.5, 0.0), (x, 0.0, 1.9), 0.06, 0.05, "fo_wood_grey", segs=5)
    mb.cyl_between((-1.7, 0, 1.85), (1.7, 0, 1.85), 0.05, 0.05, "fo_wood_grey", segs=5)
    for k in range(7):
        x = -1.2 + k * 0.3
        if 0.0 < x < 0.9:
            continue
        mb.cyl_between((x, 0, 1.82), (x, 0, 1.62), 0.01, 0.01, "rope", segs=3)
        mb.ico((x, 0, 1.28), 0.1, "fo_fish", subdiv=0, scale=(0.5, 1.0, 3.2))
        mb.cyl((x, 0, 0.92), 0.1, 0.0, 0.14, "fo_fish", segs=4, rot=(math.pi, 0, 0))
    mb.box((0.45, 0.0, 1.2), (0.85, 0.06, 1.2), "fo_hide", rot=(0, 0, 0))
    mb.box((0.45, -0.035, 1.2), (0.6, 0.02, 0.9), "fo_hide_dark")
    mb.clamp_floor()
    mb.finish("forest_rack")


def build_forest_stall():
    """Viking trader's stall: hide awning on poles, a plank table with furs, amber and pots. The
    merchant stands behind it at Blender (0, 0.6, 0) = Godot (0, 0, -0.6)."""
    mb = MeshBuilder()
    rng = _rng(467)
    cy = -0.45
    mb.box((0, cy, 0.75), (2.4, 0.8, 0.08), "fo_wood_light")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 1.05, cy + sy * 0.3, 0.37), (0.1, 0.1, 0.74), "fo_wood_dark")
    for sx in (-1, 1):
        mb.cyl_between((sx * 1.3, -0.05, 0), (sx * 1.3, -0.05, 2.5), 0.07, 0.06, "fo_wood_dark", segs=5)
        mb.cyl_between((sx * 1.3, 1.2, 0), (sx * 1.3, 1.2, 2.9), 0.07, 0.06, "fo_wood_dark", segs=5)
    ang = math.atan2(0.4, 1.25)
    mb.box((0, 0.58, 2.72), (2.9, 1.5, 0.05), "fo_hide", rot=(ang, 0, 0))
    mb.box((0, -0.12, 2.45), (2.9, 0.05, 0.3), "fo_hide_dark")
    # goods: fur pile, amber, pots, a sword
    mb.box((-0.7, cy, 0.84), (0.7, 0.55, 0.1), "fo_hide_dark", rot=(0, 0, 0.2))
    mb.box((-0.65, cy, 0.92), (0.6, 0.45, 0.08), "fo_hide", rot=(0, 0, -0.1))
    for k in range(5):
        mb.ico((0.1 + rng.uniform(-0.15, 0.15), cy + rng.uniform(-0.15, 0.15), 0.84), 0.06, "fo_amber", subdiv=0)
    for x, h in ((0.55, 0.3), (0.8, 0.22)):
        mb.lathe([(0.0, 0.0), (0.1, 0.0), (0.14, h * 0.45), (0.07, h * 0.9), (0.08, h), (0.0, h)], "fo_pot",
                 segs=7, center=(x, cy + 0.05, 0.79))
    mb.box((0.0, cy - 0.28, 0.83), (1.0, 0.07, 0.03), "fo_iron", rot=(0, 0, 0.1))
    # barrel + sack
    mb.lathe([(0.0, 0.0), (0.22, 0.0), (0.26, 0.35), (0.22, 0.7), (0.0, 0.7)], "fo_wood", segs=8, center=(1.65, -0.2, 0.0))
    mb.ico((-1.6, -0.2, 0.3), 0.3, "sack", subdiv=1, jitter=0.03, rng=rng)
    mb.clamp_floor()
    mb.finish("forest_stall")


def build_forest_boat():
    """Small rowing boat pulled up on the shore (~4 m along X)."""
    mb = MeshBuilder()
    Lh = 2.0

    def section(x):
        t = x / Lh
        w = 0.62 * (1 - t ** 4) ** 0.6 + 0.04
        g = 0.55 + 0.25 * t ** 4
        keel = 0.02 + 0.25 * t ** 6
        deck = g - 0.3
        return [Vector((x, -w, g)), Vector((x, -w * 0.7, keel + 0.12)), Vector((x, 0, keel)),
                Vector((x, w * 0.7, keel + 0.12)), Vector((x, w, g)), Vector((x, w - 0.06, g)),
                Vector((x, w * 0.55, deck)), Vector((x, -w * 0.55, deck)), Vector((x, -w + 0.06, g))]
    xs = [-Lh * 0.98, -Lh * 0.8, -Lh * 0.4, 0.0, Lh * 0.4, Lh * 0.8, Lh * 0.98]
    _loft(mb, [section(x) for x in xs], "fo_wood_light")
    for x in (-0.6, 0.5):
        mb.box((x, 0, 0.42), (0.18, 1.1, 0.05), "fo_wood")
    mb.cyl_between((-0.2, -0.3, 0.5), (1.8, 0.9, 0.2), 0.03, 0.03, "fo_wood", segs=4)
    mb.clamp_floor()
    mb.finish("forest_boat")


# ----------------------------------------------------------------------------------- the Mattis fort

def _stone_course(mb, rng, x0, x1, y, z, h, depth, mats):
    x = x0
    while x < x1 - 0.05:
        w = min(rng.uniform(0.5, 1.1), x1 - x)
        c = ((x + w / 2), y + rng.uniform(-0.04, 0.04), z + h / 2)
        mb.box(c, (w - 0.03, depth + rng.uniform(-0.05, 0.05), h - 0.02), rng.choice(mats),
               rot=(0, rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03)))
        x += w


def _fort_wall(mb, rng, length, height_fn, thick=1.5, moss=True):
    """Rough dry-stone wall along X centred at 0; height_fn(x) gives the (ruined) top."""
    mats = ["fo_stone", "fo_stone_dark", "fo_stone_light", "fo_granite"]
    steps = 8
    # stone courses across the whole length, clipped to the local top
    z = 0.0
    while z < 6.0:
        h = rng.uniform(0.55, 0.8)
        for s in (-1, 1):
            x = -length / 2
            while x < length / 2 - 0.1:
                w = min(rng.uniform(0.7, 1.35), length / 2 - x)
                top = height_fn(x + w / 2)
                zt = min(z + h, top)
                if zt - z > 0.18:
                    mb.box((x + w / 2, s * (thick / 2 + 0.02) + rng.uniform(-0.03, 0.03), (z + zt) / 2),
                           (w - 0.04, 0.14 + rng.uniform(-0.03, 0.03), zt - z - 0.03), rng.choice(mats),
                           rot=(0, rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03)))
                x += w
        z += h
    for k in range(steps):
        x0 = -length / 2 + k * length / steps
        x1 = x0 + length / steps
        top = height_fn((x0 + x1) / 2)
        # core
        mb.box(((x0 + x1) / 2, 0, top / 2), (x1 - x0 + 0.01, thick, top), "fo_stone_dark")
        if moss:
            # dark stone cap with moss cushions (a flat green slab reads badly from above)
            mb.box(((x0 + x1) / 2, 0, top + 0.04), (x1 - x0 - 0.02, thick + 0.06, 0.1), "fo_stone_dark")
            _clump(mb, ((x0 + x1) / 2 + rng.uniform(-0.15, 0.15), rng.uniform(-0.35, 0.35), top + 0.12), rng.uniform(0.3, 0.45),
                   rng.choice(["fo_moss", "fo_moss_dark", "fo_moss_light"]), rng, flat=0.4)
            if rng.random() < 0.5:
                _clump(mb, ((x0 + x1) / 2 + rng.uniform(-0.2, 0.2), rng.uniform(-0.3, 0.3), top + 0.2), rng.uniform(0.35, 0.55),
                       "fo_shrub", rng, flat=0.5)


def build_forest_fort_wall():
    """Mattis fort wall segment (4 m along X, ~1.5 m thick, ~4.5-5.5 m) with merlons and moss."""
    mb = MeshBuilder()
    rng = _rng(503)

    def h(x):
        return 4.6 + (0.8 if int((x + 2.0) / 0.5) % 2 == 0 else 0.0)
    _fort_wall(mb, rng, 4.0, h)
    mb.clamp_floor()
    mb.finish("forest_fort_wall")


def build_forest_fort_ruin():
    """Broken fort wall (4 m along X), jagged low top, fallen stones at its foot."""
    mb = MeshBuilder()
    rng = _rng(509)

    def h(x):
        return 1.3 + 2.4 * abs(math.sin(x * 0.9 + 0.7)) + 0.4 * math.sin(x * 3.1)
    _fort_wall(mb, rng, 4.0, h)
    for k in range(6):
        p = (rng.uniform(-1.8, 1.8), rng.choice((-1, 1)) * rng.uniform(1.0, 1.6), 0.2)
        _hull(mb, L.rock_points(p, (0.35, 0.3, 0.25), rng, n=8), rng.choice(["fo_stone", "fo_stone_dark", "fo_granite"]))
    mb.clamp_floor()
    mb.finish("forest_fort_ruin")


def build_forest_fort_tower():
    """Round fort tower (~5.4 m wide, ~9 m) of rough stone, broken crown, arrow slits, moss."""
    mb = MeshBuilder()
    rng = _rng(521)
    R = 2.7
    mats = ["fo_stone", "fo_stone_dark", "fo_stone_light", "fo_granite"]
    z = 0.0
    row = 0
    top_fn = lambda a: 8.2 + 1.0 * math.sin(a * 3 + 0.5) + (0.8 if int(a / (math.pi / 6)) % 2 == 0 else 0.0)
    mb.lathe([(0.0, 0.0), (R - 0.08, 0.0), (R - 0.18, 7.8), (0.0, 7.8)], "fo_stone_dark", segs=12, cap_bottom=False)
    while z < 8.0:
        h = rng.uniform(0.45, 0.65)
        n = 12
        for k in range(n):
            a0 = 2 * math.pi * k / n + (0.26 if row % 2 else 0.0)
            a1 = a0 + 2 * math.pi / n
            am = (a0 + a1) / 2
            if z + h > top_fn(am):
                continue
            r = R - 0.1 * (z / 8.0)
            c = Vector((math.cos(am) * r, math.sin(am) * r, z + h / 2))
            tang = Vector((-math.sin(am), math.cos(am), 0))
            nrm = Vector((math.cos(am), math.sin(am), 0))
            w = 2 * r * math.sin(math.pi / n) + 0.02
            mb.obox(c, (tang, Z, nrm), (w, h - 0.02, 0.3 + rng.uniform(-0.04, 0.04)), rng.choice(mats))
        z += h
        row += 1
    # arrow slits
    for a in (-math.pi / 2, -math.pi / 2 + 0.9, 0.6):
        for zz in (3.2, 5.8):
            c = Vector((math.cos(a) * (R + 0.08), math.sin(a) * (R + 0.08), zz))
            mb.obox(c, (Vector((-math.sin(a), math.cos(a), 0)), Z, Vector((math.cos(a), math.sin(a), 0))), (0.18, 0.9, 0.08), "window_dark")
    # moss crown and a small birch growing on top
    mb.cyl((0, 0, 7.85), R - 0.2, R - 0.2, 0.12, "fo_moss", segs=12)
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.3
        _clump(mb, (math.cos(a) * 2.0, math.sin(a) * 2.0, 8.3), rng.uniform(0.4, 0.6), "fo_shrub", rng, flat=0.5)
    mb.cyl_between((0.6, 0.4, 7.9), (0.9, 0.6, 10.2), 0.08, 0.04, "fo_birch_bark", segs=5)
    _clump(mb, (0.95, 0.65, 10.4), 0.8, "fo_birch_leaf", rng, flat=0.8, subdiv=1)
    mb.clamp_floor()
    mb.finish("forest_fort_tower")


def build_forest_fort_gate():
    """Fort gatehouse (8 m along X, ~7 m tall) with a round-arched opening 3.6 m wide."""
    mb = MeshBuilder()
    rng = _rng(541)
    mats = ["fo_stone", "fo_stone_dark", "fo_stone_light", "fo_granite"]
    thick = 2.0
    H = 6.2
    # two piers
    for s in (-1, 1):
        x0 = s * 1.8
        x1 = s * 4.0
        lo, hi = min(x0, x1), max(x0, x1)
        mb.box(((lo + hi) / 2, 0, H / 2), (hi - lo, thick, H), "fo_stone_dark")
        z = 0.0
        while z < H - 0.2:
            h = rng.uniform(0.42, 0.6)
            for sy in (-1, 1):
                _stone_course(mb, rng, lo, hi, sy * (thick / 2 + 0.02), z, min(h, H - z), 0.12, mats)
            z += h
    # arch over the opening (voussoirs) + wall above
    R = 1.8
    zc = 3.6
    for k in range(9):
        a0 = math.pi * k / 9
        a1 = math.pi * (k + 1) / 9
        am = (a0 + a1) / 2
        c = Vector((math.cos(am) * (R + 0.3), 0, zc + math.sin(am) * (R + 0.3)))
        tang = Vector((-math.sin(am), 0, math.cos(am)))
        rad = Vector((math.cos(am), 0, math.sin(am)))
        mb.obox(c, (tang, rad, Y), ((R + 0.3) * (a1 - a0) + 0.04, 0.6, thick + 0.1), rng.choice(mats))
    mb.box((0, 0, (zc + R + 0.6 + H) / 2 + 0.05), (3.6, thick, H - (zc + R + 0.6) + 0.1), "fo_stone_dark")
    for sy in (-1, 1):
        _stone_course(mb, rng, -1.8, 1.8, sy * (thick / 2 + 0.02), zc + R + 0.6, H - (zc + R + 0.6), 0.12, mats)
    # filler between arch and piers
    for s in (-1, 1):
        mb.box((s * 1.95, 0, zc + 1.2), (0.3, thick, 2.4), "fo_stone_dark")
    # merlons + moss
    for k in range(8):
        x = -3.75 + k * 1.07
        if k % 2 == 0:
            mb.box((x, 0, H + 0.4), (0.8, thick, 0.8), rng.choice(mats), bevel=0.03)
    mb.box((0, 0, H + 0.04), (8.0, thick + 0.08, 0.1), "fo_stone_dark")
    for k in range(6):
        _clump(mb, (-3.5 + k * 1.4 + rng.uniform(-0.2, 0.2), rng.uniform(-0.6, 0.6), H + 0.14), rng.uniform(0.3, 0.5),
               rng.choice(["fo_moss", "fo_moss_dark", "fo_moss_light"]), rng, flat=0.4)
    # iron-bound gate leaves thrown open
    for s in (-1, 1):
        mb.box((s * 1.55, -1.35, 1.6), (0.12, 1.5, 3.2), "fo_wood_dark", rot=(0, 0, s * 0.2))
    mb.clamp_floor()
    mb.finish("forest_fort_gate")


def build_forest_waterfall():
    """Granite step (~6 m along X, ~3.6 m tall) with a waterfall sheet into a foaming pool edge.
    The water falls towards the front (-Y)."""
    mb = MeshBuilder()
    rng = _rng(557)
    for (c, r, m) in [((-2.2, 0.6, 1.6), (1.4, 1.3, 1.9), "fo_granite"), ((2.1, 0.7, 1.4), (1.5, 1.2, 1.7), "fo_granite_dark"),
                      ((0.0, 1.3, 1.9), (1.5, 1.0, 2.0), "fo_granite"), ((-1.0, -0.1, 0.5), (0.8, 0.6, 0.6), "fo_granite_light"),
                      ((1.3, -0.2, 0.45), (0.7, 0.6, 0.55), "fo_granite")]:
        _mossy_rock(mb, rng, c, r, n=16, moss_level=0.78, stone=m)
    # the falling water: a curved sheet of boxes from the lip down to the pool
    lip = 3.4
    for k in range(6):
        t0 = k / 6
        t1 = (k + 1) / 6
        y0 = 0.35 - 0.9 * t0 ** 1.6
        y1 = 0.35 - 0.9 * t1 ** 1.6
        z0 = lip * (1 - t0)
        z1 = lip * (1 - t1)
        a = Vector((0, y0, z0))
        b = Vector((0, y1, z1))
        d = (b - a).normalized()
        n = X.cross(d)
        mb.obox((a + b) / 2, (X, d, n), (1.4 + 0.12 * k, (b - a).length + 0.05, 0.12), "fo_water_fall")
    for k in range(7):
        mb.ico((rng.uniform(-0.9, 0.9), -0.65 + rng.uniform(-0.25, 0.25), 0.1), rng.uniform(0.25, 0.4), "fo_foam", subdiv=0,
               scale=(1.2, 1.0, 0.45))
    mb.clamp_floor()
    mb.finish("forest_waterfall")



# ----------------------------------------------------------------------------------- borders & barrow

L.PALETTE.update({
    "fo_gard": dict(hex="#8e877d", rough=0.95),
    "fo_gard_dark": dict(hex="#6b645b", rough=0.95),
    "fo_gard_light": dict(hex="#a59e92", rough=0.95),
    "fo_withy": dict(hex="#4b3a29", rough=0.95),
    "fo_opening": dict(hex="#141210", rough=1.0),
})


def _gardsgard(model_id, seed, missing=()):
    """Swedish roundpole fence (gärdsgård), a 2 m run along X: pairs of upright posts every 1 m
    (x = -0.5, 0.5) bound with withies, and slanted grey poles resting on each other between them
    (every 0.5 m; they reach into the next run, so runs join seamlessly). ~1.3 m tall."""
    mb = MeshBuilder()
    rng = _rng(seed)
    for px in (-0.5, 0.5):
        for py in (-0.1, 0.1):
            lean = rng.uniform(-0.03, 0.03)
            mb.cyl_between((px, py, 0.0), (px + lean, py * 0.8, 1.38 + rng.uniform(-0.06, 0.06)), 0.05, 0.04,
                           "fo_gard_dark", segs=5)
        for z in (0.45, 1.0):
            mb.cyl((px, 0.0, z), 0.14, 0.14, 0.07, "fo_withy", segs=6)
    for k in range(4):
        if k in missing:
            continue
        xs = -1.2 + k * 0.5
        a = Vector((xs, rng.uniform(-0.03, 0.03), 0.08))
        b = Vector((xs + 2.25, rng.uniform(-0.03, 0.03), 1.12 + rng.uniform(-0.05, 0.05)))
        mb.cyl_between(a, b, 0.042, 0.036, ["fo_gard", "fo_gard_light", "fo_gard"][k % 3], segs=5)
    mb.finish(model_id)


def build_forest_gardsgard_a():
    """Roundpole fence run (gärdsgård)."""
    _gardsgard("forest_gardsgard_a", 1301)


def build_forest_gardsgard_b():
    """Roundpole fence run with a pole missing (weathered)."""
    _gardsgard("forest_gardsgard_b", 1302, missing=(2,))


def build_forest_barrow():
    """Barrow mound (~9 x 7 m, 3.2 m): a grassy, mossy hill with a stone-lined passage entrance
    on its front (-Y): two upright slabs, a lintel, a dark doorway and a few kerb stones."""
    mb = MeshBuilder()
    rng = _rng(1303)
    # the mound: a squashed, jittered dome
    verts = mb.ico((0, 0.6, 0.0), 1.0, "fo_mound", subdiv=2, scale=(4.6, 3.6, 3.2))
    for v in verts:
        if v.co.z < 0.0:
            v.co.z = 0.0
        else:
            v.co.x += rng.uniform(-0.12, 0.12)
            v.co.y += rng.uniform(-0.12, 0.12)
            v.co.z += rng.uniform(-0.1, 0.1)
    # grassy patches on the top
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.3, 2.4)
        c = Vector((math.cos(a) * r, 0.6 + math.sin(a) * r * 0.8, 0.0))
        c.z = 3.2 * max(0.0, 1.0 - (c.x / 4.6) ** 2 - ((c.y - 0.6) / 3.6) ** 2) ** 0.5 - 0.1
        mb.ico(c, 0.5, "fo_mound_light" if k % 2 else "fo_mound_b", subdiv=1, scale=(1.3, 1.1, 0.35))
    # entrance: two uprights, a lintel, a dark doorway, sill
    y0 = -2.75
    for s in (-1, 1):
        mb.box((s * 0.95, y0, 1.1), (0.55, 0.7, 2.2), "fo_granite", bevel=0.05)
    mb.box((0, y0 - 0.02, 2.35), (2.7, 0.85, 0.5), "fo_granite_dark", bevel=0.05)
    mb.box((0, y0 + 0.2, 1.05), (1.35, 0.6, 2.1), "fo_opening")
    mb.box((0, y0 - 0.25, 0.06), (1.4, 0.5, 0.12), "fo_granite_dark")
    # kerb stones around the foot
    for k in range(9):
        a = math.pi * (0.12 + 0.76 * k / 8.0)
        c = (math.cos(a) * 4.7, 0.6 + math.sin(a) * 3.7, 0.0)
        r = rng.uniform(0.28, 0.45)
        _hull(mb, L.rock_points(c, (r, r * 0.8, r * 0.7), rng, n=8), "fo_granite" if k % 2 else "fo_granite_light")
    mb.clamp_floor()
    mb.finish("forest_barrow")

BUILDERS = {
    "forest_pine_a": build_forest_pine_a,
    "forest_pine_b": build_forest_pine_b,
    "forest_spruce": build_forest_spruce,
    "forest_birch": build_forest_birch,
    "forest_boulder_a": build_forest_boulder_a,
    "forest_boulder_b": build_forest_boulder_b,
    "forest_log": build_forest_log,
    "forest_stump": build_forest_stump,
    "forest_mushrooms": build_forest_mushrooms,
    "forest_shrub": build_forest_shrub,
    "forest_fern": build_forest_fern,
    "forest_flowers": build_forest_flowers,
    "forest_longhouse": build_forest_longhouse,
    "forest_turfhouse": build_forest_turfhouse,
    "forest_hut": build_forest_hut,
    "forest_longship": build_forest_longship,
    "forest_jetty": build_forest_jetty,
    "forest_boat": build_forest_boat,
    "forest_fence": build_forest_fence,
    "forest_runestone": build_forest_runestone,
    "forest_firepit": build_forest_firepit,
    "forest_rack": build_forest_rack,
    "forest_stall": build_forest_stall,
    "forest_fort_wall": build_forest_fort_wall,
    "forest_fort_ruin": build_forest_fort_ruin,
    "forest_fort_tower": build_forest_fort_tower,
    "forest_fort_gate": build_forest_fort_gate,
    "forest_waterfall": build_forest_waterfall,
    "forest_gardsgard_a": build_forest_gardsgard_a,
    "forest_gardsgard_b": build_forest_gardsgard_b,
    "forest_barrow": build_forest_barrow,
}


# ----------------------------------------------------------------------------------- extra ground cover

def _blade(mb, base, height, lean_dir, width, mat):
    """One tapered blade (thin triangular prism)."""
    d = Vector(lean_dir)
    top = Vector(base) + d * (height * 0.35) + Vector((0, 0, height))
    side = Vector((-d.y, d.x, 0))
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side.normalize()
    b0 = Vector(base) - side * width * 0.5
    b1 = Vector(base) + side * width * 0.5
    b2 = Vector(base) + d * width * 0.5
    return _hull(mb, [b0, b1, b2, top], mat)


def build_forest_grass():
    """Grass tuft (~0.9 m wide, 0.55 m tall)."""
    mb = MeshBuilder()
    rng = _rng(601)
    mats = ["fo_grass", "fo_grass_light", "fo_grass", "fo_grass_dry"]
    for k in range(11):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.0, 0.3)
        base = (math.cos(a) * r, math.sin(a) * r, 0.0)
        la = a + rng.uniform(-0.5, 0.5)
        _blade(mb, base, rng.uniform(0.3, 0.6), (math.cos(la) * 0.9, math.sin(la) * 0.9, 0), 0.09, mats[k % 4])
    mb.clamp_floor()
    mb.finish("forest_grass")


def build_forest_reeds():
    """Reed clump for lake and pond shores (~1.4 m tall) with brown seed heads."""
    mb = MeshBuilder()
    rng = _rng(607)
    for k in range(14):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.0, 0.45)
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        h = rng.uniform(0.9, 1.5)
        la = a + rng.uniform(-0.4, 0.4)
        lean = Vector((math.cos(la), math.sin(la), 0)) * rng.uniform(0.05, 0.25)
        top = base + lean * (h * 0.35) + Vector((0, 0, h))
        mb.cyl_between(base, top, 0.045, 0.0, "fo_reed", segs=3)
        if k % 3 == 0:
            top = base + lean * (h * 0.35) + Vector((0, 0, h * 0.85))
            mb.ico(top, 0.05, "fo_reed_head", subdiv=0, scale=(1.0, 1.0, 2.4))
    mb.clamp_floor()
    mb.finish("forest_reeds")


def build_forest_woodpile():
    """Split firewood stacked against two posts (~2.2 m along X)."""
    mb = MeshBuilder()
    rng = _rng(613)
    for s in (-1, 1):
        mb.box((s * 1.05, 0, 0.6), (0.1, 0.1, 1.2), "fo_wood_dark")
    for row in range(4):
        for k in range(6):
            x = -0.85 + k * 0.34 + (0.17 if row % 2 else 0.0)
            if x > 0.95:
                continue
            z = 0.16 + row * 0.27
            mb.cyl_between((x, -0.35, z), (x, 0.35, z), 0.13, 0.13, "fo_log", segs=5)
            mb.cyl_between((x, -0.37, z), (x, -0.34, z), 0.12, 0.12, "fo_log_end", segs=5)
    mb.box((0, 0, 1.25), (2.4, 0.95, 0.06), "fo_wood_grey", rot=(0.15, 0, 0))
    mb.clamp_floor()
    mb.finish("forest_woodpile")


BUILDERS.update({
    "forest_grass": build_forest_grass,
    "forest_reeds": build_forest_reeds,
    "forest_woodpile": build_forest_woodpile,
})


# ----------------------------------------------------------------------------------- big open world (wilds zones)

L.PALETTE.update({
    "fo_rune_faded": dict(hex="#80503f", rough=0.95),
    "fo_heather": dict(hex="#4e5a2e", rough=1.0),
    "fo_heather_dark": dict(hex="#3c4424", rough=1.0),
    "fo_heather_flower": dict(hex="#b25a86", rough=0.9),
    "fo_heather_flower_b": dict(hex="#8e4a78", rough=0.9),
    "fo_juniper": dict(hex="#34503a", rough=0.95),
    "fo_juniper_dark": dict(hex="#26392b", rough=0.95),
    "fo_juniper_light": dict(hex="#48654a", rough=0.95),
    "fo_snag": dict(hex="#8d857a", rough=0.95),
    "fo_snag_dark": dict(hex="#615a51", rough=0.95),
    "fo_lily": dict(hex="#4d7a2c", rough=0.6),
    "fo_lily_dark": dict(hex="#3a6224", rough=0.6),
    "fo_bone": dict(hex="#d8d0bb", rough=0.8),
    "fo_mound": dict(hex="#55632f", rough=1.0),
    "fo_mound_b": dict(hex="#48562a", rough=1.0),
    "fo_mound_light": dict(hex="#6a7338", rough=1.0),
    "fo_grass_heath": dict(hex="#8c8a48", rough=0.95),
})


def _moved(mb, n0, offset, turn=0.0):
    """Turn (about Z) and move every vertex created since the builder had n0 vertices."""
    mb.bm.verts.ensure_lookup_table()
    c, s = math.cos(turn), math.sin(turn)
    off = Vector(offset)
    for i in range(n0, len(mb.bm.verts)):
        v = mb.bm.verts[i]
        x, y = v.co.x, v.co.y
        v.co = Vector((x * c - y * s, x * s + y * c, v.co.z)) + off


def _pine_at(mb, rng, base, height, mats, lean=(0.0, 0.0), crown_scale=1.0, turn=0.0):
    n0 = len(mb.bm.verts)
    _pine(mb, rng, height, mats, lean=lean, crown_scale=crown_scale)
    _moved(mb, n0, (base[0], base[1], 0.0), turn)


def _spruce_at(mb, rng, base, height, turn=0.0):
    """Norway spruce like forest_spruce, `height` tall, standing at base."""
    n0 = len(mb.bm.verts)
    k_h = height / 6.0
    mb.lathe([(0.0, 0.0), (0.24 * k_h, 0.0), (0.17 * k_h, 0.4), (0.09, 5.8 * k_h), (0.0, 6.0 * k_h)], "fo_bark_spruce",
             segs=6, cap_bottom=False)
    tiers = [(0.4, 1.9, 1.5), (1.3, 1.7, 1.4), (2.15, 1.48, 1.35), (2.95, 1.25, 1.3), (3.7, 1.0, 1.28),
             (4.4, 0.78, 1.25), (5.05, 0.55, 1.25), (5.7, 0.34, 1.4)]
    mats = ["fo_spruce", "fo_spruce_dark", "fo_spruce_light", "fo_spruce_dark"]
    for k, (z, r, h) in enumerate(tiers):
        verts = mb.lathe([(0.0, 0.0), (r * k_h, -0.25), (r * k_h * 0.8, 0.12), (0.0, h * k_h)], mats[k % len(mats)],
                         segs=7, center=(0, 0, z * k_h), phase=k * 0.9 + rng.uniform(0, 0.5))
        for vv in verts:
            if (vv.co.x ** 2 + vv.co.y ** 2) > 0.02:
                vv.co.x += rng.uniform(-0.12, 0.12)
                vv.co.y += rng.uniform(-0.12, 0.12)
                vv.co.z += rng.uniform(-0.12, 0.05)
    _moved(mb, n0, (base[0], base[1], 0.0), turn)


def _birch_at(mb, rng, base, scale=1.0, turn=0.0):
    """Silver birch like forest_birch (two white trunks, airy crown), scaled, at base."""
    n0 = len(mb.bm.verts)
    trunks = [((0.0, 0.0), (0.35, -0.2, 6.4), 0.16), ((0.15, 0.1), (-0.6, 0.4, 5.5), 0.12)]
    for (bx, by), top, r in trunks:
        a = Vector((bx, by, 0.0))
        b = Vector(top)
        mb.cyl_between(a, b, r, r * 0.45, "fo_birch_bark", segs=6)
        for k in range(4):
            t = rng.uniform(0.1, 0.75)
            p = a.lerp(b, t)
            rr = r * (1 - 0.55 * t) + 0.012
            ang = rng.uniform(0, 6.28)
            c = p + Vector((math.cos(ang) * rr * 0.75, math.sin(ang) * rr * 0.75, 0))
            mb.box(c, (0.12 * (1 - t * 0.5), 0.12 * (1 - t * 0.5), 0.08), "fo_birch_mark", rot=(0, 0, ang))
        mb.cyl_between(a, a + Vector((0, 0, 0.5)), r * 1.3, r * 1.05, "fo_birch_mark", segs=6)
        for k in range(3):
            t = rng.uniform(0.55, 0.92)
            p = a.lerp(b, t)
            ang = rng.uniform(0, 6.28)
            q = p + Vector((math.cos(ang) * 1.2, math.sin(ang) * 1.2, 0.6))
            mb.cyl_between(p, q, 0.05, 0.025, "fo_birch_bark", segs=4)
            _clump(mb, q, rng.uniform(0.7, 0.92), rng.choice(["fo_birch_leaf", "fo_birch_leaf_b", "fo_birch_leaf_c"]),
                   rng, flat=0.7, subdiv=1, jitter=0.05)
        _clump(mb, b + Vector((0, 0, 0.2)), 0.85, "fo_birch_leaf_b", rng, flat=0.8, subdiv=1, jitter=0.05)
    mb.bm.verts.ensure_lookup_table()
    for i in range(n0, len(mb.bm.verts)):
        mb.bm.verts[i].co *= scale
    _moved(mb, n0, (base[0], base[1], 0.0), turn)


def _scrub(mb, rng, center, r, n=4):
    """Blueberry scrub clumps on the forest floor."""
    mats = ["fo_shrub", "fo_shrub_light", "fo_shrub_dark"]
    for k in range(n):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0, r)
        _clump(mb, (center[0] + math.cos(a) * d, center[1] + math.sin(a) * d, 0.16), rng.uniform(0.35, 0.55),
               mats[k % 3], rng, flat=0.55)


def build_forest_stand_a():
    """A stand of Swedish pines (4 trees, 8-11 m, red upper trunks, high crowns) with blueberry
    scrub: one prop for the forest beyond the walkable ground (~9 m across)."""
    mb = MeshBuilder()
    rng = _rng(1401)
    crowns = [["fo_pine", "fo_pine_dark", "fo_pine_light"], ["fo_pine_dark", "fo_pine", "fo_pine_dark"]]
    for k, (x, y, h, lean, cs) in enumerate([(-1.9, -1.3, 10.6, (0.25, -0.1), 0.95), (2.1, -0.7, 9.0, (-0.1, 0.2), 0.9),
                                             (0.4, 2.3, 11.2, (0.05, 0.25), 1.0), (-2.7, 2.1, 8.2, (-0.25, 0.1), 0.85)]):
        _pine_at(mb, rng, (x, y), h, crowns[k % 2], lean=lean, crown_scale=cs, turn=rng.uniform(0, 6.28))
    _scrub(mb, rng, (0.2, 0.3), 3.0, n=5)
    mb.clamp_floor()
    mb.finish("forest_stand_a")


def build_forest_stand_b():
    """A mixed stand: two spruces, a birch and a pine (~9 m across)."""
    mb = MeshBuilder()
    rng = _rng(1403)
    _spruce_at(mb, rng, (-1.6, -0.9), 7.2, turn=0.4)
    _spruce_at(mb, rng, (1.9, 1.6), 5.6, turn=1.9)
    _birch_at(mb, rng, (2.2, -1.9), scale=1.05, turn=0.8)
    _pine_at(mb, rng, (-1.2, 2.6), 9.8, ["fo_pine", "fo_pine_dark", "fo_pine_light"], lean=(0.1, 0.2), crown_scale=0.95,
             turn=2.6)
    _scrub(mb, rng, (0.4, 0.2), 2.6, n=4)
    mb.clamp_floor()
    mb.finish("forest_stand_b")


def build_forest_stand_c():
    """A dark stand of Norway spruces (4 trees, 5-8 m) with a dead grey snag (~8 m across)."""
    mb = MeshBuilder()
    rng = _rng(1405)
    for (x, y, h, t) in [(-1.8, -1.1, 8.0, 0.3), (1.7, -1.5, 6.4, 1.1), (0.6, 1.9, 7.2, 2.0), (-2.4, 2.0, 5.2, 2.9)]:
        _spruce_at(mb, rng, (x, y), h, turn=t)
    n0 = len(mb.bm.verts)
    _snag(mb, rng, 5.4)
    _moved(mb, n0, (2.6, 1.2, 0.0), 0.7)
    mb.clamp_floor()
    mb.finish("forest_stand_c")


def _snag(mb, rng, height):
    """Dead standing pine: grey barkless trunk with a broken top and a few bare branches."""
    mb.lathe([(0.0, 0.0), (0.32, 0.0), (0.24, 0.4), (0.19, height * 0.6), (0.13, height * 0.92), (0.0, height)],
             "fo_snag", segs=7, cap_bottom=False, phase=rng.uniform(0, 1))
    # jagged broken top
    for k in range(3):
        a = 2 * math.pi * k / 3 + rng.uniform(-0.3, 0.3)
        mb.cyl_between((math.cos(a) * 0.05, math.sin(a) * 0.05, height * 0.9),
                       (math.cos(a) * 0.12, math.sin(a) * 0.12, height + rng.uniform(0.1, 0.5)), 0.08, 0.01, "fo_snag_dark", segs=4)
    for k in range(4):
        z = rng.uniform(0.35, 0.8) * height
        a = rng.uniform(0, 6.28)
        ln = rng.uniform(0.8, 1.6)
        p = Vector((0, 0, z))
        q = p + Vector((math.cos(a) * ln, math.sin(a) * ln, rng.uniform(0.2, 0.7)))
        mb.cyl_between(p, q, 0.07, 0.02, "fo_snag", segs=4)
        if rng.random() < 0.6:
            r2 = q + Vector((math.cos(a + 0.8) * 0.5, math.sin(a + 0.8) * 0.5, 0.35))
            mb.cyl_between(q, r2, 0.03, 0.01, "fo_snag_dark", segs=4)
    # peeling bark bands
    for z in (0.5, 1.4):
        mb.cyl((0, 0, z), 0.3, 0.27, 0.35, "fo_snag_dark", segs=7)


def build_forest_snag():
    """Dead standing pine (~6 m): a grey barkless trunk, broken top, bare branches."""
    mb = MeshBuilder()
    rng = _rng(1407)
    _snag(mb, rng, 6.2)
    mb.clamp_floor()
    mb.finish("forest_snag")


def build_forest_standing_stone():
    """Standing stone (bautasten, ~3.3 m): a tall rough granite slab with lichen spots and a
    mossy foot. Narrow side along Y."""
    mb = MeshBuilder()
    rng = _rng(1411)
    pts = []
    levels = 7
    for k in range(levels):
        t = k / (levels - 1)
        z = 3.3 * t
        w = 0.62 * (1.0 - 0.4 * t ** 1.6) + rng.uniform(-0.04, 0.04)
        d = 0.36 * (1.0 - 0.3 * t) + rng.uniform(-0.03, 0.03)
        for a in range(6):
            ang = 2 * math.pi * a / 6 + rng.uniform(-0.25, 0.25)
            pts.append((math.cos(ang) * w + 0.08 * t, math.sin(ang) * d, max(0.0, z + rng.uniform(-0.12, 0.12))))
    pts.append((0.1, 0.0, 3.45))
    _hull(mb, pts, "fo_granite")
    for k in range(6):
        t = rng.uniform(0.15, 0.8)
        z = 3.3 * t
        w = 0.62 * (1.0 - 0.4 * t ** 1.6)
        d = 0.36 * (1.0 - 0.3 * t)
        side = rng.choice((-1, 1))
        mb.ico((rng.uniform(-w * 0.6, w * 0.6) + 0.08 * t, side * (d - 0.02), z), rng.uniform(0.12, 0.22), "fo_lichen",
               subdiv=0, scale=(1.0, 0.35, 1.0))
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(-0.3, 0.3)
        _clump(mb, (math.cos(a) * 0.6, math.sin(a) * 0.4, 0.05), rng.uniform(0.25, 0.4),
               rng.choice(["fo_moss", "fo_moss_dark", "fo_shrub"]), rng, flat=0.5)
    mb.clamp_floor()
    mb.finish("forest_standing_stone")


def build_forest_runestone_old():
    """Weathered rune stone (~2.5 m): lichen-grey granite with a faded red serpent band (no glow),
    leaning a little, moss at its foot."""
    mb = MeshBuilder()
    rng = _rng(1413)
    prof = [(-0.66, 0.0), (0.7, 0.0), (0.6, 1.7), (0.42, 2.25), (0.14, 2.5), (-0.24, 2.46), (-0.5, 2.2), (-0.64, 1.6)]
    verts = mb.prism(prof, -0.22, 0.22, "fo_granite_light", frame=(Vector((0, 0, 0)), X, Z, -Y))
    _jitter(verts, rng, 0.04, zmin=0.0)
    band = []
    for k in range(11):
        a = math.pi * k / 10
        band.append(Vector((0.46 * math.cos(a), -0.25, 1.1 + 0.95 * math.sin(a))))
    band.insert(0, Vector((0.48, -0.25, 0.3)))
    band.append(Vector((-0.48, -0.25, 0.3)))
    for a, b in zip(band[:-1], band[1:]):
        mb.cyl_between(a, b, 0.08, 0.08, "fo_rune_faded", segs=5)
    for k, p in enumerate(band[2:-2]):
        if k % 2 == 0:
            mb.box(p + Vector((0, -0.06, 0)), (0.07, 0.04, 0.12), "fo_stone_dark")
    for k in range(5):
        mb.ico((rng.uniform(-0.45, 0.45), -0.22, rng.uniform(0.4, 2.0)), rng.uniform(0.1, 0.18), "fo_lichen",
               subdiv=0, scale=(1.0, 0.3, 1.0))
    for k in range(5):
        a = 2 * math.pi * k / 5
        _clump(mb, (math.cos(a) * 0.75, math.sin(a) * 0.4, 0.05), rng.uniform(0.25, 0.38),
               rng.choice(["fo_moss", "fo_moss_dark", "fo_grass"]), rng, flat=0.5)
    mb.transform([v for v in mb.bm.verts], Matrix.Rotation(0.06, 4, "Y"))
    mb.clamp_floor()
    mb.finish("forest_runestone_old")


def build_forest_cairn():
    """Cairn (~1.8 m): rounded grey stones piled into a cone, lichen on the top stones."""
    mb = MeshBuilder()
    rng = _rng(1417)
    rows = [(1.0, 8, 0.28, 0.42), (0.72, 7, 0.68, 0.36), (0.46, 5, 1.04, 0.3), (0.22, 3, 1.36, 0.25)]
    for (r, n, z, s) in rows:
        for k in range(n):
            a = 2 * math.pi * k / n + rng.uniform(-0.2, 0.2) + r
            c = (math.cos(a) * r, math.sin(a) * r, z)
            rr = s * rng.uniform(0.85, 1.15)
            _hull(mb, L.rock_points(c, (rr, rr * 0.85, rr * 0.7), rng, n=9, flat_bottom=False),
                  rng.choice(["fo_granite", "fo_granite_light", "fo_stone", "fo_granite_dark"]))
    _hull(mb, L.rock_points((0, 0, 1.62), (0.22, 0.2, 0.2), rng, n=9, flat_bottom=False), "fo_granite_light")
    mb.ico((0.05, -0.05, 1.8), 0.1, "fo_lichen", subdiv=0, scale=(1.3, 1.0, 0.4))
    mb.clamp_floor()
    mb.finish("forest_cairn")


def build_forest_log_bridge():
    """Log bridge (~12 m along Y, 3.6 m wide): two stringer logs resting on stone piers at the
    banks, a deck of split half-logs across them (top at ~0.15 m) and a pole rail each side on
    forked posts. Parts below 0 hang over the stream bed."""
    mb = MeshBuilder()
    rng = _rng(1421)
    half = 6.0
    for s in (-1, 1):
        mb.cyl_between((s * 1.15, -half - 0.3, -0.2), (s * 1.15 + rng.uniform(-0.1, 0.1), half + 0.3, -0.22), 0.3, 0.26,
                       "fo_log", segs=8)
        for e in (-1, 1):
            mb.cyl_between((s * 1.15, e * (half + 0.28), -0.2), (s * 1.15, e * (half + 0.34), -0.2), 0.27, 0.27, "fo_log_end", segs=8)
    n = int(2 * half / 0.4)
    for k in range(n):
        y = -half + 0.2 + k * 0.4
        mb.box((rng.uniform(-0.06, 0.06), y, 0.07), (3.3 + rng.uniform(-0.15, 0.15), 0.36, 0.14),
               rng.choice(["fo_wood_grey", "fo_wood", "fo_log"]), rot=(0, rng.uniform(-0.03, 0.03), rng.uniform(-0.04, 0.04)))
    for s in (-1, 1):
        for y in (-5.2, -1.8, 1.8, 5.2):
            mb.cyl((s * 1.72, y, 0.55), 0.08, 0.07, 1.0, "fo_wood_dark", segs=5)
            mb.cyl_between((s * 1.72, y, 0.95), (s * 1.72, y + 0.25, 1.15), 0.04, 0.03, "fo_wood_dark", segs=4)
        mb.cyl_between((s * 1.72, -5.6, 1.02), (s * 1.72, 5.6, 1.0), 0.07, 0.06, "fo_log", segs=6)
    for e in (-1, 1):
        for s in (-1, 1):
            _hull(mb, L.rock_points((s * 1.3, e * (half - 0.2), -0.1), (0.7, 0.6, 0.35), rng, n=10, flat_bottom=False),
                  rng.choice(["fo_granite", "fo_granite_dark"]))
    mb.finish("forest_log_bridge")


def build_forest_gate():
    """Wooden gateway (grind) over a trail: two carved posts 5 m apart (x = +-2.5) with red-painted
    bands, a lintel with upswept dragon-head ends, a shingled ridge and three round shields.
    ~4.8 m tall; the trail passes through along Y."""
    mb = MeshBuilder()
    rng = _rng(1423)
    for s in (-1, 1):
        mb.box((s * 2.5, 0, 1.95), (0.46, 0.46, 3.9), "fo_wood_dark", bevel=0.03)
        for z in (0.9, 2.2, 3.3):
            mb.box((s * 2.5, 0, z), (0.52, 0.52, 0.16), "fo_rune_paint")
        mb.box((s * 2.5, 0, 0.12), (0.7, 0.7, 0.24), "fo_granite_dark", bevel=0.04)
    mb.box((0, 0, 4.02), (6.6, 0.52, 0.4), "fo_wood", bevel=0.03)
    for s in (-1, 1):
        a = Vector((s * 3.2, 0, 4.02))
        b = Vector((s * 3.75, 0, 4.7))
        mb.cyl_between(a, b, 0.2, 0.13, "fo_wood", segs=6)
        mb.ico(b + Vector((s * 0.08, 0, 0.08)), 0.2, "fo_wood_dark", subdiv=0, scale=(1.5, 0.8, 0.9))
        mb.ico(b + Vector((s * 0.2, -0.1, 0.12)), 0.04, "fo_amber", subdiv=0)
    for s in (-1, 1):
        mb.box((0, s * 0.33, 4.42), (6.2, 0.62, 0.08), "fo_wood_grey", rot=(s * 0.55, 0, 0))
    mb.box((0, 0, 4.62), (6.2, 0.12, 0.12), "fo_wood_dark")
    for k, x in enumerate((-1.3, 0.0, 1.3)):
        mb.cyl((x, -0.3, 3.62), 0.36, 0.36, 0.08, ["fo_shield_red", "fo_shield_yellow", "fo_shield_blue"][k], segs=10,
               rot=(math.pi / 2, 0, 0))
        mb.cyl((x, -0.36, 3.62), 0.08, 0.08, 0.06, "fo_iron", segs=6, rot=(math.pi / 2, 0, 0))
    mb.clamp_floor()
    mb.finish("forest_gate")


def _dome(mb, rng, rx, ry, h, center=(0.0, 0.0)):
    verts = mb.ico((center[0], center[1], 0.0), 1.0, "fo_mound", subdiv=2, scale=(rx, ry, h))
    for v in verts:
        if v.co.z < 0.0:
            v.co.z = 0.0
        else:
            v.co.x += rng.uniform(-0.1, 0.1)
            v.co.y += rng.uniform(-0.1, 0.1)
            v.co.z += rng.uniform(-0.08, 0.08)
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.2, 0.7)
        cx, cy = math.cos(a) * r * rx, math.sin(a) * r * ry
        cz = h * max(0.0, 1.0 - (cx / rx) ** 2 - (cy / ry) ** 2) ** 0.5 - 0.1
        mb.ico((center[0] + cx, center[1] + cy, cz), 0.5, rng.choice(["fo_mound_light", "fo_mound_b", "fo_heather_dark"]),
               subdiv=1, scale=(1.4, 1.1, 0.35))


def build_forest_mound():
    """Burial mound (~8 x 7 m, 2.6 m): a grassy dome, moss patches, half-sunk kerb stones and a
    juniper on its crown."""
    mb = MeshBuilder()
    rng = _rng(1427)
    _dome(mb, rng, 4.0, 3.4, 2.6)
    for k in range(14):
        a = 2 * math.pi * k / 14 + rng.uniform(-0.08, 0.08)
        c = (math.cos(a) * 4.1, math.sin(a) * 3.5, 0.0)
        r = rng.uniform(0.28, 0.42)
        _hull(mb, L.rock_points(c, (r, r * 0.8, r * 0.65), rng, n=8), rng.choice(["fo_granite", "fo_granite_light", "fo_stone"]))
    n0 = len(mb.bm.verts)
    _juniper(mb, rng, 1.6)
    _moved(mb, n0, (0.3, 0.2, 2.45), 0.0)
    mb.clamp_floor()
    mb.finish("forest_mound")


def build_forest_mound_b():
    """Long low barrow (~12 x 5 m, 1.8 m) with a standing stone at one end."""
    mb = MeshBuilder()
    rng = _rng(1429)
    _dome(mb, rng, 6.0, 2.6, 1.8)
    for k in range(10):
        a = 2 * math.pi * k / 10
        c = (math.cos(a) * 6.1, math.sin(a) * 2.7, 0.0)
        r = rng.uniform(0.26, 0.38)
        _hull(mb, L.rock_points(c, (r, r * 0.8, r * 0.6), rng, n=8), rng.choice(["fo_granite", "fo_stone"]))
    pts = []
    for k in range(5):
        t = k / 4
        for a in range(5):
            ang = 2 * math.pi * a / 5 + rng.uniform(-0.2, 0.2)
            pts.append((6.9 + math.cos(ang) * 0.4 * (1 - 0.35 * t), math.sin(ang) * 0.25, 2.4 * t))
    _hull(mb, pts, "fo_granite_light")
    mb.clamp_floor()
    mb.finish("forest_mound_b")


def _juniper(mb, rng, height):
    mats = ["fo_juniper", "fo_juniper_dark", "fo_juniper_light"]
    mb.cyl((0, 0, 0.25), 0.09, 0.07, 0.5, "fo_bark_grey", segs=5)
    n = 5
    for k in range(n):
        t = k / (n - 1)
        z = 0.35 + t * (height - 0.55)
        r = 0.55 * (1.0 - 0.6 * t) * height / 2.4 + 0.12
        _clump(mb, (rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), z), r, mats[k % 3], rng, flat=1.25, jitter=0.18)
    _clump(mb, (0, 0, height - 0.1), 0.2, "fo_juniper_dark", rng, flat=1.4)


def build_forest_juniper():
    """Columnar juniper (en, ~2.4 m) of the heath."""
    mb = MeshBuilder()
    rng = _rng(1431)
    _juniper(mb, rng, 2.4)
    mb.clamp_floor()
    mb.finish("forest_juniper")


def build_forest_heather():
    """Heather tuft (ljung, ~1.2 m wide, 0.4 m): low dark clumps dotted with purple bells."""
    mb = MeshBuilder()
    rng = _rng(1433)
    for k in range(6):
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.15, 0.45)
        _clump(mb, (math.cos(a) * d, math.sin(a) * d, 0.12), rng.uniform(0.28, 0.38),
               rng.choice(["fo_heather", "fo_heather_dark"]), rng, flat=0.55)
    for k in range(22):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.0, 0.55)
        mb.ico((math.cos(a) * d, math.sin(a) * d, rng.uniform(0.24, 0.36)), 0.055,
               rng.choice(["fo_heather_flower", "fo_heather_flower_b"]), subdiv=0, scale=(1.0, 1.0, 1.4))
    mb.clamp_floor()
    mb.finish("forest_heather")


def build_forest_rock_slab():
    """Granite crag (~5 x 3.4 m, 3.6 m): a big angular block with a tilted top, a smaller block
    leaning on it, moss on the top and lichen spots. For outcrops and gorge rims."""
    mb = MeshBuilder()
    rng = _rng(1437)
    pts = []
    for (x, y) in ((-2.4, -1.5), (2.3, -1.6), (2.5, 1.4), (-2.2, 1.7), (0.2, -1.8), (0.0, 1.8), (-2.6, 0.0), (2.6, 0.1)):
        pts.append((x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.15, 0.15), 0.0))
        top = 3.0 + 0.25 * x + rng.uniform(-0.2, 0.2)
        pts.append((x * 0.82 + rng.uniform(-0.15, 0.15), y * 0.8 + rng.uniform(-0.15, 0.15), top))
    _hull(mb, pts, "fo_granite")
    moss = [(p[0] * 0.92, p[1] * 0.92, p[2] + 0.06) for p in pts if p[2] > 0.5]
    moss += [(p[0] * 0.98, p[1] * 0.98, p[2] - 0.35) for p in pts if p[2] > 0.5]
    _hull(mb, moss, "fo_moss_dark")
    pts2 = []
    for (x, y) in ((-1.0, -0.8), (1.0, -0.9), (1.1, 0.8), (-0.9, 0.9)):
        pts2.append((x + rng.uniform(-0.1, 0.1), y, 0.0))
        pts2.append((x * 0.75, y * 0.7, 1.8 + rng.uniform(-0.2, 0.2)))
    verts = mb.hull([(p[0] - 2.6, p[1] - 1.9, p[2]) for p in pts2], "fo_granite_dark")
    for k in range(6):
        a = rng.uniform(0, 6.28)
        mb.ico((math.cos(a) * 2.2, math.sin(a) * 1.4, rng.uniform(0.6, 2.4)), rng.uniform(0.18, 0.3), "fo_lichen",
               subdiv=0, scale=(1.0, 1.0, 0.4))
    for k in range(4):
        a = rng.uniform(0, 6.28)
        _clump(mb, (math.cos(a) * 2.6, math.sin(a) * 1.9, 0.1), rng.uniform(0.3, 0.45), rng.choice(["fo_fern", "fo_shrub"]),
               rng, flat=0.6)
    mb.clamp_floor()
    mb.finish("forest_rock_slab")


def build_forest_dwarf_hole():
    """Grey dwarf burrow (~4.4 x 3.6 m, 2.3 m): a mossy rock mound with a dark hole on its front
    (-Y), framed by stones, with gnawed bones and sticks at the entrance."""
    mb = MeshBuilder()
    rng = _rng(1439)
    _mossy_rock(mb, rng, (0, 0.6, 0.9), (2.2, 1.6, 1.4), n=22, rough=0.12, moss_level=0.62, stone="fo_granite_dark")
    mb.box((0, -0.85, 0.55), (1.3, 0.9, 1.1), "fo_opening")
    mb.ico((0, -0.9, 1.1), 0.62, "fo_opening", subdiv=1, scale=(1.05, 0.7, 0.55))
    for k in range(7):
        a = math.pi * (0.05 + 0.9 * k / 6)
        c = (math.cos(a) * 0.95, -1.05, 0.15 + math.sin(a) * 1.15)
        r = rng.uniform(0.22, 0.3)
        _hull(mb, L.rock_points(c, (r, r * 0.8, r), rng, n=8, flat_bottom=False), rng.choice(["fo_granite", "fo_stone_dark"]))
    for k in range(5):
        a = rng.uniform(-0.6, 0.6)
        p = Vector((rng.uniform(-1.0, 1.0), -1.6 - rng.uniform(0, 0.8), 0.06))
        q = p + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.0))
        mb.cyl_between(p, q, 0.05, 0.04, "fo_bone" if k % 2 else "fo_wood_dark", segs=4)
    mb.ico((0.7, -1.9, 0.12), 0.13, "fo_bone", subdiv=1, scale=(1.0, 1.2, 0.9))
    mb.clamp_floor()
    mb.finish("forest_dwarf_hole")


def build_forest_jetty_old():
    """Broken old jetty (~8 m along -Y from the shore): grey warped planks with gaps, a sagging
    end, leaning posts. Deck at z ~ 0.15."""
    mb = MeshBuilder()
    rng = _rng(1441)
    y0, y1 = 0.6, -7.8
    n = int((y0 - y1) / 0.36)
    for k in range(n):
        y = y0 - 0.18 - k * 0.36
        t = k / n
        if k in (5, 9, 10, 15) or (t > 0.7 and rng.random() < 0.35):
            continue
        sag = -0.25 * max(0.0, t - 0.6) / 0.4
        mb.box((rng.uniform(-0.08, 0.08), y, 0.12 + sag), (2.2 + rng.uniform(-0.3, 0.1), 0.28, 0.08),
               rng.choice(["fo_wood_grey", "fo_wood_grey", "fo_wood"]),
               rot=(rng.uniform(-0.04, 0.04) + (0.12 if t > 0.75 else 0.0), rng.uniform(-0.05, 0.05), rng.uniform(-0.06, 0.06)))
    for s in (-1, 1):
        mb.box((s * 0.95, (y0 + y1 * 0.7) / 2, 0.02), (0.16, y0 - y1 * 0.7, 0.14), "fo_wood_dark")
        for k in range(4):
            y = y0 - 0.4 - k * 2.4
            lean = rng.uniform(-0.15, 0.15)
            mb.cyl_between((s * 1.1, y, -0.9), (s * 1.1 + lean, y + lean * 0.5, 0.55 + rng.uniform(-0.1, 0.25)), 0.12, 0.1,
                           "fo_wood_dark", segs=6)
    mb.finish("forest_jetty_old")


def build_forest_lilypads():
    """Water lilies (~2.6 m patch): flat round pads and two white flowers, floating at z = 0."""
    mb = MeshBuilder()
    rng = _rng(1443)
    for k in range(9):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.0, 1.2)
        r = rng.uniform(0.22, 0.42)
        mb.cyl((math.cos(a) * d, math.sin(a) * d, 0.015 + k * 0.004), r, r, 0.03, rng.choice(["fo_lily", "fo_lily_dark"]),
               segs=9, twist=rng.uniform(0, 6.28))
    for k in range(2):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.2, 0.9)
        c = (math.cos(a) * d, math.sin(a) * d, 0.08)
        for p in range(6):
            pa = 2 * math.pi * p / 6
            mb.ico((c[0] + math.cos(pa) * 0.07, c[1] + math.sin(pa) * 0.07, c[2]), 0.07, "fo_flower", subdiv=0,
                   scale=(1.4, 0.7, 0.5), rot=(0, 0, pa))
        mb.ico((c[0], c[1], c[2] + 0.03), 0.04, "fo_flower_core", subdiv=0)
    mb.finish("forest_lilypads")


BUILDERS.update({
    "forest_stand_a": build_forest_stand_a,
    "forest_stand_b": build_forest_stand_b,
    "forest_stand_c": build_forest_stand_c,
    "forest_snag": build_forest_snag,
    "forest_standing_stone": build_forest_standing_stone,
    "forest_runestone_old": build_forest_runestone_old,
    "forest_cairn": build_forest_cairn,
    "forest_log_bridge": build_forest_log_bridge,
    "forest_gate": build_forest_gate,
    "forest_mound": build_forest_mound,
    "forest_mound_b": build_forest_mound_b,
    "forest_juniper": build_forest_juniper,
    "forest_heather": build_forest_heather,
    "forest_rock_slab": build_forest_rock_slab,
    "forest_dwarf_hole": build_forest_dwarf_hole,
    "forest_jetty_old": build_forest_jetty_old,
    "forest_lilypads": build_forest_lilypads,
})


def _gardsgard_long(model_id, seed, length=4.0, missing=()):
    """Roundpole fence run like _gardsgard but `length` m long (fewer border pieces): post pairs
    every 1 m, slanted poles every 0.5 m reaching into the next run."""
    mb = MeshBuilder()
    rng = _rng(seed)
    n_posts = int(round(length))
    for k in range(n_posts):
        px = -length / 2 + 0.5 + k
        for py in (-0.1, 0.1):
            lean = rng.uniform(-0.03, 0.03)
            mb.cyl_between((px, py, 0.0), (px + lean, py * 0.8, 1.38 + rng.uniform(-0.06, 0.06)), 0.05, 0.04,
                           "fo_gard_dark", segs=5)
        for z in (0.45, 1.0):
            mb.cyl((px, 0.0, z), 0.14, 0.14, 0.07, "fo_withy", segs=6)
    for k in range(int(round(length * 2))):
        if k in missing:
            continue
        xs = -length / 2 - 0.2 + k * 0.5
        a = Vector((xs, rng.uniform(-0.03, 0.03), 0.08))
        b = Vector((xs + 2.25, rng.uniform(-0.03, 0.03), 1.12 + rng.uniform(-0.05, 0.05)))
        mb.cyl_between(a, b, 0.042, 0.036, ["fo_gard", "fo_gard_light", "fo_gard"][k % 3], segs=5)
    mb.finish(model_id)


def build_forest_gardsgard_c():
    """Roundpole fence run, 4 m (the zones' border pieces)."""
    _gardsgard_long("forest_gardsgard_c", 1304)


def build_forest_gardsgard_d():
    """Roundpole fence run, 4 m, two poles gone."""
    _gardsgard_long("forest_gardsgard_d", 1305, missing=(2, 5))


BUILDERS.update({
    "forest_gardsgard_c": build_forest_gardsgard_c,
    "forest_gardsgard_d": build_forest_gardsgard_d,
})



# ----------------------------------------------------------------------------------- ground cover patches

def _fern_at(mb, rng, base, scale=1.0):
    """A fern clump like forest_fern at base (8 fronds)."""
    bx, by = base
    for k in range(7):
        a = 2 * math.pi * k / 7 + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        b0 = Vector((bx, by, 0.05))
        mid = b0 + (d * 0.45 + Vector((0, 0, 0.55))) * scale
        tip = b0 + (d * 0.85 + Vector((0, 0, 0.3))) * scale
        m = "fo_fern" if k % 2 else "fo_fern_dark"
        for p0, p1, w in ((b0, mid, 0.26 * scale), (mid, tip, 0.2 * scale)):
            axis = p1 - p0
            u = axis.normalized()
            n = u.cross(side).normalized()
            mb.obox((p0 + p1) / 2, (u, side, n), (axis.length, w, 0.03), m)


def _tuft(mb, rng, base, mats, n=5, h=(0.3, 0.55)):
    for k in range(n):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.0, 0.2)
        b = (base[0] + math.cos(a) * r, base[1] + math.sin(a) * r, 0.0)
        la = a + rng.uniform(-0.5, 0.5)
        _blade(mb, b, rng.uniform(*h), (math.cos(la) * 0.9, math.sin(la) * 0.9, 0), 0.09, mats[k % len(mats)])


def _spots(rng, n, radius):
    out = []
    for k in range(n):
        a = rng.uniform(0, 6.28)
        d = math.sqrt(rng.uniform(0.05, 1.0)) * radius
        out.append((math.cos(a) * d, math.sin(a) * d))
    return out


def build_forest_patch_scrub():
    """Blueberry and lingonberry scrub (~3.6 m across, 0.5 m): low clumps with berries, a grass
    tuft and a small fern — one prop for a stretch of the forest floor."""
    mb = MeshBuilder()
    rng = _rng(1501)
    mats = ["fo_shrub", "fo_shrub_dark", "fo_shrub_light"]
    for k, (x, y) in enumerate(_spots(rng, 9, 1.6)):
        c = (x, y, 0.1)
        _clump(mb, c, rng.uniform(0.3, 0.46), mats[k % 3], rng, flat=0.5)
        for b in range(2):
            a = rng.uniform(0, 6.28)
            mb.ico((x + math.cos(a) * 0.22, y + math.sin(a) * 0.22, rng.uniform(0.2, 0.3)), 0.045,
                   "fo_berry_blue" if (k + b) % 3 else "fo_berry_red", subdiv=0)
    _tuft(mb, rng, (1.4, -0.9), ["fo_grass", "fo_grass_light"])
    _tuft(mb, rng, (-1.5, 0.6), ["fo_grass", "fo_grass_dry"])
    _fern_at(mb, rng, (0.2, 1.5), 0.7)
    mb.clamp_floor()
    mb.finish("forest_patch_scrub")


def build_forest_patch_fern():
    """Bracken (~4 m across): four fern clumps and a moss cushion."""
    mb = MeshBuilder()
    rng = _rng(1503)
    for (x, y, sc) in ((-1.1, -0.6, 1.0), (1.0, -0.9, 0.85), (0.3, 1.1, 1.1), (-1.4, 1.3, 0.75)):
        _fern_at(mb, rng, (x, y), sc)
    mb.ico((0.4, 0.0, 0.0), 0.5, "fo_moss_dark", subdiv=1, scale=(1.4, 1.0, 0.35))
    mb.clamp_floor()
    mb.finish("forest_patch_fern")


def build_forest_patch_heath():
    """Heath (~3.6 m across): heather tufts with purple bells among dry grass."""
    mb = MeshBuilder()
    rng = _rng(1505)
    for k, (x, y) in enumerate(_spots(rng, 7, 1.6)):
        for j in range(3):
            a = rng.uniform(0, 6.28)
            _clump(mb, (x + math.cos(a) * 0.2, y + math.sin(a) * 0.2, 0.1), rng.uniform(0.2, 0.3),
                   rng.choice(["fo_heather", "fo_heather_dark"]), rng, flat=0.55)
        for j in range(4):
            a = rng.uniform(0, 6.28)
            d = rng.uniform(0.0, 0.4)
            mb.ico((x + math.cos(a) * d, y + math.sin(a) * d, rng.uniform(0.2, 0.3)), 0.045,
                   rng.choice(["fo_heather_flower", "fo_heather_flower_b"]), subdiv=0, scale=(1.0, 1.0, 1.4))
    for (x, y) in _spots(rng, 3, 1.5):
        _tuft(mb, rng, (x, y), ["fo_grass_heath", "fo_grass_dry"], n=5, h=(0.3, 0.5))
    mb.clamp_floor()
    mb.finish("forest_patch_heath")


def build_forest_patch_meadow():
    """Meadow (~3.6 m across): grass tufts and white wood anemones."""
    mb = MeshBuilder()
    rng = _rng(1507)
    for (x, y) in _spots(rng, 7, 1.6):
        _tuft(mb, rng, (x, y), ["fo_grass", "fo_grass_light", "fo_grass_dry"], n=5)
    for (x, y) in _spots(rng, 12, 1.7):
        h = rng.uniform(0.12, 0.22)
        mb.ico((x, y, h * 0.5), 0.06, "fo_stem", subdiv=0, scale=(1.2, 1.2, h * 5))
        mb.ico((x, y, h), 0.08, "fo_flower", subdiv=0, scale=(1.0, 1.0, 0.3))
        mb.ico((x, y, h + 0.02), 0.025, "fo_flower_core", subdiv=0)
    mb.clamp_floor()
    mb.finish("forest_patch_meadow")


def build_forest_patch_moss():
    """Mossy forest floor (~3.4 m across): moss cushions, lichen, a mossy stone and fly agarics."""
    mb = MeshBuilder()
    rng = _rng(1509)
    for k, (x, y) in enumerate(_spots(rng, 6, 1.4)):
        mb.ico((x, y, 0.0), rng.uniform(0.35, 0.6), ["fo_moss", "fo_moss_dark", "fo_moss_light"][k % 3], subdiv=1,
               scale=(1.3, 1.0, 0.45), rot=(0, 0, rng.uniform(0, 6.28)))
    for (x, y) in _spots(rng, 4, 1.5):
        mb.ico((x, y, 0.03), rng.uniform(0.12, 0.2), "fo_lichen", subdiv=0, scale=(1.2, 1.0, 0.35))
    _mossy_rock(mb, rng, (0.9, -0.5, 0.18), (0.45, 0.35, 0.28), n=10, moss_level=0.6)
    _mushroom(mb, (-0.8, 0.9, 0.0), 0.26, rng)
    _mushroom(mb, (-0.6, 1.1, 0.0), 0.18, rng)
    mb.clamp_floor()
    mb.finish("forest_patch_moss")


BUILDERS.update({
    "forest_patch_scrub": build_forest_patch_scrub,
    "forest_patch_fern": build_forest_patch_fern,
    "forest_patch_heath": build_forest_patch_heath,
    "forest_patch_meadow": build_forest_patch_meadow,
    "forest_patch_moss": build_forest_patch_moss,
})
