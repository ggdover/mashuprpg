"""Shared helpers for the environment asset scripts (Blender 5.2, run in --background mode).

Everything is built with bmesh directly in WORLD coordinates, so every exported object has an
identity transform (§14.1) and every kit piece is exactly one mesh object.

Blender axes: Z up, models face -Y (= Godot +Z after export_yup). Colours are given in sRGB hex
and converted to the linear values Blender's Principled BSDF expects.

OWNER: assets-environment.
"""

import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MODELS_DIR = os.path.join(REPO, "assets", "models")
SKILL_ICONS_DIR = os.path.join(REPO, "assets", "icons", "skills")


# ----------------------------------------------------------------------------------- scene

def reset_scene():
    """Fresh empty file per model (§14.1): no name collisions, no leftovers."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ----------------------------------------------------------------------------------- colours

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    """'#rrggbb' (sRGB) -> linear (r, g, b)."""
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


# Cohesive palette (sRGB hex). Stone pieces that the world tints per theme use tint_* materials
# with a neutral grey base (Blender base colour ~0.8 as required by §14.1). The other tint_
# variants are INTENTIONALLY darker so relative shading survives the per-theme tint (linear
# value -> Godot albedo sRGB):
#   tint_stone      0.80  -> 0.91  base stone (most slabs / blocks)
#   tint_stone_b    0.66  -> 0.83  variation slabs / blocks, pillar plinth, band and capital
#   tint_stone_c    0.54  -> 0.76  darker variation (sunken floor fragments, some wall_b blocks)
#   tint_stone_dark 0.30  -> 0.58  hidden / recessed stone: floor skirts, wall core, fins, base
#   tint_stone_top  0.085 -> 0.32  (0.09 blue) wall and pillar top caps (read as "solid" from above)
PALETTE = {
    # tintable stone (linear greys, not hex)
    "tint_stone": dict(lin=(0.80, 0.80, 0.80), rough=0.92),
    "tint_stone_b": dict(lin=(0.66, 0.66, 0.66), rough=0.92),
    "tint_stone_c": dict(lin=(0.54, 0.54, 0.54), rough=0.92),
    "tint_stone_dark": dict(lin=(0.30, 0.30, 0.30), rough=0.95),
    "tint_stone_top": dict(lin=(0.085, 0.085, 0.09), rough=1.0),
    # fixed-colour dungeon stone for props (rocks, rubble, crystal bases); Assets.tint() still
    # tints them as a whole if the world wants to
    "stone": dict(hex="#77726b", rough=0.95),
    "stone_light": dict(hex="#8c877f", rough=0.95),
    "stone_dark": dict(hex="#57534e", rough=0.95),
    # woods
    "wood": dict(hex="#7a5434", rough=0.85),
    "wood_dark": dict(hex="#553823", rough=0.88),
    "wood_light": dict(hex="#9c7247", rough=0.85),
    "wood_grey": dict(hex="#7d7266", rough=0.9),
    # metals
    "iron": dict(hex="#45464d", rough=0.55, metal=0.35),
    "iron_dark": dict(hex="#2c2d33", rough=0.6, metal=0.3),
    "iron_tip": dict(hex="#8d929c", rough=0.35, metal=0.5),
    "gold": dict(hex="#c99a3b", rough=0.4, metal=0.55),
    "bronze": dict(hex="#9a6a38", rough=0.5, metal=0.45),
    # organic / misc
    "bone": dict(hex="#d8cfb4", rough=0.8),
    "bone_dark": dict(hex="#a89d82", rough=0.85),
    "rope": dict(hex="#a88a5a", rough=0.95),
    "cloth_red": dict(hex="#9e3129", rough=0.9),
    "cloth_cream": dict(hex="#e0d2ae", rough=0.9),
    "cloth_blue": dict(hex="#3a5a8c", rough=0.9),
    "cloth_green": dict(hex="#4f7a3a", rough=0.9),
    "sack": dict(hex="#b39a6c", rough=0.95),
    "plaster": dict(hex="#dccfb3", rough=0.95),
    "plaster_warm": dict(hex="#d7b98f", rough=0.95),
    "roof_red": dict(hex="#94412c", rough=0.85),
    "roof_slate": dict(hex="#4c5a6e", rough=0.8),
    "roof_slate_dark": dict(hex="#3a4556", rough=0.8),
    "roof_red_dark": dict(hex="#763020", rough=0.85),
    "stone_quoin": dict(hex="#b5ad9c", rough=0.92),
    "roof_thatch": dict(hex="#a88a4c", rough=0.95),
    "roof_thatch_dark": dict(hex="#7a5f30", rough=0.95),
    "roof_thatch_b": dict(hex="#9c7e42", rough=0.95),
    "roof_red_b": dict(hex="#8a3a27", rough=0.85),
    "town_stone": dict(hex="#8d877c", rough=0.92),
    "portal_stone": dict(hex="#77737f", rough=0.9),
    "portal_stone_dark": dict(hex="#55525e", rough=0.9),
    "town_stone_dark": dict(hex="#625d56", rough=0.92),
    "town_rock": dict(hex="#7b776f", rough=0.95),
    "moss": dict(hex="#5d7a36", rough=0.95),
    "leaf": dict(hex="#5c8f38", rough=0.9),
    "leaf_dark": dict(hex="#3e6d2c", rough=0.9),
    "leaf_light": dict(hex="#7aa846", rough=0.9),
    "pine": dict(hex="#2f6041", rough=0.9),
    "pine_dark": dict(hex="#23493a", rough=0.9),
    "bark": dict(hex="#5e4430", rough=0.95),
    "window_dark": dict(hex="#26303d", rough=0.3),
    "water": dict(hex="#2b4d60", rough=0.1),
    "sign_paint": dict(hex="#e8d9a8", rough=0.8),
    "dirt": dict(hex="#5a4632", rough=1.0),
    "coal": dict(hex="#1e1a18", rough=0.95),
    "ash": dict(hex="#3a3532", rough=1.0),
    "fruit_red": dict(hex="#b8322a", rough=0.6),
    "fruit_yellow": dict(hex="#d9b43a", rough=0.6),
    "pot": dict(hex="#a45f3a", rough=0.8),
    "feather": dict(hex="#e8e2d0", rough=0.9),
    "feather_red": dict(hex="#b33a2a", rough=0.9),
    "rock_meteor": dict(hex="#3b2f2a", rough=0.95),
    # emissive (unshaded-looking glow; Godot imports emission + energy)
    "emit_fire": dict(hex="#ff8a24", emit="#ff7a1a", strength=6.0, rough=1.0),
    "emit_fire_core": dict(hex="#ffd36a", emit="#ffcc55", strength=8.0, rough=1.0),
    "emit_ember": dict(hex="#ff5a1a", emit="#ff4a10", strength=4.0, rough=1.0),
    "emit_crystal": dict(hex="#5fd8ff", emit="#3fc6ff", strength=4.0, rough=0.25),
    "emit_crystal_core": dict(hex="#c8f4ff", emit="#9fe8ff", strength=6.0, rough=0.2),
    "emit_rune": dict(hex="#62e6ff", emit="#39d4ff", strength=5.0, rough=0.5),
    "emit_portal": dict(hex="#6fa8ff", emit="#4f86ff", strength=4.0, rough=0.5),
    "emit_lamp": dict(hex="#ffcf7a", emit="#ffbb55", strength=5.0, rough=0.4),
    "emit_window": dict(hex="#ffc46b", emit="#ffae45", strength=1.6, rough=0.5),
    "emit_ice": dict(hex="#bfeaff", emit="#7fd0ff", strength=2.5, rough=0.15),
    "emit_ice_tip": dict(hex="#e8faff", emit="#bfeaff", strength=3.5, rough=0.1),
    "emit_lava": dict(hex="#ff6a1a", emit="#ff5a10", strength=6.0, rough=1.0),
    "emit_trail": dict(hex="#ffb040", emit="#ff9a30", strength=5.0, rough=1.0),
}


def material(name, spec=None):
    """Get or create a Principled material from PALETTE (or an explicit spec dict)."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    spec = spec if spec is not None else PALETTE[name]
    base = spec["lin"] if "lin" in spec else hexcol(spec["hex"])
    m = bpy.data.materials.new(name)
    m.diffuse_color = (base[0], base[1], base[2], 1.0)
    m.roughness = spec.get("rough", 0.85)
    m.metallic = spec.get("metal", 0.0)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF") if nt else None
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (base[0], base[1], base[2], 1.0)
        bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.85)
        bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
        if "emit" in spec:
            e = hexcol(spec["emit"])
            bsdf.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = spec.get("strength", 1.0)
    return m


# ----------------------------------------------------------------------------------- geometry

def v3(x, y=None, z=None):
    if y is None:
        return Vector(x)
    return Vector((x, y, z))


def mat4(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    return Matrix.LocRotScale(Vector(loc), Euler(rot, "XYZ"), Vector(scale))


class MeshBuilder:
    """Accumulates geometry for ONE mesh object, with per-part materials.

    All coordinates are world coordinates (the object stays at the identity transform)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    # -- materials
    def mat_index(self, mat_name):
        if mat_name not in self.mats:
            self.mats.append(mat_name)
            material(mat_name)
        return self.mats.index(mat_name)

    def _faces_of(self, verts):
        """Faces touching verts, in a deterministic (index) order."""
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        self.bm.faces.index_update()
        return sorted(faces, key=lambda f: f.index)

    def _assign(self, verts, mat_name):
        idx = self.mat_index(mat_name)
        faces = self._faces_of(verts)
        for f in faces:
            f.material_index = idx
        return faces

    def _edges_of(self, verts):
        """Edges touching verts, in a deterministic (index) order (set order depends on memory
        addresses, which would make bevel output - and the exported files - vary per run)."""
        edges = set()
        for v in verts:
            edges.update(v.link_edges)
        self.bm.edges.index_update()
        return sorted(edges, key=lambda e: e.index)

    def _bevel(self, verts, amount, segments=1):
        if amount <= 0:
            return verts
        # the primitives are transformed after creation, so the cached face normals are stale:
        # bevel offsets along them, and a stale normal (e.g. a box rotated > 90 deg) makes the
        # bevel go OUTWARD, leaving an inside-out block (a hole once backface culling is on)
        self.bm.normal_update()
        edges = self._edges_of(verts)
        res = bmesh.ops.bevel(self.bm, geom=edges, offset=amount, offset_type="OFFSET",
                              segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
        # collect the verts of the (now bevelled) part again
        out = set(v for v in verts if v.is_valid)
        out.update(res.get("verts", []))
        for f in res.get("faces", []):
            out.update(f.verts)
        self.bm.verts.index_update()
        return sorted(out, key=lambda v: v.index)

    # -- primitives (return the list of BMVerts of the part)
    def box(self, center, size, mat, rot=(0, 0, 0), bevel=0.0, taper=None):
        """Axis box of `size` centred at `center` (then rotated about its centre).
        taper=(sx, sy) scales the top face (for tapered blocks)."""
        m = mat4((0, 0, 0), (0, 0, 0), size)
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        verts = res["verts"]
        if taper is not None:
            for v in verts:
                if v.co.z > 0:
                    v.co.x *= taper[0]
                    v.co.y *= taper[1]
        rm = mat4(center, rot)
        for v in verts:
            v.co = rm @ v.co
        verts = self._bevel(verts, bevel)
        self._assign(verts, mat)
        return verts

    def obox(self, center, axes, sizes, mat, bevel=0.0):
        """Oriented box: axes = (a, b, c) orthonormal vectors, sizes along them."""
        a, b, c = (Vector(x) for x in axes)
        if a.cross(b).dot(c) < 0:
            c = -c
        m = Matrix(((a.x * sizes[0], b.x * sizes[1], c.x * sizes[2], center[0]),
                    (a.y * sizes[0], b.y * sizes[1], c.y * sizes[2], center[1]),
                    (a.z * sizes[0], b.z * sizes[1], c.z * sizes[2], center[2]),
                    (0.0, 0.0, 0.0, 1.0)))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        verts = self._bevel(res["verts"], bevel)
        self._assign(verts, mat)
        return verts

    def box_minmax(self, lo, hi, mat, bevel=0.0):
        c = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)
        s = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        return self.box(c, s, mat, bevel=bevel)

    def cyl(self, center, r1, r2, depth, mat, segs=8, rot=(0, 0, 0), bevel=0.0, cap=True,
            twist=0.0):
        """Cylinder/cone along local Z, centred at `center` (then rotated)."""
        m = mat4(center, rot) @ Matrix.Rotation(twist, 4, "Z")
        res = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=depth, matrix=m)
        verts = self._bevel(res["verts"], bevel)
        self._assign(verts, mat)
        return verts

    def cyl_between(self, a, b, r1, r2, mat, segs=6, cap=True):
        """Cylinder from point a to point b."""
        a = Vector(a)
        b = Vector(b)
        d = b - a
        length = d.length
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=length, matrix=m)
        self._assign(res["verts"], mat)
        return res["verts"]

    def ico(self, center, radius, mat, subdiv=1, scale=(1, 1, 1), jitter=0.0, rng=None,
            rot=(0, 0, 0), flatten_below=None):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius,
                                         matrix=Matrix())
        verts = res["verts"]
        rng = rng or random.Random(1)
        for v in verts:
            if jitter > 0:
                v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter
            v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
        m = mat4(center, rot)
        for v in verts:
            v.co = m @ v.co
            if flatten_below is not None and v.co.z < flatten_below:
                v.co.z = flatten_below
        self._assign(verts, mat)
        return verts

    def hull(self, points, mat):
        """Convex hull of points (for chunky rocks, crystals, gems)."""
        verts = [self.bm.verts.new(Vector(p)) for p in points]
        res = bmesh.ops.convex_hull(self.bm, input=verts)
        # remove interior/unused verts
        unused = [g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)]
        if unused:
            bmesh.ops.delete(self.bm, geom=unused, context="VERTS")
        verts = [v for v in verts if v.is_valid]
        faces = list(self._faces_of(verts))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        self._assign(verts, mat)
        return verts

    def face(self, pts, mat):
        """Single polygon (pts in CCW order seen from the front)."""
        verts = [self.bm.verts.new(Vector(p)) for p in pts]
        f = self.bm.faces.new(verts)
        f.material_index = self.mat_index(mat)
        return verts

    def prism(self, poly, z0, z1, mat, frame=None, cap_bottom=True, bevel=0.0):
        """Extrude a 2D polygon (CCW, local u/v) from n=z0 to n=z1 in `frame`.
        frame = (origin, u, v, n) vectors; default = world XY with n = +Z."""
        o, u, vv, n = frame if frame else (Vector((0, 0, 0)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))

        def P(p, h):
            return o + u * p[0] + vv * p[1] + n * h
        bot = [self.bm.verts.new(P(p, z0)) for p in poly]
        top = [self.bm.verts.new(P(p, z1)) for p in poly]
        k = len(poly)
        self.bm.faces.new(top)
        if cap_bottom:
            self.bm.faces.new(list(reversed(bot)))
        for i in range(k):
            j = (i + 1) % k
            self.bm.faces.new([bot[i], bot[j], top[j], top[i]])
        verts = bot + top
        verts = self._bevel(verts, bevel)
        self._assign(verts, mat)
        return verts

    def slab(self, poly, frame, depth, chamfer, mat, chamfer_depth=None, edge_chamfer=None,
             miter_edges=None):
        """A stone slab / block face: front polygon at n=depth, inset by `chamfer` on chamfered
        edges, with chamfer quads going back to the polygon outline at n=depth-chamfer_depth.
        No back or sides (neighbours / a core close it). poly = convex CCW list of (u, v).
        miter_edges: per-edge flags for FLUSH edges lying on an outer corner of the block (the
        n = 0 plane is the block boundary): the grooved outline vertices of such an edge are
        pulled inwards by their depth below n = 0, so the chamfer ends on the 45-degree miter
        plane and meets the perpendicular face's chamfer exactly (no gap at the corner)."""
        o, u, vv, n = frame
        cd = chamfer if chamfer_depth is None else chamfer_depth
        k = len(poly)
        flags = edge_chamfer if edge_chamfer is not None else [True] * k
        pts = [Vector((p[0], p[1])) for p in poly]
        # inward offset lines
        lines = []
        for i in range(k):
            a = pts[i]
            b = pts[(i + 1) % k]
            d = (b - a).normalized()
            nrm = Vector((-d.y, d.x))  # inward for CCW
            f = flags[i]
            off = chamfer if f is True else (0.0 if not f else float(f))
            lines.append((a + nrm * off, d))
        inset = []
        for i in range(k):
            p1, d1 = lines[(i - 1) % k]
            p2, d2 = lines[i]
            den = d1.x * d2.y - d1.y * d2.x
            if abs(den) < 1e-9:
                inset.append(p2.copy())
            else:
                t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den
                inset.append(p1 + d1 * t)

        def P(p, h):
            return o + u * p.x + vv * p.y + n * h
        # outline vertex depth: a corner sits in a groove if either adjacent edge is chamfered
        outer = []
        for i in range(k):
            grooved = flags[i] or flags[(i - 1) % k]
            p = pts[i].copy()
            if grooved and miter_edges is not None:
                for e in (i, (i - 1) % k):
                    if miter_edges[e] and not flags[e]:
                        d = (pts[(e + 1) % k] - pts[e]).normalized()
                        p += Vector((-d.y, d.x)) * (cd - depth)
            outer.append(self.bm.verts.new(P(p, depth - cd if grooved else depth)))
        front = [self.bm.verts.new(P(p, depth)) for p in inset]
        created = outer + front
        self.bm.faces.new(front)
        for i in range(k):
            j = (i + 1) % k
            if not flags[i]:
                continue   # flush edge: continues seamlessly into the neighbour tile
            self.bm.faces.new([outer[i], outer[j], front[j], front[i]])
        # merge coincident verts (flush corners)
        bmesh.ops.remove_doubles(self.bm, verts=[v for v in created if v.is_valid], dist=1e-6)
        created = [v for v in created if v.is_valid]
        self._assign(created, mat)
        return created

    def lathe(self, profile, mat, segs=12, center=(0, 0, 0), closed=False, cap_bottom=True,
              cap_top=True, phase=0.0, matrix=None, scale_xy=(1.0, 1.0)):
        """Surface of revolution around local Z. profile = [(r, z), ...] traversed so that the
        solid is on the LEFT (bottom -> outside -> top for a solid; CCW in the r/z half-plane
        for closed=True rings). r == 0 collapses to a pole. matrix transforms the local result."""
        cx, cy, cz = center
        rings = []
        for (r, z) in profile:
            if r <= 1e-9:
                rings.append([self.bm.verts.new((cx, cy, cz + z))])
            else:
                ring = []
                for i in range(segs):
                    a = phase + 2 * math.pi * i / segs
                    ring.append(self.bm.verts.new((cx + r * math.cos(a) * scale_xy[0],
                                                   cy + r * math.sin(a) * scale_xy[1], cz + z)))
                rings.append(ring)
        pairs = list(range(len(rings) - 1))
        if closed:
            pairs.append(len(rings) - 1)
        for k in pairs:
            ra = rings[k]
            rb = rings[(k + 1) % len(rings)]
            for i in range(segs):
                j = (i + 1) % segs
                if len(ra) == 1 and len(rb) == 1:
                    continue
                if len(ra) == 1:
                    self.bm.faces.new([ra[0], rb[j], rb[i]])
                elif len(rb) == 1:
                    self.bm.faces.new([ra[i], ra[j], rb[0]])
                else:
                    self.bm.faces.new([ra[i], ra[j], rb[j], rb[i]])
        if not closed:
            if cap_bottom and len(rings[0]) > 1:
                self.bm.faces.new(list(reversed(rings[0])))
            if cap_top and len(rings[-1]) > 1:
                self.bm.faces.new(rings[-1])
        verts = [v for ring in rings for v in ring]
        if matrix is not None:
            c = Vector(center)
            for v in verts:
                v.co = c + (matrix @ (v.co - c))
        self._assign(verts, mat)
        return verts

    def transform(self, verts, matrix):
        for v in verts:
            v.co = matrix @ v.co

    def paint_top(self, z, mat, tol=1e-4):
        """Assign `mat` to every up-facing face lying at height z (dark tops of walls/pillars)."""
        idx = self.mat_index(mat)
        self.bm.normal_update()
        for f in self.bm.faces:
            if f.normal.z > 0.999 and all(abs(v.co.z - z) < tol for v in f.verts):
                f.material_index = idx

    def clamp_floor(self, z=0.0):
        """Push every vertex below the floor up to it (props rest on y = 0)."""
        for v in self.bm.verts:
            if v.co.z < z:
                v.co.z = z

    def tri_count(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def finish(self, name, parent=None, location=(0, 0, 0)):
        """Create the object. For moving child parts (chest Lid) pass parent + location: the
        geometry must then be modelled relative to that pivot."""
        me = bpy.data.meshes.new(name)
        canon = _canonical_bmesh(self.bm)
        self.bm.free()
        canon.normal_update()
        canon.to_mesh(me)
        canon.free()
        for mname in self.mats:
            me.materials.append(bpy.data.materials[mname])
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        if parent is not None:
            ob.parent = parent
            ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.location = Vector(location)
        return ob


def _canonical_bmesh(bm, digits=5):
    """Rebuild a bmesh in a canonical element order: faces sorted by (material, vertex
    coordinates), each face's loop rotated to start at its smallest vertex, coincident vertices
    welded. Some bmesh operators (bevel, convex hull) iterate pointer-hashed sets, so their output
    order varies between runs; this makes the exported files byte-identical for identical shapes."""
    faces = []
    for f in bm.faces:
        cos = [tuple(round(c, digits) + 0.0 for c in v.co) for v in f.verts]
        # drop consecutive duplicates (cyclic)
        clean = []
        for c in cos:
            if not clean or clean[-1] != c:
                clean.append(c)
        while len(clean) > 1 and clean[0] == clean[-1]:
            clean.pop()
        if len(clean) < 3 or len(set(clean)) != len(clean):
            continue
        k = min(range(len(clean)), key=lambda i: clean[i])
        clean = clean[k:] + clean[:k]
        faces.append((f.material_index, tuple(clean)))
    faces.sort()
    nb = bmesh.new()
    vmap = {}
    seen = set()
    for mi, cos in faces:
        key = (mi, cos)
        if key in seen:
            continue
        seen.add(key)
        vs = []
        for c in cos:
            v = vmap.get(c)
            if v is None:
                v = nb.verts.new(c)
                vmap[c] = v
            vs.append(v)
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue      # exact duplicate face (hidden anyway)
        nf.material_index = mi
    return nb


# ----------------------------------------------------------------------------------- validation/export

def validate_scene(model_id, allowed_moving=("Lid",)):
    """Assert §14.1: identity transforms (except named moving parts), no .001 names."""
    for ob in bpy.data.objects:
        if "." in ob.name:
            raise RuntimeError("%s: object name with suffix: %s" % (model_id, ob.name))
        if ob.name in allowed_moving:
            r = ob.matrix_local.to_3x3()
            if any(abs(r[i][j] - (1 if i == j else 0)) > 1e-6 for i in range(3) for j in range(3)):
                raise RuntimeError("%s: %s must have identity rotation/scale" % (model_id, ob.name))
            continue
        mw = ob.matrix_world
        if any(abs(mw[i][j] - (1 if i == j else 0)) > 1e-6 for i in range(4) for j in range(4)):
            raise RuntimeError("%s: object %s has a non-identity transform" % (model_id, ob.name))
    for m in bpy.data.materials:
        if "." in m.name:
            raise RuntimeError("%s: material name with suffix: %s" % (model_id, m.name))


def prepare_materials_for_export():
    """Every environment material is single-sided: use_backface_culling -> glTF
    doubleSided = false -> Godot imports cull_mode = CULL_BACK. All shells are closed (or only
    ever seen from their front side); build_all.py --check verifies that no back face is visible."""
    for m in bpy.data.materials:
        m.use_backface_culling = True


def export_glb(model_id):
    """Export the whole scene to assets/models/<id>.glb atomically (§14.1)."""
    validate_scene(model_id)
    for m in bpy.data.materials:
        if not m.use_backface_culling:
            raise RuntimeError("%s: material %s must use backface culling" % (model_id, m.name))
    tmp_dir = os.path.join(MODELS_DIR, ".tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    tmp = os.path.join(tmp_dir, model_id + ".glb")
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_apply=True,
                              export_yup=True, export_animation_mode='ACTIONS',
                              export_def_bones=False, export_anim_slide_to_zero=True,
                              export_cameras=False, export_lights=False)
    final = os.path.join(MODELS_DIR, model_id + ".glb")
    os.replace(tmp, final)
    return final


def scene_tri_count():
    total = 0
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    return total


def scene_bounds():
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


# ----------------------------------------------------------------------------------- small shape helpers

def circle_pts(r, n, phase=0.0, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(phase + 2 * math.pi * i / n), cy + r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def jitter_pts(pts, amount, rng):
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in pts]


def rock_points(center, radii, rng, n=14, flat_bottom=True, rough=0.18):
    """Random points on a squashed ellipsoid, for hull() rocks."""
    cx, cy, cz = center
    pts = []
    for i in range(n):
        # fibonacci-ish sphere distribution
        t = (i + 0.5) / n
        phi = math.acos(1 - 2 * t)
        th = math.pi * (1 + 5 ** 0.5) * i + rng.uniform(0, 0.6)
        x = math.sin(phi) * math.cos(th)
        y = math.sin(phi) * math.sin(th)
        z = math.cos(phi)
        s = 1.0 + rng.uniform(-rough, rough)
        px, py, pz = cx + x * radii[0] * s, cy + y * radii[1] * s, cz + z * radii[2] * s
        if flat_bottom and pz < 0:
            pz = 0.0
        pts.append((px, py, pz))
    return pts
