#!/usr/bin/env bash
# M4 capture chain: a supervisor bot and two rat bots (victim, rescuer). Broom → stun → grab →
# carry → cage → the rescuer frees the victim → the 2nd capture cages it again (no elimination) →
# the rescuer is caged too → supervisors win because every rat is caught.
# Usage: tests/integration/pvp_capture.sh   (GODOT=/path/to/godot to override the binary)
source "$(dirname "$0")/pvp_lib.sh"

start_server 3 90 120
start_bot supervisor supervisor SupervisorBot capture "" 120
start_bot victim rat VictimBot capture victim 120
start_bot rescuer rat RescuerBot capture rescuer 120
finish

expect "$RESULT" '"winner": "supervisors"'                   "result: supervisors won"
expect "$RESULT" '"reason": "Every rat is caught"'           "result: by catching every rat"
expect "$RESULT" '"catches": 3'                              "result: 3 catches for the supervisor"
expect "$RESULT" '"frees": 1'                                "result: 1 free for the rescuer"
refute "$RESULT" 'eliminated VictimBot'                      "result: the victim was never eliminated"
expect "$LOGS/server.log" "BONK! VictimBot is stunned"       "server: the broom stunned the victim"
expect "$LOGS/server.log" "SupervisorBot grabbed VictimBot"  "server: grab"
expect "$LOGS/server.log" "caged VictimBot \(capture 1\)"    "server: 1st capture cages"
expect "$LOGS/server.log" "RescuerBot freed VictimBot"       "server: the rescuer freed the victim"
expect "$LOGS/server.log" "caged VictimBot \(capture 2\)"    "server: 2nd capture cages again"
refute "$LOGS/server.log" "again: eliminated"                "server: nobody eliminated"
expect "$LOGS/server.log" "caged RescuerBot \(capture 1\)"   "server: the rescuer caged too"
expect "$LOGS/victim.log" "freed, invulnerable: true"        "victim: freed with invulnerability"
expect "$LOGS/victim.log" "caged again, still in the match: true" "victim: caged again, not a ghost"
expect "$LOGS/victim.log" "\(team\) RescuerBot: hang on"     "victim: team chat from the rescuer"
refute "$LOGS/supervisor.log" "hang on"                      "supervisor: never receives rat team chat"
expect "$LOGS/rescuer.log" "free hold ended: completed"      "rescuer: the free hold completed"
common_checks
