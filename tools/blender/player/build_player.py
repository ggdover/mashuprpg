"""Build the player models (docs/ARCHITECTURE.md §14): one skinned glb per look, each with the base
body, the default outfit, every gear piece and the animation set.

  blender --background --factory-startup --python tools/blender/player/build_player.py -- \\
      [--only f,m1,m2] [--no-export] [--preview DIR] [--no-anims] [--anims MODULE]
      [--families str,dex,int|none] [--gear SPEC ...]
--anims picks the animation module (default pl_anim; it provides build_actions(arm, L) -> names and
optionally preview(arm, L, out_dir)).
--gear adds turnaround previews with gear on: SPEC = "str1" (every str tier-1 piece), "dex2", or
"helm:str:2+chest:dex:1" (single pieces joined with +). Repeat --gear for several previews.

Outputs assets/models/char_player_<look>.glb (and char_player.glb = the "m1" look, the default
stand-in used by tools and demos) and data/player_gear.json (every gear piece: slot, family, tier,
hidden base parts). PL_OUT_DIR=<dir> writes them to <dir> instead (dry runs).
"""
import os
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

import bpy  # noqa: E402

import pl_rig  # noqa: E402  (sets up sys.path for the characters' modules too)
import pl_mesh  # noqa: E402
import pl_body  # noqa: E402
import pl_preview  # noqa: E402
import pl_gear  # noqa: E402
import importlib  # noqa: E402
import json  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
# PL_OUT_DIR=<dir> writes the glbs and player_gear.json there instead (dry runs).
OUT_DIR = os.environ.get("PL_OUT_DIR", "")
MODEL_DIR = OUT_DIR or os.path.join(REPO, "assets", "models")
DATA_DIR = OUT_DIR or os.path.join(REPO, "data")
LOOK_IDS = ("f", "m1", "m2")
ASSET_ID = {"f": "char_player_f", "m1": "char_player_m1", "m2": "char_player_m2"}


def fresh():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scn = bpy.context.scene
	scn.render.fps = 30
	scn.render.fps_base = 1.0
	scn.frame_start = 0


def build_look(look, opts):
	fresh()
	L = pl_body.Look(look)
	L.build_skin()
	L.build_hair()
	L.build_outfit()
	base_parts = list(L.parts)
	reg = pl_gear.Registry()
	fams = pl_gear.build_all(L, reg, opts["families"])
	arm = pl_rig.create_armature(L.J)
	obs = {part.name: pl_mesh.build(part, arm, L.J["s"]) for part in L.parts.values()}
	base_tris = sum(L.parts[n].tri_count() for n in base_parts)
	gear_info = ", ".join("%s %d" % (n, L.parts[n].tri_count()) for n in reg.pieces if n in L.parts)
	info = ", ".join("%s %d" % (n, L.parts[n].tri_count()) for n in base_parts)
	opts.setdefault("_regs", {})[look] = reg
	actions = []
	if not opts["no_anims"]:
		amod = importlib.import_module(opts["anims"])
		actions = list(amod.build_actions(arm, L))
		arm.animation_data.action = None
		import cc_rig
		cc_rig.reset_pose(arm)
	if opts["preview"]:
		os.makedirs(opts["preview"], exist_ok=True)
		pl_preview.stand_action(arm, look)
		_show(obs, pl_gear.visible_parts(list(obs), {}, reg))
		pl_preview.turnaround(arm, os.path.join(opts["preview"], "%s_turnaround.png" % look), action="stand")
		hz = L.J["head_z"] * L.J["s"]
		pl_preview.closeup(arm, os.path.join(opts["preview"], "%s_head.png" % look), hz + 0.08, ortho=0.55, action="stand")
		for spec in opts["gear"]:
			eq = _parse_gear(spec)
			vis = pl_gear.visible_parts(list(obs), eq, reg)
			_show(obs, vis)
			tag = spec.replace(":", "").replace("+", "_")
			pl_preview.turnaround(arm, os.path.join(opts["preview"], "%s_gear_%s.png" % (look, tag)), action="stand")
			pl_preview.closeup(arm, os.path.join(opts["preview"], "%s_gear_%s_head.png" % (look, tag)), hz + 0.02, ortho=0.75,
				action="stand")
			tris_vis = sum(L.parts[n].tri_count() for n in vis)
			print("[player] %s gear %s: %d tris visible" % (look, spec, tris_vis))
		_show(obs, list(obs))
		if actions and hasattr(amod, "preview"):
			amod.preview(arm, L, opts["preview"])
		stand = bpy.data.actions.get("stand")
		if stand is not None:
			bpy.data.actions.remove(stand)
		arm.animation_data.action = None
	if not opts["no_export"]:
		validate(look, arm, L, reg, actions)
		# Gear pieces start hidden in Godot (glTF extras -> node meta, Assets.model hides them).
		for name in reg.pieces:
			obs[name]["hidden"] = 1
		export(ASSET_ID[look])
		if look == "m1":
			export("char_player")
		with open(os.path.join(DATA_DIR, "player_gear.json"), "w") as f:
			f.write(reg.to_json())
	return "%s: base %d tris (%s); gear %s: %s" % (look, base_tris, info, ",".join(fams) or "-", gear_info or "-")


## Triangle budgets per gear piece (pl_gear docs); over budget warns, over 1.25x fails the build.
PIECE_BUDGET = {"helm": 400, "chest": 2200, "gloves": 350, "boots": 550}


def validate(look, arm, L, reg, actions):
	for name, info in reg.pieces.items():
		if name not in L.parts:
			raise RuntimeError("%s: registered piece %s has no geometry" % (look, name))
		tris = L.parts[name].tri_count()
		budget = PIECE_BUDGET[info["slot"]]
		if tris > budget * 1.25:
			raise RuntimeError("%s: %s has %d tris (budget %d)" % (look, name, tris, budget))
		if tris > budget:
			print("[player] WARNING %s: %s has %d tris (budget %d)" % (look, name, tris, budget))
		if not any(m.name.startswith("tint_") for m in L.parts[name].mats):
			raise RuntimeError("%s: %s has no tint_ material" % (look, name))
	for o in bpy.data.objects:
		if "." in o.name:
			raise RuntimeError("%s: suffixed object name %s" % (look, o.name))
	for b in pl_rig.BONE_NAMES:
		if b not in arm.data.bones:
			raise RuntimeError("%s: missing bone %s" % (look, b))
	for p in ("Head", "HairTop", "Body", "Hands", "Outfit_Top", "Outfit_Legs", "Outfit_Feet"):
		if p not in L.parts:
			raise RuntimeError("%s: missing part %s" % (look, p))
	names = sorted(a.name for a in bpy.data.actions)
	if sorted(actions) != names:
		raise RuntimeError("%s: actions %s != %s" % (look, names, sorted(actions)))


def export(asset_id):
	tmp_dir = os.path.join(MODEL_DIR, ".tmp")
	os.makedirs(tmp_dir, exist_ok=True)
	tmp = os.path.join(tmp_dir, asset_id + ".glb")
	bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", export_apply=True, export_yup=True,
		export_animation_mode="ACTIONS", export_def_bones=False, export_anim_slide_to_zero=True,
		export_cameras=False, export_lights=False, export_extras=True)
	os.replace(tmp, os.path.join(MODEL_DIR, asset_id + ".glb"))


def _show(obs, names):
	for n, ob in obs.items():
		ob.hide_render = n not in names
		ob.hide_viewport = n not in names


def _parse_gear(spec):
	""""str1" -> every str tier-1 slot; "helm:str:2+chest:dex:1" -> those pieces."""
	eq = {}
	if ":" not in spec:
		fam, tier = spec[:-1], int(spec[-1])
		for slot in pl_gear.SLOTS:
			eq[slot] = (fam, tier)
		return eq
	for item in spec.split("+"):
		slot, fam, tier = item.split(":")
		eq[slot] = (fam, int(tier))
	return eq


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	opts = {"only": list(LOOK_IDS), "no_export": False, "preview": "", "no_anims": False, "anims": "pl_anim",
		"families": list(pl_gear.FAMILIES), "gear": []}
	i = 0
	while i < len(argv):
		a = argv[i]
		if a == "--only":
			i += 1
			opts["only"] = [x for x in argv[i].split(",") if x]
		elif a == "--no-export":
			opts["no_export"] = True
		elif a == "--no-anims":
			opts["no_anims"] = True
		elif a == "--anims":
			i += 1
			opts["anims"] = argv[i]
		elif a == "--preview":
			i += 1
			opts["preview"] = os.path.abspath(argv[i])
		elif a == "--families":
			i += 1
			opts["families"] = [x for x in argv[i].split(",") if x]
		elif a == "--gear":
			i += 1
			opts["gear"].append(argv[i])
		else:
			raise SystemExit("unknown argument: %s" % a)
		i += 1
	return opts


def main():
	opts = parse_args()
	t0 = time.time()
	failed = []
	for look in opts["only"]:
		t = time.time()
		try:
			msg = build_look(look, opts)
			print("[player] %s (%.1fs)" % (msg, time.time() - t))
		except Exception as e:
			import traceback
			traceback.print_exc()
			failed.append(look)
			print("[player] FAILED %s: %s" % (look, e))
	print("[player] done in %.1fs, failed: %s" % (time.time() - t0, failed))
	if failed:
		sys.exit(1)


if __name__ == "__main__":
	main()
