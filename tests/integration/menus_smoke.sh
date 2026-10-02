#!/usr/bin/env bash
# M8 menus smoke test, headless: the real main menu, server browser and dialogs, driven by test-only
# menu flags (client/menu_test_hooks.gd).
#   - LAN discovery: a client finds a server by name in the browser's LAN list and joins it
#   - password: required, then wrong, then right (the prompt comes back each time)
#   - every failure ends in an error box: kicked, lost connection, timeout, bad address
# Server full and version mismatch are in join_smoke.sh.
# Needs UDP ports 7778-7781 free on this machine (close any running copy of the game).
# Usage: tests/integration/menus_smoke.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}
PORT2=$((PORT + 1))
PORT3=$((PORT + 2))  # nothing listens there
LOGS=$(mktemp -d)
FAIL=0
LAN_NAME="LanTest-$RANDOM"

client() {  # client <name> <seconds> [extra args...]
	local name=$1 secs=$2; shift 2
	timeout -s KILL "$secs" "$GODOT" --headless --max-fps 60 -- --name "$name" "$@" > "$LOGS/$name.log" 2>&1 &
}
expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$LOGS/$1.log"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

printf '[server]\nname="%s"\n' "$LAN_NAME" > "$LOGS/lan.cfg"
"$GODOT" --headless --max-fps 60 -- --server --no-heatmap --port "$PORT" --config "$LOGS/lan.cfg" > "$LOGS/server_lan.log" 2>&1 &
LAN_SERVER=$!
"$GODOT" --headless --max-fps 60 -- --server --no-heatmap --no-lan --allow-debug --port "$PORT2" --password cheese \
	> "$LOGS/server_pw.log" 2>&1 &
PW_SERVER=$!
sleep 2
client Finder 22 --lan-join "$LAN_NAME" --dismiss-errors
client Pat 12 --connect "127.0.0.1:$PORT2" --auto-password chese,cheese
sleep 1
client Kim 12 --connect "127.0.0.1:$PORT2" --auto-password cheese --debug-kick-me --dismiss-errors
client Tim 12 --connect "127.0.0.1:$PORT3" --dismiss-errors
client Bad 6 --connect "not an address!" --dismiss-errors
sleep 12
kill "$LAN_SERVER" 2>/dev/null; wait "$LAN_SERVER" 2>/dev/null   # Finder loses its server
sleep 7
kill "$PW_SERVER" 2>/dev/null; wait "$PW_SERVER" 2>/dev/null
wait

expect server_lan "announcing '$LAN_NAME' on the LAN"           "server: announces itself on the LAN"
expect Finder "found '$LAN_NAME' at .*joining"                  "finder: saw the server in the LAN list"
expect Finder "joined as Finder"                                "finder: joined through the browser"
expect server_lan "Finder \(peer [0-9]+\) joined"               "server: the LAN client joined"
expect Finder "back to menu: Lost the connection"               "finder: noticed the server stopped"
expect Finder "error box: Lost the connection"                  "finder: told in an error box"
expect server_pw "rejected peer [0-9]+ \(Pat\): Password required" "password server: refused Pat without a password"
expect server_pw "rejected peer [0-9]+ \(Pat\): Wrong password" "password server: refused the wrong password"
expect server_pw "Pat \(peer [0-9]+\) joined"                   "password server: Pat joined with the right one"
expect Pat "asking for the password of 127.0.0.1:$PORT2 \(required\)" "pat: asked for the password"
expect Pat "asking for the password of 127.0.0.1:$PORT2 \(wrong password\)" "pat: asked again after a wrong one"
expect Pat "joined as Pat"                                      "pat: in"
expect server_pw "kicking Kim: Kicked for testing"              "password server: kicked Kim"
expect Kim "back to menu: Kicked by the server: Kicked for testing" "kim: told why"
expect Kim "error box: Kicked by the server"                    "kim: in an error box"
expect Tim "back to menu: Connection timed out"                 "tim: the connection timed out"
expect Tim "error box: Connection timed out"                    "tim: in an error box"
expect Bad "error box: Invalid address: not an address!"        "bad: the address was refused"
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
