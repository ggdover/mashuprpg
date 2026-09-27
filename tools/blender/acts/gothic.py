"""Act III — the gothic town (gothic_* models): dark-stone townhouses with steep slate roofs,
pinnacles and pointed-arch windows (many lit warm), the great cathedral, a clock tower, double-
lantern street lamps, wrought-iron fences, gate pillars, balustrades, a black carriage, coffins,
graves, hooded statues, dead trees, a fountain, the merchant's stall, the lantern shrine (act
waystone) and cobblestone floor tiles.

Reference: the user's gothic town images (Yharnam / Irithyll): dark blue-grey stone, slate, black
iron, warm windows and lamps against cold moonlight and teal fog, pale snow on ridges.

Blender axes: Z up, fronts face -Y (= Godot +Z). Origin at the base centre (floor tiles: centred,
top at z = 0). Built with envlib.MeshBuilder in world coordinates (identity transforms).
OWNER: acts-gothic.
"""

import math
import random

from mathutils import Vector

import envlib as L
from envlib import MeshBuilder
import town
from town import Face

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

L.PALETTE.update({
    "go_stone": dict(hex="#50545e", rough=0.88),
    "go_stone_b": dict(hex="#454953", rough=0.9),
    "go_stone_dark": dict(hex="#30333a", rough=0.92),
    "go_stone_light": dict(hex="#7e838c", rough=0.85),
    "go_stone_pale": dict(hex="#a5a8aa", rough=0.85),
    "go_slate": dict(hex="#283039", rough=0.5),
    "go_slate_b": dict(hex="#20262e", rough=0.55),
    "go_iron": dict(hex="#17181c", rough=0.45, metal=0.5),
    "go_iron_rust": dict(hex="#3b2d27", rough=0.7, metal=0.2),
    "go_wood": dict(hex="#3d2f27", rough=0.8),
    "go_wood_dark": dict(hex="#241c19", rough=0.85),
    "go_cloth": dict(hex="#4e1b1f", rough=0.9),
    "go_cloth_dark": dict(hex="#2b1517", rough=0.9),
    "go_gold": dict(hex="#8e6f3b", rough=0.45, metal=0.6),
    "go_glass_dark": dict(hex="#131923", rough=0.2),
    "go_snow": dict(hex="#c7d0da", rough=0.9),
    "go_water": dict(hex="#1b313a", rough=0.06),
    "go_bark": dict(hex="#2c2623", rough=0.95),
    "go_bark_b": dict(hex="#3a322d", rough=0.95),
    "go_window": dict(hex="#ffb266", emit="#ff9a40", strength=2.4, rough=0.5),
    "go_window_dim": dict(hex="#d98a4a", emit="#c4652a", strength=1.1, rough=0.5),
    "go_lamp": dict(hex="#ffd9a0", emit="#ffb860", strength=7.0, rough=0.4),
    "go_candle": dict(hex="#fff0c8", emit="#ffd080", strength=5.0, rough=0.5),
    "go_rose": dict(hex="#bfe4ee", emit="#8fd0e6", strength=2.2, rough=0.4),
    "go_clock": dict(hex="#efe2b0", emit="#ffe39a", strength=2.6, rough=0.4),
    "go_blood": dict(hex="#7a1016", emit="#9a0c14", strength=1.6, rough=0.3),
    "go_blood_pool": dict(hex="#5e0b10", emit="#4a0509", strength=0.5, rough=0.12),
    "go_puddle": dict(hex="#1b232d", emit="#34485e", strength=0.32, rough=0.04),
    "go_void": dict(hex="#040507", rough=1.0),
    "go_snow_dim": dict(hex="#8e9aa7", rough=0.95),
    "go_rope": dict(hex="#5b4a35", rough=0.95),
    "go_ember": dict(hex="#ff5a2a", emit="#ff3a14", strength=4.0, rough=0.6),
    # floor tiles: tintable (the generator tints the streets)
    "tint_go_cobble": dict(lin=(0.8, 0.8, 0.8), rough=0.4),
    "tint_go_cobble_b": dict(lin=(0.6, 0.6, 0.6), rough=0.45),
    "tint_go_mortar": dict(lin=(0.2, 0.2, 0.2), rough=0.95),
})


# ----------------------------------------------------------------------------------- helpers

def lancet(uc, v0, w, h, n=5):
    """Pointed (equilateral) arch outline, CCW in (u, v): bottom at v0, total height h, span w."""
    r = w
    rise = r * math.sin(math.radians(60.0))
    s = v0 + max(h - rise, 0.05)
    pts = [(uc - w / 2, v0), (uc + w / 2, v0), (uc + w / 2, s)]
    cx = uc - w / 2
    for i in range(1, n + 1):
        t = math.radians(60.0 * i / n)
        pts.append((cx + r * math.cos(t), s + r * math.sin(t)))
    cx = uc + w / 2
    for i in range(1, n):
        t = math.radians(120.0 + 60.0 * i / n)
        pts.append((cx + r * math.cos(t), s + r * math.sin(t)))
    return pts


def lancet_window(mb, f, uc, v0, w, h, lit, frame="go_stone_light", sill=True):
    """Pointed window: stone surround, glass (lit or dark), mullion, transom, sill."""
    f.prism(mb, lancet(uc, v0 - 0.08, w + 0.26, h + 0.2), -0.02, 0.06, frame)
    f.prism(mb, lancet(uc, v0, w, h), -0.01, 0.085, "go_window" if lit else "go_glass_dark")
    if w > 0.45:
        f.box(mb, uc, v0 + h * 0.4, 0.06, h * 0.8, 0.07, 0.11, frame)
        f.box(mb, uc, v0 + h * 0.52, w, 0.05, 0.07, 0.11, frame)
    if sill:
        f.box(mb, uc, v0 - 0.12, w + 0.42, 0.1, -0.02, 0.17, frame)


def pointed_door(mb, f, uc, v0, w, h, glow=False):
    """Pointed-arch door with a stone surround, dark leaf with iron straps (or a warm glow)."""
    f.prism(mb, lancet(uc, v0, w + 0.44, h + 0.28), -0.02, 0.1, "go_stone_light")
    f.prism(mb, lancet(uc, v0, w, h), -0.01, 0.14, "go_window_dim" if glow else "go_wood_dark")
    if not glow:
        for vv in (0.3, 0.62):
            f.box(mb, uc, v0 + h * vv, w * 0.86, 0.07, 0.13, 0.17, "go_iron")
        f.box(mb, uc, v0 + h * 0.42, 0.04, h * 0.8, 0.13, 0.16, "go_wood")


def pinnacle(mb, x, y, z0, s=0.36, h=1.6, mat="go_stone_light", cap="go_slate"):
    """Small gothic pinnacle: square shaft, gablets and a spike with a ball finial."""
    mb.box((x, y, z0 + 0.35), (s, s, 0.7), mat)
    mb.box((x, y, z0 + 0.74), (s + 0.08, s + 0.08, 0.08), mat)
    mb.cyl((x, y, z0 + 0.78 + h / 2), s * 0.62, 0.0, h, cap, segs=4, twist=math.pi / 4)
    mb.ico((x, y, z0 + 0.82 + h), 0.07, "go_iron", subdiv=0)


def cresting(mb, x0, x1, y, z, step=0.55):
    """Iron cresting along a ridge (a rail with small spikes) in X."""
    mb.box(((x0 + x1) / 2, y, z + 0.05), (x1 - x0, 0.05, 0.1), "go_iron")
    n = max(2, int((x1 - x0) / step))
    for k in range(n + 1):
        x = x0 + (x1 - x0) * k / n
        mb.cyl((x, y, z + 0.25), 0.05, 0.0, 0.34, "go_iron", segs=4)


def front_face(w, d):
    return town.box_faces(w, d)


# ----------------------------------------------------------------------------------- floor tiles

def _cobble(name, seed, rows, len_range, dome):
    """2 x 2 m tile (top at z = 0): dark mortar bed with staggered rows of setts."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    mb.box((0, 0, -0.07), (2.0, 2.0, 0.1), "tint_go_mortar")
    gap = 0.05
    rh = 2.0 / rows
    for r in range(rows):
        y = -1.0 + rh * (r + 0.5)
        x = -1.0 + gap / 2
        first = True
        while x < 1.0 - gap / 2 - 0.06:
            ln = rng.uniform(*len_range)
            if first:
                ln *= rng.uniform(0.35, 1.0)
                first = False
            x1 = min(x + ln, 1.0 - gap / 2)
            if 1.0 - gap / 2 - x1 < 0.14:
                x1 = 1.0 - gap / 2
            top = -rng.uniform(0.0, 0.012)
            h = 0.06
            mat = "tint_go_cobble" if rng.random() < 0.62 else "tint_go_cobble_b"
            mb.box(((x + x1) / 2, y + rng.uniform(-0.01, 0.01), top - h / 2), (x1 - x - gap, rh - gap, h), mat,
                   taper=(dome, dome))
            x = x1
    mb.finish(name)


def _cobble_lo(name, seed, rows, len_range):
    """2 x 2 m tile with few triangles (the zones' big streets): mortar bed, rows of flat-topped
    setts (open at the bottom, sunk into the bed)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    mb.box((0, 0, -0.07), (2.0, 2.0, 0.1), "tint_go_mortar")
    gap = 0.06
    rh = 2.0 / rows
    for r in range(rows):
        y0 = -1.0 + rh * r + gap / 2
        y1 = -1.0 + rh * (r + 1) - gap / 2
        x = -1.0 + gap / 2
        first = True
        while x < 1.0 - gap / 2 - 0.08:
            ln = rng.uniform(*len_range)
            if first:
                ln *= rng.uniform(0.4, 1.0)
                first = False
            x1 = min(x + ln, 1.0 - gap / 2)
            if 1.0 - gap / 2 - x1 < 0.2:
                x1 = 1.0 - gap / 2
            top = -rng.uniform(0.0, 0.012)
            mat = "tint_go_cobble" if rng.random() < 0.62 else "tint_go_cobble_b"
            mb.prism([(x, y0), (x1 - gap, y0), (x1 - gap, y1), (x, y1)], -0.05, top, mat, cap_bottom=False)
            x = x1
    mb.finish(name)


def build_gothic_cobble_c():
    _cobble_lo("gothic_cobble_c", 31, 4, (0.42, 0.62))


def build_gothic_cobble_d():
    _cobble_lo("gothic_cobble_d", 37, 5, (0.4, 0.66))


def build_gothic_cobble_a():
    _cobble("gothic_cobble_a", 11, 6, (0.26, 0.42), 0.8)


def build_gothic_cobble_b():
    _cobble("gothic_cobble_b", 23, 5, (0.3, 0.52), 0.84)


# ----------------------------------------------------------------------------------- houses

def _house(name, w, d, eave, ridge, seed, *, gable_front=False, turret=False, dormers=2, shop=False,
           storey=2.7, lit=0.55):
    rng = random.Random(seed)
    mb = MeshBuilder()
    base = 0.45
    mb.box((0, 0, base / 2), (w + 0.24, d + 0.24, base), "go_stone_dark", bevel=0.03)
    mb.box((0, 0, (base + eave) / 2), (w, d, eave - base), "go_stone")
    # string courses and cornice
    z = base + storey
    while z < eave - 0.6:
        mb.box((0, 0, z), (w + 0.14, d + 0.14, 0.14), "go_stone_light")
        z += storey
    mb.box((0, 0, eave - 0.08), (w + 0.3, d + 0.3, 0.22), "go_stone_light")
    # corner pilasters
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (w / 2 - 0.1), sy * (d / 2 - 0.1), (base + eave) / 2), (0.44, 0.44, eave - base + 0.1), "go_stone_b")
    faces = front_face(w, d)
    fr, rt, bk, lf = faces["front"], faces["right"], faces["back"], faces["left"]
    # roof
    if gable_front:
        hs = w / 2 + 0.35
        town.gable_roof_y(mb, d + 0.5, hs, eave, ridge, 0.24, "go_slate")
        apex = ridge - 0.3
        mb.prism([(-w / 2, eave - 0.01), (w / 2, eave - 0.01), (0, apex)], -d, 0.0, "go_stone",
                 frame=(Vector((0, -d / 2, 0)), X, Z, -Y))
        town.shingle_rows(mb, d + 0.54, hs, eave, ridge, ["go_slate", "go_slate_b"], rows=4, th=0.08,
                          delta_deg=4.0, axis="y")
        # snow on the ridge
        mb.box((0, 0, ridge + 0.02), (0.34, d + 0.5, 0.14), "go_snow")
        # tall gable window + finial
        lancet_window(mb, fr, 0.0, eave + 0.3, 0.9, (apex - eave) * 0.62, rng.random() < lit)
        pinnacle(mb, 0.0, -d / 2 - 0.05, ridge - 0.25, s=0.3, h=1.3)
        for sx in (-1, 1):
            pinnacle(mb, sx * (w / 2 - 0.05), -d / 2 + 0.05, eave, s=0.34, h=1.5)
            pinnacle(mb, sx * (w / 2 - 0.05), d / 2 - 0.05, eave, s=0.34, h=1.3)
    else:
        hs = d / 2 + 0.35
        z_in = town.gable_roof_x(mb, w + 0.5, hs, eave, ridge, 0.24, "go_slate")
        apex = z_in(0) + 0.02
        mb.prism([(-d / 2, eave - 0.01), (d / 2, eave - 0.01), (0, apex)], -w / 2, w / 2, "go_stone",
                 frame=(Vector((0, 0, 0)), Y, Z, X))
        town.shingle_rows(mb, w + 0.54, hs, eave, ridge, ["go_slate", "go_slate_b"], rows=4, th=0.08, delta_deg=4.0)
        mb.box((0, 0, ridge + 0.02), (w + 0.5, 0.34, 0.14), "go_snow")
        cresting(mb, -w / 2 + 0.3, w / 2 - 0.3, 0.0, ridge + 0.08)
        for sx in (-1, 1):
            for sy in (-1, 1):
                pinnacle(mb, sx * (w / 2 - 0.05), sy * (d / 2 - 0.05), eave, s=0.34, h=1.5)
        # side gable windows
        for f in (rt, lf):
            lancet_window(mb, f, 0.0, eave + 0.3, 0.55, (apex - eave) * 0.55, rng.random() < lit * 0.8)
        # dormers on the front slope
        H = ridge - eave
        for k in range(dormers):
            dx = (k - (dormers - 1) / 2) * (w * 0.46)
            yf = -hs * 0.66
            zf = eave + H * (1 - 0.66)
            mb.box((dx, yf + 0.8, zf + 0.45), (1.1, 1.6, 1.5), "go_stone")
            mb.prism([(-0.72, zf + 1.18), (0.72, zf + 1.18), (0.0, zf + 1.95)], 0.0, 1.7, "go_slate",
                     frame=(Vector((dx, yf - 0.12, 0)), -X, Z, Y))
            df = Face((dx, yf, 0), X, Z, -Y)
            lancet_window(mb, df, 0.0, zf - 0.05, 0.5, 0.95, rng.random() < lit, sill=False)
            mb.cyl((dx, yf - 0.1, zf + 2.2), 0.08, 0.0, 0.5, "go_iron", segs=4)
    # chimneys
    for (cx, cy) in ((-w * 0.3, d * 0.22), (w * 0.34, d * 0.3)):
        top = ridge + 0.4 if not gable_front else ridge - 0.2
        town.chimney(mb, cx, cy, eave - 0.5, top, "go_stone_dark", "go_stone_light")
    # front facade: door + ground floor windows (or a shop front), upper storeys lancets
    if shop:
        fr.box(mb, -0.9, base + 1.05, 2.4, 1.7, -0.02, 0.12, "go_wood_dark")
        fr.box(mb, -0.9, base + 1.05, 2.0, 1.3, 0.0, 0.16, "go_window")
        for k in range(3):
            fr.box(mb, -1.55 + k * 0.65, base + 1.05, 0.06, 1.3, 0.16, 0.2, "go_wood_dark")
        fr.box(mb, -0.9, base + 2.15, 2.6, 0.34, -0.02, 0.2, "go_wood")
        fr.box(mb, -0.9, base + 2.15, 1.6, 0.18, 0.2, 0.23, "go_gold")
        pointed_door(mb, fr, 1.45, base, 0.95, 2.2, glow=rng.random() < 0.3)
    else:
        pointed_door(mb, fr, 0.0, base, 1.05, 2.3, glow=rng.random() < 0.25)
        for sx in (-1, 1):
            lancet_window(mb, fr, sx * (w * 0.32), base + 0.75, 0.62, 1.35, rng.random() < lit)
    # steps
    fr.box(mb, 1.45 if shop else 0.0, base * 0.5, 1.6, base, 0.0, 0.5, "go_stone_dark", bevel=0.02)
    z = base + storey + 0.55
    while z + 1.7 < eave:
        for sx in (-1, 1):
            lancet_window(mb, fr, sx * (w * 0.24), z, 0.66, 1.55, rng.random() < lit)
        z += storey
    # side and back windows
    for f, half in ((rt, d / 2), (lf, d / 2), (bk, w / 2)):
        z = base + 0.8
        while z + 1.6 < eave:
            for uc in ((-half * 0.45, half * 0.45) if half > 2.2 else (0.0,)):
                lancet_window(mb, f, uc, z, 0.56, 1.4, rng.random() < lit * 0.7)
            z += storey
    # turret on the front-right corner
    if turret:
        tx, ty = w / 2 - 0.15, -d / 2 + 0.15
        top = eave + 1.4
        mb.cyl((tx, ty, (base + 1.2 + top) / 2), 0.95, 0.95, top - base - 1.2, "go_stone", segs=8)
        mb.cyl((tx, ty, base + 0.9), 0.3, 0.95, 0.6, "go_stone_light", segs=8)
        mb.cyl((tx, ty, top + 0.1), 1.08, 1.08, 0.2, "go_stone_light", segs=8)
        mb.cyl((tx, ty, top + 2.8), 1.06, 0.0, 5.2, "go_slate", segs=8)
        mb.ico((tx, ty, top + 5.5), 0.1, "go_gold", subdiv=0)
        mb.cyl((tx, ty, top + 5.9), 0.03, 0.03, 0.7, "go_iron", segs=4)
        for a_deg, zz in ((-60, eave - 2.2), (-120, eave - 2.2), (-90, eave - 4.8)):
            a = math.radians(a_deg)
            c = Vector((tx + math.cos(a) * 0.92, ty + math.sin(a) * 0.92, zz))
            mb.obox(c + Vector((0, 0, 0.6)), (Vector((-math.sin(a), math.cos(a), 0)), Z, Vector((math.cos(a), math.sin(a), 0))),
                    (0.36, 1.1, 0.12), "go_window" if rng.random() < 0.7 else "go_glass_dark")
    mb.finish(name)


def build_gothic_house_a():
    """Three-storey townhouse, slate gable roof along the street, two dormers, pinnacles."""
    _house("gothic_house_a", 5.2, 5.0, 8.4, 12.6, 101, dormers=2)


def build_gothic_house_b():
    """Townhouse with a corner turret and conical spire, shop front on the ground floor."""
    _house("gothic_house_b", 5.2, 5.0, 7.6, 11.6, 202, turret=True, dormers=1, shop=True)


def build_gothic_house_c():
    """Gable-fronted townhouse: tall pointed gable window, pinnacles on the gable corners."""
    _house("gothic_house_c", 5.2, 5.0, 7.0, 13.0, 303, gable_front=True)


def build_gothic_house_d():
    """Narrow gable-fronted house (2 x 3 cells), for gaps in the street rows."""
    _house("gothic_house_d", 3.4, 5.0, 8.0, 12.8, 404, gable_front=True, lit=0.6)


# ----------------------------------------------------------------------------------- cathedral

def build_gothic_cathedral():
    """The great cathedral (~30 x 17 m, spires to ~40 m): twin towers with octagonal spires, a
    rose window, three glowing portals, buttresses and pinnacles. Front (south) at y = -8.5."""
    rng = random.Random(7)
    mb = MeshBuilder()
    fy = -8.0          # facade plane (towers and screen stand a little in front)
    # front steps
    mb.box((0, fy - 0.95, 0.08), (22.0, 1.3, 0.16), "go_stone_dark", bevel=0.02)
    mb.box((0, fy - 0.6, 0.24), (21.0, 0.9, 0.18), "go_stone_b", bevel=0.02)
    # nave + roof + attic
    mb.box((0, 0.5, 8.5), (12.0, 15.0, 17.0), "go_stone")
    town.gable_roof_y(mb, 15.8, 6.6, 17.0, 27.0, 0.4, "go_slate")
    mb.prism([(-6.0, 16.98), (6.0, 16.98), (0.0, 26.5)], 0.0, 15.2, "go_stone", frame=(Vector((0, -7.0, 0)), -X, Z, Y))
    town.shingle_rows(mb, 15.9, 6.6, 17.0, 27.0, ["go_slate", "go_slate_b"], rows=6, th=0.12, delta_deg=4.0, axis="y")
    mb.box((0, 0.5, 27.05), (0.4, 15.6, 0.16), "go_snow")
    # crossing fleche
    mb.box((0, 3.5, 27.5), (1.6, 1.6, 2.2), "go_stone_light")
    mb.cyl((0, 3.5, 32.0), 0.9, 0.0, 7.0, "go_slate", segs=8)
    mb.ico((0, 3.5, 35.6), 0.18, "go_gold", subdiv=0)
    # aisles with lean-to roofs, clerestory windows, flying buttresses
    for sx in (-1, 1):
        mb.box((sx * 8.5, 1.5, 5.0), (5.0, 13.0, 10.0), "go_stone_b")
        mb.prism([(0.0, 10.0), (5.3, 10.0), (0.0, 13.2)], -8.2 if sx > 0 else -5.2, 5.2 if sx > 0 else 8.2, "go_slate",
                 frame=(Vector((sx * 6.0, 0, 0)), Vector((sx, 0, 0)), Z, Vector((0, -sx, 0))))
        side = Face((sx * 6.0, 0, 0), Vector((0, sx, 0)), Z, Vector((sx, 0, 0)))
        aisle = Face((sx * 11.0, 0, 0), Vector((0, sx, 0)), Z, Vector((sx, 0, 0)))
        for k in range(4):
            yy = -4.0 + k * 3.6
            lancet_window(mb, side, sx * yy, 13.4, 1.1, 3.0, rng.random() < 0.6)
            lancet_window(mb, aisle, sx * yy, 3.0, 1.0, 3.6, rng.random() < 0.55)
            # buttress pier + flying buttress
            px = sx * 11.6
            mb.box((px, yy + 1.8, 6.5), (1.2, 0.9, 13.0), "go_stone_b")
            pinnacle(mb, px, yy + 1.8, 13.0, s=0.7, h=2.4)
            a = Vector((px - sx * 0.4, yy + 1.8, 12.2))
            b = Vector((sx * 6.2, yy + 1.8, 15.6))
            d = (b - a)
            mb.obox((a + b) / 2, (d.normalized(), Y, d.normalized().cross(Y)), (d.length, 0.5, 0.45), "go_stone_light")
    # twin towers
    for sx in (-1, 1):
        cx = sx * 10.5
        mb.box((cx, fy + 2.8, 13.0), (7.0, 6.4, 26.0), "go_stone")
        for zz in (6.5, 13.0, 19.5):
            mb.box((cx, fy + 2.8, zz), (7.2, 6.6, 0.22), "go_stone_light")
        mb.box((cx, fy + 2.8, 26.0), (7.4, 6.8, 0.4), "go_stone_light")
        for bx in (-1, 1):
            for by in (-1, 1):
                mb.box((cx + bx * 3.45, fy + 2.8 + by * 3.15, 12.5), (0.9, 0.9, 25.0), "go_stone_b")
                pinnacle(mb, cx + bx * 3.45, fy + 2.8 + by * 3.15, 25.0, s=0.8, h=3.2)
        tf = Face((cx, fy - 0.4, 0), X, Z, -Y)
        pointed_door(mb, tf, 0.0, 0.42, 2.4, 5.2, glow=True)
        lancet_window(mb, tf, 0.0, 8.0, 1.4, 4.0, True)
        lancet_window(mb, tf, -1.3, 14.0, 0.8, 4.0, rng.random() < 0.5)
        lancet_window(mb, tf, 1.3, 14.0, 0.8, 4.0, rng.random() < 0.5)
        # belfry openings on the front and sides
        for (f, u) in ((tf, -1.4), (tf, 1.4)):
            f.prism(mb, lancet(u, 20.2, 1.4, 4.6), -0.02, 0.06, "go_stone_light")
            f.prism(mb, lancet(u, 20.3, 1.1, 4.3), -0.01, 0.09, "go_glass_dark")
        for f in (Face((cx + 3.5, fy + 2.8, 0), Y, Z, X), Face((cx - 3.5, fy + 2.8, 0), -Y, Z, -X)):
            lancet_window(mb, f, 0.0, 20.3, 1.2, 4.3, False)
            lancet_window(mb, f, 0.0, 9.0, 1.0, 3.6, rng.random() < 0.5)
        # octagonal spire with corner pinnacles
        mb.cyl((cx, fy + 2.8, 27.2), 3.2, 3.2, 2.0, "go_stone_b", segs=8, twist=math.pi / 8)
        mb.cyl((cx, fy + 2.8, 34.8), 3.0, 0.0, 13.4, "go_slate", segs=8, twist=math.pi / 8)
        mb.ico((cx, fy + 2.8, 41.6), 0.22, "go_gold", subdiv=0)
        mb.cyl((cx, fy + 2.8, 42.4), 0.06, 0.06, 1.4, "go_iron", segs=4)
        mb.box((cx, fy + 2.8, 42.6), (0.6, 0.08, 0.08), "go_iron")
    # central screen facade with the gable and rose window
    mb.box((0, fy - 0.2, 10.0), (14.0, 1.4, 20.0), "go_stone")
    mb.prism([(-7.0, 19.98), (7.0, 19.98), (0.0, 28.5)], -1.4, 0.0, "go_stone", frame=(Vector((0, fy - 0.9, 0)), X, Z, -Y))
    sf = Face((0, fy - 0.9, 0), X, Z, -Y)
    for zz in (10.4, 19.8):
        sf.box(mb, 0.0, zz, 14.0, 0.26, -0.02, 0.18, "go_stone_light")
    # rose window: disc, ring, tracery spokes, hub
    rc = 15.2
    ring = Vector((0, fy - 0.9, rc))
    mb.cyl(ring + Vector((0, -0.08, 0)), 3.5, 3.5, 0.2, "go_stone_light", segs=16, rot=(math.pi / 2, 0, 0))
    mb.cyl(ring + Vector((0, -0.2, 0)), 3.05, 3.05, 0.1, "go_rose", segs=16, rot=(math.pi / 2, 0, 0))
    for k in range(12):
        a = k * math.pi / 6
        c = ring + Vector((math.cos(a) * 1.6, -0.3, math.sin(a) * 1.6))
        mb.obox(c, (Vector((math.cos(a), 0, math.sin(a))), Vector((-math.sin(a), 0, math.cos(a))), Y), (2.9, 0.12, 0.12), "go_stone_light")
    mb.cyl(ring + Vector((0, -0.32, 0)), 0.55, 0.55, 0.14, "go_stone_light", segs=8, rot=(math.pi / 2, 0, 0))
    # gallery of niches
    for k in range(7):
        u = -5.4 + k * 1.8
        sf.prism(mb, lancet(u, 11.0, 1.1, 2.6), -0.02, 0.1, "go_stone_light")
        sf.prism(mb, lancet(u, 11.12, 0.8, 2.3), -0.01, 0.13, "go_glass_dark")
    # central portal with archivolts + glow, flanking statues
    for k, (ww, hh, mat) in enumerate(((5.6, 9.6, "go_stone_light"), (4.9, 8.9, "go_stone_b"), (4.2, 8.2, "go_stone_light"))):
        sf.prism(mb, lancet(0.0, 0.42, ww, hh), -0.02, 0.12 + k * 0.08, mat)
    sf.prism(mb, lancet(0.0, 0.42, 3.4, 7.2), -0.01, 0.4, "go_window_dim")
    sf.box(mb, 0.0, 0.42 + 2.4, 0.2, 4.8, 0.3, 0.48, "go_stone_light")
    sf.box(mb, 0.0, 0.42 + 4.9, 3.4, 0.24, 0.3, 0.48, "go_stone_light")
    for sx in (-1, 1):
        # buttresses on the screen corners
        mb.box((sx * 6.6, fy - 1.3, 11.0), (0.9, 1.4, 22.0), "go_stone_b")
        pinnacle(mb, sx * 6.6, fy - 1.3, 22.0, s=0.7, h=3.0)
        # statues on plinths by the portal
        px = sx * 4.3
        mb.box((px, fy - 1.5, 1.0), (1.0, 1.0, 2.0), "go_stone_b", bevel=0.03)
        _hooded_figure(mb, Vector((px, fy - 1.5, 2.0)), 1.0)
    # gable finial and pinnacles along the gable
    pinnacle(mb, 0.0, fy - 0.9, 28.2, s=0.6, h=2.6)
    mb.finish("gothic_cathedral")


def _hooded_figure(mb, base, s, mat="go_stone_pale", sword=True):
    """A hooded robed figure standing on `base` (height ~2.3 m * s)."""
    bx, by, bz = base
    mb.lathe([(0.0, 0.0), (0.46 * s, 0.0), (0.42 * s, 0.7 * s), (0.34 * s, 1.4 * s), (0.3 * s, 1.75 * s), (0.0, 1.8 * s)],
             mat, segs=8, center=(bx, by, bz))
    mb.box((bx, by, bz + 1.55 * s), (0.78 * s, 0.34 * s, 0.34 * s), mat)
    mb.ico((bx, by + 0.02 * s, bz + 2.0 * s), 0.3 * s, mat, subdiv=1, scale=(1.0, 1.05, 1.25))
    mb.ico((bx, by - 0.16 * s, bz + 1.93 * s), 0.17 * s, "go_stone_dark", subdiv=0, scale=(1.0, 0.6, 1.1))
    if sword:
        mb.box((bx, by - 0.42 * s, bz + 0.62 * s), (0.08 * s, 0.05 * s, 1.24 * s), "go_stone_light")
        mb.box((bx, by - 0.42 * s, bz + 1.26 * s), (0.46 * s, 0.07 * s, 0.07 * s), "go_stone_light")
        mb.box((bx, by - 0.42 * s, bz + 1.42 * s), (0.07 * s, 0.07 * s, 0.26 * s), "go_stone_light")


# ----------------------------------------------------------------------------------- clock tower

def build_gothic_clocktower():
    """Clock tower (6 x 6 m, ~40 m): buttressed shaft, lit clock faces on four sides, open
    belfry, octagonal spire with corner pinnacles."""
    rng = random.Random(9)
    mb = MeshBuilder()
    mb.box((0, 0, 0.3), (6.6, 6.6, 0.6), "go_stone_dark", bevel=0.03)
    mb.box((0, 0, 11.5), (5.6, 5.6, 22.0), "go_stone")
    for zz in (5.0, 10.5, 16.0, 21.8):
        mb.box((0, 0, zz), (5.8, 5.8, 0.2), "go_stone_light")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 2.75, sy * 2.75, 12.0), (0.8, 0.8, 24.0), "go_stone_b")
            pinnacle(mb, sx * 2.75, sy * 2.75, 29.8, s=0.62, h=2.6)
    # clock stage
    mb.box((0, 0, 25.0), (6.0, 6.0, 6.0), "go_stone_b")
    mb.box((0, 0, 28.1), (6.4, 6.4, 0.3), "go_stone_light")
    faces = town.box_faces(6.0, 6.0)
    for key, f in faces.items():
        f.box(mb, 0.0, 25.0, 3.9, 3.9, -0.02, 0.1, "go_stone_light")
        c = f.p(0.0, 25.0, 0.1)
        mb.cyl(c + f.n * 0.08, 1.7, 1.7, 0.14, "go_clock", segs=16, rot=_rot_to(f.n))
        mb.cyl(c + f.n * 0.1, 1.85, 1.85, 0.1, "go_iron", segs=16, rot=_rot_to(f.n))
        for k in range(12):
            a = k * math.pi / 6
            f.box(mb, math.cos(a) * 1.45, 25.0 + math.sin(a) * 1.45, 0.14, 0.14, 0.2, 0.27, "go_iron")
        f.box(mb, 0.35, 25.35, 0.9, 0.1, 0.24, 0.3, "go_iron")
        f.box(mb, -0.05, 25.55, 0.1, 1.2, 0.24, 0.3, "go_iron")
        # belfry and lower windows
        f.prism(mb, lancet(-1.0, 28.6, 1.3, 3.4), -0.02, 0.06, "go_stone_light")
        f.prism(mb, lancet(-1.0, 28.7, 1.0, 3.1), -0.01, 0.09, "go_glass_dark")
        f.prism(mb, lancet(1.0, 28.6, 1.3, 3.4), -0.02, 0.06, "go_stone_light")
        f.prism(mb, lancet(1.0, 28.7, 1.0, 3.1), -0.01, 0.09, "go_glass_dark")
        lancet_window(mb, f, 0.0, 12.0, 0.9, 3.0, rng.random() < 0.6)
        lancet_window(mb, f, 0.0, 17.4, 0.8, 2.8, rng.random() < 0.5)
        if key != "front":
            lancet_window(mb, f, 0.0, 6.4, 0.8, 2.6, rng.random() < 0.4)
    mb.box((0, 0, 30.0), (5.6, 5.6, 4.0), "go_stone")
    mb.box((0, 0, 32.1), (6.2, 6.2, 0.3), "go_stone_light")
    mb.cyl((0, 0, 38.4), 3.1, 0.0, 12.4, "go_slate", segs=8, twist=math.pi / 8)
    mb.ico((0, 0, 44.7), 0.24, "go_gold", subdiv=0)
    mb.cyl((0, 0, 45.4), 0.06, 0.06, 1.2, "go_iron", segs=4)
    fr = faces["front"]
    pointed_door(mb, fr, 0.0, 0.6, 1.6, 3.2, glow=True)
    fr.box(mb, 0.0, 0.3, 2.4, 0.6, 0.0, 0.7, "go_stone_dark", bevel=0.02)
    mb.finish("gothic_clocktower")


def _rot_to(n):
    """Euler rotation turning local +Z to the (axis-aligned, horizontal) direction n."""
    if abs(n.y) > 0.5:
        return (math.pi / 2, 0, 0)
    return (0, math.pi / 2, 0)


# ----------------------------------------------------------------------------------- street furniture

def build_gothic_lamp():
    """Ornate street lamp (~3.8 m): stone foot, fluted iron post, crossbar with two lanterns."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.15), (0.44, 0.44, 0.3), "go_stone_b", bevel=0.03)
    mb.lathe([(0.2, 0.3), (0.2, 0.42), (0.12, 0.5), (0.09, 0.62), (0.13, 0.7), (0.0, 0.72)], "go_iron", segs=8)
    mb.cyl((0, 0, 1.95), 0.075, 0.055, 2.5, "go_iron", segs=8)
    for zz in (1.1, 2.3, 3.1):
        mb.cyl((0, 0, zz), 0.1, 0.1, 0.08, "go_iron", segs=8)
    # crossbar with scroll brackets
    mb.box((0, 0, 3.22), (1.34, 0.07, 0.07), "go_iron")
    for sx in (-1, 1):
        mb.cyl_between((sx * 0.05, 0, 2.75), (sx * 0.5, 0, 3.2), 0.025, 0.025, "go_iron", segs=4)
        x = sx * 0.6
        mb.box((x, 0, 3.08), (0.03, 0.03, 0.24), "go_iron")
        z0 = 2.62
        mb.box((x, 0, z0), (0.26, 0.26, 0.05), "go_iron")
        mb.box((x, 0, z0 + 0.2), (0.2, 0.2, 0.36), "go_lamp")
        for ax in (-1, 1):
            for ay in (-1, 1):
                mb.box((x + ax * 0.115, ay * 0.115, z0 + 0.2), (0.03, 0.03, 0.4), "go_iron")
        mb.cyl((x, 0, z0 + 0.46), 0.2, 0.03, 0.16, "go_iron", segs=4, twist=math.pi / 4)
        mb.ico((x, 0, z0 - 0.06), 0.045, "go_iron", subdiv=0)
    mb.cyl((0, 0, 3.5), 0.08, 0.0, 0.5, "go_iron", segs=4)
    mb.ico((0, 0, 3.27), 0.07, "go_iron", subdiv=0)
    mb.finish("gothic_lamp")


def build_gothic_fence():
    """Wrought-iron fence, 2 m along X centred on the origin: low stone kerb, bars with spear
    tips, two rails, a scroll band. Segments chain end to end."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.16), (2.0, 0.3, 0.32), "go_stone_b", bevel=0.02)
    mb.box((0, 0, 0.35), (2.0, 0.22, 0.06), "go_stone_light")
    n = 13
    for k in range(n):
        x = -0.94 + k * (1.88 / (n - 1))
        mb.box((x, 0, 1.05), (0.035, 0.035, 1.4), "go_iron")
        mb.cyl((x, 0, 1.84), 0.045, 0.0, 0.18, "go_iron", segs=4, twist=math.pi / 4)
    for zz in (0.55, 1.6):
        mb.box((0, 0, zz), (2.0, 0.045, 0.05), "go_iron")
    for k in range(6):
        x = -0.8 + k * 0.32
        mb.box((x, 0, 1.42), (0.16, 0.04, 0.16), "go_iron", rot=(0, math.pi / 4, 0))
    mb.finish("gothic_fence")


def build_gothic_pillar():
    """Stone gate pillar (0.7 m square, ~3 m) with a cap and an urn finial."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.2), (0.86, 0.86, 0.4), "go_stone_dark", bevel=0.03)
    mb.box((0, 0, 1.3), (0.66, 0.66, 1.9), "go_stone")
    for sx in (-1, 1):
        mb.box((sx * 0.335, 0, 1.3), (0.04, 0.4, 1.5), "go_stone_b")
        mb.box((0, sx * 0.335, 1.3), (0.4, 0.04, 1.5), "go_stone_b")
    mb.box((0, 0, 2.32), (0.86, 0.86, 0.16), "go_stone_light", bevel=0.02)
    mb.box((0, 0, 2.44), (0.7, 0.7, 0.08), "go_stone_b")
    mb.lathe([(0.0, 2.48), (0.16, 2.48), (0.1, 2.58), (0.24, 2.72), (0.28, 2.86), (0.2, 3.0), (0.26, 3.04),
              (0.08, 3.1), (0.06, 3.22), (0.0, 3.26)], "go_stone_light", segs=8)
    mb.finish("gothic_pillar")


def build_gothic_balustrade():
    """Stone balustrade, 2 m along X centred: plinth rail, vase balusters, capping rail."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.12), (2.0, 0.42, 0.24), "go_stone_b")
    mb.box((0, 0, 0.93), (2.0, 0.46, 0.14), "go_stone_light", bevel=0.02)
    for sx in (-1, 1):
        mb.box((sx * 0.86, 0, 0.5), (0.28, 0.36, 0.9), "go_stone")
    for k in range(5):
        x = -0.52 + k * 0.26
        mb.lathe([(0.0, 0.24), (0.1, 0.24), (0.07, 0.34), (0.12, 0.52), (0.06, 0.72), (0.09, 0.84), (0.0, 0.86)],
                 "go_stone", segs=6, center=(x, 0, 0))
    mb.finish("gothic_balustrade")


def build_gothic_carriage():
    """Abandoned black coach (~1.9 x 4.3 m): curved-roof cabin, spoked wheels, coachman's box
    with a dim lantern, a coffin strapped on the roof."""
    mb = MeshBuilder()
    # chassis
    mb.box((0, 0.1, 0.72), (1.2, 3.6, 0.16), "go_wood_dark")
    mb.box((0, -1.62, 0.95), (1.1, 0.8, 0.5), "go_wood_dark")
    # cabin with a curved roof (prism along Y)
    prof = [(-0.78, 0.85), (0.78, 0.85), (0.78, 2.1)]
    for i in range(1, 6):
        a = math.pi * i / 6
        prof.append((0.78 * math.cos(a), 2.1 + 0.32 * math.sin(a)))
    prof.append((-0.78, 2.1))
    mb.prism(prof, -1.2, 1.3, "go_wood", frame=(Vector((0, 0, 0)), X, Z, -Y))
    for sx in (-1, 1):
        f = Face((sx * 0.78, 0.05, 0), Vector((0, sx, 0)), Z, Vector((sx, 0, 0)))
        f.box(mb, 0.35, 1.72, 0.8, 0.6, -0.02, 0.05, "go_glass_dark")
        f.box(mb, 0.35, 1.72, 0.92, 0.72, -0.03, 0.03, "go_gold")
        f.box(mb, -0.7, 1.4, 0.7, 1.0, -0.02, 0.04, "go_wood_dark")
        f.box(mb, -0.7, 1.4, 0.08, 0.2, 0.04, 0.08, "go_gold")
    rf = Face((0, 1.3, 0), -X, Z, Y)
    rf.box(mb, 0.0, 1.7, 0.9, 0.5, -0.02, 0.05, "go_glass_dark")
    ff = Face((0, -1.2, 0), X, Z, -Y)
    ff.box(mb, 0.0, 1.75, 1.0, 0.45, -0.02, 0.05, "go_glass_dark")
    # coachman's box, seat and lantern
    mb.box((0, -1.55, 1.3), (1.2, 0.6, 0.12), "go_wood")
    mb.box((0, -1.35, 1.6), (1.2, 0.12, 0.5), "go_wood_dark")
    mb.box((0.72, -1.7, 1.55), (0.04, 0.04, 0.5), "go_iron")
    mb.box((0.72, -1.7, 1.9), (0.16, 0.16, 0.24), "go_window_dim")
    mb.cyl((0.72, -1.7, 2.08), 0.13, 0.0, 0.12, "go_iron", segs=4, twist=math.pi / 4)
    # shafts on the ground
    for sx in (-1, 1):
        mb.cyl_between((sx * 0.45, -1.9, 0.9), (sx * 0.5, -3.1, 0.12), 0.04, 0.04, "go_wood_dark", segs=4)
    # wheels
    for (y, r) in ((0.95, 0.72), (-1.25, 0.56)):
        for sx in (-1, 1):
            x = sx * 0.86
            c = Vector((x, y, r))
            mb.cyl(c, r, r, 0.08, "go_wood_dark", segs=12, rot=(0, math.pi / 2, 0))
            mb.cyl(c + Vector((sx * 0.03, 0, 0)), r * 0.86, r * 0.86, 0.1, "go_iron", segs=12, rot=(0, math.pi / 2, 0))
            mb.cyl(c + Vector((sx * 0.07, 0, 0)), 0.1, 0.1, 0.16, "go_gold", segs=6, rot=(0, math.pi / 2, 0))
    # coffin on the roof
    _coffin(mb, Vector((0.0, 0.0, 2.38)), math.pi / 2 * 0 + 0.0, 0.85, lid=True)
    for yy in (-0.5, 0.5):
        mb.box((0, yy, 2.5), (0.86, 0.05, 0.3), "go_iron")
    mb.clamp_floor(0.0)
    mb.finish("gothic_carriage")


def _coffin(mb, base, yaw, s=1.0, lid=True):
    """Coffin lying on `base` (length 2 m * s along the yaw direction)."""
    poly = [(-0.22, -1.0), (0.22, -1.0), (0.36, 0.42), (0.26, 1.0), (-0.26, 1.0), (-0.36, 0.42)]
    c, sn = math.cos(yaw), math.sin(yaw)
    u = Vector((c, sn, 0))
    v = Vector((-sn, c, 0))
    pts = [(p[0] * s, p[1] * s) for p in poly]
    mb.prism(pts, 0.0, 0.36 * s, "go_wood_dark", frame=(Vector(base), u, v, Z))
    if lid:
        big = [(p[0] * 1.08 * s, p[1] * 1.04 * s) for p in poly]
        mb.prism(big, 0.36 * s, 0.46 * s, "go_wood", frame=(Vector(base), u, v, Z))
        o = Vector(base) + Z * (0.46 * s)
        mb.obox(o + v * (0.25 * s) + Z * 0.015, (u, v, Z), (0.08 * s, 1.1 * s, 0.03), "go_gold")
        mb.obox(o + v * (0.45 * s) + Z * 0.015, (u, v, Z), (0.44 * s, 0.08 * s, 0.03), "go_gold")


def build_gothic_coffin():
    """Two coffins, one stacked across the other, with a chain."""
    mb = MeshBuilder()
    _coffin(mb, Vector((0, 0, 0)), 0.0, 1.0)
    _coffin(mb, Vector((0.05, 0.1, 0.46)), 0.35, 0.92)
    mb.box((0.3, -0.5, 0.32), (0.06, 0.06, 0.64), "go_iron")
    mb.finish("gothic_coffin")


def build_gothic_grave_a():
    """Celtic cross headstone on a stepped base."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.12), (0.9, 0.55, 0.24), "go_stone_dark", bevel=0.02)
    mb.box((0, 0, 0.3), (0.6, 0.36, 0.14), "go_stone_b")
    mb.box((0, 0, 1.0), (0.2, 0.16, 1.4), "go_stone")
    mb.box((0, 0, 1.38), (0.86, 0.16, 0.2), "go_stone")
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        mb.box((math.cos(a) * 0.26, 0, 1.38 + math.sin(a) * 0.26), (0.12, 0.12, 0.12), "go_stone", rot=(0, -a, 0))
    mb.box((0, -0.3, 0.05), (0.16, 0.16, 0.1), "go_candle")
    mb.finish("gothic_grave_a")


def build_gothic_grave_b():
    """Pointed headstone with a grave slab in front."""
    mb = MeshBuilder()
    f = Face((0, 0.08, 0), X, Z, -Y)
    f.prism(mb, lancet(0.0, 0.0, 0.72, 1.3), -0.08, 0.08, "go_stone")
    f.prism(mb, lancet(0.0, 0.5, 0.42, 0.66), 0.08, 0.1, "go_stone_dark")
    mb.box((0, 0.08, 0.08), (0.9, 0.3, 0.16), "go_stone_b")
    mb.box((0, -0.95, 0.09), (0.8, 1.7, 0.18), "go_stone_dark", bevel=0.02)
    mb.box((0, -0.95, 0.2), (0.12, 0.9, 0.04), "go_stone_b")
    mb.box((0, -0.7, 0.2), (0.5, 0.12, 0.04), "go_stone_b")
    mb.finish("gothic_grave_b")


def build_gothic_statue():
    """Hooded statue on a tall plinth (~4.3 m), sword planted before it."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.2), (1.5, 1.5, 0.4), "go_stone_dark", bevel=0.03)
    mb.box((0, 0, 1.0), (1.1, 1.1, 1.2), "go_stone_b")
    mb.box((0, 0, 1.66), (1.3, 1.3, 0.14), "go_stone_light", bevel=0.02)
    Face((0, -0.55, 0), X, Z, -Y).box(mb, 0.0, 1.0, 0.7, 0.3, 0.0, 0.03, "go_gold")
    _hooded_figure(mb, Vector((0, 0, 1.73)), 1.15)
    mb.finish("gothic_statue")


def build_gothic_dead_tree():
    """Gnarled leafless tree (~6 m)."""
    rng = random.Random(31)
    mb = MeshBuilder()

    def branch(a, d, length, r, depth):
        b = a + d * length
        mb.cyl_between(a, b, r, r * 0.7, "go_bark" if depth % 2 == 0 else "go_bark_b", segs=5)
        if depth >= 4 or r < 0.03:
            return
        n = 2 if depth < 2 else rng.choice((1, 2, 2, 3))
        for k in range(n):
            nd = (d + Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), rng.uniform(-0.1, 0.5)))).normalized()
            branch(b - d * 0.05, nd, length * rng.uniform(0.62, 0.8), r * 0.66, depth + 1)

    mb.cyl((0, 0, 0.15), 0.42, 0.3, 0.3, "go_bark", segs=6)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        mb.cyl_between((0, 0, 0.3), (math.cos(a) * 0.8, math.sin(a) * 0.8, 0.02), 0.13, 0.05, "go_bark", segs=4)
    branch(Vector((0, 0, 0.1)), Vector((0.1, 0.05, 1)).normalized(), 2.4, 0.26, 0)
    mb.clamp_floor(0.0)
    mb.finish("gothic_dead_tree")


def build_gothic_fountain():
    """Octagonal fountain (r ~2.3 m): raised rim, dark water, tiered column, hooded figure."""
    mb = MeshBuilder()
    oct_pts = L.circle_pts(2.3, 8, phase=math.pi / 8)
    mb.prism(oct_pts, 0.0, 0.62, "go_stone_b")
    mb.prism(L.circle_pts(2.05, 8, phase=math.pi / 8), 0.62, 0.66, "go_water")
    for k in range(8):
        a0 = math.pi / 8 + k * math.pi / 4
        a1 = a0 + math.pi / 4
        p0 = Vector((math.cos(a0) * 2.18, math.sin(a0) * 2.18, 0))
        p1 = Vector((math.cos(a1) * 2.18, math.sin(a1) * 2.18, 0))
        d = p1 - p0
        mb.obox((p0 + p1) / 2 + Vector((0, 0, 0.72)), (d.normalized(), Vector((-d.y, d.x, 0)).normalized(), Z),
                (d.length + 0.14, 0.3, 0.2), "go_stone_light")
    mb.lathe([(0.0, 0.6), (0.55, 0.6), (0.5, 0.8), (0.28, 1.0), (0.24, 1.6), (0.9, 1.72), (1.0, 1.84), (0.3, 1.9),
              (0.2, 2.4), (0.36, 2.55), (0.0, 2.6)], "go_stone_light", segs=8)
    mb.prism(L.circle_pts(0.88, 8, phase=math.pi / 8), 1.8, 1.86, "go_water")
    _hooded_figure(mb, Vector((0, 0, 2.58)), 0.62, sword=False)
    mb.finish("gothic_fountain")


def build_gothic_shrine():
    """The act waystone: a stepped altar with a tall wrought-iron lantern cage holding a big
    flame, candles, and two iron spikes (~3.9 m)."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.14), (2.4, 1.8, 0.28), "go_stone_dark", bevel=0.03)
    mb.box((0, 0, 0.4), (2.0, 1.4, 0.24), "go_stone_b", bevel=0.02)
    mb.box((0, 0, 0.98), (1.4, 0.95, 0.92), "go_stone")
    mb.box((0, 0, 1.5), (1.6, 1.1, 0.14), "go_stone_light", bevel=0.02)
    Face((0, -0.48, 0), X, Z, -Y).prism(mb, lancet(0.0, 0.62, 0.5, 0.7), -0.01, 0.05, "go_blood")
    # lantern cage
    z0 = 1.57
    mb.box((0, 0, z0 + 0.05), (0.9, 0.9, 0.1), "go_iron")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 0.4, sy * 0.4, z0 + 0.95), (0.06, 0.06, 1.8), "go_iron")
    for zz in (0.6, 1.3):
        for sx in (-1, 1):
            mb.box((sx * 0.4, 0, z0 + zz), (0.04, 0.84, 0.04), "go_iron")
            mb.box((0, sx * 0.4, z0 + zz), (0.84, 0.04, 0.04), "go_iron")
    mb.ico((0, 0, z0 + 0.62), 0.3, "go_lamp", subdiv=1, scale=(1, 1, 1.5))
    mb.cyl((0, 0, z0 + 0.22), 0.2, 0.28, 0.24, "go_iron", segs=6)
    mb.cyl((0, 0, z0 + 2.15), 0.66, 0.0, 0.7, "go_iron", segs=4, twist=math.pi / 4)
    mb.cyl((0, 0, z0 + 2.7), 0.04, 0.0, 0.5, "go_iron", segs=4)
    mb.ico((0, 0, z0 + 2.48), 0.08, "go_gold", subdiv=0)
    # candles
    for (x, y, h) in ((-0.62, -0.38, 0.22), (-0.5, -0.46, 0.16), (0.6, -0.4, 0.26), (0.5, 0.38, 0.18), (-0.58, 0.36, 0.2)):
        mb.cyl((x, y, 1.57 + h / 2), 0.035, 0.035, h, "go_stone_pale", segs=5)
        mb.box((x, y, 1.57 + h + 0.03), (0.03, 0.03, 0.06), "go_candle")
    # spikes
    for sx in (-1, 1):
        mb.cyl((sx * 1.05, -0.75, 0.9), 0.05, 0.0, 1.5, "go_iron", segs=4)
    mb.finish("gothic_shrine")


def build_gothic_stall():
    """The merchant's stall (~3 x 2 m): counter with blood vials, shelves, a dark red canopy on
    posts and two lanterns. Front (customer side) faces -Y."""
    rng = random.Random(5)
    mb = MeshBuilder()
    mb.box((0, -0.55, 0.5), (2.8, 0.7, 1.0), "go_wood_dark")
    mb.box((0, -0.55, 1.03), (3.0, 0.82, 0.08), "go_wood")
    Face((0, -0.9, 0), X, Z, -Y).box(mb, 0.0, 0.62, 2.4, 0.5, 0.0, 0.04, "go_wood")
    # shelves at the back
    mb.box((0, 0.75, 1.1), (2.6, 0.4, 2.2), "go_wood_dark")
    for zz in (0.9, 1.45, 2.0):
        mb.box((0, 0.48, zz), (2.6, 0.18, 0.05), "go_wood")
        for k in range(7):
            x = -1.1 + k * 0.36 + rng.uniform(-0.05, 0.05)
            mat = "go_blood" if rng.random() < 0.6 else ("go_glass_dark" if rng.random() < 0.5 else "go_stone_pale")
            mb.cyl((x, 0.47, zz + 0.12), 0.05, 0.04, 0.2, mat, segs=5)
    for k in range(6):
        x = -1.0 + k * 0.38
        mb.cyl((x, -0.55, 1.17), 0.045, 0.035, 0.2, "go_blood", segs=5)
    # posts + canopy
    for sx in (-1, 1):
        mb.box((sx * 1.45, -0.95, 1.35), (0.12, 0.12, 2.7), "go_wood_dark")
        mb.box((sx * 1.45, 0.95, 1.55), (0.12, 0.12, 3.1), "go_wood_dark")
    d = Vector((0, -2.2, -0.6)).normalized()
    c = Vector((0, 0.0, 2.95))
    mb.obox(c, (X, d, d.cross(X)), (3.3, 2.4, 0.08), "go_cloth")
    for k in range(9):
        x = -1.5 + k * 0.375
        mb.box((x, -1.12, 2.55), (0.3, 0.05, 0.28), "go_cloth_dark", taper=(1.0, 1.0))
    # lanterns
    for sx in (-1, 1):
        x = sx * 1.45
        mb.box((x, -1.12, 2.35), (0.03, 0.03, 0.3), "go_iron")
        mb.box((x, -1.12, 2.1), (0.18, 0.18, 0.26), "go_lamp")
        mb.cyl((x, -1.12, 2.28), 0.14, 0.02, 0.1, "go_iron", segs=4, twist=math.pi / 4)
    # crates beside
    mb.box((1.9, -0.2, 0.3), (0.6, 0.6, 0.6), "go_wood", bevel=0.02)
    mb.box((1.85, -0.25, 0.8), (0.45, 0.45, 0.4), "go_wood_dark", bevel=0.02)
    mb.finish("gothic_stall")


def build_gothic_crypt():
    """Small mausoleum (~4 x 5 m): pointed door, steep stone roof, corner pinnacles, a statue."""
    mb = MeshBuilder()
    mb.box((0, 0, 0.2), (4.2, 5.0, 0.4), "go_stone_dark", bevel=0.03)
    mb.box((0, 0.2, 2.0), (3.4, 4.2, 3.2), "go_stone")
    town.gable_roof_y(mb, 4.6, 2.0, 3.6, 6.2, 0.26, "go_stone_b", x0=0.0)
    mb.prism([(-1.7, 3.59), (1.7, 3.59), (0.0, 5.9)], -4.2, 0.0, "go_stone", frame=(Vector((0, -1.9, 0)), X, Z, -Y))
    mb.box((0, 0.2, 3.62), (3.7, 4.5, 0.18), "go_stone_light")
    f = Face((0, -1.9, 0), X, Z, -Y)
    pointed_door(mb, f, 0.0, 0.4, 1.2, 2.4, glow=False)
    f.prism(mb, lancet(0.0, 3.95, 0.5, 1.2), -0.01, 0.06, "go_rose")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 1.72, 0.2 + sy * 2.1, 1.9), (0.4, 0.4, 3.4), "go_stone_b")
            pinnacle(mb, sx * 1.72, 0.2 + sy * 2.1, 3.6, s=0.36, h=1.3)
    pinnacle(mb, 0.0, -1.95, 5.7, s=0.3, h=1.1)
    mb.box((0, -2.3, 0.45), (1.8, 0.7, 0.1), "go_stone_b")
    mb.finish("gothic_crypt")


# ----------------------------------------------------------------------------------- ground decals

def _blob(rng, cx, cy, r, n=9, rough=0.3):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        rr = r * (1.0 + rng.uniform(-rough, rough))
        pts.append((cx + math.cos(a) * rr * 1.25, cy + math.sin(a) * rr * 0.85))
    return pts


def build_gothic_puddle():
    """Two flat rain puddles (glossy, dark) lying on the cobbles."""
    rng = random.Random(41)
    mb = MeshBuilder()
    mb.prism(_blob(rng, 0.0, 0.0, 0.62, 10), 0.002, 0.012, "go_puddle")
    mb.prism(_blob(rng, 0.85, 0.55, 0.3, 8), 0.002, 0.011, "go_puddle")
    mb.prism(_blob(rng, -0.8, -0.35, 0.22, 7), 0.002, 0.011, "go_puddle")
    mb.finish("gothic_puddle")


def build_gothic_blood():
    """A dark blood pool with splatter drops."""
    rng = random.Random(43)
    mb = MeshBuilder()
    mb.prism(_blob(rng, 0.0, 0.0, 0.55, 11, 0.35), 0.003, 0.013, "go_blood_pool")
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.75, 1.4)
        mb.prism(_blob(rng, math.cos(a) * d, math.sin(a) * d, rng.uniform(0.05, 0.14), 6), 0.003, 0.012, "go_blood_pool")
    mb.finish("gothic_blood")


def build_gothic_bench():
    """Iron-and-wood park bench, 1.7 m along X, facing -Y."""
    mb = MeshBuilder()
    for sx in (-1, 1):
        x = sx * 0.72
        mb.box((x, 0.0, 0.22), (0.07, 0.5, 0.06), "go_iron")
        mb.box((x, -0.2, 0.2), (0.06, 0.06, 0.4), "go_iron")
        mb.box((x, 0.2, 0.45), (0.06, 0.06, 0.9), "go_iron")
        mb.box((x, 0.0, 0.43), (0.06, 0.5, 0.05), "go_iron")
        mb.cyl((x, -0.24, 0.62), 0.07, 0.07, 0.06, "go_iron", segs=6, rot=(0, math.pi / 2, 0))
    for k in range(4):
        mb.box((0, -0.18 + k * 0.12, 0.48), (1.7, 0.1, 0.04), "go_wood")
    for k in range(3):
        mb.box((0, 0.24, 0.62 + k * 0.13), (1.7, 0.04, 0.09), "go_wood")
    mb.finish("gothic_bench")


def build_gothic_planter():
    """Square stone planter with dark soil and a thorny dead shrub."""
    rng = random.Random(47)
    mb = MeshBuilder()
    mb.box((0, 0, 0.3), (1.3, 1.3, 0.6), "go_stone_b", bevel=0.03)
    mb.box((0, 0, 0.64), (1.42, 1.42, 0.1), "go_stone_light", bevel=0.02)
    mb.box((0, 0, 0.62), (1.14, 1.14, 0.08), "dirt")
    for k in range(7):
        a = k * 2 * math.pi / 7 + rng.uniform(-0.3, 0.3)
        tip = Vector((math.cos(a) * rng.uniform(0.3, 0.6), math.sin(a) * rng.uniform(0.3, 0.6), 0.66 + rng.uniform(0.7, 1.3)))
        mid = Vector((tip.x * 0.4, tip.y * 0.4, 0.66 + (tip.z - 0.66) * 0.5))
        mb.cyl_between((0, 0, 0.64), mid, 0.05, 0.035, "go_bark", segs=4)
        mb.cyl_between(mid, tip, 0.035, 0.012, "go_bark_b", segs=4)
    mb.finish("gothic_planter")


# ----------------------------------------------------------------------------------- the zones (wilds)

def cheap_window(mb, f, uc, v0, w, h, lit, frame="go_stone_light"):
    """Pointed window with few triangles: surround, glass (lit or dark), sill."""
    f.prism(mb, lancet(uc, v0 - 0.06, w + 0.2, h + 0.14, n=2), -0.02, 0.05, frame)
    f.prism(mb, lancet(uc, v0, w, h, n=2), -0.01, 0.075, "go_window" if lit else "go_glass_dark")
    f.box(mb, uc, v0 - 0.1, w + 0.34, 0.08, -0.02, 0.14, frame)


def arch_pts(uc, s, w, n=4):
    """Pointed (equilateral) arch curve from the left springing (uc - w/2, s) over the apex to the
    right springing (uc + w/2, s)."""
    xl, xr = uc - w / 2, uc + w / 2
    pts = []
    for i in range(n + 1):
        a = math.radians(180.0 - 60.0 * i / n)
        pts.append((xr + w * math.cos(a), s + w * math.sin(a)))
    for i in range(1, n + 1):
        a = math.radians(60.0 - 60.0 * i / n)
        pts.append((xl + w * math.cos(a), s + w * math.sin(a)))
    return pts


def low_arch(uc, v0, w, h, rise, n=8):
    """A wide, low pointed arch outline (CCW in (u, v)): sides up to v0 + h - rise, then a curve
    with vertical springing and a pointed crown at v0 + h."""
    s = v0 + h - rise
    pts = [(uc - w / 2, v0), (uc + w / 2, v0), (uc + w / 2, s)]
    for i in range(1, n):
        x = uc + w / 2 - w * i / n
        pts.append((x, s + rise * math.sqrt(max(0.0, 1.0 - abs(x - uc) / (w / 2)))))
    pts.append((uc - w / 2, s))
    return pts


def _terrace(name, seed, *, bays=4, shop=False, gable=False, turret=False, lit=0.55):
    """A row of townhouses under one roof (11.6 x 5.6 m, three storeys, ~13 m): pilasters between
    the bays, doors / a shop front on the ground floor, pointed windows (many lit), dormers,
    chimneys on the party walls; the back and ends are plainer. Cheaper than two houses."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    w, d = 11.6, 5.6
    base, eave, ridge, storey = 0.45, 9.0, 13.2, 2.75
    mb.box((0, 0, base / 2), (w + 0.24, d + 0.24, base), "go_stone_dark")
    mb.box((0, 0, (base + eave) / 2), (w, d, eave - base), "go_stone")
    z = base + storey
    while z < eave - 0.6:
        mb.box((0, 0, z), (w + 0.12, d + 0.12, 0.14), "go_stone_light")
        z += storey
    mb.box((0, 0, eave - 0.08), (w + 0.3, d + 0.3, 0.22), "go_stone_light")
    faces = front_face(w, d)
    fr, rt, bk, lf = faces["front"], faces["right"], faces["back"], faces["left"]
    bw = w / bays
    for k in range(bays + 1):
        fr.box(mb, -w / 2 + k * bw, (base + eave) / 2, 0.42, eave - base, -0.02, 0.2, "go_stone_b")
    for sx in (-1, 1):
        mb.box((sx * (w / 2 - 0.1), d / 2 - 0.1, (base + eave) / 2), (0.44, 0.44, eave - base + 0.1), "go_stone_b")
    # roof along the street, gable ends, snow, pinnacles, chimneys
    hs = d / 2 + 0.35
    z_in = town.gable_roof_x(mb, w + 0.5, hs, eave, ridge, 0.24, "go_slate")
    apex = z_in(0) + 0.02
    mb.prism([(-d / 2, eave - 0.01), (d / 2, eave - 0.01), (0, apex)], -w / 2, w / 2, "go_stone",
             frame=(Vector((0, 0, 0)), Y, Z, X))
    town.shingle_rows(mb, w + 0.54, hs, eave, ridge, ["go_slate", "go_slate_b"], rows=3, th=0.08, delta_deg=4.0)
    mb.box((0, 0, ridge + 0.02), (w + 0.5, 0.34, 0.14), "go_snow")
    for sx in (-1, 1):
        pinnacle(mb, sx * (w / 2 - 0.05), -d / 2 + 0.05, eave, s=0.34, h=1.4)
    for cx in (-bw, bw):
        town.chimney(mb, cx, d * 0.16, eave - 0.5, ridge + 0.7, "go_stone_dark", "go_stone_light")
    H = ridge - eave
    yf = -hs * 0.62
    zf = eave + H * (1 - 0.62)
    if gable:
        # a wall gable over the two middle bays with a tall window and a finial
        gw = bw * 2 - 0.5
        fr.box(mb, 0.0, eave + 1.1, gw, 2.2, -1.5, 0.3, "go_stone")
        mb.prism([(-gw / 2, eave + 2.2), (gw / 2, eave + 2.2), (0.0, eave + 5.0)], -1.5, 0.3, "go_stone",
                 frame=(Vector((0, -d / 2, 0)), X, Z, -Y))
        for sx in (-1, 1):
            a = Vector((sx * (gw / 2 + 0.1), -d / 2 + 0.55, eave + 2.15))
            b = Vector((0.0, -d / 2 + 0.55, eave + 5.1))
            dd = b - a
            mb.obox((a + b) / 2, (dd.normalized(), Y, dd.normalized().cross(Y)), (dd.length + 0.3, 2.1, 0.22), "go_slate")
        gf = Face((0, -d / 2 - 0.3, 0), X, Z, -Y)
        cheap_window(mb, gf, 0.0, eave + 0.3, 0.9, 3.0, rng.random() < 0.7)
        gf.box(mb, 0.0, eave - 0.05, gw + 0.1, 0.16, -0.02, 0.12, "go_stone_light")
        pinnacle(mb, 0.0, -d / 2 - 0.2, eave + 4.9, s=0.3, h=1.3)
    for k in range(bays):
        if gable and k in (1, 2):
            continue
        if not gable and k % 2 == 1:
            continue
        dx = -w / 2 + (k + 0.5) * bw
        mb.box((dx, yf + 0.8, zf + 0.45), (1.1, 1.6, 1.5), "go_stone")
        mb.prism([(-0.72, zf + 1.18), (0.72, zf + 1.18), (0.0, zf + 1.95)], 0.0, 1.7, "go_slate",
                 frame=(Vector((dx, yf - 0.12, 0)), -X, Z, Y))
        cheap_window(mb, Face((dx, yf, 0), X, Z, -Y), 0.0, zf - 0.05, 0.5, 0.95, rng.random() < lit)
    if turret:
        tx, ty = w / 2 - 0.15, -d / 2 + 0.15
        top = eave + 1.2
        mb.cyl((tx, ty, (base + 2.0 + top) / 2), 0.9, 0.9, top - base - 2.0, "go_stone", segs=8)
        mb.cyl((tx, ty, base + 1.7), 0.3, 0.9, 0.6, "go_stone_light", segs=8)
        mb.cyl((tx, ty, top + 0.1), 1.02, 1.02, 0.2, "go_stone_light", segs=8)
        mb.cyl((tx, ty, top + 2.6), 1.0, 0.0, 4.8, "go_slate", segs=8)
        mb.ico((tx, ty, top + 5.1), 0.1, "go_gold", subdiv=0)
    # front: doors / a shop front / windows on the ground floor, windows above
    doors = (0, 2) if bays >= 4 else (0,)
    for k in range(bays):
        u = -w / 2 + (k + 0.5) * bw
        if shop and k == bays - 1:
            fr.box(mb, u, base + 1.05, bw - 0.8, 1.7, -0.02, 0.12, "go_wood_dark")
            fr.box(mb, u, base + 1.05, bw - 1.2, 1.3, 0.0, 0.16, "go_window")
            fr.box(mb, u, base + 2.15, bw - 0.6, 0.34, -0.02, 0.2, "go_wood")
        elif k in doors:
            pointed_door(mb, fr, u, base, 1.0, 2.2, glow=rng.random() < 0.25)
            fr.box(mb, u, base * 0.5, 1.5, base, 0.0, 0.45, "go_stone_dark")
        else:
            cheap_window(mb, fr, u, base + 0.8, 0.62, 1.3, rng.random() < lit)
        zz = base + storey + 0.55
        while zz + 1.6 < eave:
            cheap_window(mb, fr, u, zz, 0.66, 1.5, rng.random() < lit)
            zz += storey
    # back: plain windows (mostly dark)
    for k in range(bays):
        u = -w / 2 + (k + 0.5) * bw
        zz = base + 0.9
        while zz + 1.4 < eave:
            bk.box(mb, u, zz + 0.6, 0.6, 1.2, -0.01, 0.06, "go_window_dim" if rng.random() < lit * 0.4 else "go_glass_dark")
            zz += storey
    for f in (rt, lf):
        cheap_window(mb, f, 0.0, eave + 0.3, 0.5, (apex - eave) * 0.5, rng.random() < lit * 0.8)
        cheap_window(mb, f, 0.0, base + storey + 0.55, 0.6, 1.4, rng.random() < lit * 0.6)
    mb.finish(name)


def build_gothic_terrace_a():
    """Row of four townhouses under one long roof: two doors, a shop at the end, dormers."""
    _terrace("gothic_terrace_a", 505, shop=True)


def build_gothic_terrace_b():
    """Row of townhouses with a wall gable over the middle bays and a corner turret."""
    _terrace("gothic_terrace_b", 606, gable=True, turret=True, lit=0.6)


def build_gothic_gate():
    """Gateway between two zones: two tall stone gate pillars 11.4 m apart (a 10 m opening along
    X) with lanterns on top, an iron pointed arch with bars and spikes between them, a lantern
    hanging from its apex."""
    mb = MeshBuilder()
    px = 5.7
    for sx in (-1, 1):
        x = sx * px
        mb.box((x, 0, 0.3), (1.9, 1.9, 0.6), "go_stone_dark", bevel=0.03)
        mb.box((x, 0, 2.9), (1.4, 1.4, 4.6), "go_stone")
        for zz in (1.1, 3.9):
            mb.box((x, 0, zz), (1.52, 1.52, 0.16), "go_stone_light")
        for f in (Face((x, -0.7, 0), X, Z, -Y), Face((x, 0.7, 0), -X, Z, Y)):
            f.prism(mb, lancet(0.0, 1.5, 0.7, 2.0, n=2), -0.01, 0.05, "go_stone_b")
        mb.box((x, 0, 5.3), (1.72, 1.72, 0.24), "go_stone_light", bevel=0.02)
        mb.box((x, 0, 5.5), (1.3, 1.3, 0.16), "go_stone_b")
        # lantern
        mb.box((x, 0, 5.63), (0.5, 0.5, 0.1), "go_iron")
        mb.box((x, 0, 5.98), (0.34, 0.34, 0.6), "go_lamp")
        for ax in (-1, 1):
            for ay in (-1, 1):
                mb.box((x + ax * 0.19, ay * 0.19, 5.98), (0.04, 0.04, 0.64), "go_iron")
        mb.cyl((x, 0, 6.45), 0.34, 0.0, 0.34, "go_iron", segs=4, twist=math.pi / 4)
        mb.ico((x, 0, 6.7), 0.06, "go_iron", subdiv=0)

    def arch_z(x, z0, rise, half):
        return z0 + rise * math.sqrt(max(0.0, 1.0 - abs(x) / half))

    n = 12
    outer = [(-5.0 + 10.0 * i / n, arch_z(-5.0 + 10.0 * i / n, 5.6, 3.3, 5.0)) for i in range(n + 1)]
    inner = [(-4.9 + 9.8 * i / n, arch_z(-4.9 + 9.8 * i / n, 5.2, 2.5, 4.9)) for i in range(n + 1)]
    for curve, r in ((outer, 0.12), (inner, 0.09)):
        for i in range(n):
            a = Vector((curve[i][0], 0.0, curve[i][1]))
            b = Vector((curve[i + 1][0], 0.0, curve[i + 1][1]))
            mb.cyl_between(a, b, r, r, "go_iron", segs=6)
    for i in range(1, n):
        mb.cyl_between(Vector((outer[i][0], 0.0, outer[i][1])), Vector((inner[i][0], 0.0, inner[i][1])), 0.05, 0.05, "go_iron", segs=4)
        if i % 2 == 0:
            mb.cyl((outer[i][0], 0.0, outer[i][1] + 0.3), 0.09, 0.0, 0.6, "go_iron", segs=4)
    # the apex: a crest (iron disc, gilt ring, a pointed arch of gold), a spike, a chain and a
    # lantern under the inner arch
    top = outer[n // 2][1]
    mb.cyl((0.0, 0.0, top + 1.1), 0.12, 0.0, 1.4, "go_iron", segs=4)
    mb.cyl((0.0, 0.0, top + 0.05), 0.72, 0.72, 0.14, "go_iron", segs=10, rot=(math.pi / 2, 0, 0))
    mb.cyl((0.0, 0.0, top + 0.05), 0.58, 0.58, 0.2, "go_gold", segs=10, rot=(math.pi / 2, 0, 0))
    mb.cyl((0.0, 0.0, top + 0.05), 0.44, 0.44, 0.24, "go_iron", segs=10, rot=(math.pi / 2, 0, 0))
    for sy in (-1, 1):
        Face((0, sy * 0.12, 0), Vector((-sy, 0, 0)), Z, Vector((0, sy, 0))).prism(
            mb, lancet(0.0, top - 0.3, 0.3, 0.62, n=2), 0.0, 0.03, "go_gold")
    it = inner[n // 2][1]
    mb.box((0.0, 0.0, it - 0.45), (0.03, 0.03, 0.9), "go_iron")
    mb.box((0.0, 0.0, it - 0.95), (0.42, 0.42, 0.08), "go_iron")
    mb.box((0.0, 0.0, it - 1.28), (0.3, 0.3, 0.56), "go_lamp")
    mb.cyl((0.0, 0.0, it - 0.84), 0.3, 0.0, 0.18, "go_iron", segs=4, twist=math.pi / 4)
    mb.finish("gothic_gate")


def build_gothic_great_bridge():
    """Blackmoor Bridge, 44 m along X, deck 14 m wide in Y (top just under z = 0: the paving and
    the balustrades are separate): a ledge for statues and lamps along each side, heavy piers with
    cutwaters dropping 36 m into the gorge, abutments at both ends."""
    mb = MeshBuilder()
    L = 44.0
    mb.box((0, 0, -0.74), (L, 17.8, 1.44), "go_stone_b")
    for sy in (-1, 1):
        mb.box((0, sy * 8.95, -0.28), (L, 0.5, 0.56), "go_stone_light")
        mb.box((0, sy * 8.6, -6.35), (L, 1.0, 11.3), "go_stone")
        for k in range(9):
            x = -20.0 + k * 5.0
            mb.box((x, sy * 8.95, -1.0), (0.5, 0.64, 0.8), "go_stone_light")
        f = Face((0, sy * 9.1, 0), Vector((-sy, 0, 0)), Z, Vector((0, sy, 0)))
        for k in range(5):
            u = -19.6 + k * 9.8
            f.prism(mb, lancet(u * -sy, -9.0, 5.8, 7.0, n=3), -0.01, 0.06, "go_stone_light")
            f.prism(mb, lancet(u * -sy, -9.0, 5.0, 6.4, n=3), -0.01, 0.1, "go_void")
        for x in (-14.7, -4.9, 4.9, 14.7):
            mb.box((x, sy * 10.1, -18.3), (2.8, 2.2, 35.4), "go_stone_b")
            mb.box((x, sy * 10.15, -0.5), (3.1, 2.5, 0.22), "go_stone_light")
            mb.prism([(-1.4, 0.0), (1.4, 0.0), (0.0, 1.8)], -36.0, -2.2, "go_stone_b",
                     frame=(Vector((x, sy * 11.2, 0)), Vector((sy, 0, 0)), Vector((0, sy, 0)), Z))
    for sx in (-1, 1):
        mb.box((sx * 22.5, 0, -6.0), (3.0, 19.0, 12.0), "go_stone_b")
    mb.finish("gothic_great_bridge")


def build_gothic_bridge_tower():
    """Bridgehead tower (5.6 m square, ~29 m): battered plinth, buttressed shaft, pointed
    windows, a corbelled gallery, a belfry stage and a steep octagonal spire; a glowing door and a
    lantern on the front (-Y)."""
    rng = random.Random(61)
    mb = MeshBuilder()
    s = 5.6
    mb.box((0, 0, 0.6), (s + 1.0, s + 1.0, 1.2), "go_stone_dark", taper=(0.88, 0.88))
    mb.box((0, 0, 8.6), (s, s, 15.2), "go_stone")
    for zz in (5.6, 11.0):
        mb.box((0, 0, zz), (s + 0.16, s + 0.16, 0.18), "go_stone_light")
    for bx in (-1, 1):
        for by in (-1, 1):
            mb.box((bx * s / 2, by * s / 2, 7.6), (0.8, 0.8, 13.2), "go_stone_b")
            pinnacle(mb, bx * s / 2, by * s / 2, 14.2, s=0.6, h=1.8)
    # corbelled gallery
    mb.box((0, 0, 16.0), (s + 0.6, s + 0.6, 0.5), "go_stone_light")
    mb.box((0, 0, 16.9), (s + 1.0, s + 1.0, 1.3), "go_stone")
    mb.box((0, 0, 17.6), (s + 1.1, s + 1.1, 0.14), "go_stone_light")
    for f in town.box_faces(s + 1.0, s + 1.0).values():
        for k in range(5):
            f.box(mb, -2.6 + k * 1.3, 15.55, 0.3, 0.5, -0.01, 0.15, "go_stone_light")
    # belfry stage and spire
    mb.box((0, 0, 19.3), (s - 1.0, s - 1.0, 3.4), "go_stone_b")
    for f in town.box_faces(s - 1.0, s - 1.0).values():
        f.prism(mb, lancet(0.0, 18.2, 1.2, 2.4, n=3), -0.01, 0.08, "go_stone_light")
        f.prism(mb, lancet(0.0, 18.3, 0.9, 2.1, n=3), -0.01, 0.12, "go_glass_dark")
    mb.cyl((0, 0, 21.2), 3.0, 3.0, 0.4, "go_stone_light", segs=8, twist=math.pi / 8)
    mb.cyl((0, 0, 25.6), 2.8, 0.0, 8.4, "go_slate", segs=8, twist=math.pi / 8)
    mb.ico((0, 0, 29.9), 0.18, "go_gold", subdiv=0)
    mb.cyl((0, 0, 30.5), 0.05, 0.05, 1.0, "go_iron", segs=4)
    faces = town.box_faces(s, s)
    for key, f in faces.items():
        lancet_window(mb, f, 0.0, 11.8, 0.8, 2.6, rng.random() < 0.55)
        if key != "front":
            lancet_window(mb, f, 0.0, 6.4, 0.7, 2.2, rng.random() < 0.35)
    fr = faces["front"]
    pointed_door(mb, fr, 0.0, 1.2, 1.5, 3.0, glow=True)
    fr.box(mb, 0.0, 0.6, 2.4, 1.2, 0.0, 0.9, "go_stone_dark", bevel=0.02)
    lancet_window(mb, fr, 0.0, 6.6, 0.8, 2.4, True)
    # lantern on a bracket beside the door
    fr.box(mb, 1.4, 4.4, 0.08, 0.08, 0.0, 0.7, "go_iron")
    fr.box(mb, 1.4, 4.05, 0.3, 0.44, 0.5, 0.8, "go_lamp")
    fr.box(mb, 1.4, 4.33, 0.4, 0.08, 0.45, 0.85, "go_iron")
    mb.finish("gothic_bridge_tower")


def build_gothic_canal_bridge():
    """Stone bridge over a 10 m canal (the path runs along Y, 12.6 m wide in X; top just under
    z = 0: paving and balustrades are separate): deck slab, side walls down into the water with a
    blind pointed arch and a cornice, cutwaters."""
    mb = MeshBuilder()
    mb.box((0, 0, -0.5), (12.6, 11.2, 0.96), "go_stone_b")
    for sx in (-1, 1):
        mb.box((sx * 6.35, 0, -1.7), (0.5, 11.2, 3.2), "go_stone")
        f = Face((sx * 6.6, 0, 0), Vector((0, sx, 0)), Z, Vector((sx, 0, 0)))
        f.box(mb, 0.0, -0.22, 11.4, 0.3, -0.02, 0.18, "go_stone_light")
        f.prism(mb, low_arch(0.0, -3.2, 7.4, 3.0, 2.2), -0.01, 0.06, "go_stone_light")
        f.prism(mb, low_arch(0.0, -3.2, 6.6, 2.6, 1.9), -0.01, 0.12, "go_void")
        for sy in (-1, 1):
            mb.prism([(-0.6, 0.0), (0.6, 0.0), (0.0, 0.9)], -3.4, -0.5, "go_stone_b",
                     frame=(Vector((sx * 6.6, sy * 4.9, 0)), Vector((0, -sx, 0)), Vector((sx, 0, 0)), Z))
    mb.finish("gothic_canal_bridge")


def build_gothic_boat():
    """A black canal boat (~5.4 m along Y, waterline at z = 0): hull with a raised prow, thwarts, a
    lantern on a crook at the stern, a shrouded coffin amidships."""
    mb = MeshBuilder()
    top = [(0.0, 2.75), (0.42, 2.3), (0.7, 1.3), (0.78, 0.0), (0.72, -1.3), (0.52, -2.15), (0.0, -2.45)]
    bot = [(0.0, 2.05), (0.36, 1.5), (0.46, 0.0), (0.4, -1.5), (0.0, -1.95)]
    pts = []
    for (x, y) in top:
        pts.append((x, y, 0.42))
        if x > 0.0:
            pts.append((-x, y, 0.42))
    for (x, y) in bot:
        pts.append((x, y, -0.32))
        if x > 0.0:
            pts.append((-x, y, -0.32))
    pts.append((0.0, 3.0, 0.8))
    mb.hull(pts, "go_wood_dark")
    mb.box((0, 0.1, 0.44), (1.1, 3.4, 0.05), "go_wood")
    for y in (-1.3, 1.3):
        mb.box((0, y, 0.5), (1.3, 0.22, 0.08), "go_wood")
    mb.cyl_between(Vector((0.35, -2.0, 0.42)), Vector((0.35, -2.1, 2.0)), 0.04, 0.035, "go_iron", segs=4)
    mb.cyl_between(Vector((0.35, -2.1, 2.0)), Vector((0.35, -1.7, 2.05)), 0.03, 0.03, "go_iron", segs=4)
    mb.box((0.35, -1.7, 1.7), (0.2, 0.2, 0.3), "go_lamp")
    mb.box((0.35, -1.7, 1.88), (0.26, 0.26, 0.06), "go_iron")
    _coffin(mb, Vector((0, 0.35, 0.46)), 0.0, 0.78)
    mb.box((0, 0.35, 0.86), (0.66, 1.3, 0.04), "go_cloth_dark")
    mb.finish("gothic_boat")


def build_gothic_undercroft():
    """The Abbey Undercroft's entrance (8 m wide in X, ~5 m deep; front -Y): a gabled portal with
    three archivolts before a buttressed wall, a black doorway with a red glow from the stairs
    below, a half-open iron gate, a skull over the door, red lanterns on iron brackets."""
    mb = MeshBuilder()
    mb.box((0, 1.0, 3.3), (8.0, 3.0, 6.6), "go_stone")
    mb.box((0, 1.0, 6.7), (8.3, 3.3, 0.24), "go_stone_light")
    town.gable_roof_x(mb, 8.5, 1.9, 6.8, 8.4, 0.2, "go_slate", y0=1.0)
    mb.prism([(-1.5, 6.79), (1.5, 6.79), (0.0, 8.2)], -4.0, 4.0, "go_stone", frame=(Vector((0, 1.0, 0)), Y, Z, X))
    for sx in (-1, 1):
        mb.box((sx * 3.6, -0.6, 3.0), (0.8, 0.8, 6.0), "go_stone_b")
        pinnacle(mb, sx * 3.6, -0.6, 6.0, s=0.6, h=2.0)
        wf = Face((sx * 2.9, -0.5, 0), X, Z, -Y)
        wf.prism(mb, lancet(0.0, 2.2, 0.6, 2.6, n=3), -0.01, 0.06, "go_stone_light")
        wf.prism(mb, lancet(0.0, 2.3, 0.4, 2.3, n=3), -0.01, 0.1, "go_void")
    # the portal
    mb.box((0, -1.4, 2.9), (4.4, 1.8, 5.8), "go_stone")
    mb.prism([(-2.2, 5.79), (2.2, 5.79), (0.0, 8.3)], 0.0, 1.8, "go_stone", frame=(Vector((0, -0.5, 0)), X, Z, -Y))
    mb.prism([(-2.45, 5.52), (0.0, 8.32), (2.45, 5.52), (2.45, 5.72), (0.0, 8.52), (-2.45, 5.72)], -2.45, -0.35, "go_slate",
             frame=(Vector((0, 0, 0)), -X, Z, Y))
    fr = Face((0, -2.3, 0), X, Z, -Y)
    for k, (ww, hh, mat) in enumerate(((3.6, 4.9, "go_stone_light"), (3.1, 4.5, "go_stone_b"), (2.6, 4.1, "go_stone_light"))):
        fr.prism(mb, lancet(0.0, 0.3, ww, hh, n=4), -0.02, 0.1 + k * 0.08, mat)
    fr.prism(mb, lancet(0.0, 0.3, 2.1, 3.7, n=4), -0.01, 0.36, "go_void")
    fr.box(mb, 0.0, 0.45, 1.9, 0.3, 0.2, 0.4, "go_ember")
    fr.box(mb, 0.0, 0.15, 3.8, 0.3, 0.0, 0.9, "go_stone_dark", bevel=0.02)
    # iron gate: the left leaf shut, the right leaf swung open
    for k in range(5):
        u = -1.0 + k * 0.2
        fr.box(mb, u, 1.85, 0.05, 3.0, 0.4, 0.44, "go_iron")
    fr.box(mb, -0.6, 1.0, 0.9, 0.06, 0.4, 0.44, "go_iron")
    fr.box(mb, -0.6, 2.6, 0.9, 0.06, 0.4, 0.44, "go_iron")
    hinge = Vector((1.05, -2.72, 0.3))
    ang = math.radians(-62.0)
    dx = Vector((math.cos(ang), math.sin(ang), 0.0))
    for k in range(5):
        c = hinge + dx * (0.1 + k * 0.2) + Vector((0, 0, 1.55))
        mb.obox(c, (dx, dx.cross(Z), Z), (0.05, 0.05, 3.0), "go_iron")
    for zz in (0.7, 2.3):
        c = hinge + dx * 0.5 + Vector((0, 0, zz))
        mb.obox(c, (dx, dx.cross(Z), Z), (1.0, 0.05, 0.06), "go_iron")
    # skull over the door, finial, red lanterns on brackets
    mb.ico((0.0, -2.4, 5.75), 0.34, "go_stone_pale", subdiv=1, scale=(1.0, 0.8, 1.05))
    for sx in (-1, 1):
        mb.ico((sx * 0.12, -2.64, 5.8), 0.08, "go_void", subdiv=0)
    pinnacle(mb, 0.0, -2.2, 8.2, s=0.3, h=1.2)
    for sx in (-1, 1):
        fr.box(mb, sx * 2.0, 3.6, 0.08, 0.08, 0.0, 0.8, "go_iron")
        fr.box(mb, sx * 2.0, 3.25, 0.3, 0.45, 0.6, 0.9, "go_blood")
        fr.box(mb, sx * 2.0, 3.52, 0.38, 0.08, 0.55, 0.95, "go_iron")
    mb.finish("gothic_undercroft")


def build_gothic_arcade():
    """A cloister arcade bay (4 m along X, 3.6 m deep; the arches face -Y, onto the garth): two
    pointed arches on slender columns, the back wall with a small window, a lean-to slate roof,
    a flagstone walk. Bays chain along X (the column at +2 m belongs to the next bay)."""
    mb = MeshBuilder()
    W = 4.0
    mb.box((0, 1.55, 2.7), (W, 0.5, 5.4), "go_stone")
    mb.box((0, 0.0, 0.06), (W, 3.6, 0.12), "go_stone_b")
    for x in (-2.0, 0.0):
        mb.box((x, -1.55, 0.25), (0.46, 0.46, 0.5), "go_stone_dark")
        mb.cyl((x, -1.55, 1.65), 0.16, 0.14, 2.3, "go_stone_light", segs=6)
        mb.box((x, -1.55, 2.9), (0.5, 0.5, 0.2), "go_stone_light")
    frame = (Vector((0, -1.3, 0)), X, Z, -Y)
    for k in range(2):
        x0 = -2.0 + k * 2.0
        x1 = x0 + 2.0
        poly = [(x0, 3.0)] + arch_pts(x0 + 1.0, 3.0, 1.5, n=3) + [(x1, 3.0), (x1, 4.5), (x0, 4.5)]
        mb.prism(poly, 0.0, 0.5, "go_stone", frame=frame)
    mb.box((0, -1.55, 4.56), (W, 0.62, 0.14), "go_stone_light")
    # lean-to roof from the back wall down over the arcade
    a = Vector((0, 1.9, 5.5))
    b = Vector((0, -2.05, 4.5))
    dd = (b - a)
    nrm = dd.normalized().cross(X)
    if nrm.z < 0:
        nrm = -nrm
    mb.obox((a + b) / 2 + nrm * 0.1, (X, dd.normalized(), nrm), (W + 0.02, dd.length, 0.2), "go_slate")
    mb.obox((a + b) / 2 + nrm * 0.24 + dd.normalized() * 0.3, (X, dd.normalized(), nrm), (W + 0.02, dd.length * 0.55, 0.08), "go_slate_b")
    mb.box((0, 1.55, 5.5), (W, 0.6, 0.16), "go_snow")
    cheap_window(mb, Face((0, 1.3, 0), X, Z, -Y), 0.0, 1.6, 0.5, 1.3, False)
    cheap_window(mb, Face((0, 1.8, 0), -X, Z, Y), 0.0, 2.2, 0.5, 1.4, random.Random(71).random() < 0.5)
    mb.finish("gothic_arcade")


def build_gothic_gallows():
    """Gallows on a plank scaffold (4.6 x 3.2 m, beam at ~5 m; steps at the front, -Y): two posts
    and a braced crossbeam with two nooses, a trapdoor, a hanging iron cage."""
    mb = MeshBuilder()
    mb.box((0, 0.2, 1.1), (4.6, 3.2, 0.14), "go_wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 2.1, 0.2 + sy * 1.4, 0.55), (0.22, 0.22, 1.1), "go_wood_dark")
    for sx in (-1, 1):
        mb.box((sx * 2.1, -1.2, 0.55), (0.1, 0.1, 1.0), "go_wood_dark", rot=(0.6, 0, 0))
    for k in range(3):
        hh = 0.9 - k * 0.3
        mb.box((0, -1.6 - k * 0.4, hh / 2), (1.4, 0.4, hh), "go_wood")
    mb.box((0.6, 0.6, 1.18), (1.2, 1.0, 0.03), "go_wood_dark")
    for sx in (-1, 1):
        mb.box((sx * 1.8, 0.9, 3.1), (0.26, 0.26, 4.0), "go_wood_dark")
        mb.cyl_between(Vector((sx * 1.8, 0.9, 4.2)), Vector((sx * 1.0, 0.9, 5.0)), 0.07, 0.07, "go_wood_dark", segs=4)
    mb.box((0, 0.9, 5.15), (4.4, 0.28, 0.3), "go_wood_dark")
    for x in (-0.6, 0.6):
        mb.box((x, 0.9, 4.45), (0.04, 0.04, 1.1), "go_rope")
        mb.cyl((x, 0.9, 3.78), 0.16, 0.16, 0.05, "go_rope", segs=6, rot=(math.pi / 2, 0, 0))
    # a cage hanging from the beam's end
    mb.box((2.0, 0.9, 4.7), (0.04, 0.04, 0.7), "go_iron")
    mb.box((2.0, 0.9, 3.4), (0.7, 0.7, 0.06), "go_iron")
    mb.box((2.0, 0.9, 4.33), (0.7, 0.7, 0.06), "go_iron")
    for ax in (-1, 1):
        for ay in (-1, 1):
            mb.box((2.0 + ax * 0.33, 0.9 + ay * 0.33, 3.86), (0.04, 0.04, 0.9), "go_iron")
    mb.box((2.0, 0.9, 3.5), (0.34, 0.22, 0.14), "go_stone_pale")
    mb.finish("gothic_gallows")



def build_gothic_snowdrift():
    """A low drift of snow (~2.9 x 1.3 m, 0.2 m high) to lie along walls, fences and kerbs: a soft
    irregular mound with a flat base."""
    rng = random.Random(83)
    mb = MeshBuilder()
    pts = []
    for ring, (sx, sy, z) in enumerate(((1.45, 0.66, 0.0), (1.12, 0.52, 0.09), (0.62, 0.27, 0.17))):
        n = 9
        ph = rng.uniform(0.0, 1.0)
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (ring % 2)) / n
            j = 1.0 + 0.06 * math.sin(2 * a + ph * 6.0)
            pts.append((math.cos(a) * sx * j, math.sin(a) * sy * j, z))
    pts.append((0.1, 0.05, 0.2))
    mb.hull(pts, "go_snow_dim")
    mb.finish("gothic_snowdrift")



def build_gothic_railing():
    """Wrought-iron railing, 6 m along X centred on the origin (three fence bays in one piece, for
    long runs): stone kerb and coping, bars with spear tips, two rails, a band of diamonds."""
    mb = MeshBuilder()
    L = 6.0
    mb.box((0, 0, 0.16), (L, 0.3, 0.32), "go_stone_b")
    mb.box((0, 0, 0.35), (L, 0.22, 0.06), "go_stone_light")
    n = 25
    for k in range(n):
        x = -L / 2 + 0.12 + k * ((L - 0.24) / (n - 1))
        mb.box((x, 0, 1.05), (0.035, 0.035, 1.4), "go_iron")
        mb.cyl((x, 0, 1.83), 0.045, 0.0, 0.16, "go_iron", segs=4, twist=math.pi / 4)
    for zz in (0.55, 1.6):
        mb.box((0, 0, zz), (L, 0.045, 0.05), "go_iron")
    for k in range(12):
        x = -L / 2 + 0.25 + k * ((L - 0.5) / 11)
        mb.box((x, 0, 1.42), (0.14, 0.04, 0.14), "go_iron", rot=(0, math.pi / 4, 0))
    mb.finish("gothic_railing")



def build_gothic_shed():
    """A low stone outbuilding for the yards behind the townhouses (5.6 x 3.8 m, ~3.9 m): walls,
    a lean-to slate roof falling to the front (-Y), a plank door, a small lit window, snow."""
    mb = MeshBuilder()
    w, d = 5.6, 3.8
    mb.box((0, 0, 0.15), (w + 0.16, d + 0.16, 0.3), "go_stone_dark")
    mb.box((0, 0, 1.4), (w, d, 2.2), "go_stone_b")
    mb.prism([(-d / 2, 2.49), (d / 2, 2.49), (d / 2, 3.5), (-d / 2, 2.6)], -w / 2, w / 2, "go_stone_b",
             frame=(Vector((0, 0, 0)), Y, Z, X))
    a = Vector((0, d / 2 + 0.25, 3.62))
    b = Vector((0, -d / 2 - 0.4, 2.45))
    dd = b - a
    nrm = dd.normalized().cross(X)
    if nrm.z < 0:
        nrm = -nrm
    mb.obox((a + b) / 2 + nrm * 0.1, (X, dd.normalized(), nrm), (w + 0.4, dd.length, 0.2), "go_slate")
    mb.obox(a + dd * 0.12 + nrm * 0.2, (X, dd.normalized(), nrm), (w + 0.3, dd.length * 0.2, 0.06), "go_snow")
    fr = Face((0, -d / 2, 0), X, Z, -Y)
    fr.box(mb, -1.3, 1.25, 1.1, 1.9, -0.01, 0.1, "go_wood_dark")
    for vv in (0.8, 1.7):
        fr.box(mb, -1.3, vv, 1.0, 0.07, 0.08, 0.13, "go_iron")
    fr.box(mb, 1.2, 1.55, 0.7, 0.6, -0.02, 0.06, "go_stone_light")
    fr.box(mb, 1.2, 1.55, 0.54, 0.46, -0.01, 0.09, "go_window_dim")
    town.chimney(mb, w * 0.3, d * 0.2, 2.4, 4.3, "go_stone_dark", "go_stone_light")
    mb.finish("gothic_shed")



def build_gothic_roofs():
    """A block of the town seen from afar (24 x 14 m, ~12-15 m): two rows of houses back to back
    under slate roofs of different heights and directions, chimneys, a few lit windows. Few
    triangles: it fills the town beyond the zones (overview, far camera)."""
    rng = random.Random(97)
    mb = MeshBuilder()
    xs = [(-12.0, -6.0), (-6.0, -1.0), (-1.0, 6.0), (6.0, 12.0)]
    for row, (y0, y1) in enumerate(((-7.0, -0.2), (0.2, 7.0))):
        for k, (x0, x1) in enumerate(xs):
            h = rng.uniform(7.5, 10.5)
            w = x1 - x0 - 0.2
            d = y1 - y0
            cx = (x0 + x1) / 2
            cy = (y0 + y1) / 2
            mb.box((cx, cy, h / 2), (w, d, h), "go_stone" if (k + row) % 2 == 0 else "go_stone_b")
            rise = rng.uniform(3.0, 4.5)
            if (k + row) % 2 == 0:
                mb.prism([(-d / 2 - 0.2, h), (d / 2 + 0.2, h), (0.0, h + rise)], -w / 2 - 0.2, w / 2 + 0.2, "go_slate",
                         frame=(Vector((cx, cy, 0)), Y, Z, X))
            else:
                mb.prism([(-w / 2 - 0.2, h), (w / 2 + 0.2, h), (0.0, h + rise)], -d / 2 - 0.2, d / 2 + 0.2, "go_slate_b",
                         frame=(Vector((cx, cy, 0)), X, Z, -Y))
            mb.box((cx + w * 0.25, cy, h + rise * 0.6), (0.6, 0.6, rise * 1.2), "go_stone_dark")
            f = Face((cx, y0 if row == 0 else y1, 0), X, Z, -Y) if row == 0 else Face((cx, y1, 0), -X, Z, Y)
            for j in range(2):
                if rng.random() < 0.55:
                    f.box(mb, rng.uniform(-w / 4, w / 4), 2.5 + j * 3.0, 0.7, 1.2, -0.01, 0.06, "go_window" if rng.random() < 0.7 else "go_window_dim")
    mb.finish("gothic_roofs")


BUILDERS = {
    "gothic_cobble_a": build_gothic_cobble_a,
    "gothic_cobble_b": build_gothic_cobble_b,
    "gothic_cobble_c": build_gothic_cobble_c,
    "gothic_cobble_d": build_gothic_cobble_d,
    "gothic_house_a": build_gothic_house_a,
    "gothic_house_b": build_gothic_house_b,
    "gothic_house_c": build_gothic_house_c,
    "gothic_house_d": build_gothic_house_d,
    "gothic_cathedral": build_gothic_cathedral,
    "gothic_clocktower": build_gothic_clocktower,
    "gothic_lamp": build_gothic_lamp,
    "gothic_fence": build_gothic_fence,
    "gothic_pillar": build_gothic_pillar,
    "gothic_balustrade": build_gothic_balustrade,
    "gothic_carriage": build_gothic_carriage,
    "gothic_coffin": build_gothic_coffin,
    "gothic_grave_a": build_gothic_grave_a,
    "gothic_grave_b": build_gothic_grave_b,
    "gothic_statue": build_gothic_statue,
    "gothic_dead_tree": build_gothic_dead_tree,
    "gothic_fountain": build_gothic_fountain,
    "gothic_shrine": build_gothic_shrine,
    "gothic_stall": build_gothic_stall,
    "gothic_crypt": build_gothic_crypt,
    "gothic_puddle": build_gothic_puddle,
    "gothic_blood": build_gothic_blood,
    "gothic_bench": build_gothic_bench,
    "gothic_planter": build_gothic_planter,
    "gothic_terrace_a": build_gothic_terrace_a,
    "gothic_terrace_b": build_gothic_terrace_b,
    "gothic_gate": build_gothic_gate,
    "gothic_great_bridge": build_gothic_great_bridge,
    "gothic_bridge_tower": build_gothic_bridge_tower,
    "gothic_canal_bridge": build_gothic_canal_bridge,
    "gothic_boat": build_gothic_boat,
    "gothic_undercroft": build_gothic_undercroft,
    "gothic_arcade": build_gothic_arcade,
    "gothic_gallows": build_gothic_gallows,
    "gothic_snowdrift": build_gothic_snowdrift,
    "gothic_railing": build_gothic_railing,
    "gothic_shed": build_gothic_shed,
    "gothic_roofs": build_gothic_roofs,
}
