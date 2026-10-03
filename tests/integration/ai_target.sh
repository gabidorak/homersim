#!/usr/bin/env bash
# M10 phase A, AI bodies take hits like players' do: on the TestArena, one AI rat that stands still
# (--ai-roles rat --ai-goals rat:none) and a scripted supervisor client (pvp_bot.gd ai_target). The
# client stuns the AI rat, grabs it, carries it and cages it: the server moves a bot's body itself
# (attach_to, force_position, no RPCs). Every rat is caught, supervisors win.
# Usage: tests/integration/ai_target.sh   (GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 90 --level test --ai-roles rat --ai-goals rat:none --test-duration 60
timeout -s KILL 80 "$GODOT" --headless --max-fps 120 -- --level test --bot supervisor --connect "127.0.0.1:$PORT" \
	--name SupervisorBot --bot-scenario ai_target > "$LOGS/supervisor.log" 2>&1 &
finish

check "d.get('winner') == 'supervisors' and d.get('reason') == 'Every rat is caught'" "result: supervisors caught every rat"
check "any(s['bot'] and s['caught'] == 1 for s in d['stats'])" "result: the bot was caught (stats row marked bot)"
check "any(not s['bot'] and s['catches'] == 1 for s in d['stats'])" "result: the human has the catch"
expect "$LOGS/supervisor.log" "AI rat: .* badge true" "client: the AI rat wears its badge"
expect "$LOGS/server.log" "BONK! .* is stunned" "server: the broom stunned the AI rat"
expect "$LOGS/server.log" "SupervisorBot grabbed" "server: grabbed"
expect "$LOGS/server.log" "SupervisorBot caged .* \(capture 1\)" "server: caged"
expect "$LOGS/supervisor.log" "AI rat caged: true, inside the cage: true" "client: the AI rat is in the cage"
common_checks
