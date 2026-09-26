"""Town set (town_*): three distinct houses (~6x6 m footprint, ~6 m tall), well, two trees,
fence segment (2 m along X), lamp post, market stall, stash chest, cart, bush, rock.

Blender axes: Z up, fronts face -Y (= Godot +Z, toward the camera). Origin at the base centre.
OWNER: assets-environment.
"""

import math
import random

from mathutils import Matrix, Vector

import envlib as L
from envlib import MeshBuilder
import dungeon

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


# ----------------------------------------------------------------------------------- facade helpers

class Face:
    """A planar facade: point = origin + u*a + v*b + n*c, n = outward normal (u x v = n)."""

    def __init__(self, origin, u, v, n):
        self.o = Vector(origin)
        self.u = Vector(u)
        self.v = Vector(v)
        self.n = Vector(n)

    def p(self, a, b, c=0.0):
        return self.o + self.u * a + self.v * b + self.n * c

    def box(self, mb, uc, vc, w, h, n0, n1, mat, bevel=0.0):
        """Box spanning [uc-w/2, uc+w/2] x [vc-h/2, vc+h/2] x [n0, n1] in face coordinates."""
        return mb.obox(self.p(uc, vc, (n0 + n1) / 2), (self.u, self.v, self.n), (w, h, n1 - n0), mat, bevel)

    def beam(self, mb, a0, b0, a1, b1, width, mat, n0=-0.02, n1=0.05):
        """Timber beam in the face plane from (a0, b0) to (a1, b1)."""
        du, dv = a1 - a0, b1 - b0
        ln = math.hypot(du, dv)
        dx, dy = du / ln, dv / ln
        A = self.u * dx + self.v * dy
        B = self.u * -dy + self.v * dx
        c = self.p((a0 + a1) / 2, (b0 + b1) / 2, (n0 + n1) / 2)
        return mb.obox(c, (A, B, self.n), (ln, width, n1 - n0), mat)

    def prism(self, mb, poly, n0, n1, mat):
        return mb.prism(poly, n0, n1, mat, frame=(self.o, self.u, self.v, self.n))


def box_faces(w, d):
    """The four outward faces of an axis box of width w (X) and depth d (Y) centred at 0."""
    return {
        "front": Face((0, -d / 2, 0), X, Z, -Y),
        "right": Face((w / 2, 0, 0), Y, Z, X),
        "back": Face((0, d / 2, 0), -X, Z, Y),
        "left": Face((-w / 2, 0, 0), -Y, Z, -X),
    }


def window(mb, f, uc, vc, w, h, glow=False, shutters=None, frame="wood_dark", box=False):
    f.box(mb, uc, vc, w, h, -0.04, 0.01, "emit_window" if glow else "window_dark")
    t = 0.08
    f.box(mb, uc, vc + h / 2 + t / 2, w + 2 * t, t, -0.02, 0.07, frame)
    f.box(mb, uc, vc - h / 2 - t / 2, w + 2 * t + 0.1, t, -0.02, 0.12, frame)
    f.box(mb, uc - w / 2 - t / 2, vc, t, h, -0.02, 0.07, frame)
    f.box(mb, uc + w / 2 + t / 2, vc, t, h, -0.02, 0.07, frame)
    f.box(mb, uc, vc, 0.045, h, 0.0, 0.04, frame)
    f.box(mb, uc, vc + h * 0.1, w, 0.045, 0.0, 0.04, frame)
    if shutters:
        sw = w * 0.52
        for s in (-1, 1):
            f.box(mb, uc + s * (w / 2 + t + sw / 2 + 0.01), vc, sw, h + 0.1, 0.0, 0.045, shutters)
            f.box(mb, uc + s * (w / 2 + t + sw / 2 + 0.01), vc + h * 0.25, sw * 0.9, 0.04, 0.045, 0.065, frame)
            f.box(mb, uc + s * (w / 2 + t + sw / 2 + 0.01), vc - h * 0.25, sw * 0.9, 0.04, 0.045, 0.065, frame)
    if box:
        # flower box with flowers
        f.box(mb, uc, vc - h / 2 - 0.2, w + 0.2, 0.2, 0.0, 0.26, "wood")
        for k in range(5):
            a = uc - w / 2 + (k + 0.5) * w / 5
            c = f.p(a, vc - h / 2 - 0.06, 0.13)
            mb.ico(c, 0.085, "leaf" if k % 2 else "leaf_dark", subdiv=1, scale=(1, 1, 0.8))
            c2 = f.p(a + 0.03, vc - h / 2 + 0.0, 0.16)
            mb.ico(c2, 0.045, "fruit_red" if k % 2 == 0 else "fruit_yellow", subdiv=0)


def door(mb, f, uc, v0, w, h, leaf="wood", frame="wood_dark", arch=False, step="town_stone_dark"):
    if arch:
        r = w / 2
        poly = [(uc - r, v0), (uc + r, v0), (uc + r, v0 + h - r)]
        for i in range(1, 8):
            a = math.pi * i / 8
            poly.append((uc + r * math.cos(a), v0 + h - r + r * math.sin(a)))
        poly.append((uc - r, v0 + h - r))
        # stone surround (bigger arch), then the leaf
        R = r + 0.14
        sur = [(uc - R, v0), (uc + R, v0), (uc + R, v0 + h - r)]
        for i in range(1, 8):
            a = math.pi * i / 8
            sur.append((uc + R * math.cos(a), v0 + h - r + R * math.sin(a)))
        sur.append((uc - R, v0 + h - r))
        f.prism(mb, sur, -0.02, 0.05, frame)
        f.prism(mb, poly, 0.0, 0.08, leaf)
    else:
        f.box(mb, uc, v0 + h / 2, w, h, -0.04, 0.03, leaf)
        t = 0.1
        f.box(mb, uc, v0 + h + t / 2, w + 2 * t, t, -0.02, 0.08, frame)
        f.box(mb, uc - w / 2 - t / 2, v0 + h / 2, t, h, -0.02, 0.08, frame)
        f.box(mb, uc + w / 2 + t / 2, v0 + h / 2, t, h, -0.02, 0.08, frame)
    # planks + iron bands + handle
    for k in (-1, 1):
        f.box(mb, uc + k * w / 4, v0 + h * 0.45, 0.025, h * 0.85, 0.03, 0.095, frame)
    for vv in (0.25, 0.7):
        f.box(mb, uc, v0 + h * vv, w * 0.9, 0.06, 0.03, 0.1, "iron")
    f.box(mb, uc + w * 0.32, v0 + h * 0.48, 0.06, 0.12, 0.03, 0.13, "iron")
    if step and v0 > 0.02:
        f.box(mb, uc, v0 / 2, w + 0.5, v0, 0.0, 0.45, step, bevel=0.02)


def gable_roof_x(mb, length, half_span, z_eave, z_ridge, thick, mat, y0=0.0):
    """Thick inverted-V roof with the ridge along X. Returns inner height function z_in(|y|)."""
    W = half_span
    poly = [(-W, z_eave - thick), (0.0, z_ridge - thick), (W, z_eave - thick), (W, z_eave),
            (0.0, z_ridge), (-W, z_eave)]
    frame = (Vector((-length / 2, y0, 0)), Y, Z, X)
    mb.prism(poly, 0.0, length, mat, frame=frame)
    return lambda y: z_ridge - thick - (z_ridge - z_eave) * abs(y) / W


def gable_roof_y(mb, length, half_span, z_eave, z_ridge, thick, mat, x0=0.0):
    """Same with the ridge along Y (gable facing the front)."""
    W = half_span
    poly = [(-W, z_eave - thick), (0.0, z_ridge - thick), (W, z_eave - thick), (W, z_eave),
            (0.0, z_ridge), (-W, z_eave)]
    # u = -X, v = Z, n = Y  (u x v = n): poly u-coordinate is -x, symmetric so fine
    frame = (Vector((x0, -length / 2, 0)), -X, Z, Y)
    mb.prism(poly, 0.0, length, mat, frame=frame)
    return lambda x: z_ridge - thick - (z_ridge - z_eave) * abs(x) / W


def shingle_rows(mb, length, half_span, z_eave, z_ridge, mats, rows=5, th=0.1, delta_deg=6.0,
                 axis="x", overhang=0.05, lift=0.0):
    """Overlapping courses on both slopes of a gable roof, each a slab tilted slightly steeper
    than the roof so its lower edge steps out (reads as thatch / tiles from above).
    axis = direction of the ridge. mats = list of materials cycled per row."""
    W = half_span
    H = z_ridge - z_eave
    theta = math.atan2(H, W)
    slope_len = math.hypot(W, H)
    seg = slope_len / rows
    d = math.radians(delta_deg)
    for side in (-1, 1):
        roof_n = Vector((0.0, side * math.sin(theta), math.cos(theta)))
        B = Vector((0.0, -side * math.cos(theta + d), math.sin(theta + d)))
        C = Vector((0.0, side * math.sin(theta + d), math.cos(theta + d)))
        for r in range(rows):
            t0 = r / rows
            S = Vector((0.0, side * W * (1 - t0), z_eave + H * t0)) + roof_n * (0.01 + lift)
            if r == 0:
                S += Vector((0.0, side * overhang * math.cos(theta), -overhang * math.sin(theta)))
            ln = seg * 1.25 + (overhang if r == 0 else 0.0)
            if r == rows - 1:
                ln = seg * 1.02
            ctr = S + B * (ln / 2) + C * (th / 2)
            A = Vector((1.0, 0.0, 0.0))
            b, c = B, C
            if axis == "y":
                A = Vector((0.0, 1.0, 0.0))
                ctr = Vector((ctr.y, ctr.x, ctr.z))
                b = Vector((B.y, B.x, B.z))
                c = Vector((C.y, C.x, C.z))
            mb.obox(ctr, (A, b, c), (length, ln, th), mats[r % len(mats)])


def chimney(mb, x, y, z0, z1, mat="town_stone_dark", cap="town_stone"):
    mb.box((x, y, (z0 + z1) / 2), (0.62, 0.62, z1 - z0), mat, bevel=0.02)
    mb.box((x, y, z1 + 0.06), (0.76, 0.76, 0.12), cap, bevel=0.02)
    mb.box((x, y, z1 + 0.13), (0.4, 0.4, 0.04), "coal")


# ----------------------------------------------------------------------------------- houses

def build_town_house_a():
    """Timber-framed cottage with a thatched gable roof and a chimney."""
    mb = MeshBuilder()
    W, D = 5.0, 4.4
    base = 0.35
    # foundation + walls
    mb.box((0, 0, base / 2), (W + 0.3, D + 0.3, base), "town_stone_dark", bevel=0.04)
    z_in = gable_roof_x(mb, W + 0.9, 2.95, 2.95, 5.65, 0.34, "roof_thatch")
    wall_top = z_in(D / 2) + 0.02
    mb.box((0, 0, (base + wall_top) / 2), (W, D, wall_top - base), "plaster")
    # attic gable (under the roof)
    apex = z_in(0) + 0.02
    mb.prism([(-D / 2, wall_top - 0.01), (D / 2, wall_top - 0.01), (0, apex)], -W / 2, W / 2, "plaster",
             frame=(Vector((0, 0, 0)), Y, Z, X))
    # thatch layers, ridge roll and a darker eave edge
    shingle_rows(mb, W + 0.94, 2.95, 2.95, 5.65, ["roof_thatch", "roof_thatch_b"], rows=5, th=0.13, delta_deg=7.0)
    mb.cyl_between((-(W + 0.9) / 2 - 0.02, 0, 5.6), ((W + 0.9) / 2 + 0.02, 0, 5.6), 0.24, 0.24, "roof_thatch_dark", segs=6)
    for sy in (-1, 1):
        mb.box((0, sy * 2.93, 2.8), (W + 0.94, 0.12, 0.2), "roof_thatch_dark", rot=(-sy * math.atan(2.7 / 2.95), 0, 0))
    faces = box_faces(W, D)
    fr, rt, bk, lf = faces["front"], faces["right"], faces["back"], faces["left"]
    tw = 0.16
    top = wall_top - 0.08
    # timber frame: corner posts, sill, rail, top plate on all sides
    for f, half in ((fr, W / 2), (bk, W / 2), (rt, D / 2), (lf, D / 2)):
        f.beam(mb, -half + 0.08, base, -half + 0.08, top + 0.08, tw, "wood_dark")
        f.beam(mb, half - 0.08, base, half - 0.08, top + 0.08, tw, "wood_dark")
        f.beam(mb, -half, base + 0.06, half, base + 0.06, tw, "wood_dark")
        f.beam(mb, -half, top, half, top, tw, "wood_dark")
    # front: door, window, posts, rail, braces
    door(mb, fr, -1.3, base, 0.95, 1.95)
    window(mb, fr, 0.9, 1.75, 0.9, 0.8, glow=True, shutters="cloth_green", box=True)
    for u in (-0.55, 1.95):
        fr.beam(mb, u, base, u, top, 0.13, "wood_dark")
    fr.beam(mb, -W / 2, 2.6, W / 2, 2.6, 0.12, "wood_dark")
    fr.beam(mb, -2.42, base + 0.1, -1.95, 1.3, 0.11, "wood_dark")
    fr.beam(mb, 2.42, base + 0.1, 2.0, 1.1, 0.11, "wood_dark")
    fr.beam(mb, -0.55, 2.62, 0.7, top - 0.04, 0.11, "wood_dark")
    fr.beam(mb, 1.95, 2.62, 0.7, top - 0.04, 0.11, "wood_dark")
    # sides
    for f in (rt, lf):
        window(mb, f, 0.0, 1.8, 0.75, 0.75, glow=False, shutters="cloth_green")
        for u in (-1.05, 1.05):
            f.beam(mb, u, base, u, top, 0.13, "wood_dark")
        f.beam(mb, -2.15, base + 0.1, -1.05, 1.9, 0.11, "wood_dark")
        f.beam(mb, 2.15, base + 0.1, 1.05, 1.9, 0.11, "wood_dark")
        # gable timber (triangle above the wall)
        f.beam(mb, -D / 2 + 0.1, wall_top, 0.0, apex - 0.12, 0.13, "wood_dark")
        f.beam(mb, D / 2 - 0.1, wall_top, 0.0, apex - 0.12, 0.13, "wood_dark")
        f.beam(mb, 0.0, wall_top, 0.0, apex - 0.15, 0.13, "wood_dark")
        f.box(mb, 0.0, wall_top + 0.75, 0.42, 0.42, -0.03, 0.02, "emit_window")
        f.box(mb, 0.0, wall_top + 0.75, 0.52, 0.06, 0.0, 0.05, "wood_dark")
    # back
    window(mb, bk, -1.2, 1.75, 0.8, 0.8)
    window(mb, bk, 1.2, 1.75, 0.8, 0.8, glow=True)
    for u in (-0.4, 0.4):
        bk.beam(mb, u, base, u, top, 0.13, "wood_dark")
    # dormer on the front slope (breaks up the big thatch plane seen from the high camera)
    dx, dy = -0.75, -1.45
    mb.box((dx, dy + 0.55, 4.55), (1.05, 1.1, 1.0), "plaster")
    df = Face((dx, dy, 0), X, Z, -Y)
    df.box(mb, 0.0, 4.8, 0.5, 0.36, -0.03, 0.01, "emit_window")
    df.box(mb, 0.0, 4.8, 0.62, 0.06, 0.0, 0.05, "wood_dark")
    df.box(mb, 0.0, 4.8, 0.05, 0.48, 0.0, 0.05, "wood_dark")
    df.beam(mb, -0.52, 4.1, -0.52, 5.05, 0.1, "wood_dark")
    df.beam(mb, 0.52, 4.1, 0.52, 5.05, 0.1, "wood_dark")
    mb.prism([(-0.72, 4.98), (0.72, 4.98), (0.0, 5.48)], 0.0, 1.35, "roof_thatch",
             frame=(Vector((dx, dy - 0.15, 0)), -X, Z, Y))
    mb.prism([(-0.78, 4.92), (0.78, 4.92), (0.0, 5.47)], -0.03, 0.12, "roof_thatch_dark",
             frame=(Vector((dx, dy - 0.15, 0)), -X, Z, Y))
    # chimney through the roof
    chimney(mb, 1.55, 1.0, 2.0, 6.15)
    # small woodpile by the side
    for k in range(4):
        x = W / 2 + 0.2
        y = -1.95 + k * 0.22
        mb.cyl_between((x - 0.25, y, 0.1 + (k % 2) * 0.0), (x + 0.25, y, 0.1), 0.1, 0.1, "bark", segs=6)
    for k in range(3):
        x = W / 2 + 0.2
        y = -1.84 + k * 0.22
        mb.cyl_between((x - 0.25, y, 0.28), (x + 0.25, y, 0.28), 0.1, 0.1, "wood_light", segs=6)
    mb.finish("town_house_a")


def build_town_house_b():
    """Stone house with a slate hip roof, arched door, blue shutters and quoins."""
    mb = MeshBuilder()
    W, D = 5.2, 4.9
    H = 3.3
    mb.box((0, 0, 0.15), (W + 0.3, D + 0.3, 0.3), "town_stone_dark", bevel=0.04)
    mb.box((0, 0, H / 2), (W, D, H), "town_stone")
    # hip roof as a convex hull (flat underside, thin rim, sloped planes)
    ex, ey = 2.95, 2.8
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts.append((sx * ex, sy * ey, H - 0.1))
            pts.append((sx * ex, sy * ey, H + 0.12))
    pts += [(-1.15, 0, 5.75), (1.15, 0, 5.75)]
    mb.hull(pts, "roof_slate")
    # ridge cap
    mb.cyl_between((-1.2, 0, 5.74), (1.2, 0, 5.74), 0.09, 0.09, "town_stone_dark", segs=6)
    # slate courses: thin darker strips following the slopes
    for k in range(1, 4):
        t = k / 4
        z = H + 0.12 + (5.75 - H - 0.12) * t
        hx = ex + (1.15 - ex) * t
        hy = ey * (1 - t)
        for sy in (-1, 1):
            mb.box((0, sy * (hy + 0.03), z + 0.012), (2 * hx, 0.08, 0.03), "roof_slate_dark",
                   rot=(-sy * math.atan((5.75 - H) / ey), 0, 0))
    faces = box_faces(W, D)
    fr, rt, bk, lf = faces["front"], faces["right"], faces["back"], faces["left"]
    # quoins on the corners
    for f, half in ((fr, W / 2), (bk, W / 2), (rt, D / 2), (lf, D / 2)):
        for k in range(6):
            z = 0.35 + k * 0.5
            w = 0.5 if k % 2 == 0 else 0.3
            for s in (-1, 1):
                f.box(mb, s * (half - w / 2), z + 0.2, w, 0.4, -0.02, 0.035, "stone_quoin")
        # string course under the eaves
        f.box(mb, 0, H - 0.12, 2 * half + 0.06, 0.14, -0.02, 0.05, "town_stone_dark")
    door(mb, fr, 0.0, 0.3, 1.1, 2.3, leaf="wood", frame="town_stone_dark", arch=True)
    fr.box(mb, 0.0, 0.15, 1.8, 0.3, 0.0, 0.5, "town_stone_dark", bevel=0.02)
    for u in (-1.5, 1.5):
        window(mb, fr, u, 1.85, 0.8, 1.0, glow=(u > 0), frame="wood_dark", box=True)
    for f in (rt, lf):
        window(mb, f, -0.9, 1.85, 0.75, 0.95, shutters="cloth_blue")
        window(mb, f, 1.0, 1.85, 0.75, 0.95, glow=True, shutters="cloth_blue")
    window(mb, bk, 0.0, 1.85, 0.9, 1.0)
    chimney(mb, -1.3, 0.9, 3.0, 6.3)
    # lantern over the door
    c = fr.p(0.0, 2.95, 0.25)
    mb.box(c, (0.18, 0.18, 0.26), "emit_lamp")
    mb.box((c.x, c.y, c.z + 0.16), (0.24, 0.24, 0.06), "iron_dark")
    mb.box((c.x, c.y + 0.12, c.z + 0.16), (0.04, 0.3, 0.04), "iron_dark")
    # barrel + crate by the wall
    mb.lathe([(0.0, 0.0), (0.24, 0.0), (0.28, 0.35), (0.24, 0.72), (0.0, 0.72)], "wood", segs=10,
             center=(-2.25, -2.75, 0.0))
    for z in (0.12, 0.6):
        mb.lathe([(0.25, -0.03), (0.28, -0.03), (0.28, 0.03), (0.25, 0.03)], "iron", segs=10,
                 center=(-2.25, -2.75, z), closed=True)
    mb.finish("town_house_b")


def build_town_house_c():
    """Two-storey tavern: stone ground floor, jettied timber upper floor, red tile roof with the
    gable to the front, hanging sign."""
    mb = MeshBuilder()
    W1, D1, H1 = 4.8, 4.4, 2.5
    W2, D2 = 5.2, 4.8
    mb.box((0, 0, 0.12), (W1 + 0.3, D1 + 0.3, 0.24), "town_stone_dark", bevel=0.03)
    mb.box((0, 0, H1 / 2), (W1, D1, H1), "town_stone")
    mb.box((0, 0, H1 + 0.1), (W2 + 0.1, D2 + 0.1, 0.2), "wood_dark")
    # jetty brackets
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (W1 / 2 + 0.1), sy * (D1 / 2 - 0.2), H1 - 0.15), (0.2, 0.14, 0.3), "wood_dark")
    z_in = gable_roof_y(mb, D2 + 1.0, 2.95, 4.8, 6.7, 0.3, "roof_red")
    shingle_rows(mb, D2 + 1.04, 2.95, 4.8, 6.7, ["roof_red", "roof_red_b"], rows=6, th=0.07, delta_deg=5.0, axis="y")
    top2 = z_in(W2 / 2) + 0.02
    z2 = H1 + 0.2
    mb.box((0, 0, (z2 + top2) / 2), (W2, D2, top2 - z2), "plaster_warm")
    apex = z_in(0) + 0.02
    # front/back gables (triangle prism along Y)
    mb.prism([(-W2 / 2, top2 - 0.01), (W2 / 2, top2 - 0.01), (0, apex)], -D2 / 2, D2 / 2, "plaster_warm",
             frame=(Vector((0, 0, 0)), X, Z, -Y))
    faces1 = box_faces(W1, D1)
    faces2 = box_faces(W2, D2)
    f1, f2 = faces1["front"], faces2["front"]
    # ground floor front
    door(mb, f1, 0.0, 0.24, 1.1, 2.0, leaf="wood_light", frame="wood_dark")
    for u in (-1.55, 1.55):
        window(mb, f1, u, 1.4, 0.85, 0.85, glow=True, frame="wood_dark")
    # door canopy
    c = f1.p(0.0, 2.38, 0.45)
    mb.box((c.x, c.y, c.z), (1.6, 0.9, 0.08), "roof_red", rot=(0.35, 0, 0))
    for s in (-1, 1):
        mb.cyl_between(f1.p(s * 0.7, 2.0, 0.05), f1.p(s * 0.7, 2.3, 0.75), 0.04, 0.04, "wood_dark")
    # upper floor timber + windows
    for f, half in ((faces2["front"], W2 / 2), (faces2["back"], W2 / 2), (faces2["right"], D2 / 2), (faces2["left"], D2 / 2)):
        f.beam(mb, -half + 0.08, z2, -half + 0.08, top2, 0.16, "wood_dark")
        f.beam(mb, half - 0.08, z2, half - 0.08, top2, 0.16, "wood_dark")
        f.beam(mb, -half, top2 - 0.08, half, top2 - 0.08, 0.14, "wood_dark")
    for u in (-1.45, 1.45):
        window(mb, f2, u, 3.65, 0.8, 0.8, glow=(u < 0), box=True)
    for u in (-0.55, 0.55):
        f2.beam(mb, u, z2, u, top2, 0.13, "wood_dark")
    f2.beam(mb, -0.55, z2 + 0.1, 0.55, top2 - 0.15, 0.11, "wood_dark")
    f2.beam(mb, 0.55, z2 + 0.1, -0.55, top2 - 0.15, 0.11, "wood_dark")
    # front gable: king post, collar, round window
    gf = Face((0, -D2 / 2, 0), X, Z, -Y)
    gf.beam(mb, -W2 / 2 + 0.2, top2, 0.0, apex - 0.1, 0.14, "wood_dark")
    gf.beam(mb, W2 / 2 - 0.2, top2, 0.0, apex - 0.1, 0.14, "wood_dark")
    gf.beam(mb, -1.2, top2 + 0.62, 1.2, top2 + 0.62, 0.12, "wood_dark")
    oct_ = [(0.28 * math.cos(math.pi / 8 + k * math.pi / 4), top2 + 1.05 + 0.28 * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)]
    gf.prism(mb, oct_, -0.02, 0.03, "emit_window")
    oct2 = [(0.36 * math.cos(math.pi / 8 + k * math.pi / 4), top2 + 1.05 + 0.36 * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)]
    gf.prism(mb, oct2, -0.03, 0.015, "wood_dark")
    # back gable timber
    gb = Face((0, D2 / 2, 0), -X, Z, Y)
    gb.beam(mb, 0.0, top2, 0.0, apex - 0.12, 0.14, "wood_dark")
    # side windows
    for key in ("right", "left"):
        window(mb, faces1[key], 0.6, 1.4, 0.8, 0.8, frame="wood_dark")
        window(mb, faces2[key], -0.8, 3.65, 0.75, 0.75, glow=True, shutters="cloth_red")
        window(mb, faces2[key], 1.2, 3.65, 0.75, 0.75, shutters="cloth_red")
    window(mb, faces1["back"], -1.2, 1.4, 0.8, 0.8)
    window(mb, faces2["back"], 1.2, 3.65, 0.8, 0.8, glow=True)
    chimney(mb, 1.6, 1.3, 4.0, 7.05)
    # hanging sign (mug)
    bx, by = -2.2, -D2 / 2 - 0.05
    mb.cyl_between((bx, by, 2.3), (bx, by - 0.85, 2.3), 0.035, 0.035, "iron_dark", segs=6)
    mb.cyl_between((bx, by, 1.95), (bx, by - 0.5, 2.3), 0.025, 0.025, "iron_dark", segs=6)
    for yy in (by - 0.2, by - 0.72):
        mb.cyl_between((bx, yy, 2.3), (bx, yy, 2.18), 0.015, 0.015, "iron_dark", segs=4)
    mb.box((bx, by - 0.46, 1.9), (0.06, 0.72, 0.52), "wood", bevel=0.02)
    for s in (-1, 1):
        mb.box((bx + s * 0.035, by - 0.46, 1.9), (0.01, 0.62, 0.42), "wood_dark")
        mb.box((bx + s * 0.042, by - 0.44, 1.88), (0.012, 0.2, 0.24), "sign_paint")
        mb.box((bx + s * 0.042, by - 0.44, 2.04), (0.014, 0.22, 0.06), "cloth_cream")
        mb.box((bx + s * 0.042, by - 0.58, 1.9), (0.012, 0.06, 0.14), "sign_paint")
    # benches / barrels by the door
    mb.box((1.55, -D1 / 2 - 0.45, 0.42), (1.1, 0.35, 0.08), "wood")
    for s in (-1, 1):
        mb.box((1.55 + s * 0.45, -D1 / 2 - 0.45, 0.2), (0.08, 0.3, 0.4), "wood_dark")
    mb.lathe([(0.0, 0.0), (0.26, 0.0), (0.3, 0.4), (0.26, 0.8), (0.0, 0.8)], "wood", segs=10,
             center=(-1.6, -D1 / 2 - 0.5, 0.0))
    for z in (0.14, 0.66):
        mb.lathe([(0.27, -0.03), (0.3, -0.03), (0.3, 0.03), (0.27, 0.03)], "iron", segs=10,
                 center=(-1.6, -D1 / 2 - 0.5, z), closed=True)
    mb.finish("town_house_c")


# ----------------------------------------------------------------------------------- small town props

def build_town_well():
    mb = MeshBuilder()
    # stone ring with water inside
    mb.lathe([(0.0, 0.0), (0.92, 0.0), (0.95, 0.12), (0.95, 0.72), (1.0, 0.78), (1.0, 0.9), (0.66, 0.9),
              (0.66, 0.5), (0.0, 0.5)], "town_stone", segs=12, cap_bottom=False, cap_top=False)
    mb.cyl((0, 0, 0.51), 0.66, 0.66, 0.02, "water", segs=12)
    # stone block bumps around the ring
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        z = 0.3 if i % 2 else 0.55
        mb.box((0.955 * math.cos(a), 0.955 * math.sin(a), z), (0.42, 0.06, 0.2), "town_stone_dark",
               rot=(0, 0, a + math.pi / 2), bevel=0.01)
    # posts, beam, crank, roof
    for s in (-1, 1):
        mb.box((s * 0.82, 0, 1.55), (0.14, 0.14, 1.3), "wood", bevel=0.01)
        mb.box((s * 0.82, 0, 0.95), (0.2, 0.2, 0.12), "wood_dark")
    mb.cyl_between((-0.95, 0, 1.75), (0.95, 0, 1.75), 0.06, 0.06, "wood_dark", segs=8)
    mb.cyl_between((1.0, 0, 1.75), (1.12, 0, 1.75), 0.03, 0.03, "iron", segs=6)
    mb.box((1.12, 0, 1.65), (0.04, 0.04, 0.22), "iron")
    mb.cyl_between((1.12, 0, 1.55), (1.25, 0, 1.55), 0.025, 0.025, "wood_dark", segs=6)
    # rope + bucket
    mb.cyl_between((0.1, 0, 1.74), (0.1, 0, 1.2), 0.015, 0.015, "rope", segs=4)
    mb.lathe([(0.0, 0.0), (0.12, 0.0), (0.15, 0.22), (0.12, 0.22), (0.0, 0.05)], "wood", segs=8,
             center=(0.1, 0, 0.98))
    mb.lathe([(0.135, -0.02), (0.155, -0.02), (0.155, 0.02), (0.135, 0.02)], "iron", segs=8,
             center=(0.1, 0, 1.16), closed=True)
    # little gable roof
    for s in (-1, 1):
        mb.box((0, s * 0.38, 2.4), (2.1, 0.86, 0.07), "roof_red", rot=(s * 0.62, 0, 0))
        mb.box((0, s * 0.72, 2.18), (2.14, 0.08, 0.1), "roof_red_dark", rot=(s * 0.62, 0, 0))
    mb.box((0, 0, 2.69), (2.16, 0.14, 0.1), "wood_dark")
    for s in (-1, 1):
        mb.box((s * 0.82, 0, 2.43), (0.12, 0.12, 0.5), "wood", bevel=0.01)
    mb.clamp_floor()
    mb.finish("town_well")


def build_town_tree_a():
    """Round deciduous tree (~5.5 m)."""
    mb = MeshBuilder()
    rng = random.Random(43)
    mb.lathe([(0.0, 0.0), (0.34, 0.0), (0.24, 0.35), (0.19, 1.6), (0.15, 2.6), (0.0, 2.8)], "bark",
             segs=7, cap_bottom=False)
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.4
        mb.cyl_between((0.1 * math.cos(a), 0.1 * math.sin(a), 0.3),
                       (0.5 * math.cos(a), 0.5 * math.sin(a), 0.0), 0.11, 0.05, "bark", segs=5)
    mb.cyl_between((0, 0, 1.9), (0.9, 0.35, 3.0), 0.1, 0.06, "bark", segs=5)
    mb.cyl_between((0, 0, 2.2), (-0.8, -0.3, 3.2), 0.09, 0.05, "bark", segs=5)
    blobs = [((0.0, 0.0, 3.7), 1.55, "leaf"), ((0.95, 0.35, 3.25), 1.1, "leaf_dark"),
             ((-0.9, -0.3, 3.35), 1.15, "leaf"), ((0.2, -0.75, 3.1), 1.0, "leaf_dark"),
             ((-0.25, 0.8, 3.3), 1.05, "leaf_dark"), ((0.3, 0.2, 4.5), 1.0, "leaf_light")]
    for c, r, m in blobs:
        mb.ico(c, r, m, subdiv=1, jitter=0.12, rng=rng, scale=(1, 1, 0.85))
    mb.clamp_floor()
    mb.finish("town_tree_a")


def build_town_tree_b():
    """Conifer (~6.5 m): stacked jittered cones."""
    mb = MeshBuilder()
    rng = random.Random(47)
    mb.lathe([(0.0, 0.0), (0.26, 0.0), (0.18, 0.3), (0.12, 3.0), (0.0, 3.2)], "bark", segs=6,
             cap_bottom=False)
    tiers = [(0.9, 1.75, 2.0), (1.85, 1.4, 1.8), (2.75, 1.05, 1.6), (3.6, 0.7, 1.5), (4.45, 0.4, 1.4)]
    for k, (z, r, h) in enumerate(tiers):
        verts = mb.lathe([(0.0, 0.0), (r, 0.0), (r * 0.72, 0.28), (0.0, h)], "pine" if k % 2 == 0 else "pine_dark",
                         segs=8, center=(0, 0, z), phase=k * 0.4)
        for v in verts:
            if v.co.z < z + 0.3 and (v.co.x ** 2 + v.co.y ** 2) > 0.01:
                v.co.x += rng.uniform(-0.08, 0.08)
                v.co.y += rng.uniform(-0.08, 0.08)
                v.co.z += rng.uniform(-0.1, 0.06)
    mb.clamp_floor()
    mb.finish("town_tree_b")


def build_town_fence():
    """2 m segment along X, posts at both ends (x = +-1), so segments chain end to end."""
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.box((s * 1.0, 0, 0.5), (0.14, 0.14, 1.0), "wood_grey", bevel=0.01)
        mb.cyl((s * 1.0, 0, 1.06), 0.1, 0.0, 0.12, "wood_grey", segs=4, twist=math.pi / 4)
    for z in (0.42, 0.8):
        mb.box((0, -0.075, z), (2.0, 0.05, 0.13), "wood", bevel=0.008)
    mb.box((0, -0.07, 0.61), (1.95, 0.04, 0.1), "wood_dark", rot=(0, math.atan2(0.3, 1.9), 0))
    mb.finish("town_fence")


def build_town_lamp():
    mb = MeshBuilder()
    mb.box((0, 0, 0.15), (0.5, 0.5, 0.3), "town_stone", bevel=0.04)
    mb.box((0, 0, 0.36), (0.32, 0.32, 0.12), "town_stone_dark", bevel=0.02)
    mb.cyl((0, 0, 1.6), 0.07, 0.055, 2.4, "iron_dark", segs=8)
    mb.cyl((0, 0, 0.5), 0.1, 0.1, 0.12, "iron", segs=8)
    mb.cyl((0, 0, 2.75), 0.1, 0.08, 0.1, "iron", segs=8)
    # lantern
    z0 = 2.82
    mb.box((0, 0, z0 + 0.02), (0.3, 0.3, 0.04), "iron_dark")
    mb.box((0, 0, z0 + 0.22), (0.24, 0.24, 0.36), "emit_lamp")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 0.13, sy * 0.13, z0 + 0.22), (0.035, 0.035, 0.4), "iron_dark")
    mb.cyl((0, 0, z0 + 0.5), 0.26, 0.04, 0.22, "iron_dark", segs=4, twist=math.pi / 4)
    mb.ico((0, 0, z0 + 0.64), 0.05, "iron", subdiv=0)
    mb.finish("town_lamp")


def build_town_stall():
    """Market stall. The counter faces the front (-Y = Godot +Z); the merchant stands behind it at
    Blender (0, 0.5, 0) = Godot (0, 0, -0.5). The striped awning only covers the space behind the
    counter and its front edge is high, so a merchant standing there stays visible from the
    high game camera."""
    mb = MeshBuilder()
    rng = random.Random(53)
    cy = -0.5
    # counter
    mb.box((0, cy, 0.5), (2.4, 0.66, 1.0), "wood")
    mb.box((0, cy - 0.02, 1.03), (2.55, 0.82, 0.07), "wood_light", bevel=0.01)
    for k in range(7):
        x = -1.1 + k * (2.2 / 6)
        mb.box((x, cy - 0.34, 0.5), (0.05, 0.02, 0.9), "wood_dark")
    mb.box((0, cy - 0.35, 0.12), (2.42, 0.03, 0.08), "wood_dark")
    # striped cloth skirt on the counter front
    for k in range(8):
        x = -1.05 + k * 0.3
        mb.box((x, cy - 0.36, 0.78), (0.3, 0.02, 0.36), "cloth_red" if k % 2 == 0 else "cloth_cream")
    # posts: front pair right behind the counter, back pair taller
    for sx in (-1, 1):
        mb.box((sx * 1.2, -0.08, 1.3), (0.1, 0.1, 2.6), "wood_dark")
        mb.box((sx * 1.2, 1.05, 1.5), (0.1, 0.1, 3.0), "wood_dark")
        mb.box((sx * 1.2, 0.48, 2.78), (0.08, 1.25, 0.08), "wood_dark", rot=(math.atan2(0.4, 1.13), 0, 0))
    # striped awning: from the front posts (z 2.62) up to the back posts (z 3.02)
    ang = math.atan2(0.4, 1.13)
    n_str = 7
    for k in range(n_str):
        x = -1.35 + (k + 0.5) * (2.7 / n_str)
        m = "cloth_red" if k % 2 == 0 else "cloth_cream"
        mb.box((x, 0.48, 2.86), (2.7 / n_str + 0.005, 1.42, 0.04), m, rot=(ang, 0, 0))
        mb.box((x, -0.2, 2.56), (2.7 / n_str - 0.02, 0.03, 0.24), m)
    # goods on the counter: crates of fruit, pots, cloth bolts
    for (x, m) in ((-0.8, "fruit_red"), (-0.25, "fruit_yellow")):
        mb.box((x, cy, 1.15), (0.44, 0.36, 0.18), "wood", bevel=0.01)
        for i in range(6):
            mb.ico((x + rng.uniform(-0.15, 0.15), cy + rng.uniform(-0.1, 0.1), 1.26), 0.065, m, subdiv=1)
    for (x, h) in ((0.35, 0.32), (0.6, 0.24)):
        mb.lathe([(0.0, 0.0), (0.1, 0.0), (0.14, h * 0.45), (0.07, h * 0.9), (0.08, h), (0.0, h)], "pot",
                 segs=8, center=(x, cy + 0.05, 1.065))
    mb.cyl_between((0.85, cy - 0.12, 1.12), (0.85, cy + 0.2, 1.12), 0.08, 0.08, "cloth_green", segs=8)
    mb.cyl_between((1.05, cy - 0.12, 1.12), (1.05, cy + 0.2, 1.12), 0.08, 0.08, "cloth_blue", segs=8)
    # back shelves with jars and a hanging cloth
    for z in (0.9, 1.5):
        mb.box((0, 1.05, z), (2.3, 0.28, 0.05), "wood_dark")
        for i in range(5):
            x = -0.9 + i * 0.45
            mb.lathe([(0.0, 0.0), (0.07, 0.0), (0.08, 0.14), (0.05, 0.2), (0.0, 0.2)],
                     "pot" if (i + int(z * 10)) % 2 else "bronze", segs=6, center=(x, 1.05, z + 0.025))
    mb.box((0, 1.12, 2.2), (2.3, 0.03, 0.6), "cloth_blue")
    mb.box((0, 1.1, 2.2), (0.3, 0.03, 0.3), "gold")
    # sacks and a barrel beside the counter
    mb.ico((1.55, -0.3, 0.3), 0.3, "sack", subdiv=1, jitter=0.03, rng=rng, scale=(0.9, 0.9, 1.0))
    mb.cyl((1.55, -0.3, 0.62), 0.07, 0.04, 0.1, "rope", segs=5)
    mb.lathe([(0.0, 0.0), (0.22, 0.0), (0.26, 0.35), (0.22, 0.7), (0.0, 0.7)], "wood", segs=10,
             center=(-1.6, -0.25, 0.0))
    for z in (0.12, 0.58):
        mb.lathe([(0.23, -0.03), (0.26, -0.03), (0.26, 0.03), (0.23, 0.03)], "iron", segs=10,
                 center=(-1.6, -0.25, z), closed=True)
    mb.clamp_floor()
    mb.finish("town_stall")


def build_town_stash():
    rng = random.Random(59)
    dungeon.build_chest_parts("town_stash", 1.3, 0.82, 0.6, 0.32, "wood_dark", "iron", "gold", rng, ornate=True)


def build_town_cart():
    mb = MeshBuilder()
    rng = random.Random(61)
    # bed and side boards
    mb.box((0, 0.1, 0.66), (1.2, 1.9, 0.1), "wood")
    for s in (-1, 1):
        mb.box((s * 0.6, 0.1, 0.86), (0.06, 1.9, 0.32), "wood_light")
        for y in (-0.7, 0.1, 0.9):
            mb.box((s * 0.63, y, 0.85), (0.04, 0.08, 0.36), "wood_dark")
    mb.box((0, 1.04, 0.86), (1.2, 0.06, 0.32), "wood_light")
    mb.box((0, -0.84, 0.8), (1.2, 0.06, 0.2), "wood_light")
    # axle + wheels (spoked)
    mb.cyl_between((-0.72, 0.25, 0.45), (0.72, 0.25, 0.45), 0.04, 0.04, "iron_dark", segs=6)
    rot = Matrix.Rotation(math.pi / 2, 4, "Y")
    for s in (-1, 1):
        cx = s * 0.72
        mb.lathe([(0.36, -0.05), (0.45, -0.05), (0.45, 0.05), (0.36, 0.05)], "wood_dark", segs=12,
                 center=(cx, 0.25, 0.45), closed=True, matrix=rot)
        mb.lathe([(0.445, -0.055), (0.465, -0.055), (0.465, 0.055), (0.445, 0.055)], "iron", segs=12,
                 center=(cx, 0.25, 0.45), closed=True, matrix=rot)
        mb.cyl((cx, 0.25, 0.45), 0.09, 0.09, 0.16, "wood", segs=8, rot=(0, math.pi / 2, 0))
        for k in range(6):
            a = math.pi * k / 3
            mb.cyl_between((cx, 0.25, 0.45), (cx, 0.25 + 0.38 * math.cos(a), 0.45 + 0.38 * math.sin(a)),
                           0.025, 0.025, "wood", segs=4)
    # shafts + support leg
    for s in (-1, 1):
        mb.cyl_between((s * 0.42, -0.7, 0.62), (s * 0.3, -1.75, 0.5), 0.04, 0.035, "wood_dark", segs=6)
    mb.cyl_between((-0.3, -1.7, 0.5), (0.3, -1.7, 0.5), 0.03, 0.03, "wood_dark", segs=6)
    mb.cyl_between((0.0, -1.2, 0.56), (0.0, -1.2, 0.0), 0.035, 0.035, "wood_dark", segs=6)
    # cargo: sacks, a crate, a small barrel
    for (x, y) in ((-0.25, 0.5), (0.2, 0.62), (-0.1, 0.05)):
        mb.ico((x, y, 0.92), 0.28, "sack", subdiv=1, jitter=0.03, rng=rng, scale=(1.0, 0.8, 0.7))
        mb.cyl((x, y, 1.13), 0.06, 0.03, 0.1, "rope", segs=5)
    mb.box((0.25, -0.35, 0.93), (0.42, 0.42, 0.42), "wood", bevel=0.02, rot=(0, 0, 0.3))
    mb.box((0.25, -0.35, 0.93), (0.44, 0.1, 0.44), "wood_dark", rot=(0, 0, 0.3))
    mb.lathe([(0.0, 0.0), (0.17, 0.0), (0.2, 0.25), (0.17, 0.5), (0.0, 0.5)], "wood", segs=8,
             center=(-0.28, -0.45, 0.71))
    mb.clamp_floor()
    mb.finish("town_cart")


def build_town_bush():
    mb = MeshBuilder()
    rng = random.Random(67)
    for c, r, m in [((0.0, 0.0, 0.42), 0.55, "leaf"), ((0.45, 0.1, 0.32), 0.42, "leaf_dark"),
                    ((-0.42, 0.12, 0.3), 0.4, "leaf_dark"), ((0.1, -0.3, 0.28), 0.38, "leaf_light"),
                    ((-0.1, 0.35, 0.5), 0.36, "leaf")]:
        mb.ico(c, r, m, subdiv=1, jitter=0.07, rng=rng, scale=(1, 1, 0.85))
    for _ in range(7):
        a = rng.uniform(0, 2 * math.pi)
        mb.ico((0.5 * math.cos(a), 0.45 * math.sin(a), rng.uniform(0.45, 0.75)), 0.05, "fruit_red", subdiv=0)
    mb.clamp_floor()
    mb.finish("town_bush")


def build_town_rock():
    mb = MeshBuilder()
    rng = random.Random(71)
    pts = L.rock_points((0, 0, 0.42), (0.8, 0.62, 0.5), rng, n=16, rough=0.14)
    mb.hull(pts, "town_rock")
    moss = [(x * 0.92, y * 0.92, z + 0.04) for (x, y, z) in pts if z > 0.62]
    moss += [(x * 0.95, y * 0.95, 0.62) for (x, y, z) in pts if z > 0.62]
    if len(moss) >= 4:
        mb.hull(moss, "moss")
    mb.hull(L.rock_points((0.7, -0.35, 0.14), (0.26, 0.22, 0.18), rng, n=9), "town_stone_dark")
    mb.clamp_floor()
    mb.finish("town_rock")


BUILDERS = {
    "town_house_a": build_town_house_a,
    "town_house_b": build_town_house_b,
    "town_house_c": build_town_house_c,
    "town_well": build_town_well,
    "town_tree_a": build_town_tree_a,
    "town_tree_b": build_town_tree_b,
    "town_fence": build_town_fence,
    "town_lamp": build_town_lamp,
    "town_stall": build_town_stall,
    "town_stash": build_town_stash,
    "town_cart": build_town_cart,
    "town_bush": build_town_bush,
    "town_rock": build_town_rock,
}
