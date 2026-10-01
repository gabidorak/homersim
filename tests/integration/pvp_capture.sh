#!/usr/bin/env bash
# M4 capture chain: a supervisor bot and two rat bots (victim, rescuer). Broom → stun → grab →
# carry → cage → the rescuer frees the victim → 2nd capture eliminates it → ghost chat → the
# rescuer is caged too → supervisors win because every rat is caught.
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
expect "$RESULT" 'eliminated VictimBot'                      "result: the victim was eliminated"
expect "$LOGS/server.log" "BONK! VictimBot is stunned"       "server: the broom stunned the victim"
expect "$LOGS/server.log" "SupervisorBot grabbed VictimBot"  "server: grab"
expect "$LOGS/server.log" "caged VictimBot \(capture 1\)"    "server: 1st capture cages"
expect "$LOGS/server.log" "RescuerBot freed VictimBot"       "server: the rescuer freed the victim"
expect "$LOGS/server.log" "caught VictimBot again: eliminated" "server: 2nd capture eliminates"
expect "$LOGS/server.log" "caged RescuerBot \(capture 1\)"   "server: the rescuer caged too"
expect "$LOGS/victim.log" "freed, invulnerable: true"        "victim: freed with invulnerability"
expect "$LOGS/victim.log" "eliminated, now a ghost"          "victim: became a ghost (spectator)"
expect "$LOGS/victim.log" "\(ghost\) VictimBot: boo from the other side" "victim: ghost chat works"
expect "$LOGS/victim.log" "\(ghost\) VictimBot: can the living hear me" "victim: ALL from a ghost goes to ghosts"
refute "$LOGS/rescuer.log" "\(ghost\)"                       "rescuer: never receives ghost chat"
refute "$LOGS/supervisor.log" "\(ghost\)"                    "supervisor: never receives ghost chat"
expect "$LOGS/victim.log" "\(team\) RescuerBot: hang on"     "victim: team chat from the rescuer"
refute "$LOGS/supervisor.log" "hang on"                      "supervisor: never receives rat team chat"
expect "$LOGS/rescuer.log" "free hold ended: completed"      "rescuer: the free hold completed"
common_checks
