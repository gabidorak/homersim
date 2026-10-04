#!/usr/bin/env bash
# M10 phase E, the CCTV: one supervisor bot (Cctv and FixCamera only) and one rat bot (BreakCamera
# only) placed by camera 8 in Main Hall West (--ai-scenario cctv). The plant is calm: the supervisor
# sits at the CCTV chair; the rat breaks the cameras near it (8, and 3 and 4 nearby); the supervisor
# sees them broken on its screens, stands up (a rat on camera, or after cctv_max_s) and repairs them.
# Usage: tests/integration/ai_cctv.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 150 --ai-only --ai-roles supervisor,rat --ai-goals supervisor:Cctv,supervisor:FixCamera,rat:BreakCamera \
	--ai-scenario cctv --test-duration 90 --ai-log
finish

expect "$LOGS/server.log" "sat down at the CCTV" "server: the supervisor bot sat at the CCTV"
expect "$LOGS/server.log" "stood up from the CCTV" "server: …and stood up again"
expect "$LOGS/server.log" "\[cctv\] .* broke camera" "server: the rat bot broke a camera"
expect "$LOGS/server.log" "\[cctv\] .* repaired camera" "server: the supervisor bot repaired one"
common_checks
