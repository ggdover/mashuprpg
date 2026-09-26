"""Build every environment asset: dungeon kit + props (env_*), town set (town_*), projectiles
(proj_*) and the skill icons (assets/icons/skills/<skill_id>.png).

    blender --background --factory-startup --python tools/blender/environment/build_all.py -- [options]

Options (after "--"):
    --only a,b,...   build only these. Tokens: a model id (env_wall_a), a skill id (fireball) or
                     icon:<skill_id>, a glob (env_floor_*), or a group: all, models, icons, env,
                     kit (floors/walls/pillar), props, town, proj.
    --list           print the ids and exit.
    --check          after building each model, ray-cast it for back-face first hits (models
                     are exported with backface culling, so any visible back face is a hole) and,
                     when the kit is built, check that no see-through slit exists at the base of a
                     wall standing between floor tiles (facecheck.py). Failures fail the build.
    --no-export      build (and check) without writing any file.

Each model is built in a fresh empty file (read_factory_settings) and exported atomically
(assets/models/.tmp/<id>.glb -> os.replace). Deterministic (fixed seeds).
OWNER: assets-environment.
"""

import fnmatch
import os
import sys
import time
import traceback

sys.dont_write_bytecode = True   # keep tools/blender/environment free of __pycache__
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import envlib  # noqa: E402
import dungeon  # noqa: E402
import town  # noqa: E402
import projectiles  # noqa: E402
import icons  # noqa: E402
import facecheck  # noqa: E402

KIT_IDS = {"env_floor_a", "env_floor_b", "env_floor_c", "env_wall_a", "env_wall_b", "env_pillar"}
WITH_LID = {"env_chest", "town_stash"}


def run_checks(model_id):
    """facecheck for one freshly built model (scene still loaded). Returns a list of failures."""
    fails = []
    if model_id in KIT_IDS:
        # kit pieces are only ever seen from the game camera; the walls' dark core may show
        # through the corner notches (never the void)
        args = dict(min_elev=20.0, allow_interior=model_id.startswith("env_wall"))
    elif model_id.startswith("proj_"):
        args = dict(min_elev=-60.0)         # projectiles fly at y ~ 1.1 and may pitch
    else:
        args = dict(min_elev=0.0)           # props stand on the floor; the camera is always above
    runs = [False, True] if model_id in WITH_LID else [False]
    for lid_open in runs:
        ok, rep = facecheck.check_backfaces(model_id, lid_open=lid_open, **args)
        print("[check] %s %s" % ("ok  " if ok else "FAIL", rep))
        if not ok:
            fails.append(model_id + (" (lid open)" if lid_open else ""))
    return fails


def registry():
    reg = {}
    for mod in (dungeon, town, projectiles):
        for k, fn in mod.BUILDERS.items():
            reg[k] = ("model", fn)
    for sid in icons.SKILL_IDS:
        reg["icon:" + sid] = ("icon", sid)
    return reg


def select(reg, only):
    if not only:
        return list(reg.keys())
    out = []
    for tok in [t.strip() for t in only.split(",") if t.strip()]:
        if tok == "all":
            match = list(reg.keys())
        elif tok == "models":
            match = [k for k, v in reg.items() if v[0] == "model"]
        elif tok == "icons":
            match = [k for k, v in reg.items() if v[0] == "icon"]
        elif tok == "env":
            match = [k for k in reg if k.startswith("env_")]
        elif tok == "kit":
            match = [k for k in reg if k in KIT_IDS]
        elif tok == "props":
            match = [k for k in reg if k.startswith("env_") and k not in KIT_IDS]
        elif tok == "town":
            match = [k for k in reg if k.startswith("town_")]
        elif tok == "proj":
            match = [k for k in reg if k.startswith("proj_")]
        elif tok in reg:
            match = [tok]
        elif ("icon:" + tok) in reg:
            match = ["icon:" + tok]
        else:
            match = [k for k in reg if fnmatch.fnmatch(k, tok) or fnmatch.fnmatch(k, "icon:" + tok)]
        if not match:
            raise SystemExit("build_all: unknown id/group '%s'" % tok)
        for m in match:
            if m not in out:
                out.append(m)
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    list_only = False
    check = False
    export = True
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--only="):
            only = a.split("=", 1)[1]
        elif a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
            i += 1
        elif a == "--list":
            list_only = True
        elif a == "--check":
            check = True
        elif a == "--no-export":
            export = False
        i += 1
    reg = registry()
    ids = select(reg, only)
    if list_only:
        for k in ids:
            print(k)
        return 0
    failures = []
    t_all = time.time()
    for k in ids:
        kind, payload = reg[k]
        t0 = time.time()
        try:
            envlib.reset_scene()
            if kind == "model":
                payload()
                envlib.prepare_materials_for_export()
                tris = envlib.scene_tri_count()
                lo, hi = envlib.scene_bounds()
                if check:
                    bad = run_checks(k)
                    if bad:
                        raise RuntimeError("face check failed: " + ", ".join(bad))
                path = envlib.export_glb(k) if export else "(not exported)"
                print("[env] %-18s tris=%5d  min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)  %.1fs -> %s" % (
                    k, tris, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, time.time() - t0,
                    os.path.relpath(path, envlib.REPO) if export else path))
            elif not export:
                continue
            else:
                path = icons.build_icon(payload)
                print("[env] %-18s %.1fs -> %s" % (k, time.time() - t0, os.path.relpath(path, envlib.REPO)))
        except Exception:
            traceback.print_exc()
            failures.append(k)
            print("[env] FAILED %s" % k)
    if check and any(k in KIT_IDS for k in ids):
        for fl in ("env_floor_a", "env_floor_b", "env_floor_c"):
            for wl in ("env_wall_a", "env_wall_b"):
                ok, rep = facecheck.check_wall_slit(dungeon.BUILDERS[fl], dungeon.BUILDERS[wl], envlib.reset_scene)
                print("[check] %s %s + %s %s" % ("ok  " if ok else "FAIL", fl, wl, rep))
                if not ok:
                    failures.append("slit:%s+%s" % (fl, wl))
    print("[env] built %d/%d in %.1fs%s" % (len(ids) - len(failures), len(ids), time.time() - t_all,
                                           ("; FAILED: " + ", ".join(failures)) if failures else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
