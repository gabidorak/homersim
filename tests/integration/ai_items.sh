#!/usr/bin/env bash
# M10 phase E, a supervisor bot's traps and donuts: one supervisor bot (PlaceTrap, Refill and Donut
# only) and one rat bot that stays in the nest (--ai-goals rat:none). The supervisor eats a donut in
# the Break Room, lays its 3 traps on the rats' stand spots and vent exits, refills them at Storage
# (the plant is calm) and lays more.
# Usage: tests/integration/ai_items.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 150 --ai-only --ai-roles supervisor,rat --ai-goals supervisor:PlaceTrap,supervisor:Refill,supervisor:Donut,rat:none \
	--test-duration 100 --ai-log
finish

check "any(s['role'] == 1 and s['donuts'] >= 1 for s in d['stats'])" "result: the supervisor bot ate a donut"
expect "$LOGS/server.log" "placed a Snap trap" "server: a snap trap on a rats' stand spot"
expect "$LOGS/server.log" "placed a Cheese lure" "server: a cheese lure at a vent exit"
expect "$LOGS/server.log" "refilled the traps" "server: refilled at Storage"
n_after=$(sed -n "/refilled the traps/,\$p" "$LOGS/server.log" | grep -c "\[item\].* placed a ")
if [ "$n_after" -ge 1 ]; then echo "ok   - placed again after the refill"; else echo "FAIL - no trap placed after the refill"; FAIL=1; fi
n=$(grep -c "\[item\].* placed a " "$LOGS/server.log")
if [ "$n" -ge 4 ]; then echo "ok   - $n traps placed (3 charges, then a refill)"; else echo "FAIL - only $n traps placed"; FAIL=1; fi
common_checks
