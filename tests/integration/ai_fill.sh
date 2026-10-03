#!/usr/bin/env bash
# M10 phase A, filling a match with AI bots: a server with bot_fill_to=6 in its config (no test flags,
# so it also runs against an exported release server: SERVER_BIN=/path/to/server) and ONE headless test
# client. The client readies up alone, the match starts with 5 bots (the client keeps its Rat
# preference: 2 bot supervisors, 3 bot rats) that walk around and wear their badge, then the client
# quits mid-match: with no humans left, the server goes back to the lobby, without the bots.
# Usage: tests/integration/ai_fill.sh   (GODOT=/path/to/godot, SERVER_BIN=/path/to/exported/server)
source "$(dirname "$0")/ai_lib.sh"
SERVER_BIN=${SERVER_BIN:-$GODOT}

printf '[match]\ncountdown_s=3\nbot_fill_to=6\n' > "$LOGS/server.cfg"
timeout -s KILL 60 "$SERVER_BIN" --headless -- --server --no-heatmap --no-lan --port "$PORT" --config "$LOGS/server.cfg" \
	> "$LOGS/server.log" 2>&1 &
SERVER=$!
sleep 3
timeout -s KILL 50 "$GODOT" --headless --max-fps 120 -- --bot rat --connect "127.0.0.1:$PORT" --name HumanRat \
	--bot-scenario ai_fill > "$LOGS/client.log" 2>&1
sleep 4
kill "$SERVER" 2>/dev/null
wait "$SERVER" 2>/dev/null

expect "$LOGS/server.log" "bots fill matches up to 6 players" "server: bots on, the navigation is baked"
expect "$LOGS/server.log" "roles: .*HumanRat=Rat" "server: the human keeps its Rat preference"
expect "$LOGS/server.log" "roles: (.*Supervisor \(bot\)){2}" "server: 2 bot supervisors"
expect "$LOGS/server.log" "roles: (.*Rat \(bot\)){3}" "server: 3 bot rats"
expect "$LOGS/server.log" "state: PLAYING" "server: the match started with one human"
expect "$LOGS/client.log" "match roster: 6 entries, 5 bots \(2 supervisors, 3 rats\), I am a Rat" "client: sees 5 bots"
expect "$LOGS/client.log" "bot bodies: 5 with a badge" "client: every bot wears its badge"
expect "$LOGS/client.log" "bot bodies: 5 with a badge, [3-5] moved" "client: the bots walk around (3+ moved over 2 m in 6 s)"
expect "$LOGS/server.log" "no humans left in the match, back to the lobby" "server: no humans left, back to the lobby"
expect "$LOGS/server.log" "back to the lobby with 0 player" "server: no bots in the lobby"
refute "$LOGS/server.log" "Ignoring sync data" "server: bot bodies retired cleanly"
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi
if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
