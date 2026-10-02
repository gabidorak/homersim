#!/usr/bin/env bash
# Regenerates every generated asset (M7, docs/ASSETS.md §4) and lets Godot import them:
#   1. assets/palette.png                      tools/art/make_palette.py
#   2. assets/generated/*.glb                  tools/blender/export_all.py (Blender 4.2+)
#   3. assets/audio/{sfx,music}/*.ogg          tools/audio/make_audio.py (numpy + ffmpeg)
#   4. levels/plant/** and its baked shells    tools/map/gen_plant.py --force + tools/godot/bake_shells.gd
#   5. Godot import of whatever changed (the models are re-imported, so the import script applies)
# Usage: tools/build_assets.sh [models|audio|level|all] (default all)
#   BLENDER=/path/to/blender GODOT=/path/to/godot tools/build_assets.sh models
set -euo pipefail
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-blender}
GODOT=${GODOT:-godot}
WHAT=${1:-all}

step() { echo; echo "== $*"; }

if [ "$WHAT" = all ] || [ "$WHAT" = models ]; then
	step "palette"
	python3 tools/art/make_palette.py
	step "models (Blender)"
	"$BLENDER" -b -P tools/blender/export_all.py 2>&1 | grep -E "exported|export_all|Error|Traceback" || true
	# Force a re-import of the models: Godot only re-imports a file whose contents changed, and the
	# import script (tools/godot/toon_import.gd) may have changed instead.
	rm -f .godot/imported/*.glb-*
fi
if [ "$WHAT" = all ] || [ "$WHAT" = audio ]; then
	step "audio"
	python3 tools/audio/make_audio.py
fi
step "import"
"$GODOT" --headless --import > /dev/null 2>&1 || true
if [ "$WHAT" = all ] || [ "$WHAT" = level ]; then
	step "level"
	python3 tools/map/gen_plant.py --force
	"$GODOT" --headless -s tools/godot/bake_shells.gd
	"$GODOT" --headless --import > /dev/null 2>&1 || true
fi
step "done: run the unit tests (tests/unit/test_assets.gd checks the assets) and look at tests/helpers/MapTour.tscn"
