#!/usr/bin/env bash
# M6 repair minigames, on the plant: the supervisor wins the wrench minigame on the pumps (+50),
# a hacked instant win on the valves is refused (too fast) and jams the point, an honest valve
# game then wins (+50), a lost breaker game on the grid gives +10 and jams, and walking away closes
# an open game, and so does a bite. The minigames run in the real overlay (MinigameHost) and play themselves (autoplay).
# Usage: tests/integration/minigames.sh   (GODOT=/path/to/godot to override the binary)
LEVEL=plant
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 60 90
start_bot sup supervisor SupervisorBot minigame "" 90
start_bot rat rat RatBot minigame "" 90
finish

S="$LOGS/server.log"
expect "$S" "SupervisorBot started the wrench_rhythm minigame at CoolantPumps/RepairPoint" "server: wrench minigame opened"
expect "$LOGS/sup.log" "minigame open: WrenchRhythm"                 "supervisor: the overlay shows the wrench game"
expect "$S" "SupervisorBot won the wrench_rhythm minigame in [3-9]\." "server: won after at least 3 s"
expect "$S" "repair pumps by SupervisorBot: health 50 -> 100"      "server: the win gave +50"
expect "$S" "rejected SupervisorBot's minigame win: too fast"      "server: the instant win was refused"
expect "$LOGS/sup.log" "after the hack: valves 40%, jammed true, overlay open false" "supervisor: no repair, jammed, closed"
expect "$S" "sent a minigame result with no minigame open"         "server: a result without a game is ignored"
expect "$LOGS/sup.log" "repair prompt while jammed: Coolant valves jammed" "supervisor: the prompt shows the jam"
expect "$S" "SupervisorBot won the valve_rotate minigame"          "server: the honest valve game won"
expect "$S" "repair valves by SupervisorBot: health 40 -> 90"      "server: +50 on the valves"
expect "$S" "SupervisorBot lost the breaker_sequence minigame"     "server: the breaker game was lost"
expect "$S" "repair grid by SupervisorBot: health 40 -> 50"        "server: a loss still gives +10"
expect "$LOGS/sup.log" "grid after the lost minigame: 50%, jammed true" "supervisor: jammed after the loss"
expect "$S" "SupervisorBot's minigame ended: moved"                "server: walking away closed the game"
expect "$LOGS/sup.log" "walked away: the minigame closed"          "supervisor: the overlay closed"
expect "$S" "SupervisorBot's minigame ended: bitten"               "server: a bite closed the game"
expect "$LOGS/sup.log" "bitten: the minigame closed"               "supervisor: the overlay closed after the bite"
common_checks
