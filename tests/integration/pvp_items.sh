#!/usr/bin/env bash
# M4 items: steal → locked out of the keycard door → a stun drops the keycard → pick it up and
# open the door → steal again → snap trap, cheese lure → donut, trap refill → spare keycard
# after 30 s. One supervisor bot, one rat bot.
# Usage: tests/integration/pvp_items.sh   (GODOT=/path/to/godot to override the binary)
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 75 110
start_bot supervisor supervisor SupervisorBot items "" 110
start_bot rat rat RatBot items "" 110
finish

expect "$LOGS/server.log" "RatBot stole SupervisorBot's keycard"         "server: steal"
expect "$LOGS/server.log" "refused .*ReaderFront: not available"        "server: no keycard, no door"
expect "$LOGS/supervisor.log" "door open after pressing without a keycard: false" "supervisor: locked out"
expect "$LOGS/server.log" "RatBot dropped the keycard"                  "server: the stunned rat dropped it"
expect "$LOGS/supervisor.log" "keycard back: true"                      "supervisor: picked the keycard up"
expect "$LOGS/server.log" "BreakRoomKeycardDoor opened for 3 s"         "server: the keycard door opened"
count "$LOGS/server.log" "RatBot stole SupervisorBot's keycard" 2       "server: the second steal"
expect "$LOGS/server.log" "placed a Snap trap"                          "server: snap trap placed"
expect "$LOGS/server.log" "placed a Cheese lure"                        "server: cheese lure placed"
expect "$LOGS/server.log" "RatBot stepped on a snap trap"               "server: the snap trap went off"
expect "$LOGS/supervisor.log" "SNAP! A trap went off"                   "supervisor: heard the SNAP"
refute "$LOGS/rat.log" "SNAP! A trap went off"                          "rat: the SNAP is for supervisors only"
expect "$LOGS/rat.log" "lured: revealed true"                           "rat: revealed by the lure"
expect "$LOGS/supervisor.log" "donut: boosted true, speed x1.20"        "supervisor: donut rush"
expect "$LOGS/supervisor.log" "traps refilled: 3"                       "supervisor: trap refill"
expect "$LOGS/server.log" "refused .*SpareKeycard: not available"       "server: no spare keycard before 30 s"
expect "$LOGS/supervisor.log" "spare keycard taken: true"               "supervisor: spare keycard after 30 s"
expect "$RESULT" '"steals": 2'                                          "result: 2 steals"
common_checks
