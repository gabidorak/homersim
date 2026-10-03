#!/usr/bin/env bash
# M10 soak (manual, not in run_all.sh: it takes minutes): bots-only matches back to back on one server
# (--ai-only, no --exit-after-match), MATCHES of them (default 10) of DURATION seconds (default 45).
# Samples the server's memory after each match; checks that every match ended, nobody got hard stuck,
# no validator strikes, no errors, and that memory stays stable (the last sample within 15 % of the
# second one: the first match warms caches up).
# Usage: tests/integration/ai_soak.sh   (MATCHES=N DURATION=S SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"
MATCHES=${MATCHES:-10}
DURATION=${DURATION:-45}

printf '[match]\ncountdown_s=3\npost_match_s=3\n' > "$LOGS/server.cfg"
"$GODOT" --headless --max-fps 120 -- --server --no-heatmap --no-lan --port "$PORT" --config "$LOGS/server.cfg" \
	--allow-debug --ai-only --ai-fill 6 --ai-seed "$SEED" --test-duration "$DURATION" > "$LOGS/server.log" 2>&1 &
SERVER=$!
SAMPLES=()
deadline=$(( $(date +%s) + MATCHES * (DURATION + 15) + 30 ))
while [ "$(grep -c 'state: POST_MATCH' "$LOGS/server.log")" -lt "$MATCHES" ] && [ "$(date +%s)" -lt "$deadline" ]; do
	ended=$(grep -c 'state: POST_MATCH' "$LOGS/server.log")
	if [ "$ended" -gt "${#SAMPLES[@]}" ]; then
		SAMPLES+=("$(awk '/VmRSS/ {print $2}' /proc/$SERVER/status)")
		echo "   match $ended done, server memory ${SAMPLES[-1]} kB"
	fi
	sleep 2
done
kill "$SERVER" 2>/dev/null
wait "$SERVER" 2>/dev/null

n=$(grep -c 'state: POST_MATCH' "$LOGS/server.log")
if [ "$n" -ge "$MATCHES" ]; then echo "ok   - $n matches played"; else echo "FAIL - only $n of $MATCHES matches ended"; FAIL=1; fi
if [ "${#SAMPLES[@]}" -ge 3 ]; then
	first=${SAMPLES[1]}; last=${SAMPLES[-1]}
	if [ "$last" -le $(( first * 115 / 100 )) ]; then echo "ok   - memory stable ($first kB -> $last kB)"
	else echo "FAIL - memory grew ($first kB -> $last kB)"; FAIL=1; fi
fi
if grep -qE "strike [0-9]+ for" "$LOGS/server.log"; then echo "FAIL - the movement validator flagged someone"; FAIL=1; fi
refute "$LOGS/server.log" "is hard stuck" "no bot got hard stuck"
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/server.log; then echo "FAIL - errors in the log"; FAIL=1; fi
if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
