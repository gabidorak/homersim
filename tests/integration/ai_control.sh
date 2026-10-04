#!/usr/bin/env bash
# M10 phase E, the Control Room: two supervisor bots (Console only) and a rat bot that stays in the
# nest. The core starts at 950 (--ai-scenario hot): one supervisor uses the emergency coolant
# (core −150, still above 760), the other lifts the SCRAM cover and presses the button (the shift
# gets 30 s longer).
# Usage: tests/integration/ai_control.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 120 --ai-only --ai-roles supervisor,supervisor,rat --ai-goals supervisor:Console,rat:none \
	--ai-scenario hot --test-duration 50 --ai-log
finish

expect "$LOGS/server.log" "used the emergency coolant" "server: a bot used the emergency coolant"
expect "$LOGS/server.log" "lifted the SCRAM cover" "server: a bot lifted the SCRAM cover"
expect "$LOGS/server.log" "pressed SCRAM" "server: …and pressed the button"
expect "$LOGS/server.log" "timer \+30 s" "server: the shift got 30 s longer"
common_checks
