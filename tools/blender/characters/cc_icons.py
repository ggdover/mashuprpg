"""Item icon rendering (docs/ARCHITECTURE.md §14.4): 128x128 transparent PNG, EEVEE, orthographic
3/4 camera + sun, Standard view transform, rendered after the model export (the icon pass may
recolour tint_* materials to a representative look; the exported glb is already written).
A 1 px dark outline is added around the silhouette so icons stay readable at 48 px.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

from cc_mesh import lin

SIZE = 128


def _world(strength=0.55, color=(0.42, 0.42, 0.46)):
	w = bpy.data.worlds.new("IconWorld")
	bpy.context.scene.world = w
	bg = w.node_tree.nodes.get("Background")
	if bg is not None:
		bg.inputs["Color"].default_value = (color[0], color[1], color[2], 1.0)
		bg.inputs["Strength"].default_value = strength
	return w


def _sun(name, rot, energy, color=(1.0, 1.0, 1.0)):
	ld = bpy.data.lights.new(name, "SUN")
	ld.energy = energy
	ld.color = color
	ld.angle = math.radians(8)
	ob = bpy.data.objects.new(name, ld)
	bpy.context.scene.collection.objects.link(ob)
	ob.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
	return ob


def _mesh_points(objs):
	pts = []
	dg = bpy.context.evaluated_depsgraph_get()
	for o in objs:
		ev = o.evaluated_get(dg)
		me = ev.to_mesh()
		mw = o.matrix_world
		for v in me.vertices:
			pts.append(mw @ v.co)
		ev.to_mesh_clear()
	return pts


def setup_scene(size=SIZE):
	scn = bpy.context.scene
	scn.render.engine = "BLENDER_EEVEE"
	scn.render.resolution_x = size
	scn.render.resolution_y = size
	scn.render.resolution_percentage = 100
	scn.render.film_transparent = True
	scn.render.image_settings.file_format = "PNG"
	scn.render.image_settings.color_mode = "RGBA"
	scn.view_settings.view_transform = "Standard"
	scn.view_settings.look = "None"
	# No date/time/render-time metadata in the PNG, so rebuilding gives byte-identical icons.
	for flag in ("use_stamp_date", "use_stamp_time", "use_stamp_render_time", "use_stamp_frame", "use_stamp_frame_range",
			"use_stamp_memory", "use_stamp_hostname", "use_stamp_camera", "use_stamp_lens", "use_stamp_scene",
			"use_stamp_marker", "use_stamp_filename", "use_stamp_sequencer_strip", "use_stamp_note"):
		if hasattr(scn.render, flag):
			setattr(scn.render, flag, False)
	try:
		scn.eevee.taa_render_samples = 32
	except AttributeError:
		pass
	_world()
	_sun("IconKey", (50, 10, -35), 3.2, (1.0, 0.96, 0.9))
	_sun("IconFill", (70, 0, 150), 1.0, (0.8, 0.85, 1.0))
	_sun("IconRim", (-60, 0, 20), 1.2, (1.0, 1.0, 1.0))


def frame_camera(objs, elev=18.0, yaw=24.0, margin=1.1, size=SIZE, zmin=None, pivot=None):
	"""Orthographic camera looking from the front (-Y) rotated by yaw (to the right) and elev."""
	scn = bpy.context.scene
	cam = bpy.data.cameras.new("IconCam")
	cam.type = "ORTHO"
	co = bpy.data.objects.new("IconCam", cam)
	scn.collection.objects.link(co)
	scn.camera = co
	# Camera rotation: default camera looks down -Z; rotate to look along +Y (from -Y), then orbit.
	rot = Euler((math.radians(90 - elev), 0.0, math.radians(yaw)), "XYZ").to_matrix()
	fwd = rot @ Vector((0, 0, -1))
	right = rot @ Vector((1, 0, 0))
	up = rot @ Vector((0, 1, 0))
	bpy.context.view_layer.update()
	pts = _mesh_points(objs)
	if zmin is not None and pivot is not None:
		# Frame only the part of the model above local z = zmin (long weapons: show the business end).
		inv = pivot.matrix_world.inverted()
		kept = [p for p in pts if (inv @ p).z >= zmin]
		pts = kept or pts
	xs = [p.dot(right) for p in pts]
	ys = [p.dot(up) for p in pts]
	zs = [p.dot(fwd) for p in pts]
	cx = (min(xs) + max(xs)) / 2.0
	cy = (min(ys) + max(ys)) / 2.0
	ext = max(max(xs) - min(xs), max(ys) - min(ys))
	cam.ortho_scale = ext * margin
	center = right * cx + up * cy + fwd * min(zs)
	co.matrix_world = Matrix.Translation(center - fwd * 5.0) @ rot.to_4x4()
	cam.clip_start = 0.01
	cam.clip_end = 20.0
	return co


def outline(path, color=(0.05, 0.035, 0.025), strength=0.85):
	"""Add a 1 px dark outline and a faint drop shadow around the alpha silhouette (numpy)."""
	import numpy as np
	img = bpy.data.images.load(path, check_existing=False)
	w, h = img.size
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
	a = px[:, :, 3]
	solid = a > 0.35
	def shift(mask, dy, dx):
		# Shift without wrap-around (np.roll would bleed cut-off edges onto the opposite side).
		out = np.zeros_like(mask)
		ys = slice(max(dy, 0), h + min(dy, 0))
		yd = slice(max(-dy, 0), h + min(-dy, 0))
		xs = slice(max(dx, 0), w + min(dx, 0))
		xd = slice(max(-dx, 0), w + min(-dx, 0))
		out[ys, xs] = mask[yd, xd]
		return out
	dil = solid.copy()
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			dil |= shift(solid, dy, dx)
	ring = dil & ~solid
	# Drop shadow: silhouette shifted down-right by 2 px (image rows go bottom->top in Blender).
	sh = shift(dil, -2, 2) & ~dil
	out = px.copy()
	for mask, alpha in ((sh, 0.35), (ring, strength)):
		na = alpha * (1.0 - a[mask])
		tot = a[mask] + na
		for ch in range(3):
			out[:, :, ch][mask] = (px[:, :, ch][mask] * a[mask] + color[ch] * na) / np.maximum(tot, 1e-6)
		out[:, :, 3][mask] = tot
	img.pixels[:] = out.ravel().tolist()
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()
	bpy.data.images.remove(img)


def render_icon(item_id, hints, out_dir):
	"""Render assets/icons/items/<id>.png atomically (tmp + os.replace)."""
	objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	for mname, col in (hints.get("icon_tints") or {}).items():
		m = bpy.data.materials.get(mname)
		if m is not None:
			c = lin(col)
			b = m.node_tree.nodes.get("Principled BSDF")
			b.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
	pivot = bpy.data.objects.new("IconPivot", None)
	bpy.context.scene.collection.objects.link(pivot)
	for o in objs:
		o.parent = pivot
	# Emission is tuned for Godot's glow; tone it down so glowing parts keep their colour in the icon.
	for m in bpy.data.materials:
		b = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
		if b is not None and b.inputs["Emission Strength"].default_value > 0.0:
			b.inputs["Emission Strength"].default_value = min(1.2, b.inputs["Emission Strength"].default_value * 0.3)
	rx, ry, rz = hints.get("icon_rot", (0, 0, 0))
	M = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix().to_4x4()
	if hints.get("diag"):
		# Long weapons: show the side (+X) to the camera (or diag_spin), tip toward the upper right,
		# thickened across the shaft (icon_fat) so thin hafts stay readable at 48 px.
		fat = hints.get("icon_fat", 1.0)
		spin = hints.get("diag_spin", -90.0)
		M = (Euler((0, math.radians(45), 0), "XYZ").to_matrix().to_4x4()
			@ Euler((0, 0, math.radians(spin)), "XYZ").to_matrix().to_4x4() @ M
			@ Matrix.Diagonal((fat, fat, 1.0, 1.0)))
	pivot.matrix_world = M
	setup_scene()
	frame_camera(objs, elev=hints.get("icon_elev", 16.0), yaw=hints.get("icon_yaw", 22.0 if not hints.get("diag") else 12.0),
		margin=hints.get("icon_margin", 1.12), zmin=hints.get("icon_zmin"), pivot=pivot)
	tmp_dir = os.path.join(out_dir, ".tmp")
	os.makedirs(tmp_dir, exist_ok=True)
	tmp = os.path.join(tmp_dir, item_id + ".png")
	bpy.context.scene.render.filepath = tmp
	bpy.ops.render.render(write_still=True)
	outline(tmp)
	os.replace(tmp, os.path.join(out_dir, item_id + ".png"))
