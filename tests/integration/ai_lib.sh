# Shared helpers for the M10 AI bot integration tests (sourced, not run).
# A headless server on a random port with bots (--ai-* flags, debug builds), optionally with headless
# test clients (tests/helpers/bot_client.gd). The result JSON has an "ai" section (AiDirector.report()).
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}
SEED=${SEED:-$((RANDOM % 1000))}
LOGS=$(mktemp -d)
RESULT="$LOGS/result.json"
FAIL=0
echo "seed $SEED"

expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

refute() {  # refute <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "FAIL - $3"; FAIL=1; else echo "ok   - $3"; fi
}

# check <python expression on d = the result JSON> <description>
check() {
	if python3 -c "import json,sys; d=json.load(open('$RESULT')); sys.exit(0 if ($1) else 1)" 2>/dev/null; then
		echo "ok   - $2"
	else
		echo "FAIL - $2"; FAIL=1
	fi
}

# start_server <timeout_s> <extra server args...>   (writes $LOGS/server.log)
start_server() {
	local limit=$1
	shift
	printf '[match]\ncountdown_s=3\n' > "$LOGS/server.cfg"
	timeout -s KILL "$limit" "$GODOT" --headless --max-fps 120 -- --server --no-heatmap --no-lan --port "$PORT" \
		--config "$LOGS/server.cfg" --allow-debug --ai-seed "$SEED" --exit-after-match --result-file "$RESULT" "$@" \
		> "$LOGS/server.log" 2>&1 &
	SERVER=$!
	sleep 2
}

finish() {
	wait "$SERVER"
	local code=$?
	sleep 1
	pkill -f -- "--connect 127.0.0.1:$PORT" 2>/dev/null
	if [ "$code" -eq 0 ]; then echo "ok   - server exited with code 0"; else echo "FAIL - server exit code $code"; FAIL=1; fi
	if [ ! -f "$RESULT" ]; then echo "FAIL - no result file"; FAIL=1; echo '{}' > "$RESULT"; fi
}

common_checks() {
	if grep -qE "strike [0-9]+ for" "$LOGS/server.log"; then echo "FAIL - the movement validator flagged someone"; FAIL=1; fi
	refute "$LOGS/server.log" "is hard stuck" "no bot got hard stuck"
	if grep -lE "SCRIPT ERROR|^ERROR|leaked at exit|timed out waiting" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi
	if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
	rm -rf "$LOGS"
	echo "all good"
}
