#!/usr/bin/env bash
# Play solo and Host a game: the client starts a server itself (client/local_server.gd), headless,
# through the real menu cards (test flags --solo / --host-game, client/menu_test_hooks.gd).
#   - solo: a server on 127.0.0.1 with bots, the player becomes the host and plays a rat, the match
#     starts with no stop in the lobby; leaving closes the server
#   - host: a server on the chosen port, found on the LAN by a friend who joins; when the host
#     leaves, the friend is sent back to the menu ("the host left") and the server stops
#   - a port already in use: an error box, no server left behind
#   - the host's game is killed: its server notices and stops by itself (--owner-pid)
# The servers' output goes to their client's log (they inherit its stdout).
# Needs UDP ports 7778-7781 free on this machine (the friend's LAN list).
# Usage: tests/integration/local_games.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=${PORT:-$((20000 + RANDOM % 20000))}
PORT2=$((PORT + 1))
LOGS=$(mktemp -d)
FAIL=0
HOST_NAME="HostTest-$RANDOM"

client() {  # client <name> <seconds> [extra args...]
	local name=$1 secs=$2; shift 2
	timeout -s KILL "$secs" "$GODOT" --headless --max-fps 60 -- --name "$name" "$@" > "$LOGS/$name.log" 2>&1 &
}
expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$LOGS/$1.log"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}
server_pid() {  # the pid of the server a client started (from its log)
	grep -oE "starting a (solo|hosted) server \(pid [0-9]+\)" "$LOGS/$1.log" | grep -oE "[0-9]+" | head -1
}
expect_gone() {  # expect_gone <client> <description>: the server it started is no longer running
	local pid; pid=$(server_pid "$1")
	if [ -z "$pid" ]; then echo "FAIL - $2 (no server pid in the log)"; FAIL=1
	elif kill -0 "$pid" 2>/dev/null; then echo "FAIL - $2 (pid $pid still runs)"; FAIL=1; kill "$pid"
	else echo "ok   - $2"; fi
}

# Something already listens on PORT2.
"$GODOT" --headless --max-fps 60 -- --server --no-heatmap --no-lan --port "$PORT2" > "$LOGS/blocker.log" 2>&1 &
BLOCKER=$!
client Solo 45 --solo rat --leave-after 20
client Hosty 45 --host-game "$HOST_NAME" --host-port "$PORT" --host-bots 0 --leave-after 16
client Crash 14 --solo
sleep 3
client Joiner 42 --lan-join "$HOST_NAME" --dismiss-errors
client Busy 15 --host-game Busy --host-port "$PORT2" --dismiss-errors
sleep 34   # Solo: joined ~3 s, leaves at ~24 s; Hosty leaves at ~20 s; Crash is killed at 14 s
expect_gone Crash  "crash: its server stopped once the game was killed"
expect_gone Solo   "solo: the server stopped after the player left"
expect_gone Hosty  "host: the server stopped after the host left"
expect_gone Busy   "busy port: no server left behind"
kill "$BLOCKER" 2>/dev/null; wait "$BLOCKER" 2>/dev/null
wait

expect Solo "pressing Start on the solo card"                             "solo: the card's Start button"
expect Solo "'Solo game' listening on UDP [0-9]+ of 127.0.0.1"           "solo: the server listens on 127.0.0.1 only"
expect Solo "joined as Solo"                                              "solo: joined its own server"
expect Solo "Solo is the host"                                            "solo: the server knows its host"
expect Solo "roles: .*Solo=Rat.*\(bot\)"                                  "solo: a rat as asked, with bots"
expect Solo "\[C[0-9]+\]\[match\] state: PLAYING"                         "solo: the match started without pressing Ready"
expect Solo "back to menu: Left the server"                               "solo: left"
expect Solo "the host left, closing the server"                           "solo: the server closed"
expect Solo "\[local\] the server stopped"                                "solo: the game saw it stop"
expect Hosty "pressing Host on the host card"                             "host: the card's Host button"
expect Hosty "'$HOST_NAME' listening on UDP $PORT, max"                   "host: the server listens on every address"
expect Hosty "announcing '$HOST_NAME' on the LAN"                         "host: announced on the LAN"
expect Hosty "Hosty is the host"                                          "host: the server knows its host"
expect Joiner "found '$HOST_NAME' at .*joining"                           "friend: saw the game in the LAN list"
expect Joiner "joined as Joiner"                                          "friend: joined"
expect Hosty "the host left, closing the server \(1 player"               "host: left, the server closed for the friend"
expect Joiner "back to menu: The host left"                               "friend: told the host left"
expect Joiner "error box: The host left"                                  "friend: in an error box"
expect Busy "cannot listen on UDP port $PORT2"                            "busy port: the server couldn't listen"
expect Busy "error box: Could not start the server: UDP port $PORT2 is in use" "busy port: an error box says so"
expect Crash "joined as Crash"                                            "crash: joined its own server"
expect Crash "the game that started this server \(pid [0-9]+\) is gone, stopping" "crash: the server noticed"
# (Busy's log has the expected "can't listen" errors.)
if grep -lE "SCRIPT ERROR|^ERROR|leaked at exit" "$LOGS"/{Solo,Hosty,Joiner,Crash,blocker}.log; then
	echo "FAIL - errors in the logs above"; FAIL=1
fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
