#!/usr/bin/env bash
# A rat's tail spin (X): it smashes the traps within 1.5 m (a snap trap and a cheese lure side by
# side, neither goes off) but not one 2.5 m away; a spin during the cooldown, a supervisor's spin and
# a stunned rat's spin are refused; then the far trap is smashed too. Everyone's feed says a trap was
# smashed, but only the rat's client learns where. One supervisor bot, one rat bot.
# Usage: tests/integration/pvp_tailspin.sh   (GODOT=/path/to/godot to override the binary)
source "$(dirname "$0")/pvp_lib.sh"

start_server 2 60 90
start_bot supervisor supervisor SupervisorBot tailspin "" 90
start_bot rat rat RatBot tailspin "" 90
finish

expect "$LOGS/supervisor.log" "tail spin: 3 traps laid"                     "supervisor: a pair and a far trap laid"
expect "$LOGS/rat.log" "spinning by the pair: true"                          "rat: X spins"
expect "$LOGS/server.log" "RatBot spun its tail: smashed 2 trap\(s\)"         "server: the pair smashed"
expect "$LOGS/rat.log" "after the first spin: 1 trap\(s\) left, stunned false, revealed false" \
                                                                             "rat: the far trap stays, and the smashed ones never went off"
refute "$LOGS/server.log" "RatBot stepped on"                               "server: no trap went off"
refute "$LOGS/supervisor.log" "SNAP! A trap went off"                       "supervisor: no SNAP"
expect "$LOGS/server.log" "RatBot refused tail_spin: cooling down"          "server: a spin during the cooldown is refused"
expect "$LOGS/server.log" "SupervisorBot refused tail_spin: not a "         "server: supervisors have no tail"
expect "$LOGS/rat.log" "stunned, the client lets us spin: false"            "rat: no spin while stunned (client)"
expect "$LOGS/server.log" "RatBot refused tail_spin: can't act"             "server: no spin while stunned"
expect "$LOGS/rat.log" "spinning by the far trap: true"                      "rat: spins again after the cooldown"
expect "$LOGS/server.log" "RatBot spun its tail: smashed 1 trap\(s\) \(snap\)" "server: the far trap smashed"
expect "$LOGS/rat.log" "after the second spin: 0 trap\(s\) left"             "rat: every trap gone"
expect "$LOGS/supervisor.log" "tail spin: every trap smashed"               "supervisor: every trap gone"
# The feed: one line per trap, for everyone. Where: only for rats.
count "$LOGS/supervisor.log" "feed: tail_snap RatBot" 2                      "supervisor feed: 2 snap traps smashed"
count "$LOGS/supervisor.log" "feed: tail_lure RatBot" 1                      "supervisor feed: 1 cheese lure smashed"
count "$LOGS/rat.log" "feed: tail_(snap|lure) RatBot" 3                      "rat feed: 3 traps smashed"
expect "$LOGS/rat.log" "tail spin seen: RatBot, 2 smash position\(s\)"       "rat: told where the pair broke"
expect "$LOGS/rat.log" "tail spin seen: RatBot, 1 smash position\(s\)"       "rat: told where the far trap broke"
refute "$LOGS/supervisor.log" "tail spin seen: RatBot, [1-9]"                "supervisor: never told where"
count "$LOGS/supervisor.log" "tail spin seen: RatBot, 0 smash position\(s\)" 2 "supervisor: sees both spins"
common_checks
