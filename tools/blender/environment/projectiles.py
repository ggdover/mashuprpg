"""Projectiles (proj_*): point along Blender -Y (= Godot +Z), origin at the centre.
Chunky proportions so they read from the high camera (skills add trails/glow in code).
Materials whose name contains "tip" mark the leading end (checked by the probe).
OWNER: assets-environment.
"""

import math
import random

from mathutils import Matrix, Vector

import envlib as L
from envlib import MeshBuilder

O = Vector((0, 0, 0))
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

# local +Z -> Blender -Y (flight direction)
TO_FRONT = Matrix.Rotation(math.pi / 2, 4, "X")
# local +Z -> Blender +Y (backwards)
TO_BACK = Matrix.Rotation(-math.pi / 2, 4, "X")


def _fin(mb, y0, y1, height, angle, mat, back_sweep=0.02, thick=0.007):
    """Triangular fin along the shaft (Y), sticking out in direction `angle` around the shaft."""
    d = Vector((math.cos(angle), 0.0, math.sin(angle)))
    u = Y
    v = d
    n = u.cross(v)
    poly = [(y0, 0.0), (y1, 0.0), (y1 - back_sweep, height)]
    # poly winding must be CCW in (u, v): (y0,0)->(y1,0)->(y1-s,h) is CCW when y1 > y0
    mb.prism(poly, -thick / 2, thick / 2, mat, frame=(O, u, v, n))


def build_proj_arrow():
    mb = MeshBuilder()
    # shaft (tail at +Y, head at -Y)
    mb.cyl_between((0, 0.44, 0), (0, -0.3, 0), 0.022, 0.022, "wood_light", segs=6)
    # broad head, flat side up so it reads from above
    mb.hull([(0, -0.47, 0), (0.065, -0.32, 0), (-0.065, -0.32, 0), (0, -0.29, 0.022), (0, -0.29, -0.022),
             (0.02, -0.28, 0), (-0.02, -0.28, 0)], "iron_tip")
    # fletching: two flat fins (seen from above) + one upright
    for a, m in ((0.0, "feather_red"), (math.pi, "feather_red"), (math.pi / 2, "feather")):
        _fin(mb, 0.24, 0.43, 0.075, a, m)
    mb.cyl((0, 0.45, 0), 0.03, 0.03, 0.04, "iron_dark", segs=6, rot=(math.pi / 2, 0, 0))
    mb.finish("proj_arrow")


def build_proj_bolt():
    mb = MeshBuilder()
    mb.cyl_between((0, 0.3, 0), (0, -0.2, 0), 0.03, 0.03, "wood_dark", segs=6)
    # heavy square head
    head = mb.lathe([(0.0, 0.0), (0.06, 0.0), (0.065, 0.03), (0.0, 0.14)], "iron_tip", segs=4,
                    phase=math.pi / 4)
    mb.transform(head, Matrix.Translation((0, -0.2, 0)) @ TO_FRONT)
    mb.cyl((0, -0.19, 0), 0.042, 0.042, 0.04, "iron", segs=6, rot=(math.pi / 2, 0, 0))
    # four stiff vanes
    for k in range(4):
        _fin(mb, 0.14, 0.3, 0.06, k * math.pi / 2, "bronze", back_sweep=0.0, thick=0.012)
    mb.finish("proj_bolt")


def build_proj_ice_spear():
    mb = MeshBuilder()
    rng = random.Random(73)
    body = mb.lathe([(0.0, -0.66), (0.06, -0.52), (0.115, -0.05), (0.1, 0.22)], "emit_ice", segs=6,
                    cap_top=False)
    tip = mb.lathe([(0.1, 0.22), (0.0, 0.66)], "emit_ice_tip", segs=6, cap_bottom=False)
    mb.transform(body + tip, TO_FRONT)
    # side shards swept back
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        base = Vector((0.05 * math.cos(a), 0.05, 0.05 * math.sin(a)))
        d = Vector((0.45 * math.cos(a), 1.0, 0.45 * math.sin(a))).normalized()
        ln = 0.34 + 0.06 * (k % 2)
        shard = mb.lathe([(0.0, -0.02), (0.045, 0.0), (0.04, ln * 0.6), (0.0, ln)], "emit_ice", segs=5,
                         cap_bottom=False, phase=rng.uniform(0, 1))
        q = Vector((0, 0, 1)).rotation_difference(d)
        mb.transform(shard, Matrix.Translation(base) @ q.to_matrix().to_4x4())
    mb.finish("proj_ice_spear")


def build_proj_meteor():
    mb = MeshBuilder()
    rng = random.Random(79)
    pts = L.rock_points((0, 0, 0), (0.42, 0.44, 0.4), rng, n=18, flat_bottom=False, rough=0.16)
    mb.hull(pts, "rock_meteor")
    # glowing lava cracks: small shards poking out of the surface
    for _ in range(9):
        th = rng.uniform(0, 2 * math.pi)
        ph = rng.uniform(0.3, 2.8)
        d = Vector((math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th), math.cos(ph)))
        c = d * 0.36
        mb.ico(c, rng.uniform(0.07, 0.11), "emit_lava", subdiv=0, scale=(1.0, 1.0, 0.45),
               rot=(rng.uniform(0, 3), rng.uniform(0, 3), 0))
    # flame trail behind (+Y)
    # closed shells (capped at the rock end): the coarse rock hull does not fully hide the
    # trail's base ring, and the models are single-sided
    trail = mb.lathe([(0.34, 0.0), (0.36, 0.25), (0.26, 0.6), (0.12, 0.95), (0.0, 1.2)], "emit_trail",
                     segs=8)
    mb.transform(trail, Matrix.Translation((0, 0.12, 0)) @ TO_BACK)
    core = mb.lathe([(0.26, 0.0), (0.2, 0.4), (0.0, 0.75)], "emit_fire_core", segs=6)
    mb.transform(core, Matrix.Translation((0, 0.2, 0.02)) @ TO_BACK)
    mb.finish("proj_meteor")


BUILDERS = {
    "proj_arrow": build_proj_arrow,
    "proj_bolt": build_proj_bolt,
    "proj_ice_spear": build_proj_ice_spear,
    "proj_meteor": build_proj_meteor,
}
