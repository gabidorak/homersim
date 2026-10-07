#!/usr/bin/env bash
# Online games: the launcher (server/launcher/launcher.gd, what runs on the VPS) started from source
# on this machine, and headless clients that go through the real menu cards and server browser (test
# flags --host-online / --online-join, client/menu_test_hooks.gd; --online-url / --online-key point
# them at it).
#   - the API: no key -> 401, the list, a health check
#   - Hosty starts a game on the Host a game card (Online server); Joiner finds it in the Online tab
#     and joins; Hosty leaves and Joiner stays in (online games have no host); once Joiner leaves too,
#     the game stops by itself (idle_quit_s) and leaves the list
#   - a second game while max_games (1) run: an error box says the online server is full
#   - a wrong friends key: an error box says so
# The games' servers write to the launcher's log (they inherit its output).
# Usage: tests/integration/online_games.sh   (GODOT=/path/to/godot to override the binary; needs curl)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}  # the launcher's TCP port; its games get UDP PORT+1..PORT+4
LOGS=$(mktemp -d)
FAIL=0
KEY="k-test-$RANDOM$RANDOM"
GAME="Online-$RANDOM"
URL="http://127.0.0.1:$PORT"

cat > "$LOGS/launcher.cfg" <<EOF
[launcher]
port=$PORT
bind="127.0.0.1"
key="$KEY"
max_games=1
game_ports="$((PORT + 1))-$((PORT + 4))"
idle_quit_s=8
EOF

client() {  # client <name> <seconds> [extra args...]
	local name=$1 secs=$2; shift 2
	timeout -s KILL "$secs" "$GODOT" --headless --max-fps 60 -- --name "$name" --online-url "$URL" "$@" \
		> "$LOGS/$name.log" 2>&1 &
}
expect() {  # expect <file> <pattern> <description>
	if grep -qE -e "$2" "$LOGS/$1.log"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}
expect_not() {  # expect_not <file> <pattern> <description>
	if grep -qE -e "$2" "$LOGS/$1.log"; then echo "FAIL - $3"; FAIL=1; else echo "ok   - $3"; fi
}

timeout -s KILL 60 "$GODOT" --headless -- --launcher --config "$LOGS/launcher.cfg" > "$LOGS/launcher.log" 2>&1 &
LAUNCHER=$!
for _ in $(seq 40); do  # (until it listens)
	grep -q "\[launcher\] listening on TCP" "$LOGS/launcher.log" && break
	sleep 0.25
done

curl -s -m 5 -w " [%{http_code}]" "$URL/" > "$LOGS/health.log" 2>&1
curl -s -m 5 -w " [%{http_code}]" "$URL/games" > "$LOGS/nokey.log" 2>&1
curl -s -m 5 -w " [%{http_code}]" -H "Authorization: Bearer $KEY" "$URL/games" > "$LOGS/empty.log" 2>&1

client Hosty 45 --online-key "$KEY" --host-online "$GAME" --host-bots 0 --teams 1,2 --leave-after 12
sleep 4
client Joiner 50 --online-key "$KEY" --online-join "$GAME" --leave-after 16
client Busy 20 --online-key "$KEY" --host-online "Busy-$RANDOM" --dismiss-errors
client BadKey 20 --online-key "wrong-key" --host-online "Nope" --dismiss-errors
sleep 6
curl -s -m 5 -w " [%{http_code}]" -H "Authorization: Bearer $KEY" "$URL/games" > "$LOGS/listed.log" 2>&1
# Hosty leaves at ~15 s, Joiner at ~24 s; the game stops 8 s later.
for _ in $(seq 120); do
	grep -q "on UDP [0-9]* ended" "$LOGS/launcher.log" && break
	sleep 0.5
done
curl -s -m 5 -w " [%{http_code}]" -H "Authorization: Bearer $KEY" "$URL/games" > "$LOGS/after.log" 2>&1
kill "$LAUNCHER" 2>/dev/null
wait

expect health  '"game":"homersim".* \[200\]'                                 "api: health check"
expect nokey   '"error":"key".* \[401\]'                                     "api: no key, no list"
expect empty   '"games":\[\].* \[200\]'                                      "api: no games at first"
expect listed  "\"name\":\"$GAME\".*\"players\":2.* \[200\]"                 "api: the game is listed with both players"
expect after   '"games":\[\].* \[200\]'                                      "api: no games at the end"
expect Hosty   "pressing Host on the online host card"                       "host: the card's Host button, online"
expect Hosty   "the online server started '$GAME' at 127.0.0.1:[0-9]+"       "host: the launcher started the game"
expect launcher "starting '$GAME' for 127.0.0.1 on UDP $((PORT + 1))"         "launcher: started it on the first game port"
expect launcher "starting '$GAME' .*, 1 v 2, bots 0"                           "launcher: with the teams picked on the card"
expect launcher "match rule max_rats = 2"                                    "game: its server plays with those teams"
expect launcher "'$GAME' listening on UDP $((PORT + 1)), max"                 "launcher: its server listens"
expect launcher "quits after 8 s with nobody in the game"                    "launcher: the game stops by itself when idle"
expect Hosty   "joined as Hosty"                                             "host: joined"
expect Joiner  "found '$GAME' online on port $((PORT + 1))"                  "friend: saw the game in the Online tab"
expect Joiner  "joined as Joiner"                                            "friend: joined"
expect launcher "Hosty \(peer [0-9]+\) left, 1 player"                        "host left: the friend is still in"
expect_not Joiner "The host left"                                            "friend: not sent back to the menu by the host leaving"
expect Joiner  "--leave-after: leaving"                                      "friend: left by itself, later"
expect launcher "nobody in the game for 8 s, stopping"                       "game: stopped once empty"
expect launcher "'$GAME' on UDP [0-9]+ ended"                                "launcher: forgot the game"
expect launcher "refused a new game from 127.0.0.1: 1 games already run"     "busy: the launcher refused a second game"
expect Busy    "error box: Online server: full"                              "busy: an error box says it is full"
expect launcher "refused a request from 127.0.0.1: wrong friends key"        "bad key: refused"
expect BadKey  "error box: Online server: wrong friends key"                 "bad key: an error box says so"
if grep -lE "SCRIPT ERROR|^ERROR|leaked at exit" "$LOGS"/{launcher,Hosty,Joiner,Busy,BadKey}.log; then
	echo "FAIL - errors in the logs above"; FAIL=1
fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
