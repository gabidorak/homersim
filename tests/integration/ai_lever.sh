#!/usr/bin/env bash
# M10 phase C, teamwork: two rat bots and nobody else (--ai-roles rat,rat), with only the lever pair
# goal (--ai-goals rat:LeverPair). One opens a pair on the blackboard, the other joins it, both
# levers are held together for 6 s: a critical sabotage credited to both.
# Usage: tests/integration/ai_lever.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 120 --ai-only --ai-roles rat,rat --ai-goals rat:LeverPair --test-duration 60
finish

check "any(e.startswith('sabotage rods by') or e.startswith('sabotage turbine by') for e in d['events'])" \
	"result: a critical sabotage (control rods or turbine)"
check "any(' + ' in e and e.startswith('sabotage ') for e in d['events'])" "result: credited to both rats"
check "all(s['sabotages'] >= 1 for s in d['stats'])" "result: both rats have the sabotage in their stats"
expect "$LOGS/server.log" "critical sabotage of .* done" "server: the lever pair completed"
common_checks
