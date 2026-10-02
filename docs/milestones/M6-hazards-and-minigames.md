# M6: Hazards & minigames

**Goal**: the plant fights back. Damaged subsystems spawn hazards that hit everyone, repairs become short skill minigames, and the Control Room gets its remote actions (emergency coolant, partial SCRAM).
**Estimated effort**: 2–3 weeks.
**Prerequisites**: M5.
**Design refs**: [GDD §4.4, §4.5, §6](../GDD.md#6-hazards), [ARCHITECTURE §4 Minigames, §6 HazardDirector](../ARCHITECTURE.md#minigames).

## 1. Tasks
### Hazards
- [x] `hazards/hazard.gd` (`class_name Hazard extends Area3D`): exported `subsystem_id`, `active` (synced), and a cycle config (`on_s`, `off_s`, `phase`). The cycle is derived from a synced `start_time` (server clock offset), so clients animate without per-frame sync. Server-only `_on_body_entered` / per-tick overlap → apply the effect through `StatusComponent` or `MovementComponent.apply_impulse`.
- [x] Server clock sync: on join the server sends its time, and the client stores an offset (ping/2 correction). This lives in `Net.server_time()`.
- [x] Hazards:
  - [x] `steam_jet/`: a cone `Area3D`, 3 s on / 3 s off, knockback 6 m/s + `STUNNED 1 s`, with steam particles and a hiss.
  - [x] `electric_puddle/`: 2 s live every 5 s → `STUNNED 1.5 s` then `SLOWED 0.5 × 2 s`. Sparks and a blue glow when live.
  - [x] `radiation_zone/`: exposure accumulates while inside; after 5 s → `SLOWED 0.8` while inside plus `REVEALED` while inside and for 5 s after. Green glow and Geiger clicks that scale with exposure.
  - [x] `debris/`: every 8 s a random spot in the Turbine Hall shows a 1 s warning decal → impact → supervisor `KNOCKED_DOWN`, rat `STUNNED 2 s`.
  - [x] `smoke/`: toggles a local `FogVolume` in the vents and the Control Room (visibility ≈ 6 m). It's cosmetic only, so the server doesn't need a check.
- [x] `server/hazard_director.gd`: subscribes to PlantSim health changes and sets `active` on each POI's hazard group (`hazard_<subsystem>`) when health < 50 (hysteresis: turn off at ≥ 60).
- [x] Unit test the hysteresis and cycle-phase math (pure helper functions).

### Minigames
- [x] `minigames/minigame.gd` (`class_name Minigame extends Control`): `start(seed: int, difficulty: float)`, `signal finished(success: bool)`. Escape cancels.
- [x] `client/MinigameHost.tscn`: an overlay that opens a minigame on `open_minigame(kind, seed)` from the server, releases the mouse, blocks movement input, and sends `request_minigame_result(success)`.
- [x] Server flow in `RepairPoint` (kind = `minigame`): start → remember `started_at` → result arrives → validate `elapsed ≥ min_duration` (3 s), the player is still in range and `can_act()` → success: +50 health; fail: +10 and a 3 s lockout. Interrupted (stunned, bitten) → closed on the client by `on_minigame_cancelled`.
- [x] Minigames (each about 4–6 s, mouse-only, readable at a glance):
  - [x] `wrench_rhythm/` (Pumps, Turbine): click when the moving marker is inside the green zone, 3 times in a row.
  - [x] `breaker_sequence/` (Grid, Ventilation): a seeded sequence of 4–5 breakers flashes; repeat it.
  - [x] `valve_rotate/` (Valves, Rods): drag in circles to turn the wheel to the target angle, then hold it for 1 s.
- [x] Keep the hold repair as an accessibility option (settings toggle in M8); the server accepts both, and the hold variant gives +35.

### Control room actions
- [x] `interactables/console_action/console_action.gd`: supervisor-only instant interactions with cooldowns synced to their screen.
  - [x] Emergency coolant: requires grid health ≥ 25, `core_temp −150`, 90 s cooldown.
  - [x] Partial SCRAM: `scram_until = now + 30`, heat ×0.5, **+30 s on the match timer**, 120 s cooldown. A big red button under a flip cover (2-step interaction).
- [x] Alarm state hooks: lighting colour, rotating beacons, music layer (placeholder until M7), and HUD flash.

## 2. Done when
- [x] Damaging pumps to below 50 visibly and audibly activates the steam jets, which knock back **both** teams. Repairing to ≥ 60 turns them off. *(`tests/integration/hazards.sh`; visuals checked with `tests/helpers/HazardTour.tscn` screenshots. The hiss is only checked by ear in a real game.)*
- [ ] All 3 minigames work at 100 ms latency, and a hacked "instant success" result is rejected by the duration check. *(The hack is rejected in `tests/integration/minigames.sh`, and all 3 minigames win there on localhost. Still to do: a run under `tc netem` 100 ms.)*
- [x] Emergency coolant and SCRAM work, show their cooldowns on the Control Room screens, and the SCRAM timer penalty shows on the HUD. *(`tests/integration/control_room.sh`.)*
- [ ] A playtest confirms the hazards are funny rather than frustrating (adjust the stun durations in data if needed). Notes are written.

## Notes from the implementation
- Hazards are static nodes in the generated level (`tools/map/gen_plant.py`: `STEAM_JETS`, `PUDDLES`, `RADIATION`, `DEBRIS`, `SMOKE`), not spawned: they never come and go, and a static node's synchronizer reaches late joiners too.
- One normal sabotage leaves a subsystem at exactly 50, which is not *below* 50: its hazards need a second sabotage (or a critical one). That follows the GDD; revisit after the playtest if hazards show up too rarely.
- `tests/helpers/HazardTour.tscn` (windowed) screenshots every hazard live, the consoles, the smoke and the three minigame overlays.

## 3. Pitfalls
- Hazard knockback is a server → owner `apply_impulse` RPC, so the validator's grace window must allow it.
- Don't run hazard overlap checks on clients. Clients just visualise.
- Minigames must work at any window size (use anchors/containers), and must not depend on frame rate.
