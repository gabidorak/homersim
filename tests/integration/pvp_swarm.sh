#!/usr/bin/env bash
# M4 bites: a supervisor bot carries rat 1 until rat 2 bites it (drop), then all three rats bite
# the supervisor: knockdown, the swarm bonus exactly once, knockdown immunity, no perma-stun.
# Usage: tests/integration/pvp_swarm.sh   (GODOT=/path/to/godot to override the binary)
source "$(dirname "$0")/pvp_lib.sh"

start_server 4 40 80
start_bot supervisor supervisor SupervisorBot swarm "" 80
for i in 1 2 3; do start_bot "rat$i" rat "Rat${i}Bot" swarm "$i" 80; done
finish

expect "$LOGS/server.log" "SupervisorBot grabbed Rat1Bot"            "server: grab"
expect "$LOGS/server.log" "Rat1Bot got away \(Rat2Bot bit the carrier\)" "server: a bite made the carrier drop the rat"
expect "$LOGS/server.log" "bit SupervisorBot: KNOCKED DOWN"          "server: three bites knocked the supervisor down"
expect "$LOGS/server.log" "bit SupervisorBot: ignored"               "server: bites on a knocked-down supervisor are ignored"
count "$LOGS/server.log" "swarm bonus: \+15% meltdown" 1             "server: the swarm bonus triggered exactly once"
expect "$RESULT" '"knockdowns": [1-9]'                               "result: knockdowns counted"
expect "$RESULT" '"bites": [1-9]'                                    "result: bites counted"
# Knockdown immunity: after a knockdown ends there are 3 s where bites can't knock down again.
GAPS=$(grep -E "bit SupervisorBot: KNOCKED DOWN" "$LOGS/server.log" | sed -E 's/^\[([0-9]+):([0-9]+):([0-9]+)\].*/\1 \2 \3/' \
	| awk '{ t = $1 * 3600 + $2 * 60 + $3; if (NR > 1) printf "%d ", t - last; last = t }')
SHORT=0
for g in $GAPS; do [ "$g" -lt 6 ] && SHORT=1; done  # 7 s, minus the logs' 1 s resolution
if [ $SHORT -eq 0 ]; then echo "ok   - knockdowns are at least 7 s apart (4 s down + 3 s immunity): $GAPS"
else echo "FAIL - knockdowns too close together: $GAPS"; FAIL=1; fi
common_checks
