"""Build every assets-characters model (+ item icons).

  blender --background --factory-startup --python tools/blender/characters/build_all.py -- [--only id,id,...]
      [--no-icons] [--no-export] [--preview DIR]

  --only       comma separated ids (or the groups 'chars', 'items', 'weapons', 'icons'); default: all
  --no-icons   skip item icon rendering
  --no-export  build + validate only (with --preview: dev iteration without touching assets/)
  --preview    also render developer contact sheets (Workbench) of every animation into DIR

Outputs (atomic: written to a .tmp/ dir, then os.replace'd into place):
  assets/models/<id>.glb           characters, weapons, off-hands, helmets, ground items
  assets/icons/items/<id>.png      128x128 icons for every item model id
Each model is built in a fresh file (read_factory_settings), with fixed seeds, identity transforms.
"""
import os
import sys
import time

sys.dont_write_bytecode = True   # keep tools/blender/characters free of __pycache__
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

import bpy  # noqa: E402

import cc_anim  # noqa: E402
import cc_chars  # noqa: E402
import cc_ground  # noqa: E402
import cc_items  # noqa: E402
import cc_rig  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MODEL_DIR = os.path.join(REPO, "assets", "models")
ICON_DIR = os.path.join(REPO, "assets", "icons", "items")

PLAYER_PARTS = ["Head", "Torso", "Arms", "Hands", "Legs", "Feet"]
TRI_BUDGET_CHAR = 3000
TRI_BUDGET_WEAPON = 800


def fresh():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scn = bpy.context.scene
	scn.render.fps = cc_rig.FPS
	scn.render.fps_base = 1.0
	scn.frame_start = 0


def tri_count(ob):
	return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def check_identity(ob):
	M = ob.matrix_world
	for i in range(4):
		for j in range(4):
			if abs(M[i][j] - (1.0 if i == j else 0.0)) > 1e-6:
				raise RuntimeError("%s: object transform is not identity" % ob.name)


def export(asset_id):
	tmp_dir = os.path.join(MODEL_DIR, ".tmp")
	os.makedirs(tmp_dir, exist_ok=True)
	tmp = os.path.join(tmp_dir, asset_id + ".glb")
	bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", export_apply=True, export_yup=True,
		export_animation_mode="ACTIONS", export_def_bones=False, export_anim_slide_to_zero=True,
		export_cameras=False, export_lights=False)
	os.replace(tmp, os.path.join(MODEL_DIR, asset_id + ".glb"))


def validate_character(cid, anims):
	names = sorted(a.name for a in bpy.data.actions)
	if names != sorted(anims):
		raise RuntimeError("%s: actions %s != %s" % (cid, names, sorted(anims)))
	obs = {o.name: o for o in bpy.data.objects}
	if "Armature" not in obs:
		raise RuntimeError("%s: no object named Armature" % cid)
	for o in bpy.data.objects:
		if "." in o.name:
			raise RuntimeError("%s: suffixed object name %s" % (cid, o.name))
		check_identity(o)
	arm = obs["Armature"]
	for b in cc_rig.BONE_NAMES:
		if b not in arm.data.bones:
			raise RuntimeError("%s: missing bone %s" % (cid, b))
	if cid == "char_player":
		for p in PLAYER_PARTS:
			if p not in obs:
				raise RuntimeError("char_player: missing part %s" % p)
			if not any(s.material and s.material.name.startswith("tint_") for s in obs[p].material_slots):
				raise RuntimeError("char_player: part %s has no tint_ material" % p)
	tris = sum(tri_count(o) for o in bpy.data.objects if o.type == "MESH")
	if tris > TRI_BUDGET_CHAR:
		raise RuntimeError("%s: %d tris > budget %d" % (cid, tris, TRI_BUDGET_CHAR))
	return tris


def validate_item(iid):
	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	if not meshes:
		raise RuntimeError("%s: no mesh" % iid)
	for o in bpy.data.objects:
		if "." in o.name:
			raise RuntimeError("%s: suffixed object name %s" % (iid, o.name))
		check_identity(o)
	if not any(s.material and s.material.name.startswith("tint_") for o in meshes for s in o.material_slots):
		raise RuntimeError("%s: no tint_ material" % iid)
	tris = sum(tri_count(o) for o in meshes)
	if iid.startswith("weapon_") and tris > TRI_BUDGET_WEAPON:
		raise RuntimeError("%s: %d tris > budget %d" % (iid, tris, TRI_BUDGET_WEAPON))
	return tris


# Held items used by the developer previews, per animation.
PREVIEW_HELD = {
	"shoot_bow": ("weapon_bow", "offhand_quiver"),
	"shoot_crossbow": ("weapon_crossbow", "offhand_quiver"),
	"cast": ("weapon_wand", "offhand_focus"),
	"cast_area": ("weapon_staff", None),
	"attack_slam": ("weapon_maul", None),
	"attack_stab": ("weapon_dagger", "offhand_shield"),
	"channel": ("weapon_greatsword", None),
}


def preview_character(cid, arm, anims, out_dir):
	import cc_preview
	os.makedirs(out_dir, exist_ok=True)
	holds = cid in ("char_player", "char_skeleton")
	groups = {}
	for a in anims:
		held = PREVIEW_HELD.get(a, ("weapon_sword", "offhand_shield")) if holds else (None, None)
		groups.setdefault(held, []).append(a)
	for (main, off), group in groups.items():
		fresh_objs = []
		if main:
			fresh_objs.append(cc_preview.attach(arm, cc_items.ITEMS[main], "grip_r", "PrevMain"))
		if off:
			bone = "chest" if off == "offhand_quiver" else "grip_l"
			fresh_objs.append(cc_preview.attach(arm, cc_items.ITEMS[off], bone, "PrevOff"))
		if "idle" in group:
			views = [("idle", 0.0, y) for y in (0, -45, -90, 180)] + [("idle", 0.0, -30, 56)]
			cc_preview.contact_sheet(arm, views, os.path.join(out_dir, "%s_views.png" % cid), size=360, cols=5)
			hz = arm.data.bones["head"].head_local.z
			hh = arm.data.bones["head"].length
			por = [("idle", 0.0, y, 8, hh * 3.2, hz + hh * 0.35) for y in (0, -40, -110)]
			por.append(("idle", 0.0, -30, 8, hz * 0.62, hz * 0.62))
			cc_preview.contact_sheet(arm, por, os.path.join(out_dir, "%s_portrait.png" % cid), size=360, cols=4)
		for a in group:
			d = bpy.data.actions[a].frame_range[1] / cc_rig.FPS
			ts = [d * f for f in (0.0, 0.15, 0.3, 0.45, 0.6, 0.8)]
			if a in cc_anim.HIT_FRAME:
				hf = cc_anim.HIT_FRAME[a] * d
				ts = sorted(set([0.0, d * 0.25, hf * 0.8, hf, hf + d * 0.12, d * 0.8]))
			frames = [(a, t, -35.0, 12.0) for t in ts] + [(a, t, -60.0, 56.0) for t in ts]
			cc_preview.contact_sheet(arm, frames, os.path.join(out_dir, "%s_%s.png" % (cid, a)), cols=len(ts), size=220)
			_report_grips(arm, a, ts)
		for pair in fresh_objs:
			for o in pair or []:
				bpy.data.objects.remove(o)


def _report_grips(arm, a, ts):
	"""Print the grip_r blade direction (right, forward, up) at each preview time."""
	scn = bpy.context.scene
	arm.animation_data.action = bpy.data.actions.get(a)
	out = []
	for t in ts:
		scn.frame_set(int(round(t * cc_rig.FPS)))
		m = arm.pose.bones["grip_r"].matrix
		y = m.col[1]
		p = m.col[3]
		q = arm.pose.bones["grip_l"].matrix.col[3]
		out.append("%.2f:R dir(r%+.2f f%+.2f u%+.2f) pos(r%+.2f f%+.2f u%.2f) L pos(r%+.2f f%+.2f u%.2f)" % (
			t, -y.x, -y.y, y.z, -p.x, -p.y, p.z, -q.x, -q.y, q.z))
	arm.animation_data.action = None
	print("[grip] %s" % a)
	for o in out:
		print("[grip]    " + o)


LOOPS = ("idle", "run", "channel")
NO_GROUND = ("die", "dodge")   # these handle the floor themselves (cc_anim.die / dodge)


def _item_vertices(iid):
	"""Vertices (item space) of an item model, built temporarily into the current file and removed
	again (reference geometry for held-weapon floor contact)."""
	before_obs = set(bpy.data.objects)
	before_me = set(bpy.data.meshes)
	before_ma = set(bpy.data.materials)
	cc_items.ITEMS[iid]()
	verts = []
	for o in set(bpy.data.objects) - before_obs:
		if o.type == "MESH":
			verts.extend(o.matrix_world @ v.co for v in o.data.vertices)
		bpy.data.objects.remove(o)
	for m in set(bpy.data.meshes) - before_me:
		bpy.data.meshes.remove(m)
	for m in set(bpy.data.materials) - before_ma:
		bpy.data.materials.remove(m)
	return verts


def build_character(cid, opts):
	fresh()
	arm, style, anims = cc_chars.CHARACTERS[cid]()
	skin = cc_ground.Skin(arm)
	hover = style.get("hover", 0.0) > 0.0
	has_feet = any(True for _ in skin.select(bones=cc_ground.FEET))
	style["arm"] = arm
	style["skin"] = skin
	style["rig"] = cc_ground.RigInfo(arm, skin) if has_feet and not hover else None
	if style.get("weapon") and "Weapon" not in skin.parts and "attack_slam" in anims:
		style["slam_held"] = _item_vertices("weapon_maul")
	notes = []
	for name in anims:
		keys = cc_anim.BUILDERS[name](style)
		act = cc_rig.key_action(arm, name, keys)
		if name in NO_GROUND:
			# cc_anim placed these keys on the floor; keep the in-betweens above it too.
			lo, hi = cc_ground.bake_ground(arm, act, skin, bones=None, lift_only=True)
			if hi > 0.002:
				notes.append("%s lifted up to %.3f between keys" % (name, hi))
		elif not hover and has_feet:
			lo, hi = cc_ground.bake_ground(arm, act, skin, loop=name in LOOPS, soft=0.045 if name == "run" else 0.0)
			if max(abs(lo), abs(hi)) > 0.05:
				notes.append("%s snap %.3f..%.3f" % (name, lo, hi))
	arm.animation_data.action = None
	cc_rig.reset_pose(arm)
	_report_character(cid, arm, style, skin, anims, hover, has_feet, notes)
	tris = validate_character(cid, anims)
	if not opts["no_export"]:
		export(cid)
	if opts["preview"]:
		preview_character(cid, arm, anims, opts["preview"])
	return "%s: %d tris, %d parts, %d actions" % (cid, tris, len([o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]), len(anims))


def _report_character(cid, arm, style, skin, anims, hover, has_feet, notes):
	"""Print the ground-contact / run-speed / pose numbers the probe also asserts (in Godot)."""
	parts = sorted({o.name for o in arm.children if o.type == "MESH"})
	print("[chars] %s parts=%s" % (cid, ",".join(parts)))
	if has_feet and not hover and "run" in anims:
		rs = cc_ground.run_speed(arm, bpy.data.actions["run"])
		print("[chars] %s run %.3fs planted-foot speed r %.2f l %.2f m/s (ref %.1f)" % (
			cid, bpy.data.actions["run"].frame_range[1] / cc_rig.FPS, rs["r"][0], rs["l"][0], cc_ground.REF_RUN_SPEED))
	if has_feet and not hover:
		worst = (0.0, "")
		for a in anims:
			if a in NO_GROUND:
				continue
			lo, hi = cc_ground.contact_range(arm, bpy.data.actions[a], skin)
			for v in (lo, hi):
				if abs(v) > abs(worst[0]):
					worst = (v, a)
		print("[chars] %s feet contact worst %.3f m (%s)" % (cid, worst[0], worst[1] or "-"))
	if "die" in anims:
		G = cc_ground.action_G(arm, bpy.data.actions["die"], bpy.data.actions["die"].frame_range[1] / cc_rig.FPS)
		core = skin.lowest(G, bones=cc_ground.CORE)
		allv = skin.lowest(G)
		msg = "[chars] %s die end: lowest %.3f core %.3f" % (cid, allv, core)
		if "Weapon" in skin.parts:
			w = skin.posed(G, parts=("Weapon",))
			msg += " weapon z %.3f..%.3f" % (min(v.z for v in w), max(v.z for v in w))
		print(msg)
	if style.get("slam_floor") or style.get("slam_held"):
		act = bpy.data.actions["attack_slam"]
		t = cc_anim.HIT_FRAME["attack_slam"] * act.frame_range[1] / cc_rig.FPS
		G = cc_ground.action_G(arm, act, t)
		st = dict(style)

		def wlow(Gx):
			return skin.lowest(Gx, parts=("Weapon",)) if style.get("slam_floor") else cc_anim._held_lowest(st, Gx)
		lows = [wlow(cc_ground.action_G(arm, act, f / cc_rig.FPS)) for f in range(13, 19)]  # impact .. hold
		print("[chars] %s attack_slam hit %.2fs %s lowest %.3f feet %.3f; frames 13-18: %s" % (cid, t,
			"weapon" if style.get("slam_floor") else "held weapon_maul", wlow(G), skin.lowest(G, bones=cc_ground.FEET),
			" ".join("%.3f" % v for v in lows)))
	for n in notes:
		print("[chars] %s %s" % (cid, n))


def build_item(iid, opts):
	fresh()
	hints = cc_items.ITEMS[iid]() or {}
	tris = validate_item(iid)
	if not opts["no_export"]:
		export(iid)
	if not opts["no_icons"]:
		import cc_icons
		out_dir = ICON_DIR if not opts["no_export"] else os.path.join(opts["preview"] or "/tmp", "icons")
		os.makedirs(out_dir, exist_ok=True)
		cc_icons.render_icon(iid, hints, out_dir)
	return "%s: %d tris" % (iid, tris)


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	opts = {"only": [], "no_icons": False, "no_export": False, "preview": ""}
	i = 0
	while i < len(argv):
		a = argv[i]
		if a == "--only":
			i += 1
			opts["only"] = [x.strip() for x in argv[i].split(",") if x.strip()]
		elif a.startswith("--only="):
			opts["only"] = [x.strip() for x in a[7:].split(",") if x.strip()]
		elif a == "--no-icons":
			opts["no_icons"] = True
		elif a == "--no-export":
			opts["no_export"] = True
		elif a == "--preview":
			i += 1
			opts["preview"] = os.path.abspath(argv[i])
		elif a.startswith("--preview="):
			opts["preview"] = os.path.abspath(a[10:])
		else:
			raise SystemExit("unknown argument: %s" % a)
		i += 1
	return opts


def main():
	opts = parse_args()
	all_ids = list(cc_chars.CHARACTERS) + list(cc_items.ITEMS)
	ids = []
	for x in opts["only"] or all_ids:
		if x == "chars":
			ids += list(cc_chars.CHARACTERS)
		elif x in ("items", "icons"):
			ids += list(cc_items.ITEMS)
		elif x == "weapons":
			ids += [i for i in cc_items.ITEMS if i.startswith("weapon_")]
		elif x in all_ids:
			ids.append(x)
		else:
			raise SystemExit("unknown id: %s" % x)
	os.makedirs(MODEL_DIR, exist_ok=True)
	os.makedirs(ICON_DIR, exist_ok=True)
	t0 = time.time()
	failed = []
	for aid in ids:
		t = time.time()
		try:
			if aid in cc_chars.CHARACTERS:
				msg = build_character(aid, opts)
			else:
				msg = build_item(aid, opts)
			print("[build] %s (%.1fs)" % (msg, time.time() - t))
		except Exception as e:  # keep building the others, report at the end
			import traceback
			traceback.print_exc()
			failed.append(aid)
			print("[build] FAILED %s: %s" % (aid, e))
	# The icon tmp dir is ours alone: remove it when empty (assets/models/.tmp is shared with other modules).
	try:
		os.rmdir(os.path.join(ICON_DIR, ".tmp"))
	except OSError:
		pass
	print("[build] done: %d built, %d failed %s in %.1fs" % (len(ids) - len(failed), len(failed), failed, time.time() - t0))
	if failed:
		sys.exit(1)


if __name__ == "__main__":
	main()
