#!/usr/bin/env bash
# M10 phase F, balance (manual, not in run_all.sh: full matches take minutes): MATCHES bots-only
# matches (default 10), each on its own headless server with its own seed (SEED, SEED+1, …), JOBS of
# them at a time (default 4). Each match runs its real length unless DURATION is set (seconds), at the
# difficulty DIFFICULTY (0 easy, 1 normal, 2 hard; default 1). Prints one line per match (winner, why,
# meltdown, the team stats) and the totals: both teams should win sometimes (GDD §5.5, M10 phase F).
# Fails only on errors in the logs, hard-stuck bots or validator strikes.
# AI_LOG=1 adds --ai-log, GOALS=role:Goal,… passes --ai-goals (experiments), KEEP_LOGS=1 keeps the logs.
# Usage: tests/integration/ai_balance.sh   (MATCHES=N JOBS=N SEED=N DURATION=S DIFFICULTY=D, GODOT=…)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
MATCHES=${MATCHES:-10}
JOBS=${JOBS:-4}
SEED=${SEED:-$((RANDOM % 1000))}
DIFFICULTY=${DIFFICULTY:-1}
BASE_PORT=$((20000 + RANDOM % 19000))
LOGS=$(mktemp -d)
printf '[match]\ncountdown_s=3\nbot_difficulty=%d\n' "$DIFFICULTY" > "$LOGS/server.cfg"
EXTRA=()
if [ -n "${DURATION:-}" ]; then EXTRA=(--test-duration "$DURATION"); fi
if [ -n "${AI_LOG:-}" ]; then EXTRA+=(--ai-log); fi
if [ -n "${GOALS:-}" ]; then EXTRA+=(--ai-goals "$GOALS"); fi
echo "seeds $SEED..$((SEED + MATCHES - 1)), difficulty $DIFFICULTY, ${DURATION:-full} s, $JOBS at a time (logs in $LOGS)"

run_one() {  # run_one <index>
	local seed=$((SEED + $1)) port=$((BASE_PORT + $1))
	timeout -s KILL 900 "$GODOT" --headless --max-fps 120 -- --server --no-heatmap --no-lan --port "$port" \
		--config "$LOGS/server.cfg" --allow-debug --ai-only --ai-fill 6 --ai-seed "$seed" --exit-after-match \
		--result-file "$LOGS/result_$seed.json" "${EXTRA[@]}" > "$LOGS/server_$seed.log" 2>&1
}

running=0
for i in $(seq 0 $((MATCHES - 1))); do
	if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running - 1)); fi
	run_one "$i" &
	running=$((running + 1))
done
wait

python3 - "$LOGS" "$SEED" "$MATCHES" <<'EOF'
import json, os, sys
logs, seed, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
keys = ["sabotages", "repairs", "catches", "frees", "bites", "knockdowns", "steals"]
wins = {}
totals = {k: 0 for k in keys}
for s in range(seed, seed + n):
    path = os.path.join(logs, "result_%d.json" % s)
    if not os.path.exists(path):
        print("  seed %4d: no result" % s)
        continue
    d = json.load(open(path))
    wins[d["winner"]] = wins.get(d["winner"], 0) + 1
    team = {}
    for row in d["stats"]:
        for k in keys:
            team[k] = team.get(k, 0) + row.get(k, 0)
            totals[k] += row.get(k, 0)
    print("  seed %4d: %-11s %-28s meltdown %5.1f | %s" % (s, d["winner"], d["reason"][:28], d["meltdown"],
        " ".join("%s %d" % (k, team[k]) for k in keys)))
print("wins:", wins)
print("totals:", " ".join("%s %d" % (k, v) for k, v in totals.items()))
EOF

FAIL=0
if grep -lE "SCRIPT ERROR|^ERROR|leaked at exit" "$LOGS"/server_*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi
if grep -l "is hard stuck" "$LOGS"/server_*.log; then echo "FAIL - hard-stuck bots in the logs above"; FAIL=1; fi
if grep -lE "strike [0-9]+ for" "$LOGS"/server_*.log; then echo "FAIL - validator strikes in the logs above"; FAIL=1; fi
if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
if [ -z "${KEEP_LOGS:-}" ]; then rm -rf "$LOGS"; fi
echo "no errors"
