#!/usr/bin/env bash
# M10 phase B, the AI bots' navigation: a bots-only match (--ai-only --ai-fill 6) in which every bot
# walks to its share of all the targets of its role (--ai-scenario tour): sabotage points, levers,
# repair points, cages, pickups, consoles, cameras, keycard readers (through the keycard doors),
# vent exits (through the ducts, up the shaft and the yard ladder). The match ends when all are done.
# Checks: every target reached and usable from there (ai.tour.failed == []), nobody hard stuck,
# no validator strikes, no errors.
# Usage: tests/integration/ai_nav_tour.sh   (SEED=N to pick the seed, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 360 --ai-only --ai-fill 6 --ai-scenario tour --test-duration 300
finish

check "d['ai']['tour']['targets'] >= 60" "result: the tour has every target (60+)"
check "d['ai']['tour']['reached'] == d['ai']['tour']['targets']" "result: every target reached"
check "d['ai']['tour']['failed'] == []" "result: no target failed"
check "len(d['ai']['bots']) == 6" "result: 6 bots"
check "all(b['stuck_hard'] == 0 for b in d['ai']['bots'])" "result: nobody hard stuck"
expect "$LOGS/server.log" "every bot finished its tour" "server: every bot finished its tour"
common_checks
