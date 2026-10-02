#!/usr/bin/env bash
# M3 full-loop test: a headless server and two headless bot clients (separate processes) on a
# random local port. The rat bot sabotages the coolant pumps (after an early release and a step
# aside, which the server must both cancel), the supervisor bot repairs them, the 25 s timer
# runs out, supervisors win.
# Checks the server's exit code, its result JSON and that no log has errors.
# Usage: tests/integration/run_match_loop.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}
LOGS=$(mktemp -d)
RESULT="$LOGS/result.json"
FAIL=0

# The real ready vote rather than --debug-start: --debug-start would begin the match the moment the
# 2nd bot joins, before the bots' role preferences arrive. Each bot sends its preference, then ready.
cat > "$LOGS/server.cfg" <<CFG
[match]
countdown_s=3
min_players=2
CFG

expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

timeout -s KILL 60 "$GODOT" --headless --max-fps 120 -- --server --no-heatmap --port "$PORT" --config "$LOGS/server.cfg" \
	--allow-debug --test-duration 25 --exit-after-match --result-file "$RESULT" \
	> "$LOGS/server.log" 2>&1 &
SERVER=$!
sleep 2
for role in rat supervisor; do
	timeout -s KILL 60 "$GODOT" --headless --max-fps 120 -- --bot "$role" --connect "127.0.0.1:$PORT" --name "${role^}Bot" \
		> "$LOGS/$role.log" 2>&1 &
done
wait "$SERVER"
CODE=$?
sleep 1
pkill -f -- "--connect 127.0.0.1:$PORT" 2>/dev/null

if [ "$CODE" -eq 0 ]; then echo "ok   - server exited with code 0"; else echo "FAIL - server exit code $CODE"; FAIL=1; fi
if [ -f "$RESULT" ]; then
	echo "ok   - result file written"
	expect "$RESULT" '"state_path": ".*COUNTDOWN>PLAYING>POST_MATCH"' "result: COUNTDOWN -> PLAYING -> POST_MATCH"
	expect "$RESULT" '"winner": "supervisors"'                          "result: supervisors won"
	expect "$RESULT" '"sabotage pumps by RatBot: health 100 -> 50"'     "result: the sabotage cost the pumps 50 health"
	expect "$RESULT" '"repair pumps by SupervisorBot: health 50 -> 85"' "result: the repair gave back 35"
	expect "$RESULT" '"sabotages": 1'                                   "result: the sabotage is in the stats"
	expect "$RESULT" '"repairs": [1-9]'                                   "result: the repair is in the stats"
else
	echo "FAIL - no result file"; FAIL=1
fi
expect "$LOGS/server.log" "RatBot's hold on CoolantPumps/SabotageA ended: released" "server: early release cancelled the hold"
expect "$LOGS/server.log" "RatBot's hold on CoolantPumps/SabotageA ended: moved" "server: stepping aside cancelled the hold"
expect "$LOGS/server.log" "RatBot completed CoolantPumps/SabotageA"   "server: sabotage completed"
expect "$LOGS/server.log" "SupervisorBot completed CoolantPumps/RepairPoint" "server: repair completed"
expect "$LOGS/rat.log" "the interactor found CoolantPumps/SabotageA by itself" "rat: front-cone targeting"
expect "$LOGS/supervisor.log" "the interactor found CoolantPumps/RepairPoint by itself" "supervisor: look-ray targeting"
expect "$LOGS/rat.log" "state: POST_MATCH"                             "rat: saw the end of the match"
if grep -qE "strike [0-9]+ for" "$LOGS/server.log"; then echo "FAIL - validator flagged a bot"; FAIL=1; fi
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
