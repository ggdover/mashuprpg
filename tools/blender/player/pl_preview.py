"""Developer previews of the player (tools/blender/player): turnaround sheets like the reference
art (front, 3/4 front left, left side, back, 3/4 front right) and animation contact sheets, with
held items pinned to bones like Godot's BoneAttachment3D. Not part of the shipped assets."""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

import cc_preview
from cc_rig import add, key_action, pose

VIEWS = [("front", 0.0), ("3/4 front left", 45.0), ("left side", 90.0), ("back", 180.0), ("3/4 front right", -45.0)]


def _light_setup():
	scn = bpy.context.scene
	scn.render.engine = "BLENDER_WORKBENCH"
	sh = scn.display.shading
	sh.light = "STUDIO"
	sh.color_type = "MATERIAL"
	sh.show_shadows = False
	sh.show_cavity = True
	sh.cavity_type = "WORLD"
	sh.show_backface_culling = True   # double-sided cloth would z-fight otherwise (Godot culls too)


def turnaround(arm, out_png, action=None, t=0.0, size=420, elev=6.0, height=None):
	"""Five views of the (posed) character side by side."""
	frames = []
	scn = bpy.context.scene
	h = height or max(v.co.z for o in scn.objects if o.type == "MESH" and o.parent == arm for v in o.data.vertices)
	for _name, yaw in VIEWS:
		frames.append((action or "", t, yaw, elev, h * 1.12, h * 0.5))
	_light_setup()
	cc_preview.contact_sheet(arm, frames, out_png, size=size, cols=len(frames))
	return out_png


def closeup(arm, out_png, z, ortho=0.5, size=420, views=((0.0, 4.0), (40.0, 4.0), (90.0, 4.0), (180.0, 4.0)), action=""):
	"""Head / detail close-ups: views (yaw, elev) around height z (posed by `action` at t 0)."""
	frames = [(action, 0.0, yaw, elev, ortho, z) for yaw, elev in views]
	_light_setup()
	cc_preview.contact_sheet(arm, frames, out_png, size=size, cols=len(frames))
	return out_png


def stance(look):
	"""The relaxed standing pose (no weapon) used by the turnarounds: arms down along the body, a
	slight contrapposto for the female exile."""
	p = pose(upper_arm_s=(3, -2, 0), lower_arm_s=(24, 0, 0), hand_s=(4, 0, 0), clavicle_s=(0, -2, 0),
		upper_leg_s=(-2, 2, 0), lower_leg_s=(3, 0, 0), foot_s=(-1, -2, 0))
	if look == "f":
		p = add(p, pose(hips=(0, 3, 2), spine=(0, -2, -1), chest=(0, -1.5, 0), head=(-2, 2, 0),
			upper_leg_r=(-1, 0, 0), upper_leg_l=(-4, -3, 0), lower_leg_l=(7, 0, 0)))
	return p


def stand_action(arm, look):
	"""A one-frame "stand" action (previews only; removed before export)."""
	return key_action(arm, "stand", [(0.0, stance(look)), (1.0 / 30.0, stance(look))])
