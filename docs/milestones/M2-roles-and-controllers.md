# M2: Roles & controllers

**Goal**: a lobby where players pick a role preference and ready up. The server assigns teams with the balance table, counts down and spawns each role. Supervisors play in first person, rats in third person with vents. Basic text chat for playtests.
**Estimated effort**: 2 weeks.
**Prerequisites**: M1.
**Design refs**: [GDD §2, §3, §5](../GDD.md#2-teams-and-win-conditions), [ARCHITECTURE §4, §6, §7](../ARCHITECTURE.md#4-scene-and-node-structure).

## 1. Tasks
### Data
- [ ] `common/role.gd`: `class_name Role`, `enum Kind { NONE, SUPERVISOR, RAT, SPECTATOR }`.
- [ ] `data/role_data.gd` (`class_name RoleData extends Resource`): `kind`, `height`, `radius`, `walk_speed`, `sprint_speed`, `stamina_s`, `stamina_regen_s`, `jump_height`, `can_use_vents`, `visual_scene`, `camera_kind`.
- [ ] `data/roles/supervisor.tres`, `data/roles/rat.tres` with the GDD §5 values.
- [ ] `data/match_rules.gd` + `data/match_rules.tres` (duration, countdown, post-match, min players, team table).

### Match flow (lobby → countdown)
- [ ] `common/match_rules_model.gd` (`RefCounted`, pure): `assign_roles(prefs: Dictionary[int, Role.Kind], rules) -> Dictionary[int, Role.Kind]`. Honour preferences where possible, then fill from the balance table. Seed the RNG so it can be tested.
- [ ] `tests/unit/test_role_assignment.gd`: every player count from 2 to 6, all-"Any", all-"Rat", all-"Supervisor", mixed.
- [ ] `common/match_manager.gd`: states `LOBBY, ROLE_ASSIGN, COUNTDOWN` (PLAYING arrives in M3; for now, after the countdown, just unfreeze). Ready vote. `--debug-start` skips the vote. Synced: `state`, `countdown_left`, `roster` (peer → name, role pref, ready, role).
- [ ] Lobby UI (`client/Lobby.tscn`, inside `ClientOnly`): roster list, role preference buttons, Ready toggle. Requests: `request_set_pref`, `request_set_ready`.
- [ ] Spawn by role: `SpawnPoint` markers with an exported `role` (Supervisors → Break Room area of TestArena, Rats → "nest" corner). The server despawns lobby bodies and respawns them with roles at COUNTDOWN. Frozen via `set_locked(true)` until the countdown ends.

### Controllers
- [ ] `MovementComponent` reads `RoleData` and applies status speed modifiers (stub for now: `speed_multiplier = 1.0`). It handles sprint plus stamina, jump height → velocity (`sqrt(2 * g * h)`), coyote time 0.1 s, jump buffer 0.1 s.
- [ ] Supervisor: `components/camera/first_person_rig.gd`, with head bob (toggle), FOV setting, and a simple FP arms placeholder (a box "broom").
- [ ] Rat: `components/camera/third_person_rig.gd`, using a `SpringArm3D` (length 2.5 m, collision mask = world) for orbit with the mouse. The rat body rotates toward its movement direction. Camera shoulder offset, and the camera pulls closer in vents.
- [ ] **Vents**: `interactables/vent/vent_volume.gd` (an `Area3D` marking rat-only space) plus physical 0.7 m openings. Supervisors physically can't fit (capsule radius 0.35 → 0.7 m width; make openings 0.6 m high so the supervisor's height also blocks). The server's `MovementValidator` also flags a supervisor inside a `VentVolume`.
- [ ] Placeholder visuals: supervisor = tall yellow capsule with a hard-hat cylinder; rat = small grey capsule plus 2 sphere ears and a cylinder tail.

### Status and validation (skeletons)
- [ ] `components/status/status_component.gd`: a dictionary of status → expiry time, `apply(status, duration)` (server), `has(status)`, plus `speed_multiplier()` and `can_act()`. Replicated by `StatusSync` (authority 1). Only `LOCKED` is used in M2.
- [ ] `components/movement/movement_component.gd` RPCs from the server: `set_locked(bool)`, `force_position(Vector3)`, `apply_impulse(Vector3)`.
- [ ] `server/movement_validator.gd` v1: speed check per role (with a grace window after impulses and teleports), vent check, strike counter, logs only (no kicks yet).

### Chat (basic)
- [ ] `common/chat_service.gd`: `request_send(text, channel)` → the server validates (length ≤ 200, 1 msg/s, strips `[`/`]`) → `on_message(from_name, text, channel)` to the recipients. Channels: `ALL` (now), `TEAM` and `GHOST` (M4).
- [ ] `client/Chat.tscn`: log + LineEdit. Enter to open; while open, gameplay input is blocked.

## 2. Done when
- [ ] 4 clients join, pick preferences and ready up → the countdown runs → 1 supervisor and 3 rats spawn in the correct areas, frozen during the countdown.
- [ ] The supervisor's FP controller feels responsive. The rat's TP camera never clips through walls, and rats can go through the 0.7 m tunnel while supervisors can't.
- [ ] Sprint drains and regenerates stamina (a temporary stamina bar on the HUD is OK).
- [ ] Hacked or oversized movement (temporarily set a client's speed ×3 in debug) is logged by the validator.
- [ ] Chat works between all clients, and spam is rate-limited.
- [ ] The role assignment unit tests pass in CI.

## 3. Pitfalls
- `SpringArm3D` should exclude the player's own collider (`add_excluded_object(player.get_rid())`).
- Keep **one** `Player.tscn` with role-specific children instanced at spawn. Don't make two player scenes with diverging code.
- Small rat capsules and stairs: use `floor_snap_length` around 0.3 and ramps or low steps (≤ 0.25 m), or the rat gets stuck.
- Mouse sensitivity must be independent of FPS (use `event.relative`, not `delta`).
