#!/usr/bin/env bash
# Runs the integration tests in parallel: each one gets its own port, its output is printed in one
# block when it finishes (in finishing order), then a summary. Exit code 1 if any test failed.
# Every headless Godot process takes ~200 MB and up to one core, and the bot tests are timing
# sensitive (hold durations, knockdown windows), so don't push -j past the cores you have.
# Usage: tests/integration/run_all.sh [-j N] [test ...]   (default: every test, -j 4)
#   e.g. tests/integration/run_all.sh -j 2 hazards pvp_items
#        tests/integration/run_all.sh --list   (prints the test names, one per line: ci.yml makes a job of each)
set -u
cd "$(dirname "$0")"
JOBS=4
LIST=0
if [ "${1:-}" = "--list" ]; then LIST=1; shift; fi
if [ "${1:-}" = "-j" ]; then JOBS=$2; shift 2; fi
# Longest first, so the slowest ones don't start last (here and in CI).
ALL=(ai_match ai_steal ai_items ai_nav_tour ai_cctv ai_control ai_lever pvp_items hazards critical_lever minigames
	pvp_swarm run_match_loop pvp_capture local_games lobby_smoke plant_cctv menus_smoke ai_fill pvp_hack control_room
	join_smoke ai_target ai_capture map_check)
if [ $# -gt 0 ]; then
	TESTS=("$@")
else
	TESTS=("${ALL[@]}")
	for t in *.sh; do  # a new test that isn't in ALL yet still runs
		t=${t%.sh}
		if [ "$t" != run_all ] && [ "$t" != pvp_lib ] && [ "$t" != ai_lib ] && [ "$t" != ai_soak ] && [ "$t" != ai_balance ] && [[ " ${ALL[*]} " != *" $t "* ]]; then TESTS+=("$t"); fi
	done
fi
if [ $LIST -eq 1 ]; then printf '%s\n' "${TESTS[@]}"; exit 0; fi

OUT=$(mktemp -d)
BASE_PORT=$((20000 + RANDOM % 19000))
START=$(date +%s)
declare -A PID_TEST=()
FAILED=()

report() {  # report <test> <exit code>
	local secs; secs=$(( $(date +%s) - $(cat "$OUT/$1.start") ))
	if [ "$2" -eq 0 ]; then echo "=== PASS $1 (${secs} s)"; else echo "=== FAIL $1 (${secs} s, exit $2)"; FAILED+=("$1"); fi
	cat "$OUT/$1.log"
	echo
}

wait_one() {
	local pid code
	wait -n -p pid "${!PID_TEST[@]}"
	code=$?
	report "${PID_TEST[$pid]}" "$code"
	unset "PID_TEST[$pid]"
}

i=0
for t in "${TESTS[@]}"; do
	[ "${#PID_TEST[@]}" -ge "$JOBS" ] && wait_one
	date +%s > "$OUT/$t.start"
	PORT=$((BASE_PORT + i * 10)) ./"$t".sh > "$OUT/$t.log" 2>&1 &
	PID_TEST[$!]=$t
	i=$((i + 1))
done
while [ "${#PID_TEST[@]}" -gt 0 ]; do wait_one; done

echo "${#TESTS[@]} tests in $(( $(date +%s) - START )) s with -j $JOBS"
rm -rf "$OUT"
if [ ${#FAILED[@]} -gt 0 ]; then echo "FAILED: ${FAILED[*]}"; exit 1; fi
echo "all passed"
