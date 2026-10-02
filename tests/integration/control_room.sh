#!/usr/bin/env bash
# M6 Control Room actions, on the plant: emergency coolant is refused without grid power, then
# drops the core by 150 and goes on cooldown; SCRAM takes two presses (cover, button), adds 30 s to
# the match timer, halves the heat, and is then on cooldown.
# Usage: tests/integration/control_room.sh   (GODOT=/path/to/godot to override the binary)
LEVEL=plant
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 20 70
start_bot sup supervisor SupervisorBot control "" 70
start_bot rat rat RatBot control "" 70
finish

S="$LOGS/server.log"
expect "$LOGS/sup.log" "coolant prompt without power: No power"     "supervisor: the prompt says no power"
expect "$S" "SupervisorBot refused ControlRoom/ConsoleCoolant: not available" "server: no coolant without power"
expect "$S" "emergency coolant: core 6[0-9][0-9] -> [45][0-9][0-9]"   "server: core −150"
expect "$S" "SupervisorBot used the emergency coolant"              "server: coolant used"
expect "$LOGS/sup.log" "coolant used: core [0-9]+, cooldown (89|90) s" "supervisor: the cooldown is synced"
count "$S" "SupervisorBot refused ControlRoom/ConsoleCoolant: not available" 2 "server: coolant refused again on cooldown"
expect "$S" "SupervisorBot lifted the SCRAM cover"                  "server: first press lifts the cover"
expect "$LOGS/sup.log" "SCRAM cover open, prompt: SCRAM!"           "supervisor: the prompt changed"
expect "$S" "SupervisorBot pressed SCRAM"                           "server: second press fires"
expect "$S" "SCRAM for 30 s"                                        "server: SCRAM for 30 s"
expect "$S" "timer \+30 s"                                          "server: +30 s on the timer"
expect "$LOGS/sup.log" "SCRAM active (29|30) s, timer [0-9]+ -> [0-9]+ \(\+30\)" "supervisor: SCRAM and the penalty synced"
expect "$S" "SupervisorBot refused ControlRoom/ConsoleScram: not available" "server: SCRAM on cooldown"
expect "$LOGS/sup.log" "SCRAM cooldown 1[12][0-9] s"                "supervisor: the SCRAM cooldown"
expect "$RESULT" '"timer \+30 s"'                                   "result: the penalty is in the events"
common_checks
