#!/usr/bin/env bash
# Starts a headless server plus N windowed clients on this machine. Ctrl+C stops everything.
# Usage: tools/dev/run_local.sh [clients=3] [port=7777]
#   SERVER_ARGS="--debug-start 2" tools/dev/run_local.sh 2   # extra server args (here: skip the ready vote)
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
N=${1:-3}
PORT=${2:-7777}
trap 'kill 0' EXIT
# shellcheck disable=SC2086  # SERVER_ARGS is split on purpose
"$GODOT" --headless -- --server --port "$PORT" ${SERVER_ARGS:-} &
sleep 1.5
for i in $(seq 1 "$N"); do
	"$GODOT" -- --connect "127.0.0.1:$PORT" --name "P$i" &
done
wait
