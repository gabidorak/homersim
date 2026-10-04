#!/usr/bin/env bash
# M10 phase E, keycards: one supervisor bot (Repair and Keycard only) and one rat bot (Steal only).
# The pumps start at 55 and the rat waits 5 m behind the pumps' repair spot (--ai-scenario steal):
# the supervisor walks over and repairs, facing the machine; the rat sneaks behind it, steals its
# keycard (a 1 s hold) and runs to a vent. The supervisor gets a keycard back: the spare at Storage
# 30 s later, or the stolen one if the rat drops it (stunned) on the way.
# Usage: tests/integration/ai_steal.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 150 --ai-only --ai-roles supervisor,rat --ai-goals supervisor:Repair,supervisor:Keycard,rat:Steal \
	--ai-scenario steal --test-duration 100 --ai-log
finish

check "any(s['role'] == 2 and s['steals'] >= 1 for s in d['stats'])" "result: the rat bot stole a keycard"
expect "$LOGS/server.log" "stole .*'s keycard" "server: the keycard was stolen"
expect "$LOGS/server.log" "got a keycard back" "server: the supervisor got a keycard back (the spare, or the dropped one)"
common_checks
