"""Skill icons: one 128x128 PNG per player skill id (§8.4) -> assets/icons/skills/<id>.png.

Each icon is a small 3D composition rendered with EEVEE from an orthographic top camera: a dark
round badge with a colour-coded rim (melee red/orange, bow/crossbow green, spells by element,
utility teal, basic attack steel) and a bold bevelled glyph that stays readable at 48 px.
Rendered to assets/icons/skills/.tmp/<id>.png, then os.replace()d into place.
OWNER: assets-environment.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

import envlib as L

SKILL_IDS = [
    "basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam", "whirlwind",
    "infernal_blow", "war_cry", "power_shot", "split_arrow", "rain_of_arrows", "explosive_bolt",
    "scatter_shot", "rapid_fire", "ice_shot", "venom_arrow", "fireball", "ice_spear", "frost_nova",
    "chain_lightning", "teleport", "spark", "meteor", "blood_rite",
]

# rim colour, dark background, inner glow (sRGB hex)
CATEGORIES = {
    "neutral": ("#c3c8d2", "#15171b", "#3b414d"),
    "melee": ("#e4572e", "#1c0b08", "#5e1d10"),
    "ranged": ("#63c24a", "#0b170a", "#1f4d19"),
    "fire": ("#ff8f24", "#1d0f05", "#6e2c08"),
    "cold": ("#4db9ff", "#07111c", "#123f68"),
    "lightning": ("#ffd83a", "#171405", "#5c4b0a"),
    "chaos": ("#b85cf2", "#12091a", "#46195f"),
    "utility": ("#48e3cf", "#071817", "#0f4f4a"),
}

SKILL_CATEGORY = {
    "basic_attack": "neutral",
    "heavy_strike": "melee", "cleave": "melee", "ground_slam": "melee", "leap_slam": "melee",
    "whirlwind": "melee", "infernal_blow": "melee", "war_cry": "melee",
    "power_shot": "ranged", "split_arrow": "ranged", "rain_of_arrows": "ranged",
    "explosive_bolt": "ranged", "scatter_shot": "ranged", "rapid_fire": "ranged",
    "ice_shot": "ranged", "venom_arrow": "ranged",
    "fireball": "fire", "meteor": "fire",
    "ice_spear": "cold", "frost_nova": "cold",
    "chain_lightning": "lightning", "spark": "lightning",
    "teleport": "utility", "blood_rite": "chaos",
}

GLYPH_Z = 0.12      # top of glyph shapes
GLYPH_H = 0.06      # extrusion depth


# ----------------------------------------------------------------------------------- materials

def imat(name, hexcol, emit=0.45, rough=0.4, metal=0.0):
    """Icon material: base colour plus a matching emission so it stays bright and saturated."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    c = L.hexcol(hexcol)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Emission Color"].default_value = (c[0], c[1], c[2], 1.0)
    bsdf.inputs["Emission Strength"].default_value = emit
    return m


def flat(name, hexcol):
    """Pure emission (unlit) material for backgrounds."""
    return imat(name, hexcol, emit=1.0, rough=1.0)


M = {}


def _mats():
    M.clear()
    M["steel"] = imat("steel", "#dfe6ef", emit=0.35, rough=0.25, metal=0.3)
    M["steel_dark"] = imat("steel_dark", "#8e98a8", emit=0.3, rough=0.3, metal=0.3)
    M["gold"] = imat("gold", "#f2c14e", emit=0.4, rough=0.3, metal=0.3)
    M["wood"] = imat("wood", "#a9723f", emit=0.35)
    M["wood_dark"] = imat("wood_dark", "#6e4726", emit=0.3)
    M["white"] = imat("white", "#f4f1ea", emit=0.6)
    M["feather"] = imat("feather", "#f0ece0", emit=0.5)
    M["red"] = imat("red", "#e8412e", emit=0.6)
    M["orange"] = imat("orange", "#ff8a1f", emit=0.9)
    M["yellow"] = imat("yellow", "#ffd84a", emit=1.0)
    M["fire_core"] = imat("fire_core", "#fff1a8", emit=1.4)
    M["ice"] = imat("ice", "#8fd8ff", emit=0.8, rough=0.15)
    M["ice_light"] = imat("ice_light", "#e0f6ff", emit=1.0, rough=0.1)
    M["ice_deep"] = imat("ice_deep", "#3c9ae6", emit=0.7, rough=0.2)
    M["bolt"] = imat("bolt", "#fff06a", emit=1.4)
    M["bolt_core"] = imat("bolt_core", "#ffffff", emit=1.6)
    M["poison"] = imat("poison", "#8fe03a", emit=0.9)
    M["poison_dark"] = imat("poison_dark", "#4d9a1e", emit=0.7)
    M["chaos"] = imat("chaos", "#c46cff", emit=0.9)
    M["chaos_dark"] = imat("chaos_dark", "#6a2d92", emit=0.7)
    M["blood"] = imat("blood", "#d11a2a", emit=0.7, rough=0.2)
    M["blood_light"] = imat("blood_light", "#ff6a70", emit=1.0, rough=0.2)
    M["teal"] = imat("teal", "#5ff5de", emit=1.0)
    M["teal_dark"] = imat("teal_dark", "#1fae9c", emit=0.8)
    M["rock"] = imat("rock", "#5a4336", emit=0.25)
    M["rock_light"] = imat("rock_light", "#8a6a54", emit=0.3)
    M["ground"] = imat("ground", "#8a6f55", emit=0.35)
    M["crack"] = imat("crack", "#2a1c12", emit=0.1)
    M["horn"] = imat("horn", "#e9dcc0", emit=0.45)
    M["dark"] = imat("dark", "#141414", emit=0.0)


# ----------------------------------------------------------------------------------- 2D helpers

def rot2(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def xf(pts, cx=0.0, cy=0.0, ang=0.0, sx=1.0, sy=1.0):
    out = []
    for p in pts:
        q = rot2((p[0] * sx, p[1] * sy), ang)
        out.append((q[0] + cx, q[1] + cy))
    return out


def circle(cx, cy, r, n=28, phase=0.0):
    return [(cx + r * math.cos(phase + 2 * math.pi * i / n), cy + r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def arc(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def star(cx, cy, r_out, r_in, n, phase=math.pi / 2):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = phase + math.pi * i / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def crescent(cx, cy, r, a0, a1, w_max, n=26, w_start=0.0):
    """Swoosh band along an arc whose width grows from w_start to w_max and tapers to 0."""
    outer, inner = [], []
    for i in range(n):
        t = i / (n - 1)
        if t < 0.5:
            w = w_start + (w_max - w_start) * math.sin(math.pi * t)
        else:
            w = w_max * math.sin(math.pi * t)
        w = max(w, 0.0)
        a = a0 + (a1 - a0) * t
        outer.append((cx + (r + w / 2) * math.cos(a), cy + (r + w / 2) * math.sin(a)))
        inner.append((cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)))
    return outer + list(reversed(inner))


def _signed_area(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def _dedupe(pts, eps=1e-5):
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps:
            out.append(p)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    return out


# ----------------------------------------------------------------------------------- 3D shape builders

def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def poly(pts, mat, z=GLYPH_Z, h=GLYPH_H, bevel=0.014, name="g"):
    """Extruded 2D polygon (any simple polygon) with a rounded top edge."""
    pts = _dedupe(pts)
    if _signed_area(pts) < 0:
        pts = list(reversed(pts))
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z - h)) for x, y in pts]
    top = [bm.verts.new((x, y, z)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    k = len(pts)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    if bevel > 0:
        topset = set(top)
        bm.edges.index_update()
        edges = sorted((e for e in bm.edges if e.verts[0] in topset and e.verts[1] in topset), key=lambda e: e.index)
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=2, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = False
    return _link(bpy.data.objects.new(name, me))


def disc(cx, cy, r, mat, z, h=0.01, n=48):
    return poly(circle(cx, cy, r, n), mat, z=z, h=h, bevel=0.0)


def tube(pts, r, mat, z=GLYPH_Z - 0.02, closed=False, radii=None, name="t"):
    """Round stroke through 2D points (a bevelled curve)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        sp.points[i].co = (x, y, z, 1.0)
        if radii is not None:
            sp.points[i].radius = radii[i]
    sp.use_cyclic_u = closed
    cu.materials.append(mat)
    return _link(bpy.data.objects.new(name, cu))


def ring(cx, cy, r, w, mat, z=GLYPH_Z, h=GLYPH_H, n=40, a0=0.0, a1=2 * math.pi):
    """Flat band along an arc (closed ring when a1 - a0 = 2 pi)."""
    if abs((a1 - a0) - 2 * math.pi) < 1e-6:
        # two half rings (a polygon cannot have a hole)
        poly(arc(cx, cy, r + w / 2, 0, math.pi, n // 2) + arc(cx, cy, r - w / 2, math.pi, 0, n // 2), mat, z, h, bevel=0.01)
        return poly(arc(cx, cy, r + w / 2, math.pi, 2 * math.pi, n // 2) + arc(cx, cy, r - w / 2, 2 * math.pi, math.pi, n // 2), mat, z, h, bevel=0.01)
    return poly(arc(cx, cy, r + w / 2, a0, a1, n) + arc(cx, cy, r - w / 2, a1, a0, n), mat, z, h, bevel=0.01)


# ----------------------------------------------------------------------------------- composite glyphs

def sword(cx, cy, ang, length=1.25, w=0.16, blade="steel", z=GLYPH_Z):
    """Sword with its point along local +Y, grip centred near (cx, cy) - length/2."""
    bl = length * 0.68
    base = -length * 0.5
    y0 = base + length * 0.3
    blade_pts = [(-w / 2, y0), (w / 2, y0), (w / 2, y0 + bl - w * 0.9), (0, y0 + bl), (-w / 2, y0 + bl - w * 0.9)]
    poly(xf(blade_pts, cx, cy, ang), M[blade], z=z)
    poly(xf([(-0.018, y0 + 0.04), (0.018, y0 + 0.04), (0.018, y0 + bl - w * 1.2), (-0.018, y0 + bl - w * 1.2)], cx, cy, ang),
         M["steel_dark"], z=z + 0.012, h=0.02, bevel=0.0)
    gw = w * 2.6
    poly(xf([(-gw / 2, y0 - 0.06), (gw / 2, y0 - 0.06), (gw / 2, y0), (-gw / 2, y0)], cx, cy, ang), M["gold"], z=z + 0.01, bevel=0.012)
    poly(xf([(-0.045, base + 0.07), (0.045, base + 0.07), (0.045, y0 - 0.06), (-0.045, y0 - 0.06)], cx, cy, ang), M["wood_dark"], z=z)
    pc = xf([(0, base + 0.05)], cx, cy, ang)[0]
    poly(circle(pc[0], pc[1], 0.065, 14), M["gold"], z=z + 0.01)


def arrow(x0, y0, x1, y1, shaft=0.05, head_len=0.26, head_w=0.24, head="steel", shaft_mat="wood",
          fletch="feather", z=GLYPH_Z, fletch_len=0.24, fletch_w=0.1):
    """Arrow from tail (x0, y0) to tip (x1, y1)."""
    d = Vector((x1 - x0, y1 - y0))
    ln = d.length
    ang = math.atan2(d.y, d.x) - math.pi / 2
    local_shaft = [(-shaft / 2, 0.02), (shaft / 2, 0.02), (shaft / 2, ln - head_len + 0.02), (-shaft / 2, ln - head_len + 0.02)]
    poly(xf(local_shaft, x0, y0, ang), M[shaft_mat], z=z - 0.01)
    hd = [(-head_w / 2, ln - head_len), (0, ln - head_len + 0.05), (head_w / 2, ln - head_len), (0, ln)]
    poly(xf(hd, x0, y0, ang), M[head], z=z)
    if fletch:
        for s in (-1, 1):
            f = [(0, 0.0), (s * fletch_w, -0.05), (s * fletch_w, fletch_len - 0.08), (0, fletch_len)]
            if s < 0:
                f = list(reversed(f))
            poly(xf(f, x0, y0, ang), M[fletch], z=z - 0.005)


def bolt_proj(x0, y0, x1, y1, w=0.07, head="steel", z=GLYPH_Z):
    """Stubby crossbow bolt from (x0, y0) to its tip (x1, y1)."""
    d = Vector((x1 - x0, y1 - y0))
    ln = d.length
    ang = math.atan2(d.y, d.x) - math.pi / 2
    poly(xf([(-w / 2, 0.0), (w / 2, 0.0), (w / 2, ln - 0.14), (-w / 2, ln - 0.14)], x0, y0, ang), M["wood_dark"], z=z - 0.01)
    poly(xf([(-w * 1.2, ln - 0.16), (w * 1.2, ln - 0.16), (0, ln)], x0, y0, ang), M[head], z=z)
    for s in (-1, 1):
        f = [(0, 0.0), (s * 0.08, -0.02), (s * 0.08, 0.1), (0, 0.16)]
        if s < 0:
            f = list(reversed(f))
        poly(xf(f, x0, y0, ang), M["gold"], z=z - 0.005)


def flame(cx, cy, s, ang=0.0, outer="orange", inner="yellow", core="fire_core", z=GLYPH_Z):
    """Three-tongued flame pointing along local +Y, base at (cx, cy)."""
    def shape(sc):
        pts = []
        base = arc(0, 0.28 * sc, 0.34 * sc, math.pi * 1.05, math.pi * 1.95, 10)
        pts += base
        pts += [(0.36 * sc, 0.42 * sc), (0.26 * sc, 0.7 * sc), (0.18 * sc, 0.55 * sc), (0.06 * sc, 1.0 * sc),
                (-0.1 * sc, 0.62 * sc), (-0.22 * sc, 0.82 * sc), (-0.36 * sc, 0.45 * sc)]
        return pts
    poly(xf(shape(s), cx, cy, ang), M[outer], z=z)
    poly(xf(shape(s * 0.66), cx, cy + 0.0, ang), M[inner], z=z + 0.02, h=0.02)
    poly(xf(shape(s * 0.36), cx, cy + 0.0, ang), M[core], z=z + 0.035, h=0.02)


def lightning(pts_center, w, mat="bolt", core="bolt_core", z=GLYPH_Z):
    """Jagged bolt along a polyline, as a tapered polygon + bright core tube."""
    left, right = [], []
    n = len(pts_center)
    for i, p in enumerate(pts_center):
        a = pts_center[max(i - 1, 0)]
        b = pts_center[min(i + 1, n - 1)]
        d = Vector((b[0] - a[0], b[1] - a[1])).normalized()
        nrm = Vector((-d.y, d.x))
        ww = w * (1.0 - 0.75 * i / (n - 1))
        left.append((p[0] + nrm.x * ww / 2, p[1] + nrm.y * ww / 2))
        right.append((p[0] - nrm.x * ww / 2, p[1] - nrm.y * ww / 2))
    poly(left + list(reversed(right)), M[mat], z=z, bevel=0.006)
    tube(pts_center, w * 0.12, M[core], z=z + 0.01)


def snowflake(cx, cy, r, w=0.07, mat="ice_light", z=GLYPH_Z):
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        tip = (cx + r * math.cos(a), cy + r * math.sin(a))
        tube([(cx, cy), tip], w / 2, M[mat], z=z)
        for t, bl in ((0.55, 0.3), (0.8, 0.2)):
            p = (cx + r * t * math.cos(a), cy + r * t * math.sin(a))
            for s in (-1, 1):
                b = a + s * 0.75
                q = (p[0] + r * bl * math.cos(b), p[1] + r * bl * math.sin(b))
                tube([p, q], w * 0.38, M[mat], z=z)


def drop(cx, cy, s, mat, ang=0.0, z=GLYPH_Z):
    """Teardrop with its round part centred at (cx, cy) and the point up (local +Y)."""
    d = 2.1 * s
    beta = math.acos(s / d)
    pts = arc(0, 0, s, math.pi / 2 + beta, 2 * math.pi + math.pi / 2 - beta, 22) + [(0, d)]
    return poly(xf(pts, cx, cy, ang), mat, z=z)


def impact(cx, cy, r, mat="yellow", n=8, inner=0.45, z=GLYPH_Z, phase=math.pi / 2):
    poly(star(cx, cy, r, r * inner, n, phase), M[mat], z=z, bevel=0.008)


# ----------------------------------------------------------------------------------- badge + scene

def badge(category):
    rim_hex, bg_hex, glow_hex = CATEGORIES[category]
    imat("rim_" + category, rim_hex, emit=0.55, rough=0.3, metal=0.4)
    rim_dark = imat("rimdark_" + category, _mix(rim_hex, "#000000", 0.55), emit=0.3, rough=0.4)
    # dark background with a soft radial glow (stepped discs)
    steps = 9
    for i in range(steps):
        t = i / (steps - 1)
        r = 0.86 - 0.62 * t
        col = _mix(bg_hex, glow_hex, t ** 1.3)
        disc(0, 0, r, flat("bg_%s_%d" % (category, i), col), z=0.001 * i, h=0.005)
    # bevelled rim ring: lathe profile
    mb = L.MeshBuilder()
    mb.lathe([(0.845, -0.01), (0.845, 0.06), (0.885, 0.1), (0.955, 0.1), (0.995, 0.05), (0.995, -0.01)],
             "rim_" + category, segs=64, cap_bottom=False, cap_top=False)
    mb.lathe([(0.825, 0.0), (0.845, 0.0), (0.845, 0.03), (0.825, 0.03)], "rimdark_" + category, segs=64,
             closed=True)
    ob = mb.finish("rim")
    for p in ob.data.polygons:
        p.use_smooth = True
    # small studs on the rim
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        poly(circle(0.92 * math.cos(a), 0.92 * math.sin(a), 0.035, 10), rim_dark, z=0.115, h=0.03, bevel=0.01)


def _mix(h1, h2, t):
    a = [int(h1.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    b = [int(h2.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    try:
        sc.eevee.taa_render_samples = 32
    except AttributeError:
        pass
    sc.render.resolution_x = 128
    sc.render.resolution_y = 128
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.compression = 90
    # no metadata (render time/date stamps would make every build differ)
    for attr in dir(sc.render):
        if attr.startswith("use_stamp"):
            try:
                setattr(sc.render, attr, False)
            except (AttributeError, TypeError):
                pass
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    world = bpy.data.worlds.new("w")
    world.color = (0.25, 0.25, 0.27)
    sc.world = world
    if world.node_tree:
        bg = world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs["Color"].default_value = (0.25, 0.25, 0.27, 1.0)
            bg.inputs["Strength"].default_value = 1.0
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (0, 0, 5)
    sc.camera = cam
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 2.2
    sun_data.angle = 0.2
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    sun.rotation_euler = Vector((0.55, -0.6, -1.0)).to_track_quat("-Z", "Y").to_euler()


# ----------------------------------------------------------------------------------- glyphs per skill

def g_basic_attack():
    arrow(0.55, -0.55, -0.55, 0.55, head="steel", shaft=0.055, head_len=0.26, head_w=0.24)
    sword(0.02, 0.02, math.radians(-45), length=1.3, w=0.17, z=GLYPH_Z + 0.03)


def g_heavy_strike():
    impact(0.18, 0.22, 0.52, "orange", n=9, inner=0.45)
    impact(0.18, 0.22, 0.3, "yellow", n=9, inner=0.5, z=GLYPH_Z + 0.02)
    ang = math.radians(35)
    handle = xf([(-0.055, -0.62), (0.055, -0.62), (0.055, 0.25), (-0.055, 0.25)], -0.12, -0.05, ang)
    poly(handle, M["wood"])
    head = xf([(-0.32, 0.18), (0.32, 0.18), (0.32, 0.5), (-0.32, 0.5)], -0.12, -0.05, ang)
    poly(head, M["steel"], z=GLYPH_Z + 0.03)
    band = xf([(-0.34, 0.3), (0.34, 0.3), (0.34, 0.38), (-0.34, 0.38)], -0.12, -0.05, ang)
    poly(band, M["gold"], z=GLYPH_Z + 0.045, h=0.02)


def g_cleave():
    poly(crescent(0.0, -0.05, 0.56, math.radians(200), math.radians(-20), 0.22), M["white"], z=GLYPH_Z - 0.02)
    ang = math.radians(-35)
    poly(xf([(-0.045, -0.6), (0.045, -0.6), (0.045, 0.45), (-0.045, 0.45)], 0.05, 0.0, ang), M["wood"])
    blade = [(0.02, 0.1), (0.36, 0.0)] + arc(0.12, 0.3, 0.36, math.radians(-35), math.radians(55), 8) + [(0.02, 0.45)]
    poly(xf(blade, 0.05, 0.0, ang), M["steel"], z=GLYPH_Z + 0.02)
    poly(xf([(-0.1, 0.22), (0.02, 0.18), (0.02, 0.38), (-0.1, 0.34)], 0.05, 0.0, ang), M["steel_dark"], z=GLYPH_Z + 0.02)


def g_ground_slam():
    poly([(-0.72, -0.42), (0.72, -0.42), (0.6, -0.62), (-0.6, -0.62)], M["ground"], z=GLYPH_Z - 0.02)
    for (x, h, a) in ((-0.42, 0.32, 0.35), (-0.18, 0.5, 0.15), (0.08, 0.58, -0.05), (0.34, 0.44, -0.25), (0.56, 0.26, -0.45)):
        pts = xf([(-0.09, 0.0), (0.09, 0.0), (0.02, h), (-0.04, h * 0.8)], x, -0.42, a)
        poly(pts, M["rock_light"], z=GLYPH_Z)
        poly(xf([(-0.03, 0.0), (0.03, 0.0), (0.0, h * 0.6)], x, -0.42, a), M["orange"], z=GLYPH_Z + 0.02, h=0.02, bevel=0.0)
    tube([(-0.35, -0.52), (-0.1, -0.46), (0.05, -0.55), (0.3, -0.48)], 0.018, M["crack"], z=GLYPH_Z - 0.005)
    ring(0.0, -0.42, 0.62, 0.05, M["yellow"], z=GLYPH_Z - 0.01, a0=math.radians(20), a1=math.radians(160))
    # hammer head coming down
    poly([(-0.2, 0.22), (0.26, 0.22), (0.26, 0.5), (-0.2, 0.5)], M["steel"], z=GLYPH_Z + 0.03)
    poly([(-0.035, 0.5), (0.075, 0.5), (0.075, 0.8), (-0.035, 0.8)], M["wood"], z=GLYPH_Z + 0.03)


def g_leap_slam():
    pts = arc(0.02, -0.55, 0.62, math.radians(165), math.radians(28), 22)
    tube(pts, 0.05, M["white"], radii=[0.4 + 0.6 * math.sin(math.pi * i / 21) for i in range(22)])
    end = pts[-1]
    a = math.atan2(end[1] - pts[-2][1], end[0] - pts[-2][0])
    poly(xf([(0.0, 0.16), (0.14, -0.06), (-0.14, -0.06)], end[0], end[1], a - math.pi / 2), M["white"])
    impact(0.52, -0.42, 0.3, "orange", n=8)
    impact(0.52, -0.42, 0.16, "yellow", n=8, z=GLYPH_Z + 0.02)
    # little figure mid-leap (sword raised)
    sword(-0.22, 0.2, math.radians(20), length=0.62, w=0.1)


def g_whirlwind():
    for k in range(3):
        a0 = math.radians(90 + k * 120)
        poly(crescent(0, 0, 0.44, a0, a0 + math.radians(105), 0.2, w_start=0.02), M["steel"], z=GLYPH_Z)
        tube(arc(0, 0, 0.62, a0 - math.radians(10), a0 + math.radians(70), 10), 0.022, M["white"], z=GLYPH_Z)
    poly(circle(0, 0, 0.14, 16), M["gold"], z=GLYPH_Z + 0.01)
    poly(circle(0, 0, 0.07, 12), M["wood_dark"], z=GLYPH_Z + 0.03, h=0.02, bevel=0.0)


def g_infernal_blow():
    flame(0.0, -0.62, 1.3, outer="red", inner="orange", core="yellow")
    sword(0.0, 0.05, math.radians(180), length=1.25, w=0.17)


def g_war_cry():
    # horn on the left
    horn = [(-0.72, -0.1), (-0.66, -0.2)] + arc(-0.3, 0.12, 0.42, math.radians(-120), math.radians(-40), 8) + \
           [(0.02, 0.2), (0.02, -0.26)] + arc(-0.3, 0.12, 0.24, math.radians(-50), math.radians(-120), 6)
    poly(horn, M["horn"])
    poly([(0.0, 0.24), (0.1, 0.28), (0.1, -0.3), (0.0, -0.28)], M["gold"], z=GLYPH_Z + 0.01)
    for k, r in enumerate((0.3, 0.48, 0.66)):
        ring(0.02, -0.01, r, 0.075 - k * 0.01, M["red"] if k != 1 else M["orange"], a0=math.radians(-48), a1=math.radians(48))


def g_power_shot():
    ang = math.radians(35)
    for (off, ln) in ((0.14, 0.42), (-0.14, 0.34), (0.0, 0.55)):
        a = (-0.72 + math.cos(ang + math.pi / 2) * off, -0.5 + math.sin(ang + math.pi / 2) * off)
        b = (a[0] + math.cos(ang) * ln, a[1] + math.sin(ang) * ln)
        tube([a, b], 0.022, M["white"], z=GLYPH_Z - 0.02)
    arrow(-0.45, -0.3, 0.66, 0.46, shaft=0.07, head_len=0.34, head_w=0.32, fletch_len=0.3, fletch_w=0.13)
    impact(0.66, 0.46, 0.2, "yellow", n=6, z=GLYPH_Z - 0.03)


def g_split_arrow():
    for a in (-38, 0, 38):
        ang = math.radians(90 + a)
        x0, y0 = 0.0 - 0.52 * math.cos(ang) * 0.0, -0.62
        x1, y1 = x0 + 1.18 * math.cos(ang), y0 + 1.18 * math.sin(ang)
        arrow(x0 + 0.2 * math.cos(ang), y0 + 0.2 * math.sin(ang), x1, y1, shaft=0.05, head_len=0.24, head_w=0.22,
              fletch_len=0.2, fletch_w=0.09)
    poly(circle(0.0, -0.6, 0.08, 12), M["gold"], z=GLYPH_Z + 0.02)


def g_rain_of_arrows():
    poly([(-0.7, -0.5), (0.7, -0.5), (0.6, -0.62), (-0.6, -0.62)], M["ground"], z=GLYPH_Z - 0.03)
    for (x, top, bot) in ((-0.42, 0.58, -0.28), (-0.14, 0.72, -0.1), (0.14, 0.6, -0.4), (0.42, 0.7, -0.2)):
        arrow(x, top, x, bot, shaft=0.045, head_len=0.2, head_w=0.19, fletch_len=0.18, fletch_w=0.08)


def g_explosive_bolt():
    impact(0.3, 0.28, 0.46, "orange", n=10, inner=0.5)
    impact(0.3, 0.28, 0.28, "yellow", n=10, inner=0.5, z=GLYPH_Z + 0.02)
    poly(circle(0.3, 0.28, 0.1, 12), M["fire_core"], z=GLYPH_Z + 0.04, h=0.02)
    bolt_proj(-0.62, -0.56, 0.18, 0.16, w=0.1)


def g_scatter_shot():
    for k, a in enumerate((-36, -18, 0, 18, 36)):
        ang = math.radians(a)
        ln = 0.95 if k % 2 == 0 else 0.78
        x0, y0 = -0.55, 0.0
        x1, y1 = x0 + ln * math.cos(ang), y0 + ln * math.sin(ang)
        tube([(x0 + 0.25 * math.cos(ang), y0 + 0.25 * math.sin(ang)), (x1 - 0.1 * math.cos(ang), y1 - 0.1 * math.sin(ang))],
             0.018, M["white"], z=GLYPH_Z - 0.02)
        poly(xf([(-0.075, -0.07), (0.0, 0.1), (0.075, -0.07)], x1, y1, ang - math.pi / 2), M["steel"])
    poly([(-0.72, -0.12), (-0.5, -0.1), (-0.5, 0.1), (-0.72, 0.12)], M["wood_dark"])
    poly(circle(-0.5, 0.0, 0.1, 12), M["gold"], z=GLYPH_Z + 0.01)


def g_rapid_fire():
    for k in range(3):
        dx = -0.12 + k * 0.1
        dy = 0.36 - k * 0.36
        tube([(-0.72 + dx, dy), (-0.36 + dx, dy)], 0.02, M["white"], z=GLYPH_Z - 0.02)
        bolt_proj(-0.3 + dx, dy, 0.62 + dx * 0.4, dy, w=0.085)


def g_ice_shot():
    snowflake(0.42, 0.42, 0.3, w=0.07)
    arrow(-0.62, -0.62, 0.36, 0.36, shaft=0.06, head="ice_light", shaft_mat="ice_deep", fletch="ice",
          head_len=0.3, head_w=0.28)


def g_venom_arrow():
    for (x, y, r) in ((0.3, -0.36, 0.3), (0.02, -0.46, 0.2), (0.52, -0.12, 0.2), (0.12, -0.2, 0.18)):
        poly(circle(x, y, r, 20), M["chaos_dark"], z=GLYPH_Z - 0.04, h=0.03)
    for (x, y, r) in ((0.36, -0.3, 0.14), (0.06, -0.42, 0.08), (0.5, -0.1, 0.08)):
        poly(circle(x, y, r, 14), M["chaos"], z=GLYPH_Z - 0.02, h=0.02, bevel=0.0)
    arrow(-0.64, 0.64, 0.16, -0.16, shaft=0.065, head="poison", fletch="poison_dark", head_len=0.3, head_w=0.3)
    drop(-0.08, -0.5, 0.075, M["poison"], ang=0.0)
    drop(0.3, -0.62, 0.06, M["poison"])


def g_fireball():
    tail = [(0.2, 0.34), (-0.28, 0.72), (-0.1, 0.36), (-0.72, 0.55), (-0.2, 0.12), (-0.66, 0.0), (0.0, -0.1)]
    poly(xf(tail, 0.05, -0.05, math.radians(-10)), M["red"], z=GLYPH_Z - 0.02)
    poly(xf([(0.1, 0.3), (-0.35, 0.5), (-0.12, 0.2), (-0.46, 0.08), (0.02, 0.0)], 0.05, -0.05, math.radians(-10)),
         M["orange"], z=GLYPH_Z - 0.01)
    poly(circle(0.24, -0.16, 0.34, 26), M["orange"], z=GLYPH_Z)
    poly(circle(0.28, -0.2, 0.23, 22), M["yellow"], z=GLYPH_Z + 0.02, h=0.03)
    poly(circle(0.3, -0.22, 0.12, 16), M["fire_core"], z=GLYPH_Z + 0.04, h=0.03)


def g_ice_spear():
    ang = math.radians(-45)
    body = [(0.0, 0.82), (0.13, 0.35), (0.11, -0.45), (0.0, -0.78), (-0.11, -0.45), (-0.13, 0.35)]
    poly(xf(body, 0.0, 0.0, ang), M["ice"])
    poly(xf([(0.0, 0.8), (0.07, 0.35), (0.0, -0.7)], 0.0, 0.0, ang), M["ice_light"], z=GLYPH_Z + 0.02, h=0.02, bevel=0.0)
    for s in (-1, 1):
        shard = [(s * 0.08, -0.25), (s * 0.34, -0.62), (s * 0.12, -0.5)]
        poly(xf(shard, 0.0, 0.0, ang), M["ice_deep"], z=GLYPH_Z - 0.01)


def g_frost_nova():
    ring(0, 0, 0.66, 0.08, M["ice"])
    for k in range(12):
        a = k * math.pi / 6
        poly(xf([(-0.05, 0.62), (0.05, 0.62), (0.0, 0.78)], 0, 0, a), M["ice"], z=GLYPH_Z)
    snowflake(0, 0, 0.44, w=0.085)
    poly(circle(0, 0, 0.1, 6, math.pi / 2), M["ice_light"], z=GLYPH_Z + 0.02)


def g_chain_lightning():
    nodes = [(-0.58, 0.4), (0.02, 0.1), (-0.22, -0.52), (0.55, -0.3)]
    paths = [[(-0.58, 0.4), (-0.36, 0.34), (-0.3, 0.2), (-0.12, 0.16), (0.02, 0.1)],
             [(0.02, 0.1), (-0.02, -0.08), (-0.16, -0.14), (-0.12, -0.34), (-0.22, -0.52)],
             [(-0.22, -0.52), (0.02, -0.44), (0.12, -0.3), (0.34, -0.36), (0.55, -0.3)]]
    for p in paths:
        lightning(p, 0.13)
    for (x, y) in nodes:
        poly(circle(x, y, 0.1, 14), M["yellow"], z=GLYPH_Z + 0.02)
        poly(circle(x, y, 0.05, 10), M["bolt_core"], z=GLYPH_Z + 0.04, h=0.02)
    lightning([(0.2, 0.7), (0.28, 0.52), (0.18, 0.46), (0.3, 0.26), (0.02, 0.1)], 0.16)


def g_teleport():
    pts = []
    for i in range(60):
        t = i / 59
        r = 0.08 + 0.55 * t
        a = 4.2 * math.pi * t
        pts.append((r * math.cos(a), r * math.sin(a)))
    tube(pts, 0.05, M["teal"], radii=[0.5 + 0.9 * (i / 59) for i in range(60)])
    for (x, y, s) in ((0.5, 0.52, 0.16), (-0.56, -0.44, 0.12), (0.58, -0.42, 0.1), (-0.48, 0.5, 0.09)):
        poly(star(x, y, s, s * 0.3, 4), M["white"], z=GLYPH_Z + 0.02)
    poly(circle(0, 0, 0.12, 14), M["white"], z=GLYPH_Z + 0.02)


def g_spark():
    poly(circle(0, 0, 0.2, 18), M["yellow"])
    poly(circle(0, 0, 0.11, 14), M["bolt_core"], z=GLYPH_Z + 0.02, h=0.02)
    for k in range(5):
        a = math.pi / 2 + k * 2 * math.pi / 5
        c, s = math.cos(a), math.sin(a)
        n_ = (-s, c)
        p = []
        for i, t in enumerate((0.26, 0.4, 0.52, 0.66, 0.78)):
            j = 0.07 * (1 if i % 2 else -1)
            p.append((c * t + n_[0] * j, s * t + n_[1] * j))
        lightning(p, 0.1)


def g_meteor():
    tail = [(0.74, 0.74), (0.62, 0.3), (0.52, 0.42), (0.2, -0.05), (-0.1, -0.2), (-0.2, 0.1), (0.3, 0.52), (0.4, 0.62)]
    poly(tail, M["orange"], z=GLYPH_Z - 0.02)
    poly([(0.56, 0.6), (0.4, 0.3), (0.06, 0.0), (0.0, 0.12), (0.3, 0.44)], M["yellow"], z=GLYPH_Z - 0.01)
    rock = circle(-0.2, -0.22, 0.34, 9, 0.3)
    rock = [(x + 0.03 * math.sin(7 * i), y + 0.03 * math.cos(5 * i)) for i, (x, y) in enumerate(rock)]
    poly(rock, M["rock"], z=GLYPH_Z)
    for (x, y) in ((-0.28, -0.12), (-0.12, -0.3), (-0.3, -0.36)):
        poly(star(x, y, 0.07, 0.03, 4, 0.3), M["orange"], z=GLYPH_Z + 0.015, h=0.02, bevel=0.0)
    poly(arc(-0.2, -0.22, 0.34, math.radians(10), math.radians(100), 10) + arc(-0.2, -0.22, 0.26, math.radians(100), math.radians(10), 10),
         M["yellow"], z=GLYPH_Z + 0.01, h=0.02, bevel=0.0)


def g_blood_rite():
    ring(0, 0, 0.64, 0.07, M["chaos"])
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        c = (0.64 * math.cos(a), 0.64 * math.sin(a))
        poly(xf([(-0.07, -0.07), (0.07, -0.07), (0.07, 0.07), (-0.07, 0.07)], c[0], c[1], a + math.pi / 4), M["chaos"], z=GLYPH_Z + 0.01)
    tri = [(0.0, 0.5), (-0.44, -0.26), (0.44, -0.26)]
    for i in range(3):
        a = tri[i]
        b = tri[(i + 1) % 3]
        tube([a, b], 0.022, M["chaos"], z=GLYPH_Z - 0.02)
    drop(0.0, -0.18, 0.24, M["blood"])
    poly(circle(-0.07, -0.08, 0.06, 10), M["blood_light"], z=GLYPH_Z + 0.02, h=0.02, bevel=0.0)


GLYPHS = {name[2:]: fn for name, fn in globals().items() if name.startswith("g_") and callable(fn)}


def build_icon(skill_id):
    """Build and render one icon; returns the final PNG path."""
    if skill_id not in GLYPHS:
        raise KeyError("no glyph for skill " + skill_id)
    setup_render()
    _mats()
    badge(SKILL_CATEGORY[skill_id])
    GLYPHS[skill_id]()
    tmp_dir = os.path.join(L.SKILL_ICONS_DIR, ".tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    tmp = os.path.join(tmp_dir, skill_id + ".png")
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    final = os.path.join(L.SKILL_ICONS_DIR, skill_id + ".png")
    os.replace(tmp, final)
    try:
        os.rmdir(tmp_dir)   # only succeeds when empty (this .tmp dir belongs to this module alone)
    except OSError:
        pass
    return final
