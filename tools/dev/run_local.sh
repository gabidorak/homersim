#!/usr/bin/env bash
# Starts a headless server plus N windowed clients on this machine. Ctrl+C stops everything.
# Usage: tools/dev/run_local.sh [clients=3] [port=7777]
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
N=${1:-3}
PORT=${2:-7777}
trap 'kill 0' EXIT
"$GODOT" --headless -- --server --port "$PORT" &
sleep 1.5
for i in $(seq 1 "$N"); do
	"$GODOT" -- --connect "127.0.0.1:$PORT" --name "P$i" &
done
wait
