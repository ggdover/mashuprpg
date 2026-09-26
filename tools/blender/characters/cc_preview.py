"""Developer previews rendered in Blender (Workbench): contact sheets of animation frames with
held items attached like Godot's BoneAttachment3D (Copy Transforms at the bone HEAD).
Used by build_all.py --preview DIR; not part of the shipped assets.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector


def _join_new_objects(before, name):
	new = [o for o in bpy.context.scene.objects if o.name not in before and o.type == "MESH"]
	if not new:
		return None
	bpy.ops.object.select_all(action="DESELECT")
	for o in new:
		o.select_set(True)
	bpy.context.view_layer.objects.active = new[0]
	if len(new) > 1:
		bpy.ops.object.join()
	ob = bpy.context.view_layer.objects.active
	ob.name = name
	return ob


def attach(arm, builder, bone, name):
	"""Build an item next to the character and pin it to `bone` like Godot's BoneAttachment3D:
	origin at the bone head, the item's glTF +Y (Blender +Z) along the bone, i.e. the item sits
	under an Empty that copies the bone head transform, rotated by Rx(-90)."""
	before = {o.name for o in bpy.context.scene.objects}
	builder()
	ob = _join_new_objects(before, name)
	if ob is None:
		return None
	holder = bpy.data.objects.new(name + "_Holder", None)
	bpy.context.scene.collection.objects.link(holder)
	c = holder.constraints.new("COPY_TRANSFORMS")
	c.target = arm
	c.subtarget = bone
	c.head_tail = 0.0
	ob.parent = holder
	ob.matrix_parent_inverse = Matrix.Identity(4)
	ob.matrix_basis = Euler((math.radians(-90), 0, 0), "XYZ").to_matrix().to_4x4()
	return [ob, holder]


def _setup(size, cam_dist, target_z, yaw, elev, ortho):
	scn = bpy.context.scene
	scn.render.engine = "BLENDER_WORKBENCH"
	scn.display.shading.light = "STUDIO"
	scn.display.shading.color_type = "MATERIAL"
	scn.display.shading.show_shadows = True
	scn.display.shading.show_cavity = False
	scn.render.resolution_x = size
	scn.render.resolution_y = size
	scn.render.resolution_percentage = 100
	scn.render.film_transparent = False
	scn.render.image_settings.file_format = "PNG"
	scn.render.image_settings.color_mode = "RGBA"
	scn.view_settings.view_transform = "Standard"
	w = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
	w.color = (0.2, 0.21, 0.24)
	scn.world = w
	cam = bpy.data.cameras.new("PrevCam")
	cam.type = "ORTHO"
	cam.ortho_scale = ortho
	co = bpy.data.objects.new("PrevCam", cam)
	scn.collection.objects.link(co)
	scn.camera = co
	rot = Euler((math.radians(90 - elev), 0, math.radians(yaw)), "XYZ").to_matrix()
	fwd = rot @ Vector((0, 0, -1))
	co.matrix_world = Matrix.Translation(Vector((0, 0, target_z)) - fwd * cam_dist) @ rot.to_4x4()
	# floor
	me = bpy.data.meshes.new("PrevFloor")
	s = 3.0
	me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
	fl = bpy.data.objects.new("PrevFloor", me)
	m = bpy.data.materials.new("PrevFloorMat")
	m.diffuse_color = (0.3, 0.3, 0.32, 1)
	me.materials.append(m)
	scn.collection.objects.link(fl)
	return co, fl


def contact_sheet(arm, frames, out_png, size=300, yaw=-35.0, elev=12.0, ortho=None, cols=None, target_z=None):
	"""frames: list of (action_name, time_seconds). Renders each and tiles them into one PNG."""
	import numpy as np
	from cc_rig import FPS
	scn = bpy.context.scene
	h = max(v.co.z for o in scn.objects if o.type == "MESH" and o.parent == arm for v in o.data.vertices)
	if ortho is None:
		ortho = max(2.2, h * 1.35)
	if target_z is None:
		target_z = h * 0.5
	cam_ob, floor_ob = _setup(size, 10.0, target_z, yaw, elev, ortho)
	tmp = os.path.join(os.path.dirname(out_png), "_frame.png")
	tiles = []
	for fr in frames:
		act_name, t = fr[0], fr[1]
		if len(fr) > 2:
			rot = Euler((math.radians(90 - (fr[3] if len(fr) > 3 else elev)), 0, math.radians(fr[2])), "XYZ").to_matrix()
			fwd = rot @ Vector((0, 0, -1))
			tz = fr[5] if len(fr) > 5 else target_z
			cam_ob.data.ortho_scale = fr[4] if len(fr) > 4 else ortho
			cam_ob.matrix_world = Matrix.Translation(Vector((0, 0, tz)) - fwd * 10.0) @ rot.to_4x4()
		act = bpy.data.actions.get(act_name)
		arm.animation_data.action = act
		scn.frame_set(int(round(t * FPS)))
		scn.render.filepath = tmp
		bpy.ops.render.render(write_still=True)
		img = bpy.data.images.load(tmp, check_existing=False)
		px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
		bpy.data.images.remove(img)
		tiles.append(px)
	n = len(tiles)
	if cols is None:
		cols = min(n, 4)
	rows = (n + cols - 1) // cols
	sheet = np.zeros((rows * size, cols * size, 4), dtype=np.float32)
	for i, px in enumerate(tiles):
		r = rows - 1 - i // cols
		c = i % cols
		sheet[r * size:(r + 1) * size, c * size:(c + 1) * size] = px
	img = bpy.data.images.new("sheet", cols * size, rows * size, alpha=True)
	img.pixels[:] = sheet.ravel().tolist()
	img.filepath_raw = out_png
	img.file_format = "PNG"
	img.save()
	if os.path.exists(tmp):
		os.remove(tmp)
	bpy.data.images.remove(img)
	bpy.data.objects.remove(cam_ob)
	bpy.data.objects.remove(floor_ob)
	arm.animation_data.action = None
