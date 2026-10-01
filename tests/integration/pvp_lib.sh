# Shared helpers for the M4 PvP integration tests (sourced, not run).
# A headless server on a random port with the real ready vote (min_players = number of bots),
# plus headless bot clients running a PvP scenario (tests/helpers/pvp_bot.gd).
# They play on the TestArena sandbox (LEVEL=test, the scenarios use its spots); M5 tests on the
# plant set LEVEL=plant before sourcing this.
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=$((20000 + RANDOM % 20000))
LOGS=$(mktemp -d)
RESULT="$LOGS/result.json"
FAIL=0
LEVEL=${LEVEL:-test}

expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

refute() {  # refute <file> <pattern> <description>
	if grep -qE "$2" "$1"; then echo "FAIL - $3"; FAIL=1; else echo "ok   - $3"; fi
}

count() {  # count <file> <pattern> <expected> <description>
	local n
	n=$(grep -cE "$2" "$1")
	if [ "$n" -eq "$3" ]; then echo "ok   - $4"; else echo "FAIL - $4 (found $n, expected $3)"; FAIL=1; fi
}

# start_server <min_players> <test_duration_s> <timeout_s>
start_server() {
	cat > "$LOGS/server.cfg" <<CFG
[match]
countdown_s=3
min_players=$1
CFG
	timeout -s KILL "$3" "$GODOT" --headless -- --server --no-heatmap --level "$LEVEL" --port "$PORT" --config "$LOGS/server.cfg" \
		--allow-debug --test-duration "$2" --exit-after-match --result-file "$RESULT" \
		> "$LOGS/server.log" 2>&1 &
	SERVER=$!
	sleep 2
}

# start_bot <log_name> <role> <name> <scenario> <part> <timeout_s>
start_bot() {
	timeout -s KILL "$6" "$GODOT" --headless -- --level "$LEVEL" --bot "$2" --connect "127.0.0.1:$PORT" --name "$3" \
		--bot-scenario "$4" --bot-part "$5" > "$LOGS/$1.log" 2>&1 &
}

finish() {
	wait "$SERVER"
	local code=$?
	sleep 1
	pkill -f -- "--connect 127.0.0.1:$PORT" 2>/dev/null
	if [ "$code" -eq 0 ]; then echo "ok   - server exited with code 0"; else echo "FAIL - server exit code $code"; FAIL=1; fi
	if [ ! -f "$RESULT" ]; then echo "FAIL - no result file"; FAIL=1; touch "$RESULT"; fi
}

common_checks() {
	if grep -qE "strike [0-9]+ for" "$LOGS/server.log"; then echo "FAIL - validator flagged a bot"; FAIL=1; fi
	if grep -lE "SCRIPT ERROR|^ERROR|timed out waiting" "$LOGS"/*.log; then echo "FAIL - errors or bot timeouts in the logs above"; FAIL=1; fi
	if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
	rm -rf "$LOGS"
	echo "all good"
}
