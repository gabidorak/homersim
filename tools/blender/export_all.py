"""Regenerates every model into assets/generated/ (ASSETS §4). Run from the repo root:

    blender -b -P tools/blender/export_all.py                 # everything
    blender -b -P tools/blender/export_all.py -- crate valve  # only these scripts

Every script in tools/blender/ (except common.py and this file) is a module with:
    ASSETS = [("out_name", {build kwargs}), ...]   one entry per .glb to write
    def build(**kwargs) -> list of root objects (or one object)
    ANIMATED = True                                 optional: export actions (characters)
Then run tools/build_assets.sh (or `godot --headless --import`) so Godot re-imports them.
"""
import importlib
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

SKIP = {"common", "export_all", "preview"}


def modules(only=None):
    names = sorted(f[:-3] for f in os.listdir(HERE) if f.endswith(".py") and f[:-3] not in SKIP)
    if only:
        missing = set(only) - set(names)
        if missing:
            raise SystemExit("unknown script(s): %s" % ", ".join(sorted(missing)))
        names = [n for n in names if n in only]
    return names


def export_module(name):
    mod = importlib.import_module(name)
    count = 0
    for out_name, kwargs in getattr(mod, "ASSETS", []):
        C.reset()
        roots = mod.build(**kwargs)
        if not isinstance(roots, (list, tuple)):
            roots = [roots]
        C.export(os.path.join(C.GENERATED, out_name + ".glb"), list(roots), animations=getattr(mod, "ANIMATED", False))
        count += 1
    return count


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    failed, total = [], 0
    for name in modules(only):
        try:
            total += export_module(name)
        except Exception:  # keep going, report at the end
            traceback.print_exc()
            failed.append(name)
    print("export_all: %d models written%s" % (total, (", FAILED: " + ", ".join(failed)) if failed else ""))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
