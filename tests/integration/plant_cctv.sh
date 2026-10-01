#!/usr/bin/env bash
# M5 plant test, on the real map: a supervisor sits at the CCTV chair, a rat breaks camera 1, the
# supervisor stands up and repairs it, then climbs the yard ladder to the vent roof and gets
# teleported out of bounds (the kill volume must put it back by itself); the rat climbs the vent
# shaft to the roof. No validator strikes, no errors.
# Usage: tests/integration/plant_cctv.sh   (GODOT=/path/to/godot to override the binary)
LEVEL=plant
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 40 70
start_bot sup supervisor SupervisorBot plant "" 70
start_bot rat rat RatBot plant "" 70
finish

expect "$RESULT" '"winner": "supervisors"'                         "result: the timer ran out, supervisors won"
expect "$LOGS/server.log" "SupervisorBot sat down at the CCTV"      "server: the supervisor sat down"
expect "$LOGS/server.log" "RatBot broke camera 1"                   "server: the rat broke camera 1"
expect "$LOGS/server.log" "SupervisorBot left the CCTV: stood up"   "server: the supervisor stood up"
expect "$LOGS/server.log" "SupervisorBot repaired camera 1"         "server: camera 1 repaired"
expect "$LOGS/sup.log" "watching the cameras"                       "supervisor: the CCTV view opened"
expect "$LOGS/sup.log" "the CCTV shows camera 1 broken"             "supervisor: saw the camera break"
expect "$LOGS/sup.log" "climbed the ladder to the vent roof"        "supervisor: climbed the ladder"
expect "$LOGS/sup.log" "out of bounds at"                           "supervisor: the kill volume caught it"
expect "$LOGS/sup.log" "back in bounds"                             "supervisor: back where it stood"
expect "$LOGS/rat.log" "camera break hold ended: completed"         "rat: broke the camera"
expect "$LOGS/rat.log" "climbed the shaft to the vent roof"         "rat: climbed the shaft"
common_checks
