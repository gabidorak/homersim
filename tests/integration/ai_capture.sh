#!/usr/bin/env bash
# M10 phase D, the capture chain by a bot: one supervisor bot (Chase and Capture only) and one rat bot
# that stands still (--ai-goals rat:none), placed in the Cage Room when the match starts
# (--ai-scenario capture). The supervisor sees the rat, walks up, swings the broom (its reflex),
# grabs the stunned rat and cages it: every rat is caught, supervisors win.
# Usage: tests/integration/ai_capture.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 120 --ai-only --ai-roles supervisor,rat --ai-goals supervisor:Chase,supervisor:Capture,rat:none \
	--ai-scenario capture --test-duration 60
finish

check "d.get('winner') == 'supervisors' and d.get('reason') == 'Every rat is caught'" "result: every rat caught"
check "any(s['role'] == 1 and s['catches'] == 1 and s['bonks'] >= 1 for s in d['stats'])" "result: a bonk and a catch for the supervisor bot"
expect "$LOGS/server.log" "swung the broom: BONK!" "server: the broom stunned the rat"
expect "$LOGS/server.log" "grabbed" "server: grabbed"
expect "$LOGS/server.log" "caged .* \(capture 1\)" "server: caged"
common_checks
