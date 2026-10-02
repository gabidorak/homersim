#!/usr/bin/env bash
# M3 critical sabotage test: two rat bots on the two Control rods levers (both must hold at the
# same time; the 2nd arrives 2 s later, so the progress must wait for it), then a supervisor bot
# reboots the rods (health 0) and repairs them three times. A 40 s match, supervisors win.
# Usage: tests/integration/critical_lever.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}
LOGS=$(mktemp -d)
RESULT="$LOGS/result.json"
FAIL=0

cat > "$LOGS/server.cfg" <<CFG
[match]
countdown_s=3
min_players=3
CFG

expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}
bot() {  # bot <log name> <args...>
	local log=$1; shift
	timeout -s KILL 70 "$GODOT" --headless --max-fps 120 -- --connect "127.0.0.1:$PORT" --bot-target rods "$@" \
		> "$LOGS/$log.log" 2>&1 &
}

timeout -s KILL 70 "$GODOT" --headless --max-fps 120 -- --server --no-heatmap --port "$PORT" --config "$LOGS/server.cfg" \
	--allow-debug --test-duration 40 --exit-after-match --result-file "$RESULT" \
	> "$LOGS/server.log" 2>&1 &
SERVER=$!
sleep 2
bot ratA --bot rat --name RatA --bot-lever A
bot ratB --bot rat --name RatB --bot-lever B --bot-delay 2
bot sup --bot supervisor --name Sup
wait "$SERVER"
CODE=$?
sleep 1
pkill -f -- "--connect 127.0.0.1:$PORT" 2>/dev/null

if [ "$CODE" -eq 0 ]; then echo "ok   - server exited with code 0"; else echo "FAIL - server exit code $CODE"; FAIL=1; fi
expect "$RESULT" '"winner": "supervisors"'                                "result: supervisors won"
expect "$RESULT" '"sabotage rods by Rat[AB] \+ Rat[AB]: health 100 -> 0"' "result: both rats credited, rods at 0"
expect "$RESULT" '"reboot rods by Sup'                                    "result: rods rebooted"
expect "$RESULT" '"repair rods by Sup: health 0 -> 35"'                   "result: first repair after the reboot"
expect "$RESULT" '"repair rods by Sup: health 70 -> 100"'                 "result: repaired to full"
expect "$LOGS/server.log" "critical sabotage of Control rods done"         "server: lever pair completed"
expect "$LOGS/ratA.log" "lever hold ended: completed"                     "rat A: hold completed"
expect "$LOGS/ratB.log" "lever hold ended: completed"                     "rat B: hold completed"
expect "$LOGS/ratA.log" "the interactor found ControlRods/LeverA by itself" "rat A: targeting"
# RatA held alone for ~2 s: the pair must still need 6 s of holding together.
secs() { date -d "$(grep -m1 -oE "^\[[0-9:]+\].*$1" "$LOGS/server.log" | cut -c2-9)" +%s; }
WAITED=$(( $(secs "critical sabotage of") - $(secs "RatA started") ))
if [ "$WAITED" -ge 7 ]; then echo "ok   - server: progress waited for the 2nd rat (${WAITED} s)"
else echo "FAIL - server: the pair completed after ${WAITED} s, expected >= 7"; FAIL=1; fi
if grep -qE "strike [0-9]+ for" "$LOGS/server.log"; then echo "FAIL - validator flagged a bot"; FAIL=1; fi
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
