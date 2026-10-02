#!/usr/bin/env bash
# M6 hazards test, on the plant: the rat sabotages the pumps to 50 (not below 50: no jets), the
# supervisor breaks them to 30 (test hook): the steam jets switch on and knock back both teams; a
# repair to 65 switches them off. Then a live puddle stuns and slows the rat, the radiation zone
# reveals and slows it after 5 s, falling debris knocks the supervisor down, and smoke fills the
# Control Room. No validator strikes (the knockback is server-imposed), no errors.
# Usage: tests/integration/hazards.sh   (GODOT=/path/to/godot to override the binary)
LEVEL=plant
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 75 100
start_bot sup supervisor SupervisorBot hazards "" 100
start_bot rat rat RatBot hazards "" 100
finish

S="$LOGS/server.log"
expect "$S" "sabotage pumps by RatBot: health 100 -> 50"         "server: pumps sabotaged to 50"
expect "$LOGS/sup.log" "pumps at 50%, jets active: false"          "supervisor: no jets at exactly 50%"
expect "$S" "pumps hazards ON"                                     "server: pump hazards on below 50"
expect "$LOGS/sup.log" "the pump jets are on"                      "supervisor: saw the jets switch on"
expect "$S" "PumpHouse/SteamJet hit RatBot"                        "server: a jet hit the rat"
expect "$S" "PumpHouse/SteamJet3 hit SupervisorBot"                "server: a jet hit the supervisor (both teams)"
expect "$LOGS/rat.log" "steam jet: stunned and pushed [1-9]"        "rat: knocked back at least 1 m"
expect "$LOGS/sup.log" "steam jet: stunned and pushed [1-9]"        "supervisor: knocked back at least 1 m"
expect "$S" "repair pumps by SupervisorBot: health 30 -> 65"       "server: hold repair to 65"
expect "$S" "pumps hazards off"                                    "server: pump hazards off at 60+"
expect "$LOGS/sup.log" "the pump jets are off at 65%"              "supervisor: saw the jets switch off"
expect "$S" "grid hazards ON"                                      "server: puddles on"
expect "$S" "Substation/ElectricPuddle hit RatBot"                 "server: the puddle zapped the rat"
expect "$LOGS/rat.log" "puddle: after the stun, slowed true \(x0.50\)" "rat: slowed to 50% after the stun"
expect "$S" "ReactorHall/RadiationZone hit RatBot"                 "server: the radiation got the rat"
expect "$LOGS/rat.log" "radiation: revealed after [4-6]\.[0-9] s, speed x0.80" "rat: revealed and slowed after 5 s"
expect "$LOGS/rat.log" "outside the radiation: still revealed true" "rat: still revealed after leaving"
expect "$S" "TurbineHall/DebrisZone hit SupervisorBot"             "server: debris hit the supervisor"
expect "$LOGS/sup.log" "debris: knocked down"                      "supervisor: knocked down by debris"
expect "$S" "ventilation hazards ON"                               "server: smoke on"
expect "$LOGS/sup.log" "smoke in the Control Room: true"           "supervisor: the smoke is synced"
expect "$RESULT" '"hazard_hits": [1-9]'                            "result: hazard hits in the stats"
common_checks
