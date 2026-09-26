"""Dungeon kit (floors, walls, pillar) and dungeon props (env_*).

Conventions (§14.1/§14.4), Blender axes (Z up, front = -Y = Godot +Z):
- floor tiles: 2x2 m, top at z = 0, centred; walls: 2x2 m footprint, 2.4 m tall, rising from 0
  (only the hidden dark core / bottom plate reach down to W_BASE = -0.06, below the floor
  tiles' edge groove, so no see-through slit shows at the wall base).
- every model is single-sided (backface culling): all shells are closed or only ever seen from
  their front; build_all.py --check verifies it by ray casting (facecheck.py).
- kit pieces are ONE mesh object each; stone uses tint_* materials (tinted per theme in code).
- props: origin at base centre. env_torch: origin on the wall face at floor level, sticks out -Y.
- env_chest: base + child object "Lid" whose origin is the hinge (back-top edge).

OWNER: assets-environment.
"""

import math
import random

from mathutils import Matrix, Vector

import envlib as L
from envlib import MeshBuilder

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
O = Vector((0, 0, 0))

KIT_TRI_BUDGET = 500

# ----------------------------------------------------------------------------------- floors

F_CH = 0.045      # groove half-width (chamfer) between floor slabs
F_CD = 0.045      # groove depth below z = 0
FLOOR_FRAME = (O, X, Y, Z)


def _fslab(mb, poly, top, mat, chamfer=F_CH, flags=None):
    """Floor slab with its top at `top` (<= 0) and every groove bottom at exactly -F_CD, so
    neighbouring tiles always meet seamlessly."""
    mb.slab(poly, FLOOR_FRAME, depth=top, chamfer=chamfer, chamfer_depth=top + F_CD, mat=mat,
            edge_chamfer=flags)


def _floor_skirt(mb):
    """Vertical skirt under the tile edges (visible only where no neighbour exists)."""
    z0, z1 = -0.2, -F_CD
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        mb.face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], "tint_stone_dark")


def _rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def _check_budget(mb, model_id):
    n = mb.tri_count()
    if n > KIT_TRI_BUDGET:
        raise RuntimeError("%s: %d triangles > budget %d" % (model_id, n, KIT_TRI_BUDGET))
    return n


def build_env_floor_a():
    """Four square flagstones, one split in two, one with a chipped corner."""
    mb = MeshBuilder()
    _fslab(mb, _rect(-1, -1, 0, 0), 0.0, "tint_stone")
    # top-left slab split into two halves
    _fslab(mb, _rect(-1, 0, 0, 0.45), -0.006, "tint_stone_b")
    _fslab(mb, _rect(-1, 0.45, 0, 1), -0.003, "tint_stone")
    # chipped corner (convex pentagon)
    _fslab(mb, [(0, -1), (1, -1), (1, -0.18), (0.82, 0), (0, 0)], -0.004, "tint_stone")
    _fslab(mb, [(0.82, 0), (1, -0.18), (1, 0)], -0.03, "tint_stone_c", chamfer=0.02)
    _fslab(mb, _rect(0, 0, 1, 1), -0.008, "tint_stone_b")
    _floor_skirt(mb)
    _check_budget(mb, "env_floor_a")
    mb.finish("env_floor_a")


def build_env_floor_b():
    """Irregular pinwheel flagstones."""
    mb = MeshBuilder()
    _fslab(mb, _rect(-1, -1, 0.3, -0.25), 0.0, "tint_stone")
    _fslab(mb, _rect(0.3, -1, 1, 0.35), -0.007, "tint_stone_b")
    _fslab(mb, _rect(-1, -0.25, -0.3, 1), -0.004, "tint_stone_b")
    _fslab(mb, _rect(-0.3, -0.25, 0.3, 0.35), -0.012, "tint_stone_c")
    _fslab(mb, _rect(-0.3, 0.35, 1, 1), -0.002, "tint_stone")
    _floor_skirt(mb)
    _check_budget(mb, "env_floor_b")
    mb.finish("env_floor_b")


def build_env_floor_c():
    """Worn / cracked: one slab broken into sunken fragments and one cracked slab."""
    mb = MeshBuilder()
    # intact slab
    _fslab(mb, _rect(-1, -1, 0, 0), 0.0, "tint_stone")
    # cracked slab (two convex pieces, narrow crack)
    crack = 0.018
    _fslab(mb, [(0, -1), (1, -1), (1, -0.62), (0, -0.3)], -0.004, "tint_stone_b",
           flags=[True, True, crack, True])
    _fslab(mb, [(0, -0.3), (1, -0.62), (1, 0), (0, 0)], -0.009, "tint_stone_b",
           flags=[crack, True, True, True])
    # broken + sunken slab (three fragments)
    _fslab(mb, [(-1, 0), (-0.35, 0), (-0.55, 0.55), (-1, 0.62)], -0.022, "tint_stone_c",
           flags=[True, crack * 1.4, crack * 1.4, True])
    _fslab(mb, [(-0.35, 0), (0, 0), (0, 1), (-0.42, 1), (-0.55, 0.55)], -0.012, "tint_stone_b",
           flags=[True, True, True, crack * 1.4, crack * 1.4])
    _fslab(mb, [(-1, 0.62), (-0.55, 0.55), (-0.42, 1), (-1, 1)], -0.03, "tint_stone_c",
           flags=[crack * 1.4, crack * 1.4, True, True])
    # plain slab
    _fslab(mb, _rect(0, 0, 1, 1), -0.005, "tint_stone")
    _floor_skirt(mb)
    _check_budget(mb, "env_floor_c")
    mb.finish("env_floor_c")


# ----------------------------------------------------------------------------------- walls

W_ROWS = [0.0, 0.6, 1.2, 1.8, 2.4]
W_CH = 0.045
W_CD = 0.045
WALL_H = 2.4
# (origin on the face plane, u, v, outward normal) with u x v = n
WALL_FACES = [
    (Vector((0, -1, 0)), X, Z, -Y),
    (Vector((1, 0, 0)), Y, Z, X),
    (Vector((0, 1, 0)), -X, Z, Y),
    (Vector((-1, 0, 0)), -Y, Z, -X),
]


def _wall_block(mb, frame, row, u0, u1, depth, mat, chip=None):
    """One ashlar block. Odd rows continue across the tile boundary (flush, no groove) so the
    running bond is seamless; even rows have a joint exactly on the boundary."""
    v0, v1 = W_ROWS[row], W_ROWS[row + 1]
    left_flush = row % 2 == 1 and u0 <= -1 + 1e-6
    right_flush = row % 2 == 1 and u1 >= 1 - 1e-6
    if left_flush or right_flush:
        depth = 0.0
    if row == len(W_ROWS) - 2:
        depth = min(depth, 0.0)
    bottom = row > 0
    top = row < len(W_ROWS) - 2
    poly = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    flags = [bottom, not right_flush, top, not left_flush]
    # flush ends lie on the block's vertical corners: mitre their row grooves (see slab())
    miter = [False, right_flush, False, left_flush]
    if chip is not None:
        # cut one corner: chip = (corner index 0..3, du, dv)
        ci, du, dv = chip
        if ci == 2 and top and not right_flush:
            poly = [(u0, v0), (u1, v0), (u1, v1 - dv), (u1 - du, v1), (u0, v1)]
            flags = [bottom, True, True, top, not left_flush]
            miter = [False, False, False, False, left_flush]
        elif ci == 1 and bottom and not right_flush:
            poly = [(u0, v0), (u1 - du, v0), (u1, v0 + dv), (u1, v1), (u0, v1)]
            flags = [bottom, True, True, top, not left_flush]
            miter = [False, False, False, False, left_flush]
        elif ci == 3 and top and not left_flush:
            poly = [(u0, v0), (u1, v0), (u1, v1), (u0 + du, v1), (u0, v1 - dv)]
            flags = [bottom, not right_flush, top, True, True]
            miter = [False, right_flush, False, False, False]
    mb.slab(poly, frame, depth=depth, chamfer=W_CH, chamfer_depth=depth + W_CD, mat=mat,
            edge_chamfer=flags, miter_edges=miter)


W_BASE = -0.06    # the wall core starts below the floor's edge groove (-F_CD), see below
W_FIN = 0.006     # thickness of the corner fins
W_FIN_GAP = 0.0005  # fins stop this short of the block boundary (no z-fight with flush blocks)


def _quad(mb, pts, normal, mat):
    """Quad facing `normal` (winding fixed up as needed)."""
    p = [Vector(q) for q in pts]
    if (p[1] - p[0]).cross(p[2] - p[0]).dot(Vector(normal)) < 0:
        p.reverse()
    mb.face([tuple(q) for q in p], mat)


def _wall_core_and_cap(mb):
    """Dark core behind the face slabs (what the joints between blocks show), the dark top cap
    and a bottom plate. The models are single-sided (backface culling), so the core must close
    every opening between the slabs:
    - the core starts at W_BASE, below the floor tiles' edge groove (bottom at -F_CD), and an
      up-facing plate at W_BASE spans the whole footprint: a ray entering the slit between the
      floor groove and the bottom of the face slabs always lands on dark stone, never the void;
    - at each vertical corner, between the core and the block boundary, the end grooves of two
      faces leave a 4.5 cm shaft. Thin two-sided fins in the core planes close it, so a ray
      entering a corner notch (or running along the gap behind a face's slabs) always meets a
      FRONT face of dark core stone (the row grooves of flush blocks are mitred at the corners,
      see _wall_block / MeshBuilder.slab)."""
    t = W_CD
    c = [(-1 + t, -1 + t), (1 - t, -1 + t), (1 - t, 1 - t), (-1 + t, 1 - t)]
    for i in range(4):
        a = c[i]
        b = c[(i + 1) % 4]
        mb.face([(a[0], a[1], W_BASE), (b[0], b[1], W_BASE), (b[0], b[1], WALL_H), (a[0], a[1], WALL_H)], "tint_stone_dark")
    mb.face([(-1, -1, WALL_H), (1, -1, WALL_H), (1, 1, WALL_H), (-1, 1, WALL_H)], "tint_stone_top")
    mb.face([(-1, -1, W_BASE), (1, -1, W_BASE), (1, 1, W_BASE), (-1, 1, W_BASE)], "tint_stone_dark")
    # corner fins: for every face, at both ends, u in the shaft, n from the core plane inwards
    z0, z1 = W_BASE, WALL_H
    for (o, U, _V, N) in WALL_FACES:
        def P(u, n, z):
            q = o + U * u + N * n
            return (q.x, q.y, z)
        for sgn in (-1, 1):
            u_in, u_out = sgn * (1 - t), sgn * (1 - W_FIN_GAP)
            n_out, n_in = -t, -t - W_FIN
            # side facing the face's outside (seen through the corner notches)
            _quad(mb, [P(u_in, n_out, z0), P(u_out, n_out, z0), P(u_out, n_out, z1), P(u_in, n_out, z1)], N, "tint_stone_dark")
            # side facing the neighbouring face's gap
            _quad(mb, [P(u_in, n_in, z0), P(u_out, n_in, z0), P(u_out, n_in, z1), P(u_in, n_in, z1)], -N, "tint_stone_dark")
            # end facing the neighbouring face's outside
            _quad(mb, [P(u_out, n_in, z0), P(u_out, n_out, z0), P(u_out, n_out, z1), P(u_out, n_in, z1)], U * sgn, "tint_stone_dark")


def build_env_wall_a():
    """Regular ashlar running bond (1.0 x 0.6 m blocks)."""
    mb = MeshBuilder()
    rng = random.Random(11)
    for frame in WALL_FACES:
        for row in range(4):
            joints = [-1.0, 0.0, 1.0] if row % 2 == 0 else [-1.0, -0.5, 0.5, 1.0]
            for k in range(len(joints) - 1):
                d = rng.uniform(-0.02, 0.0)
                m = "tint_stone" if rng.random() < 0.7 else "tint_stone_b"
                _wall_block(mb, frame, row, joints[k], joints[k + 1], d, m)
    _wall_core_and_cap(mb)
    _check_budget(mb, "env_wall_a")
    mb.finish("env_wall_a")


def build_env_wall_b():
    """Rougher, irregular blocks with chipped corners; same boundary rules as wall_a, so a and b
    can be mixed freely along a wall run."""
    mb = MeshBuilder()
    rng = random.Random(23)
    for frame in WALL_FACES:
        for row in range(4):
            if row % 2 == 0:
                j = rng.uniform(-0.35, 0.35)
                joints = [-1.0, j, 1.0]
            else:
                a = rng.uniform(-0.8, -0.45)
                b = rng.uniform(0.25, 0.7)
                joints = [-1.0, a, b, 1.0]
            for k in range(len(joints) - 1):
                d = rng.uniform(-0.034, 0.0)
                r = rng.random()
                m = "tint_stone" if r < 0.5 else ("tint_stone_b" if r < 0.85 else "tint_stone_c")
                chip = None
                if rng.random() < 0.35:
                    chip = (rng.choice([1, 2, 3]), rng.uniform(0.08, 0.18), rng.uniform(0.06, 0.14))
                _wall_block(mb, frame, row, joints[k], joints[k + 1], d, m, chip)
    _wall_core_and_cap(mb)
    _check_budget(mb, "env_wall_b")
    mb.finish("env_wall_b")


# ----------------------------------------------------------------------------------- pillar

def build_env_pillar():
    mb = MeshBuilder()
    # plinth (two steps)
    mb.box((0, 0, 0.14), (1.22, 1.22, 0.28), "tint_stone_b", bevel=0.04)
    mb.box((0, 0, 0.36), (1.0, 1.0, 0.16), "tint_stone", bevel=0.03)
    # octagonal shaft with a band
    mb.cyl((0, 0, 0.44 + 0.8), 0.46, 0.42, 1.6, "tint_stone", segs=8, twist=math.pi / 8)
    mb.cyl((0, 0, 1.3), 0.49, 0.49, 0.14, "tint_stone_b", segs=8, twist=math.pi / 8)
    # capital
    mb.box((0, 0, 2.12), (0.86, 0.86, 0.16), "tint_stone", bevel=0.03, taper=(1.06, 1.06))
    mb.box((0, 0, 2.3), (0.98, 0.98, 0.2), "tint_stone_b", bevel=0.04)
    mb.paint_top(2.4, "tint_stone_top")
    _check_budget(mb, "env_pillar")
    mb.finish("env_pillar")


# ----------------------------------------------------------------------------------- flames

def _flame(mb, base, height, radius, rng, segs=6, core=True, lean=0.0):
    """Stylised low-poly flame: twisted cone (outer) + bright inner core."""
    bx, by, bz = base
    prof = [(0.0, 0.0), (radius * 0.85, height * 0.12), (radius, height * 0.3),
            (radius * 0.7, height * 0.58), (radius * 0.3, height * 0.82), (0.0, height)]
    verts = mb.lathe(prof, "emit_fire", segs=segs, center=(bx, by, bz), phase=rng.uniform(0, 1))
    for v in verts:
        t = (v.co.z - bz) / height
        a = t * 1.1
        x, y = v.co.x - bx, v.co.y - by
        v.co.x = bx + x * math.cos(a) - y * math.sin(a) + lean * t * t
        v.co.y = by + x * math.sin(a) + y * math.cos(a)
    if core:
        prof2 = [(0.0, 0.0), (radius * 0.55, height * 0.12), (radius * 0.5, height * 0.35),
                 (radius * 0.25, height * 0.55), (0.0, height * 0.72)]
        mb.lathe(prof2, "emit_fire_core", segs=5, center=(bx, by, bz + height * 0.02),
                 phase=rng.uniform(0, 1))


# ----------------------------------------------------------------------------------- props

def build_env_torch():
    """Wall sconce: origin on the wall face (y = 0) at floor level; sticks out along -Y."""
    mb = MeshBuilder()
    rng = random.Random(5)
    # back plate
    mb.box((0, -0.025, 1.62), (0.2, 0.05, 0.36), "iron_dark", bevel=0.015)
    mb.box((0, -0.055, 1.62), (0.06, 0.03, 0.24), "iron", bevel=0.008)
    # arm going out and up
    mb.cyl_between((0, -0.05, 1.52), (0, -0.26, 1.7), 0.025, 0.025, "iron", segs=6)
    mb.cyl_between((0, -0.05, 1.76), (0, -0.22, 1.74), 0.02, 0.02, "iron", segs=6)
    # cup
    mb.lathe([(0.0, 0.0), (0.05, 0.0), (0.1, 0.12), (0.115, 0.14), (0.08, 0.14), (0.0, 0.06)],
             "iron", segs=8, center=(0, -0.27, 1.66))
    # torch stick + wrapped head
    mb.cyl_between((0, -0.27, 1.58), (0, -0.3, 1.9), 0.035, 0.045, "wood", segs=6)
    mb.cyl((0, -0.3, 1.9), 0.06, 0.055, 0.1, "rope", segs=6)
    _flame(mb, (0, -0.3, 1.93), 0.42, 0.11, rng, lean=0.0)
    mb.finish("env_torch")


def build_env_brazier():
    mb = MeshBuilder()
    rng = random.Random(7)
    # tripod legs + ring
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.3
        foot = (0.42 * math.cos(a), 0.42 * math.sin(a), 0.0)
        top = (0.2 * math.cos(a), 0.2 * math.sin(a), 0.72)
        mb.cyl_between(foot, top, 0.04, 0.035, "iron_dark", segs=6)
        mb.box((foot[0], foot[1], 0.03), (0.12, 0.12, 0.06), "iron_dark", rot=(0, 0, a))
    mb.lathe([(0.32, -0.03), (0.34, 0.0), (0.34, 0.03), (0.32, 0.06)], "iron", segs=10,
             center=(0, 0, 0.36), closed=True)
    # bowl (open, with inner surface)
    mb.lathe([(0.0, 0.0), (0.2, 0.0), (0.42, 0.2), (0.48, 0.24), (0.48, 0.3), (0.42, 0.28),
              (0.2, 0.08), (0.0, 0.08)], "iron", segs=10, center=(0, 0, 0.68),
             cap_bottom=False, cap_top=False)
    # coals / embers
    for i in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.3)
        c = (r * math.cos(a), r * math.sin(a), 0.82 + 0.1 * (1 - r / 0.3))
        mb.ico(c, rng.uniform(0.07, 0.11), "coal" if i % 3 else "emit_ember", subdiv=0, jitter=0.02, rng=rng)
    mb.cyl((0, 0, 0.86), 0.3, 0.22, 0.08, "emit_ember", segs=8)
    # flames
    _flame(mb, (0.0, 0.0, 0.86), 0.62, 0.2, rng, segs=7)
    _flame(mb, (0.14, 0.08, 0.86), 0.4, 0.12, rng, segs=5, core=False)
    _flame(mb, (-0.12, 0.1, 0.86), 0.36, 0.11, rng, segs=5, core=False)
    _flame(mb, (0.02, -0.15, 0.86), 0.34, 0.1, rng, segs=5, core=False)
    mb.clamp_floor()
    mb.finish("env_brazier")


def build_env_crate():
    mb = MeshBuilder()
    s = 0.8
    h = s / 2
    t = 0.08
    mb.box((0, 0, h), (s - 0.04, s - 0.04, s - 0.04), "wood", bevel=0.0)
    # 12 edge beams
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (h - t / 2), sy * (h - t / 2), h), (t, t, s), "wood_dark", bevel=0.01)
    for sz in (0, 1):
        z = t / 2 if sz == 0 else s - t / 2
        for sy in (-1, 1):
            mb.box((0, sy * (h - t / 2), z), (s - 2 * t, t, t), "wood_dark", bevel=0.01)
        for sx in (-1, 1):
            mb.box((sx * (h - t / 2), 0, z), (t, s - 2 * t, t), "wood_dark", bevel=0.01)
    # diagonal braces on the four sides
    diag = math.atan2(s - 2 * t, s - 2 * t)
    L_ = (s - 2 * t) * math.sqrt(2) - 0.06
    mb.box((0, -h + 0.005, h), (L_, 0.03, 0.09), "wood_dark", rot=(0, diag, 0))
    mb.box((0, h - 0.005, h), (L_, 0.03, 0.09), "wood_dark", rot=(0, -diag, 0))
    mb.box((-h + 0.005, 0, h), (0.03, L_, 0.09), "wood_dark", rot=(-diag, 0, 0))
    mb.box((h - 0.005, 0, h), (0.03, L_, 0.09), "wood_dark", rot=(diag, 0, 0))
    # plank lines on top
    for k in (-1, 1):
        mb.box((k * 0.12, 0, s - 0.015), (0.02, s - 2 * t, 0.012), "wood_dark")
    mb.finish("env_crate")


def build_env_barrel():
    mb = MeshBuilder()
    segs = 12
    prof = [(0.0, 0.0), (0.27, 0.0), (0.31, 0.2), (0.33, 0.46), (0.31, 0.72), (0.27, 0.92),
            (0.24, 0.92), (0.24, 0.89), (0.0, 0.89)]
    mb.lathe(prof, "wood", segs=segs, cap_bottom=False, cap_top=False)
    # hoops
    for z, r in ((0.1, 0.295), (0.3, 0.325), (0.62, 0.325), (0.82, 0.295)):
        mb.lathe([(r - 0.01, -0.035), (r + 0.012, -0.035), (r + 0.012, 0.035), (r - 0.01, 0.035)],
                 "iron", segs=segs, center=(0, 0, z), closed=True)
    # stave lines (dark thin strips) on the belly
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.26
        mb.box((0.332 * math.cos(a), 0.332 * math.sin(a), 0.46), (0.012, 0.03, 0.22), "wood_dark",
               rot=(0, 0, a))
    # lid planks
    mb.box((0, 0, 0.895), (0.04, 0.44, 0.012), "wood_dark")
    mb.finish("env_barrel")


def _bone(mb, a, b, r, rng, mat="bone"):
    mb.cyl_between(a, b, r, r * 0.85, mat, segs=5)
    for p in (a, b):
        mb.ico(p, r * 1.7, mat, subdiv=0, jitter=r * 0.3, rng=rng, flatten_below=0.0)


def _skull(mb, c, s, yaw, rng):
    cx, cy, cz = c
    rot = Matrix.Rotation(yaw, 4, "Z")
    verts = mb.ico((0, 0, 0), 1.0, "bone", subdiv=1, scale=(0.13 * s, 0.16 * s, 0.13 * s))
    jaw = mb.box((0, -0.1 * s, -0.07 * s), (0.16 * s, 0.1 * s, 0.07 * s), "bone", bevel=0.01 * s)
    eyes = []
    for ex in (-0.045, 0.045):
        eyes += mb.ico((ex * s, -0.135 * s, 0.01 * s), 0.035 * s, "coal", subdiv=0)
    nose = mb.box((0, -0.15 * s, -0.035 * s), (0.025 * s, 0.03 * s, 0.03 * s), "coal")
    allv = verts + jaw + eyes + nose
    m = Matrix.Translation((cx, cy, cz)) @ rot
    mb.transform(allv, m)


def build_env_bones():
    mb = MeshBuilder()
    rng = random.Random(9)
    first = len(mb.bm.verts)
    _skull(mb, (0.12, -0.08, 0.13), 1.0, 0.5, rng)
    _bone(mb, (-0.45, -0.1, 0.035), (0.05, 0.25, 0.035), 0.028, rng)
    _bone(mb, (-0.2, -0.38, 0.03), (0.28, -0.3, 0.03), 0.026, rng)
    _bone(mb, (0.3, 0.35, 0.03), (0.48, -0.05, 0.03), 0.024, rng, "bone_dark")
    _bone(mb, (-0.38, 0.35, 0.025), (-0.12, 0.42, 0.025), 0.02, rng, "bone_dark")
    # ribs: short arcs
    for i in range(4):
        y = 0.05 + i * 0.08
        a = (-0.32, y, 0.02)
        m = (-0.2, y + 0.03, 0.09)
        b = (-0.08, y, 0.02)
        mb.cyl_between(a, m, 0.015, 0.015, "bone", segs=4)
        mb.cyl_between(m, b, 0.015, 0.015, "bone", segs=4)
    # spine chunk
    mb.cyl_between((-0.2, 0.0, 0.03), (-0.2, 0.36, 0.03), 0.022, 0.022, "bone_dark", segs=5)
    # a little bolder so the pile reads from the high game camera
    mb.transform(list(mb.bm.verts)[first:], Matrix.Scale(1.3, 4))
    mb.clamp_floor()
    mb.finish("env_bones")


def build_env_rubble():
    """Pile of broken stone blocks and chunks (non-colliding debris, tinted like the walls)."""
    mb = MeshBuilder()
    rng = random.Random(13)
    # a couple of broken ashlar blocks
    mb.box((0.15, 0.1, 0.16), (0.55, 0.36, 0.32), "stone_light", rot=(0.05, -0.08, 0.35), bevel=0.03)
    mb.box((-0.35, -0.15, 0.12), (0.4, 0.3, 0.24), "stone", rot=(0.12, 0.2, -0.5), bevel=0.03)
    for _ in range(10):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.15, 0.7)
        c = (r * math.cos(a), r * math.sin(a) * 0.8, 0.0)
        size = rng.uniform(0.08, 0.2) * (1.2 - r * 0.5)
        pts = L.rock_points((c[0], c[1], size * 0.45), (size, size * 0.8, size * 0.6), rng, n=9)
        mb.hull(pts, rng.choice(["stone", "stone_light", "stone_dark"]))
    # fix any vertex dipping below the floor
    mb.clamp_floor()
    mb.finish("env_rubble")


def build_env_rock_a():
    mb = MeshBuilder()
    rng = random.Random(17)
    pts = L.rock_points((0, 0, 0.45), (0.75, 0.6, 0.62), rng, n=18, rough=0.16)
    mb.hull(pts, "stone")
    pts = L.rock_points((0.55, -0.35, 0.18), (0.3, 0.26, 0.24), rng, n=10)
    mb.hull(pts, "stone_dark")
    mb.clamp_floor()
    mb.finish("env_rock_a")


def build_env_rock_b():
    mb = MeshBuilder()
    rng = random.Random(19)
    for (c, r, m) in [((0.0, 0.0, 0.3), (0.42, 0.36, 0.38), "stone_light"),
                      ((0.42, 0.2, 0.18), (0.28, 0.24, 0.22), "stone"),
                      ((-0.3, 0.32, 0.14), (0.22, 0.2, 0.16), "stone_dark"),
                      ((-0.28, -0.3, 0.1), (0.16, 0.14, 0.12), "stone")]:
        mb.hull(L.rock_points(c, r, rng, n=12, rough=0.2), m)
    mb.clamp_floor()
    mb.finish("env_rock_b")


def _crystal(mb, base, direction, length, radius, mat, rng, tip=0.28):
    """Hexagonal prism with a pointed tip, from `base` along `direction`."""
    d = Vector(direction).normalized()
    q = Vector((0, 0, 1)).rotation_difference(d)
    body = length * (1 - tip)
    prof = [(0.0, -0.05), (radius * 0.9, -0.05), (radius, body * 0.5), (radius * 0.92, body), (0.0, length)]
    verts = mb.lathe(prof, mat, segs=6, phase=rng.uniform(0, 1), cap_bottom=False)
    m = Matrix.Translation(base) @ q.to_matrix().to_4x4()
    mb.transform(verts, m)


def build_env_crystal():
    mb = MeshBuilder()
    rng = random.Random(21)
    # rocky base
    mb.hull(L.rock_points((0, 0, 0.12), (0.55, 0.46, 0.22), rng, n=14), "stone_dark")
    mb.hull(L.rock_points((0.3, 0.2, 0.08), (0.28, 0.24, 0.13), rng, n=9), "stone")
    specs = [((0.0, 0.0, 0.1), (0.05, 0.02, 1.0), 1.35, 0.14, "emit_crystal"),
             ((0.18, -0.08, 0.08), (0.45, -0.25, 1.0), 0.85, 0.1, "emit_crystal"),
             ((-0.16, 0.05, 0.08), (-0.5, 0.15, 1.0), 0.95, 0.11, "emit_crystal"),
             ((0.05, 0.2, 0.08), (0.15, 0.55, 1.0), 0.7, 0.09, "emit_crystal_core"),
             ((-0.12, -0.18, 0.06), (-0.35, -0.6, 1.0), 0.55, 0.08, "emit_crystal_core"),
             ((0.3, 0.12, 0.05), (0.7, 0.35, 0.8), 0.45, 0.07, "emit_crystal")]
    for base, d, ln, r, m in specs:
        _crystal(mb, Vector(base), d, ln, r, m, rng)
    mb.clamp_floor()
    mb.finish("env_crystal")


# ----------------------------------------------------------------------------------- chest

CHEST_W = 1.0
CHEST_D = 0.64
CHEST_H = 0.48
LID_H = 0.26


def _band_x(mb, x, y0, y1, z0, z1, mat="iron", t=0.06, out=0.012):
    """Iron strap wrapping around a box region at x (front, top and back sides)."""
    mb.box((x, (y0 + y1) / 2, z1 + out / 2), (t, (y1 - y0) + 2 * out, out), mat)
    mb.box((x, y0 - out / 2, (z0 + z1) / 2), (t, out, z1 - z0), mat)
    mb.box((x, y1 + out / 2, (z0 + z1) / 2), (t, out, z1 - z0), mat)


def build_chest_parts(model_id, w, d, h, lid_h, wood, trim, lock_mat, rng, ornate=False):
    """Shared by env_chest and town_stash: base object + hinged 'Lid' child."""
    base = MeshBuilder()
    hw, hd = w / 2, d / 2
    # base box: outer shell + dark interior visible when opened
    base.box((0, 0, h / 2 - 0.02), (w, d, h - 0.04), wood, bevel=0.015)
    base.box((0, 0, h - 0.03), (w - 0.1, d - 0.1, 0.02), "coal")
    # rim
    for (cx, cy, sx, sy) in [(0, -hd + 0.03, w, 0.06), (0, hd - 0.03, w, 0.06),
                             (-hw + 0.03, 0, 0.06, d - 0.12), (hw - 0.03, 0, 0.06, d - 0.12)]:
        base.box((cx, cy, h - 0.02), (sx, sy, 0.04), wood if not ornate else trim)
    # gold inside (seen when the lid opens)
    for i in range(7):
        base.ico((rng.uniform(-hw + 0.15, hw - 0.15), rng.uniform(-hd + 0.12, hd - 0.12), h - 0.02),
                 rng.uniform(0.035, 0.06), "gold", subdiv=0, scale=(1, 1, 0.45))
    # straps, corners, feet
    for x in (-hw + 0.16, hw - 0.16):
        _band_x(base, x, -hd, hd, 0.0, h - 0.02, trim)
    base.box((0, -hd - 0.006, 0.05), (w + 0.02, 0.014, 0.06), trim)
    base.box((0, hd + 0.006, 0.05), (w + 0.02, 0.014, 0.06), trim)
    for sx in (-1, 1):
        for sy in (-1, 1):
            base.box((sx * (hw - 0.03), sy * (hd - 0.03), h * 0.5), (0.08, 0.08, h + 0.004), trim)
    # lock plate on the front
    base.box((0, -hd - 0.012, h - 0.1), (0.16, 0.024, 0.16), lock_mat, bevel=0.01)
    base.box((0, -hd - 0.026, h - 0.11), (0.03, 0.01, 0.06), "coal")
    base_ob = base.finish(model_id)

    # lid, modelled relative to its hinge at (0, +hd, h): spans y in [-d, 0], z in [0, lid_h]
    lid = MeshBuilder()
    prof = []
    n = 6
    for i in range(n + 1):
        a = math.pi * i / n
        # arched profile in (y, z) around the lid centre line
        y = -hd + hd * math.cos(a)
        z = 0.08 + (lid_h - 0.08) * math.sin(a)
        prof.append((y, z))
    poly = [(-d, 0.0), (0.0, 0.0)] + [(p[0], p[1]) for p in prof]   # CCW in (y,z) seen from +X
    # extrude along X: frame u = Y, v = Z, n = X (Y x Z = X)
    frame = (Vector((-hw, 0, 0)), Y, Z, X)
    clean = []
    for p in poly:
        if not clean or (abs(p[0] - clean[-1][0]) > 1e-6 or abs(p[1] - clean[-1][1]) > 1e-6):
            clean.append(p)
    if abs(clean[0][0] - clean[-1][0]) < 1e-6 and abs(clean[0][1] - clean[-1][1]) < 1e-6:
        clean.pop()
    lid.prism(clean, 0.0, w, wood, frame=frame)
    # lid straps (follow the arch)
    for x in (-hw + 0.16, hw - 0.16):
        for i in range(n):
            a0 = math.pi * i / n
            a1 = math.pi * (i + 1) / n
            p0 = (-hd + hd * math.cos(a0), 0.08 + (lid_h - 0.08) * math.sin(a0))
            p1 = (-hd + hd * math.cos(a1), 0.08 + (lid_h - 0.08) * math.sin(a1))
            mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
            ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
            nrm = (-math.sin(ang), math.cos(ang))
            c = (x, mid[0] - nrm[0] * 0.008, mid[1] - nrm[1] * 0.008)
            lid.box(c, (0.062, ln + 0.01, 0.026), trim, rot=(ang, 0, 0))
    # lid front strap + lock hasp
    lid.box((0, -d - 0.008, 0.045), (w + 0.02, 0.016, 0.07), trim)
    lid.box((0, -d - 0.02, 0.02), (0.1, 0.02, 0.12), lock_mat, bevel=0.008)
    if ornate:
        lid.box((0, -hd, lid_h + 0.005), (0.22, 0.22, 0.03), lock_mat, bevel=0.01)
    lid.finish("Lid", parent=base_ob, location=(0, hd, h))
    return base_ob


def build_env_chest():
    rng = random.Random(27)
    build_chest_parts("env_chest", CHEST_W, CHEST_D, CHEST_H, LID_H, "wood", "iron", "gold", rng)


# ----------------------------------------------------------------------------------- portal & waypoint

def build_env_portal():
    """Standing stone ring on a dais. Opening (Godot): centre (0, 1.65, 0), inner radius 1.05,
    facing +Z. The swirl is added in code."""
    mb = MeshBuilder()
    # dais: two octagonal steps
    mb.lathe([(0.0, 0.0), (1.75, 0.0), (1.75, 0.14), (1.45, 0.14), (1.45, 0.28), (0.0, 0.28)],
             "portal_stone", segs=8, phase=math.pi / 8, scale_xy=(1.0, 0.62))
    # ring (rectangular section) standing in the XZ plane
    rot = Matrix.Rotation(math.pi / 2, 4, "X")
    mb.lathe([(1.05, -0.2), (1.38, -0.2), (1.38, 0.2), (1.05, 0.2)], "portal_stone", segs=20,
             center=(0, 0, 1.65), closed=True, matrix=rot)
    # inner rune ring (slightly recessed band on the inner face, emissive)
    mb.lathe([(1.02, -0.12), (1.05, -0.12), (1.05, 0.12), (1.02, 0.12)], "emit_portal", segs=20,
             center=(0, 0, 1.65), closed=True, matrix=rot)
    # keystones around the ring
    for i in range(8):
        a = math.pi / 2 + 2 * math.pi * i / 8
        r = 1.3
        c = (r * math.cos(a), 0.0, 1.65 + r * math.sin(a))
        mb.box(c, (0.3, 0.5, 0.26), "portal_stone_dark", rot=(0, -a + math.pi / 2, 0), bevel=0.03)
        # rune plate on the front
        rc = (1.21 * math.cos(a + math.pi / 8), -0.205, 1.65 + 1.21 * math.sin(a + math.pi / 8))
        mb.box(rc, (0.1, 0.02, 0.14), "emit_portal", rot=(0, -(a + math.pi / 8) + math.pi / 2, 0))
        rc2 = (rc[0], 0.205, rc[2])
        mb.box(rc2, (0.1, 0.02, 0.14), "emit_portal", rot=(0, -(a + math.pi / 8) + math.pi / 2, 0))
    # crest finial: also makes the model's AABB centre coincide with the opening centre (y 1.65)
    mb.box((0, 0, 3.12), (0.34, 0.46, 0.12), "portal_stone", bevel=0.02)
    mb.hull([(0, 0, 3.3), (0.12, 0, 3.18), (-0.12, 0, 3.18), (0, -0.12, 3.18), (0, 0.12, 3.18), (0, 0, 3.12)],
            "emit_portal")
    # feet / buttresses
    for sx in (-1, 1):
        mb.box((sx * 1.05, 0, 0.5), (0.5, 0.56, 0.5), "portal_stone_dark", bevel=0.04,
               rot=(0, 0, 0))
        mb.box((sx * 1.3, 0, 0.36), (0.3, 0.46, 0.2), "portal_stone", bevel=0.03)
    mb.finish("env_portal")


def build_env_waypoint():
    """Dungeon gate: rune-carved monoliths with a lintel on a round platform with a rune circle."""
    mb = MeshBuilder()
    # platform
    mb.lathe([(0.0, 0.0), (2.1, 0.0), (2.1, 0.16), (1.8, 0.16), (1.8, 0.32), (0.0, 0.32)],
             "town_stone", segs=16)
    # rune circle inlay on top
    mb.lathe([(1.2, 0.0), (1.4, 0.0), (1.4, 0.012), (1.2, 0.012)], "emit_rune", segs=24,
             center=(0, 0, 0.32), closed=True)
    for i in range(8):
        a = 2 * math.pi * i / 8
        mb.box((0.95 * math.cos(a), 0.95 * math.sin(a), 0.326), (0.14, 0.05, 0.012), "emit_rune",
               rot=(0, 0, a + math.pi / 2))
    mb.cyl((0, 0, 0.326), 0.35, 0.35, 0.012, "emit_rune", segs=8)
    mb.cyl((0, 0, 0.333), 0.25, 0.25, 0.012, "town_stone_dark", segs=8)
    # monoliths
    for sx in (-1, 1):
        x = sx * 1.3
        mb.box((x, 0, 0.32 + 1.4), (0.56, 0.5, 2.8), "town_stone_dark", bevel=0.05, taper=(0.85, 0.85))
        mb.box((x, 0, 0.32 + 0.15), (0.72, 0.66, 0.3), "town_stone", bevel=0.04)
        # runes on front and back faces
        for k, z in enumerate((0.9, 1.35, 1.8, 2.25)):
            w = 0.18 if k % 2 == 0 else 0.1
            for fy in (-1, 1):
                wy = fy * (0.25 - 0.018 * (z - 0.32) / 2.8 * 2)
                mb.box((x, wy, z), (w, 0.03, 0.08), "emit_rune")
                mb.box((x + (0.05 if k % 2 else -0.05), wy, z + 0.1), (0.05, 0.03, 0.14), "emit_rune")
    # lintel
    mb.box((0, 0, 3.32), (3.4, 0.62, 0.42), "town_stone", bevel=0.05)
    mb.box((0, 0, 3.6), (2.8, 0.5, 0.16), "town_stone_dark", bevel=0.04)
    # rune band along the lintel (front and back)
    for fy in (-1, 1):
        y = fy * 0.318
        for k, x in enumerate((-1.25, -0.95, -0.65, 0.65, 0.95, 1.25)):
            mb.box((x, y, 3.32), (0.16 if k % 2 == 0 else 0.06, 0.02, 0.05), "emit_rune")
            mb.box((x + (0.05 if k % 2 == 0 else 0.0), y, 3.32 + (0.07 if k % 2 == 0 else -0.06)),
                   (0.05, 0.02, 0.1), "emit_rune")
    # keystone gem
    mb.box((0, -0.32, 3.32), (0.3, 0.06, 0.3), "town_stone_dark", bevel=0.02, rot=(0, math.pi / 4, 0))
    mb.hull([(0, -0.4, 3.32), (0.1, -0.34, 3.32), (-0.1, -0.34, 3.32), (0, -0.34, 3.42), (0, -0.34, 3.22)],
            "emit_rune")
    mb.hull([(0, 0.4, 3.32), (0.1, 0.34, 3.32), (-0.1, 0.34, 3.32), (0, 0.34, 3.42), (0, 0.34, 3.22)],
            "emit_rune")
    mb.finish("env_waypoint")


BUILDERS = {
    "env_floor_a": build_env_floor_a,
    "env_floor_b": build_env_floor_b,
    "env_floor_c": build_env_floor_c,
    "env_wall_a": build_env_wall_a,
    "env_wall_b": build_env_wall_b,
    "env_pillar": build_env_pillar,
    "env_torch": build_env_torch,
    "env_brazier": build_env_brazier,
    "env_crate": build_env_crate,
    "env_barrel": build_env_barrel,
    "env_bones": build_env_bones,
    "env_rubble": build_env_rubble,
    "env_rock_a": build_env_rock_a,
    "env_rock_b": build_env_rock_b,
    "env_crystal": build_env_crystal,
    "env_chest": build_env_chest,
    "env_portal": build_env_portal,
    "env_waypoint": build_env_waypoint,
}
