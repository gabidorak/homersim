# M3: First playable loop ⭐

**Goal**: the complete game loop in the test arena. Rats sabotage six stations, core temperature rises, supervisors repair, and the match ends with a winner when the timer runs out or meltdown hits 100%. **This is the first milestone to playtest with friends.** If it isn't fun yet with capsules, iterate here before adding content.
**Estimated effort**: 2 weeks.
**Prerequisites**: M2.
**Design refs**: [GDD §2, §4](../GDD.md#4-plant-simulation), [ARCHITECTURE §3 Intent RPCs, §4 Interactables, §6](../ARCHITECTURE.md#intent-rpcs-client--server).

## 1. Tasks
> Implemented on 2026-10-01. Notes on what differs from the plan are in *italics* under each task.
### Plant model (pure logic, test-first)
- [x] `data/subsystem_data.gd` (`SubsystemData`: `id`, `display_name`, `heat_weight`, `critical`, `hazard_kind`, `icon`) plus six `.tres` files in `data/subsystems/`.
- [x] `data/plant_tuning.gd` + `.tres`: cooling rate, nominal/min/max temp, warning/critical thresholds, meltdown fill/decay rates, sabotage damage (normal/critical), sabotage cooldown, hold repair amount, reboot time.
- [x] `common/plant_model.gd` (`RefCounted`): `healths`, `core_temp`, `meltdown`, `cooldowns`, `scram_until`; `tick(dt, now)`, `apply_damage(id, amount, now)`, `apply_repair(id, amount)`, `needs_reboot(id)`, `alarm_state()`.
- [x] `tests/unit/test_plant_model.gd`:
  - all healthy → temp stays at 300, meltdown 0
  - rods + pumps + valves at 0 → temp reaches 700 in 67 s ± 2 (GDD worked check)
  - meltdown only rises above 700 and decays below 400
  - sabotage cooldown blocks a second sabotage for 20 s
  - repair is clamped to 100, and health 0 requires a reboot
  - *also: meltdown rate at 800, cap at 100, alarm thresholds, SCRAM, reset. `tests/unit/test_match_winner.gd` covers `check_winner`.*
- [x] `common/plant_sim.gd`: a node wrapping the model. 10 Hz `Timer` tick on the server only. Synced properties are copied from the model after each tick (`PlantSync`, 0.2 s interval). Emits `Events.plant_alarm_changed` on clients when the alarm changes.
  - *Subsystems are addressed by index (the order in `plant_tuning.tres`). Cooldowns sync as seconds left; "needs a reboot" syncs as the `offline_mask` bitmask.*

### Interaction framework
- [x] `interactables/interactable.gd` (see ARCHITECTURE §4): `allowed_roles`, `kind`, `duration_s`, `prompt`, `reach` (default 1.8 m supervisor / 1.0 m rat), server-side `holders: Dictionary[int, float]` (peer → progress). Synced `progress` for the progress ring.
- [x] `components/interactor/interactor_component.gd` (local player): find the best target (a ray from the camera for the supervisor; for the rat, the nearest interactable in a front cone within reach), show the prompt, hold E → `request_interact_start`, heartbeat every 0.25 s, release → `request_interact_stop`.
- [x] `common/interaction_service.gd`: `request_interact_start/heartbeat/stop` handlers with full validation (role, `status.can_act()`, distance ≤ reach + 0.75 m, LOS raycast, interactable `can_interact`). Server `_physics_process` advances progress, cancels on timeout, movement over 0.5 m, or status change.
  - *Heartbeats are reliable with a 1 s timeout (unreliable ones were sometimes dropped in tests). The server tells the client about every end of a hold it didn't ask for (`on_hold_ended`); a rate limit of 20 requests/s per peer applies.*
- [x] `interactables/sabotage_point/sabotage_point.gd`: rat-only, hold 4 s → `PlantSim.apply_damage(id, 50)`. Disabled while on cooldown (with a visual: sparks placeholder plus a red light).
- [x] `interactables/critical_lever/critical_lever.gd`: paired via an exported NodePath. It completes only when both levers are held at the same time for 6 s (progress pauses if either is released).
- [x] `interactables/repair_point/repair_point.gd`: supervisor-only, hold 6 s → +35. If health is 0 → a "Reboot" hold of 3 s first.
- [x] Place in TestArena: 6 stations (each with 2 sabotage points or 1 lever pair, plus 1 repair point), spread about 15–25 m apart, with name labels.

### Match end
- [x] `match_rules_model.gd`: `check_winner(state) -> Team` (none / supervisors / rats), with the GDD priority order. Unit tests.
- [x] `MatchManager`: add `PLAYING` (timer: `duration_s` or `duration_single_supervisor_s`) and `POST_MATCH` (15 s) → back to `LOBBY` (despawn, keep the roster). Mid-match disconnect: if a team is empty, the other team wins.
- [x] Stats collected on the server: sabotages and repairs per player.

### HUD (`client/HUD.tscn`)
- [x] Timer (top centre), meltdown bar, core temperature gauge (colour by alarm), 6 subsystem icons with health fill and cooldown overlay, interaction prompt plus radial progress ring, stamina bar.
- [x] `client/PostMatch.tscn`: winner banner + a stats table.
  - *Subsystem "icons" are drawn boxes with a short name (ROD, PMP…) until real icons arrive in M7; the beep is generated in code.*
- [x] Alarm feedback: screen-edge tint and a placeholder beep on the WARNING/CRITICAL transitions.

### Automated integration test
- [x] `tests/helpers/bot_client.gd`: a scene that connects, sends `request_join` and ready, then (as a rat) teleports via debug RPC next to a sabotage point and holds interact. The debug RPC only exists when `OS.is_debug_build()` and the server was started with `--allow-debug`.
- [x] `tests/integration/run_match_loop.sh`: start **separate processes** (simpler than several MultiplayerAPIs in one process): a headless server with `--port <random> --debug-start --allow-debug --test-duration 20 --exit-after-match --result-file /tmp/result.json`, plus 2 headless bot clients (`--bot rat`, `--bot supervisor`). The script waits for the server to exit, then checks that the exit code is 0 and that the result JSON says states went COUNTDOWN → PLAYING → POST_MATCH, the sabotage reduced health, and the winner was the supervisors. It fails if any log contains `ERROR` or `SCRIPT ERROR`. CI runs this script.
  - *The bots are started with `--bot rat --connect …`. The test uses the ready vote (`min_players=2` in a temp server.cfg) instead of `--debug-start`, which would start the match before the bots' role preferences arrive. The match lasts 25 s, so the rat also tests an early release and a step aside (both must cancel) and the supervisor has time to repair. Bots also check that the interactor's own targeting finds the target. Extra: `tests/integration/critical_lever.sh` (2 rats on a lever pair, then a reboot and repairs).*

## 2. Done when
- [ ] With 4 human players: a full 9-minute match is playable start to finish and ends with the correct winner, and the next match can start from the lobby.
- [ ] Rats can win if they coordinate. Supervisors can win if they patrol. **Record the first playtest notes** in `docs/playtests/YYYY-MM-DD.md` (what was fun, what was boring, the balance numbers changed).
- [ ] Unit and integration tests pass in CI.
- [x] Interrupting a hold (walking away, releasing E, getting disconnected) always cancels the progress cleanly on the server.
  - *Releasing and stepping aside are checked by `run_match_loop.sh`. A killed client was checked by hand: its hold ends by heartbeat timeout within 1 s, then the empty team loses. A clean leave goes through `player_removed`.*

## 3. Pitfalls
- Don't let clients send "I finished the sabotage". The **server** owns progress.
- Use the server's time (`Time.get_ticks_msec()` on the server) for cooldowns, and sync remaining durations rather than absolute client times.
- Sync `PackedFloat32Array` as a whole property. Synchronizers don't sync individual elements of an array that is changed in place, so reassign it.
- Don't over-tune balance at this stage. Make sure everything is driven from `.tres` so it's easy later.
