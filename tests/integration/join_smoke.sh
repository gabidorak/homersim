#!/usr/bin/env bash
# M1 networking smoke test: a headless server and headless clients on a random local port.
# Checks joining, spawning, "Server full", version mismatch, and leave detection after a kill.
# Usage: tests/integration/join_smoke.sh   (GODOT=/path/to/godot to override the binary)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
PORT=$((20000 + RANDOM % 20000))
LOGS=$(mktemp -d)
FAIL=0

client() {  # client <name> <seconds> [extra args...]
	local name=$1 secs=$2; shift 2
	timeout -s KILL "$secs" "$GODOT" --headless -- --connect "127.0.0.1:$PORT" --name "$name" "$@" \
		> "$LOGS/$name.log" 2>&1 &
}
expect() {  # expect <file> <pattern> <description>
	if grep -qE "$2" "$LOGS/$1.log"; then echo "ok   - $3"; else echo "FAIL - $3"; FAIL=1; fi
}

"$GODOT" --headless -- --server --port "$PORT" --max-players 2 > "$LOGS/server.log" 2>&1 &
SERVER=$!
sleep 2
client A 9
client B 9
sleep 3
client Full 3                          # third player with max 2
sleep 1                                # (staggered: two peers dropping in the same instant make
client Old 3 --game-version 0.0.0      #  ENet log a harmless "unable to send packet" error)
sleep 11                               # A/B are killed at 8 s; ENet notices within ~5 s
kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null

expect server "A \(peer [0-9]+\) joined"  "server: A joined"
expect server "B \(peer [0-9]+\) joined"  "server: B joined"
expect server "rejected .*Server full"    "server: rejected the 3rd player"
expect server "rejected .*Version mismatch" "server: rejected the old version"
expect server "A \(peer [0-9]+\) left"    "server: noticed A was killed"
expect server "B \(peer [0-9]+\) left"    "server: noticed B was killed"
expect A "joined as A"                    "A: accepted"
expect A "spawned B .*peer"               "A: sees B's body"
expect B "spawned A .*peer"               "B: sees A's body"
expect B "spawned B .*\[local\]"          "B: owns its body"
expect Full "back to menu: Server full"   "3rd player: told the server is full"
expect Old "back to menu: Version mismatch" "old client: told about the version"
if grep -lE "SCRIPT ERROR|^ERROR" "$LOGS"/*.log; then echo "FAIL - errors in the logs above"; FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo "logs kept in $LOGS"; exit 1; fi
rm -rf "$LOGS"
echo "all good"
