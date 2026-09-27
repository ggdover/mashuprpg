"""Build the act assets (desert_*, forest_*, gothic_* models) with Blender 5.2.

    blender --background --factory-startup --python tools/blender/acts/build_all.py -- [options]

Options (after "--"):
    --only a,b,...   build only these: a model id (desert_palm_a), a glob (forest_pine_*), or an
                     act group: all, desert, forest, gothic.
    --list           print the ids and exit.
    --check          ray-cast each built model for back-face first hits (models are exported with
                     backface culling, so a visible back face is a hole); failures fail the build.
    --no-export      build (and check) without writing any file.

Each act module (desert.py, forest.py, gothic.py next to this file) exposes BUILDERS = {id: fn};
a builder builds ONE model into the (freshly reset) scene with envlib's MeshBuilder and calls
mb.finish(id). Modules may add their own materials to envlib.PALETTE at import (prefix the names:
"ds_", "fo_", "go_"). Missing act modules are skipped. The shared helpers live in
tools/blender/environment/envlib.py (+ town.py facade helpers).
Each model is exported atomically to assets/models/<id>.glb (§14.1). Deterministic.
OWNER: acts framework (driver); act modules are owned by their act.
"""

import fnmatch
import importlib
import os
import sys
import time
import traceback

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(os.path.dirname(HERE), "environment")
for p in (HERE, ENV):
    if p not in sys.path:
        sys.path.insert(0, p)

import envlib  # noqa: E402
import facecheck  # noqa: E402

ACT_MODULES = ("desert", "forest", "gothic")


def registry():
    reg = {}
    for name in ACT_MODULES:
        if not os.path.exists(os.path.join(HERE, name + ".py")):
            print("[acts] no %s.py yet, skipped" % name)
            continue
        try:
            mod = importlib.import_module(name)
            builders = mod.BUILDERS
        except Exception:
            traceback.print_exc()
            print("[acts] %s.py failed to import; its models are skipped" % name)
            continue
        for k, fn in builders.items():
            reg[k] = fn
    return reg


def select(reg, only):
    if not only:
        return list(reg.keys())
    out = []
    for tok in [t.strip() for t in only.split(",") if t.strip()]:
        if tok == "all":
            match = list(reg.keys())
        elif tok in ACT_MODULES:
            match = [k for k in reg if k.startswith(tok + "_")]
        elif tok in reg:
            match = [tok]
        else:
            match = [k for k in reg if fnmatch.fnmatch(k, tok)]
        if not match:
            raise SystemExit("acts/build_all: unknown id/group '%s'" % tok)
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
        t0 = time.time()
        try:
            envlib.reset_scene()
            reg[k]()
            envlib.prepare_materials_for_export()
            tris = envlib.scene_tri_count()
            lo, hi = envlib.scene_bounds()
            if check:
                ok, rep = facecheck.check_backfaces(k, min_elev=0.0)
                print("[check] %s %s" % ("ok  " if ok else "FAIL", rep))
                if not ok:
                    raise RuntimeError("face check failed")
            path = envlib.export_glb(k) if export else "(not exported)"
            print("[acts] %-22s tris=%5d  min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)  %.1fs -> %s" % (
                k, tris, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, time.time() - t0,
                os.path.relpath(path, envlib.REPO) if export else path))
        except Exception:
            traceback.print_exc()
            failures.append(k)
            print("[acts] FAILED %s" % k)
    print("[acts] built %d/%d in %.1fs%s" % (len(ids) - len(failures), len(ids), time.time() - t_all,
                                            ("; FAILED: " + ", ".join(failures)) if failures else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
