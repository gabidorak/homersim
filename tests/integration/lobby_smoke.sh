#!/usr/bin/env bash
# M2 lobby smoke test: a headless server and headless test clients on a random local port.
# Checks preferences + ready vote -> role assignment -> countdown -> unfreeze, late joiners
# spectating, chat relay + rate limit, the movement validator, and (since M3) the supervisors
# winning when every rat leaves mid-match.
# Usage: tests/integration/lobby_smoke.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=$((20000 + RANDOM % 20000))
LOGS=$(mktemp -d)
FAIL=0

cat > "$LOGS/server.cfg" <<CFG
[match]
min_players=4
countdown_s=3
CFG

client() {  # client <name> <seconds> [extra args...]
	local name=$1 secs=$2; shift 2
	timeout -s KILL "$secs" "$GODOT" --headless -- --connect "127.0.0.1:$PORT" --name "$name" "$@" \
		> "$LOGS/$name.log" 2>&1 &
}
expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$LOGS/$1.log"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

"$GODOT" --headless -- --server --port "$PORT" --config "$LOGS/server.cfg" > "$LOGS/server.log" 2>&1 &
SERVER=$!
sleep 2
client Cheat 14 --pref rat --auto-move --debug-speed 3   # never readies: 3 of 4 is enough
sleep 2.5                                                # it runs around the lobby meanwhile
client Sup 26 --pref supervisor --auto-ready
client RatA 12 --pref rat --auto-ready --say hello
client RatB 13 --pref any --auto-ready                   # 1 s apart: two peers dropping at once can make ENet log an error
sleep 5                                                  # vote passes, 3 s countdown, playing
client Late 6
sleep 15                                                 # rats killed by ~14 s; ENet notices in ~5 s
kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null

expect server "match rule min_players = 4"                  "server: [match] overrides from server.cfg"
expect server "roles: .*Sup=Supervisor"                     "server: the supervisor fan got Supervisor"
expect server "roles: .*RatA=Rat"                           "server: a rat fan got Rat"
expect server "roles: .*Cheat=Rat"                          "server: the other rat fan got Rat"
expect server "state: COUNTDOWN"                            "server: countdown"
expect server "state: PLAYING"                              "server: playing after the countdown"
expect server "Late joined mid-match"                       "server: late joiner spectates"
expect server "strike [0-9]+ for Cheat .*too fast"          "server: validator flagged the x3 speed"
expect server "\[chat\] RatA: hello"                        "server: relayed chat"
expect server "Supervisors win: All rats left the game"     "server: rats all gone, supervisors win"
expect Sup "spawned Sup \(peer [0-9]+\) as Lobby \[local\]" "Sup: lobby body first"
expect Sup "spawned Sup \(peer [0-9]+\) as Supervisor \[local\]" "Sup: respawned as Supervisor"
expect Sup "state: PLAYING"                                 "Sup: saw the match start"
expect Sup "state: POST_MATCH"                              "Sup: saw the post-match screen"
expect RatB "spawned RatB \(peer [0-9]+\) as Rat \[local\]" "RatB: 'Any' became a rat"
expect RatB "spawned Sup \(peer [0-9]+\) as Supervisor$"    "RatB: sees the supervisor"
expect RatB "\[chat\] RatA: hello"                          "RatB: got the chat message"
expect RatA "Slow down"                                     "RatA: rate-limited the 2nd message"
expect Late "state: PLAYING"                                "Late: received the match state on join"
expect Late "spawned Sup \(peer [0-9]+\) as Supervisor$"    "Late: sees the supervisor"
if grep -qE "strike [0-9]+ for (Sup|RatA|RatB|Late) " "$LOGS/server.log"; then
	echo "FAIL - validator flagged an honest player"; FAIL=1
else
	echo "ok   - server: no strikes for honest players (respawns included)"
fi
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
