# M2: Roles & controllers

**Goal**: a lobby where players pick a role preference and ready up. The server assigns teams with the balance table, counts down and spawns each role. Supervisors play in first person, rats in third person with vents. Basic text chat for playtests.
**Estimated effort**: 2 weeks.
**Prerequisites**: M1.
**Design refs**: [GDD §2, §3, §5](../GDD.md#2-teams-and-win-conditions), [ARCHITECTURE §4, §6, §7](../ARCHITECTURE.md#4-scene-and-node-structure).

## 1. Tasks
### Data
- [x] `common/role.gd`: `class_name Role`, `enum Kind { NONE, SUPERVISOR, RAT, SPECTATOR }`.
- [x] `data/role_data.gd` (`class_name RoleData extends Resource`): `kind`, `height`, `radius`, `walk_speed`, `sprint_speed`, `stamina_s`, `stamina_regen_s`, `jump_height`, `can_use_vents`, `visual_scene`, `camera_kind`. (Also `stamina_regen_delay_s`, which the GDD's "after a 1 s delay" needs.)
- [x] `data/roles/supervisor.tres`, `data/roles/rat.tres` with the GDD §5 values. Plus `data/roles/lobby.tres` (role `NONE`) for the pre-match bodies: supervisor-sized, first person, tinted per player.
- [x] `data/match_rules.gd` + `data/match_rules.tres` (duration, countdown, post-match, min players, team table). Any key can be overridden in `server.cfg` `[match]` (`Config.load_match_rules`).

### Match flow (lobby → countdown)
- [x] `common/match_rules_model.gd` (`RefCounted`, pure): `assign_roles(prefs: Dictionary[int, Role.Kind], rules) -> Dictionary[int, Role.Kind]`. Honour preferences where possible, then fill from the balance table. Seed the RNG so it can be tested.
- [x] `tests/unit/test_role_assignment.gd`: every player count from 2 to 6, all-"Any", all-"Rat", all-"Supervisor", mixed.
- [x] `common/match_manager.gd`: states `LOBBY, ROLE_ASSIGN, COUNTDOWN` (PLAYING arrives in M3; for now, after the countdown, just unfreeze). Ready vote. `--debug-start [N]` skips the vote and starts once N players (default 1) have joined. Synced: `state`, `countdown_left`, `roster` (peer → name, role pref, ready, role).
- [x] Lobby UI (`client/Lobby.tscn`, inside `ClientOnly`): roster list, role preference buttons, Ready toggle. Requests: `request_set_pref`, `request_set_ready`.
- [x] Spawn by role: `SpawnPoint` markers with an exported `role` (Supervisors → Break Room area of TestArena, Rats → "nest" corner). The server despawns lobby bodies and respawns them with roles at COUNTDOWN. Frozen until the countdown ends. *Implemented with the `LOCKED` status, applied in the spawn function on every peer, so the body is frozen from its very first frame (an RPC sent after the spawn could arrive late). `set_locked` exists for later server-imposed freezes.*

### Controllers
- [x] `MovementComponent` reads `RoleData` and applies status speed modifiers (stub for now: `speed_multiplier = 1.0`). It handles sprint plus stamina, jump height → velocity (`sqrt(2 * g * h)`), coyote time 0.1 s, jump buffer 0.1 s.
- [x] Supervisor: `components/camera/first_person_rig.gd`, with head bob (toggle), FOV setting, and a simple FP arms placeholder (a box "broom").
- [x] Rat: `components/camera/third_person_rig.gd`, using a `SpringArm3D` (length 2.5 m, collision mask = world) for orbit with the mouse. The rat body rotates toward its movement direction. Camera shoulder offset, and the camera pulls closer in vents.
- [x] **Vents**: `interactables/vent/vent_volume.gd` (an `Area3D` marking rat-only space) plus physical 0.7 m openings. Supervisors physically can't fit (capsule radius 0.35 → 0.7 m width; make openings 0.6 m high so the supervisor's height also blocks). *TestArena: the purple tunnel (5 m long) plus the two vents in the Rat Nest walls. The nest is walled in, so rats leave it through the vents.* The server's `MovementValidator` also flags a supervisor inside a `VentVolume`.
- [x] Placeholder visuals: supervisor = tall yellow capsule with a hard-hat cylinder; rat = small grey capsule plus 2 sphere ears and a cylinder tail.

### Status and validation (skeletons)
- [x] `components/status/status_component.gd`: a dictionary of status → expiry time, `apply(status, duration)` (server), `has(status)`, plus `speed_multiplier()` and `can_act()`. Replicated by `StatusSync` (authority 1). Only `LOCKED` is used in M2.
- [x] `components/movement/movement_component.gd` RPCs from the server: `set_locked(bool)`, `force_position(Vector3)`, `apply_impulse(Vector3)`.
- [x] `server/movement_validator.gd` v1: speed check per role (with a grace window after impulses and teleports), vent check, strike counter, logs only (no kicks yet). *It checks every 0.25 s rather than every tick, because BodySync packets arrive in bursts. Every freshly spawned body gets a 1 s grace window, because a respawn reuses the node path and the owner's last packets for the old body can land on the new one.*

### Chat (basic)
- [x] `common/chat_service.gd`: `request_send(text, channel)` → the server validates (length ≤ 200, 1 msg/s, strips `[`/`]`) → `on_message(from_name, text, channel)` to the recipients. Channels: `ALL` (now), `TEAM` and `GHOST` (M4).
- [x] `client/Chat.tscn`: log + LineEdit. Enter to open; while open, gameplay input is blocked.

## 2. Done when
- [x] 4 clients join, pick preferences and ready up → the countdown runs → 1 supervisor and 3 rats spawn in the correct areas, frozen during the countdown.
- [ ] The supervisor's FP controller feels responsive. The rat's TP camera never clips through walls, and rats can go through the 0.7 m tunnel while supervisors can't.
- [ ] Sprint drains and regenerates stamina (a temporary stamina bar on the HUD is OK).
- [x] Hacked or oversized movement (temporarily set a client's speed ×3 in debug) is logged by the validator.
- [x] Chat works between all clients, and spam is rate-limited.
- [x] The role assignment unit tests pass in CI.

The ticked items are checked automatically by `tests/integration/lobby_smoke.sh`: 4 headless clients use the test-only flags `--pref`, `--auto-ready`, `--say`, `--auto-move` and `--debug-speed 3`, plus a late joiner and an abort back to the lobby. The spawn areas were checked on screenshots (`--screenshot`). The role assignment tests pass locally and run in CI on the next push. The unticked items are about feel and need a human with a mouse: run `SERVER_ARGS="--debug-start 2" tools/dev/run_local.sh 2`, or see the manual test below.

## Manual test
```bash
godot --headless -- --server --debug-start 2 &       # skip the vote: start once 2 players joined
godot -- --connect 127.0.0.1:7777 --name Sup --pref supervisor &
godot -- --connect 127.0.0.1:7777 --name Rat --pref rat &
```
- Supervisor: walk to the purple tunnel (west of the centre) and try to enter: blocked. Sprint (Shift) until the bar turns red, then watch it refill after 1 s.
- Rat: leave the nest through a wall vent, run through the tunnel, and orbit the camera against walls (the spring arm should pull in). Jump onto the 1 m crates.
- Speed hack: add `--debug-speed 3` to a client and walk around; the server prints `[validator] strike N …`.

## 3. Pitfalls
- `SpringArm3D` should exclude the player's own collider (`add_excluded_object(player.get_rid())`).
- Keep **one** `Player.tscn` with role-specific children instanced at spawn. Don't make two player scenes with diverging code.
- Small rat capsules and stairs: use `floor_snap_length` around 0.3 and ramps or low steps (≤ 0.25 m), or the rat gets stuck.
- Mouse sensitivity must be independent of FPS (use `event.relative`, not `delta`).
