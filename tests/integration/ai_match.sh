#!/usr/bin/env bash
# M10 phase D, a whole bots-only match: --ai-only --ai-fill 6 (2 supervisor bots, 4 rat bots) for
# 150 s. Checks: the rats sabotage and the supervisors repair, every bot never caught walks more than
# 100 m, no bot stalls (wants to move but can't) for more than 8 s or gets hard stuck, no validator
# strikes, no errors. Since phase E supervisor bots catch rats: a match the supervisors win early by
# catching every rat must show the 4 catches instead (no sabotage, repair or 100 m needed). Thresholds
# are loose on purpose: loop it with different seeds (SEED=N).
# Usage: tests/integration/ai_match.sh   (SEED=N, GODOT=/path/to/godot)
source "$(dirname "$0")/ai_lib.sh"

start_server 240 --ai-only --ai-fill 6 --test-duration 150
finish

check "len(d['ai']['bots']) == 6" "result: 6 bots"
if python3 -c "import json,sys; d=json.load(open('$RESULT')); sys.exit(0 if d.get('reason') == 'Every rat is caught' else 1)" 2>/dev/null; then
	echo "     (the supervisors caught every rat early)"
	check "sum(s['catches'] for s in d['stats']) >= 4" "result: 4 catches"
else
	check "any(e.startswith('sabotage ') for e in d['events'])" "result: the rats sabotaged"
	check "any(e.startswith('repair ') or e.startswith('reboot ') for e in d['events'])" "result: the supervisors repaired"
	check "sum(s['sabotages'] for s in d['stats']) >= 1 and sum(s['repairs'] for s in d['stats']) >= 1" "result: in the stats"
	check "all(b['distance'] > 100 for b in d['ai']['bots'] if not any(s['name'] == b['name'] and s['caught'] for s in d['stats']))" \
		"result: every bot never caught walked more than 100 m"
fi
check "all(b['max_stall_s'] <= 8 for b in d['ai']['bots'])" "result: no bot stalled more than 8 s"
check "all(b['stuck_hard'] == 0 for b in d['ai']['bots'])" "result: nobody hard stuck"
check "all(s['bot'] for s in d['stats'])" "result: every stats row is a bot"
python3 -c "
import json; d = json.load(open('$RESULT'))
print('  ', d.get('winner'), '-', d.get('reason'), '- meltdown', d.get('meltdown'))
for b in d['ai']['bots']:
    print('   %-14s %-10s %6.0f m  stall %4.1f s  path failures %3d  %.3f ms/tick  %s' % (b['name'], b['role'], b['distance'], b['max_stall_s'], b['path_failures'], b['ms_per_tick'], b['goals']))
" 2>/dev/null
common_checks
