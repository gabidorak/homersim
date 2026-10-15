#!/usr/bin/env bash
# Bot rats smash the traps they notice with their tail spin: on the TestArena, one AI rat that stands
# still (--ai-roles rat --ai-goals rat:none, hard bots: they notice 95% of the traps) and a scripted
# supervisor client (pvp_bot.gd ai_tailspin) that lays three traps about 1 m around it. The rat
# spins (several times: the 5 s cooldown) until every trap is gone, and none of them goes off.
# Usage: tests/integration/ai_tailspin.sh   (GODOT=/path/to/godot, SEED=N)
source "$(dirname "$0")/ai_lib.sh"

MATCH_CFG="bot_difficulty=2" start_server 90 --level test --ai-roles rat --ai-goals rat:none --test-duration 45
timeout -s KILL 80 "$GODOT" --headless --max-fps 120 -- --level test --bot supervisor --connect "127.0.0.1:$PORT" \
	--name SupervisorBot --bot-scenario ai_tailspin > "$LOGS/supervisor.log" 2>&1 &
finish

n=$(grep -c "placing a trap by the AI rat: true" "$LOGS/supervisor.log")
if [ "$n" -eq 3 ]; then echo "ok   - client: 3 traps laid by the AI rat"; else echo "FAIL - client: $n traps laid, expected 3"; FAIL=1; fi
expect "$LOGS/server.log" "spun its tail: smashed [1-3] trap" "server: the AI rat smashed traps with its tail"
refute "$LOGS/server.log" "stepped on a"                     "server: no trap went off"
refute "$LOGS/server.log" "refused tail_spin"                "server: the AI never asks for a spin it can't have"
expect "$LOGS/supervisor.log" "AI rat: traps left 0, stunned false" "client: every trap is gone"
n=$(grep -cE "feed: tail_(snap|lure) " "$LOGS/supervisor.log")
if [ "$n" -eq 3 ]; then echo "ok   - client feed: 3 traps smashed"; else echo "FAIL - client feed: $n traps smashed, expected 3"; FAIL=1; fi
refute "$LOGS/supervisor.log" "tail spin seen: .*, [1-9] smash" "client: a supervisor is never told where"
common_checks
