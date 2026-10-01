#!/usr/bin/env bash
# M4 "hacked client": a supervisor bot and a rat bot send raw request_* RPCs with the wrong role,
# bad arguments, out of range or during a cooldown. The server must refuse every one of them and
# nothing may happen to anyone.
# Usage: tests/integration/pvp_hack.sh   (GODOT=/path/to/godot to override the binary)
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 20 60
start_bot supervisor supervisor SupervisorBot hack "" 60
start_bot rat rat RatBot hack "" 60
finish

S="$LOGS/server.log"
expect "$S" "SupervisorBot refused bite: not a Supervisor ability"   "supervisor can't bite"
expect "$S" "SupervisorBot refused laser: not a Supervisor ability"  "unknown ability"
expect "$S" "SupervisorBot refused snap_trap: traps are placed with" "traps aren't 'used'"
count "$S" "SupervisorBot refused broom: cooling down" 2             "broom spam: 2 of 3 refused"
expect "$S" "SupervisorBot swung the broom: missed"                  "the one allowed swing hit nobody"
expect "$S" "refused to place broom .*not a trap"                    "not a trap"
expect "$S" "refused to place snap_trap .*too far"                   "trap too far"
expect "$S" "refused to place snap_trap .*not on a floor"            "trap in the air"
expect "$S" "refused to place snap_trap .*bad position"              "trap at NaN"
count "$S" "SupervisorBot placed a Snap trap" 3                      "3 traps, then out of charges"
expect "$S" "refused to place snap_trap .*no charges"                "no 4th trap"
expect "$S" "SupervisorBot refused .*GrabHandle"                     "can't grab a rat that isn't stunned"
expect "$S" "SupervisorBot refused .*CageA"                          "can't cage without a rat"
expect "$S" "SupervisorBot refused .*MatchManager: no such interactable" "not an interactable"
expect "$S" "refused SupervisorBot's message on channel 2"           "the living can't use the ghost chat"
expect "$S" "RatBot refused broom: not a Rat ability"                "rat can't use the broom"
expect "$S" "RatBot bit the air"                                     "a bite out of range hits nothing"
expect "$S" "RatBot refused bite: cooling down"                      "bite cooldown"
expect "$S" "RatBot refused to place snap_trap .*not a trap of this role" "rats can't place traps"
expect "$S" "RatBot refused .*StealHandle: too far"                  "steal from far away"
expect "$S" "RatBot refused .*StealHandle: not available"            "steal while the supervisor faces you"
expect "$S" "RatBot refused .*CageA"                                 "free an empty cage"
expect "$S" "refused RatBot's message on channel 2"                  "rats can't use the ghost chat"
refute "$S" "stunned|stole|grabbed|caged|KNOCKED|slowed"             "nothing happened to anyone"
expect "$RESULT" '"winner": "supervisors"'                           "the match ran to the timer"
common_checks
