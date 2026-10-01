#!/usr/bin/env bash
# M5 map check: bakes navigation meshes for supervisors and rats from the plant's collision and
# checks the GDD §7 design rules (reachability, walk times, two rat routes per sabotage point,
# supervisors kept out of the vents and the nest). See tests/helpers/map_check.gd.
# Usage: tests/integration/map_check.sh [--update-docs]   (rewrites the table in docs/map/README.md)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
REPORT=$(mktemp)
timeout -s KILL 120 "$GODOT" --headless tests/helpers/MapCheck.tscn -- --report "$REPORT" > "$REPORT.log" 2>&1
CODE=$?
cat "$REPORT"
if grep -E "SCRIPT ERROR|^ERROR" "$REPORT.log"; then echo "FAIL - errors in the log above"; CODE=1; fi
if [ "${1:-}" = "--update-docs" ] && [ -s "$REPORT" ]; then
	python3 - "$REPORT" <<'PY'
import sys, re
report = open(sys.argv[1]).read().strip()
path = "docs/map/README.md"
text = open(path).read()
text = re.sub(r"(<!-- map-check:begin -->\n).*?(<!-- map-check:end -->)", lambda m: m.group(1) + report + "\n" + m.group(2), text, flags=re.S)
open(path, "w").write(text)
print("updated", path)
PY
fi
rm -f "$REPORT" "$REPORT.log"
if [ $CODE -ne 0 ]; then echo "map check FAILED"; exit 1; fi
echo "all good"
