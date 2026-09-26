"""Back-face / see-through checks for the environment models (Blender 5.2, --background).

The models are exported with backface culling (glTF doubleSided = false -> Godot CULL_BACK), so
every surface a camera can see must be a FRONT face. These checks ray-cast the built scene the way
a renderer would and report:

- check_backfaces(): rays from many directions around/above the model; a first hit on a BACK face
  means a hole or a flipped face that would render see-through with culling on.
- check_wall_slit(): a wall block surrounded by floor tiles (the dungeon arrangement) with a
  "void" catcher plane far below; rays from game-camera angles aimed at the wall base must never
  reach the void (the floor edge groove used to show a see-through slit under the walls).

Used by build_all.py --check (and --check-only). OWNER: assets-environment.
"""

import math

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


GRAZE = 0.03    # |cos| below which a back-face hit counts as a grazing silhouette hit


def _scene_polys(extra_matrix=None, lid_open=False):
    """World-space triangles of every mesh object: (verts, tris, normals, mats)."""
    bpy.context.view_layer.update()
    verts = []
    polys = []
    normals = []
    mats = []
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world.copy()
        if lid_open and ob.name == "Lid":
            # Godot rotation.x = -110 deg == Blender rotation about X by -110 deg (about the pivot)
            mw = ob.parent.matrix_world @ Matrix.Translation(ob.location) @ Matrix.Rotation(math.radians(-110), 4, "X")
        if extra_matrix is not None:
            mw = extra_matrix @ mw
        nm = mw.to_3x3().inverted_safe().transposed()
        me = ob.data
        base = len(verts)
        verts.extend(mw @ v.co for v in me.vertices)
        # the exporter's triangulation (loop triangles): non-planar quads (twisted flames,
        # jittered foliage) must be tested as the triangles the GPU will actually draw
        me.calc_loop_triangles()
        for lt in me.loop_triangles:
            polys.append([base + i for i in lt.vertices])
            n = nm @ lt.normal
            normals.append(n.normalized() if n.length > 1e-12 else n)
            mi = lt.material_index
            mname = me.materials[mi].name if me.materials and mi < len(me.materials) and me.materials[mi] else "?"
            mats.append(mname)
    return verts, polys, normals, mats


def _bounds(verts):
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    return lo, hi


def _basis(d):
    """Two unit vectors perpendicular to d."""
    a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(a).normalized()
    v = d.cross(u).normalized()
    return u, v


def _march(tree, o, d, max_dist):
    """Follow a ray like a renderer with backface culling: skip back faces. Returns
    (first_hit_index, first_was_back, final, final_index) where final is 'front' (a front face
    was reached after 0+ back faces), 'escape' (nothing but back faces: see-through) or None
    (missed)."""
    first = None
    first_back = False
    p = o
    travelled = 0.0
    for _ in range(64):
        loc, n, idx, dist = tree.ray_cast(p, d, max_dist - travelled)
        if loc is None:
            return first, first_back, ("escape" if first is not None else None), None
        # BVHTree returns the normal of the hit TRIANGLE (winding order), like a rasteriser.
        # Nearly edge-on back faces (a grazing ray along a twisted, non-planar quad at the
        # silhouette) are skipped: they are sub-pixel slivers, not holes.
        nd = n.dot(d)
        if 0.0 < nd <= GRAZE:
            travelled += dist + 1e-5
            p = loc + d * 1e-5
            continue
        back = nd > 0.0
        if first is None:
            first = idx
            first_back = back
        if not back:
            return first, first_back, "front", idx
        travelled += dist + 1e-5
        p = loc + d * 1e-5
    return first, first_back, "front", None


def check_backfaces(model_id, min_elev=0.0, max_elev=90.0, n_az=24, n_el=9, grid=36,
                    lid_open=False, tolerance=0.0, allow_interior=False):
    """Cast rays at the scene from n_az x n_el directions (elevation in degrees above the
    horizon of the direction the viewer looks FROM). Counts first hits on BACK faces (a flipped
    face or a hole in a shell) and rays that pass only back faces (see-through with culling).
    allow_interior: a back face followed by a front face (the wall kit's dark core seen through
    a corner notch) is reported but does not fail; see-through always fails.
    Returns (ok, report_string)."""
    verts, polys, normals, mats = _scene_polys(lid_open=lid_open)
    if not polys:
        return True, "%s: no geometry" % model_id
    tree = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    lo, hi = _bounds(verts)
    c = (lo + hi) / 2
    R = max((hi - lo).length / 2, 0.05)
    hits = 0
    back = 0
    through = 0
    back_mats = {}
    examples = []
    for ie in range(n_el):
        el = math.radians(min_elev + (max_elev - min_elev) * (ie + 0.5) / n_el)
        for ia in range(n_az):
            az = 2 * math.pi * (ia + 0.37 * ie) / n_az
            # viewer position direction (from the model towards the viewer)
            to_viewer = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
            d = -to_viewer
            u, v = _basis(d)
            for gi in range(grid):
                for gj in range(grid):
                    a = (gi + 0.5) / grid * 2 - 1
                    b = (gj + 0.5) / grid * 2 - 1
                    o = c + to_viewer * (3 * R) + u * (a * R) + v * (b * R)
                    idx, was_back, final, _fi = _march(tree, o, d, 7 * R)
                    if idx is None:
                        continue
                    hits += 1
                    if was_back:
                        back += 1
                        if final == "escape":
                            through += 1
                        back_mats[mats[idx]] = back_mats.get(mats[idx], 0) + 1
                        if len(examples) < 6:
                            loc, _n, _i, _d = tree.ray_cast(o, d, 7 * R)
                            examples.append("(%.3f, %.3f, %.3f) el=%.0f %s" % (loc.x, loc.y, loc.z, math.degrees(el), final))
    if allow_interior:
        ok = through == 0
    else:
        ok = back <= tolerance * hits
    rep = "%s%s: %d hits, %d back-face first hits (%.3f%%), %d see-through" % (
        model_id, " [lid open]" if lid_open else "", hits, back, 100.0 * back / max(hits, 1), through)
    if back:
        top = sorted(back_mats.items(), key=lambda kv: -kv[1])[:6]
        rep += " by material %s; e.g. %s" % (top, "; ".join(examples))
    return ok, rep


def check_wall_slit(floor_builder, wall_builder, reset):
    """Build a 3x3 block (wall in the centre, floor tiles around) plus a void catcher plane at
    z = -3 and aim rays from game-camera angles at the wall base. Returns (ok, report)."""
    import bmesh  # noqa: F401  (builders use it)
    parts = []
    # wall at the centre cell, floors on the 8 neighbours (random quarter turns like the world)
    for (ix, iy) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1), (0, 0)]:
        reset()
        (wall_builder if (ix, iy) == (0, 0) else floor_builder)()
        rot = Matrix.Rotation(math.pi / 2 * ((ix * 3 + iy * 5) % 4), 4, "Z")
        m = Matrix.Translation((2.0 * ix, 2.0 * iy, 0.0)) @ rot
        parts.append(_scene_polys(extra_matrix=m))
    verts, polys, normals, mats = [], [], [], []
    for pv, pp, pn, pm in parts:
        base = len(verts)
        verts.extend(pv)
        polys.extend([[base + i for i in p] for p in pp])
        normals.extend(pn)
        mats.extend(pm)
    # void catcher
    base = len(verts)
    verts.extend([Vector((-9, -9, -3)), Vector((9, -9, -3)), Vector((9, 9, -3)), Vector((-9, 9, -3))])
    polys.append([base, base + 1, base + 2, base + 3])
    normals.append(Vector((0, 0, 1)))
    mats.append("VOID")
    tree = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    void = 0
    back = 0
    total = 0
    examples = []
    # targets: a band around the wall base on all four faces
    targets = []
    for k in range(80):
        t = -1.0 + 2.0 * (k + 0.5) / 80
        for off in (0.0, 0.02, 0.05):
            for z in (-0.04, -0.01, 0.01, 0.04):
                targets += [Vector((t, -1 - off, z)), Vector((t, 1 + off, z)), Vector((-1 - off, t, z)), Vector((1 + off, t, z))]
    for el_deg in (20, 30, 34, 40, 48, 56, 64, 72, 79):
        el = math.radians(el_deg)
        for az_deg in range(0, 360, 10):
            az = math.radians(az_deg + 3)
            to_viewer = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
            d = -to_viewer
            for tg in targets:
                o = tg + to_viewer * 6.0
                idx, was_back, final, fidx = _march(tree, o, d, 20.0)
                if idx is None:
                    continue
                total += 1
                if was_back:
                    back += 1
                if final == "escape" or (fidx is not None and mats[fidx] == "VOID"):
                    void += 1
                    if len(examples) < 6:
                        examples.append("target (%.2f, %.2f, %.2f) el=%d az=%d" % (tg.x, tg.y, tg.z, el_deg, az_deg))
    ok = void == 0
    rep = "wall slit: %d rays at the wall base, %d reached the void (%d saw the dark core through a back face first)" % (total, void, back)
    if examples:
        rep += "; e.g. " + "; ".join(examples)
    return ok, rep
