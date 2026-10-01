# Technical Architecture

## 1. Stack
| Concern | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x, latest stable** — pinned to **4.7.2-stable** (also in `README.md` and `.github/workflows/ci.yml`) | MIT, small, Linux-native editor, built-in high-level multiplayer |
| Language | **GDScript with static typing everywhere** (`var hp: int`, `func f() -> void`) | Fast iteration; typed code catches errors and runs faster |
| Transport | `ENetMultiplayerPeer` (reliable + unreliable UDP channels) | Built in, works through the high-level `@rpc` / `MultiplayerSynchronizer` API |
| Server | The same project exported with the **"Dedicated Server"** export mode, run with `--headless` | One codebase, no client/server drift |
| Tests | [GUT](https://github.com/bitwes/Gut) | De-facto Godot unit test framework, runs headless |
| CI | GitHub Actions + [`barichello/godot-ci`](https://github.com/abarichello/godot-ci) Docker image | Ready-made headless Godot with export templates |
| VCS | Git + Git LFS | Binary assets kept out of the git history |
| Optional later | [netfox](https://github.com/foxssake/netfox) | Client prediction and rollback if needed |

Reference docs to keep open:
- High-level multiplayer: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- Dedicated server export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html
- Scene replication (MultiplayerSpawner/Synchronizer): https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/

## 2. Process model
```
          ┌──────────────── Dedicated server (headless) ────────────────┐
          │ Session (shared scene, authoritative here)                   │
          │  ├─ MatchManager   (state machine, roles, win checks)        │
          │  ├─ PlantSim       (subsystems, core_temp, meltdown)         │
          │  ├─ World (Plant.tscn + Players spawned by MultiplayerSpawner)│
          │  └─ ServerOnly: HazardDirector, MovementValidator            │
          └──────────────▲───────────────────────────▲──────────────────┘
       intents (RPC)     │ state (sync + RPC)          │
        own position     │                             │
   ┌─────────────────────┴───┐               ┌─────────┴───────────────┐
   │ Client A (supervisor)   │   …  up to 6  │ Client B (rat)          │
   │  MainMenu → Game scene  │               │                         │
   │  HUD, Chat, Minigames   │               │                         │
   └─────────────────────────┘               └─────────────────────────┘
```
- The server has peer id **1**. Clients get random ids from ENet.
- The server **does not play**. It has no camera and no player body.
- Only one match per server process. To host several matches, run several processes on different ports (Docker makes this trivial).

### Entry point (`main.gd`)
```gdscript
func _ready() -> void:
    var args := Cli.parse(OS.get_cmdline_user_args())   # args after "--"
    if OS.has_feature("dedicated_server") or args.has("server"):
        get_tree().change_scene_to_file.call_deferred("res://server/ServerMain.tscn")
    else:
        get_tree().change_scene_to_file.call_deferred("res://client/MainMenu.tscn")
```
Supported CLI args (user args after `--`):
- Server: `--server`, `--port N`, `--max-players N`, `--config path`, `--debug-start [N]` (skip the ready vote; start once N players, default 1, have joined)
- Client: `--connect host:port`, `--name X`
- Test only (honoured only in debug builds): `--allow-debug` (enables debug RPCs such as teleport), `--test-duration S`, `--exit-after-match`, `--result-file path`, `--bot rat|supervisor` (headless scripted client)
- Test-only client flags since M2 (debug builds, `client/debug_hooks.gd` and `MovementComponent`): `--pref rat|supervisor|any`, `--auto-ready`, `--say TEXT`, `--auto-move`, `--debug-speed N`, `--screenshot PATH [--screenshot-delay S]`
- Bot options since M3 (`tests/helpers/bot_client.gd`): `--bot-target SUBSYSTEM` (default `pumps`), `--bot-lever A|B` (critical subsystems), `--bot-delay S`. The bot scene lives under `tests/`, which is excluded from exports.

### `server.cfg` (ConfigFile/INI)
```ini
[server]
port=7777
max_players=6
name="Sunny Acres #1"
password=""
[match]
rules="res://data/match_rules.tres"   ; can be overridden per key below
duration_s=540
min_players=3
```
Every key of `[match]` other than `rules` overrides the `MatchRules` property of the same name (`Config.load_match_rules`).

## 3. Authority model
**Rule of thumb: clients own their *own body's movement*. The server owns *everything else*.**

| Thing | Authority | How it's replicated |
|---|---|---|
| Own player position, rotation, look pitch, anim state | Owning client | `BodySync` MultiplayerSynchronizer (unreliable, ~20 Hz, interpolated on others) |
| Player status (stunned, carried, caged, items, role) | Server | `StatusSync` MultiplayerSynchronizer, authority = 1 (reliable "on change") |
| Plant state (healths, core_temp, meltdown, alarm) | Server | `PlantSync` on PlantSim (~5 Hz, plus on change) |
| Match state, timer, scores | Server | `MatchSync` plus `@rpc` events (`match_started`, `match_ended`) |
| Interactable state (progress, cooldowns, door open) | Server | One synchronizer per interactable, or events |
| Hazards | Server | Spawned with `MultiplayerSpawner`. Timing is computed from a synced start time so clients animate without per-frame sync. |
| Cosmetic effects (particles, sounds) | Every client, locally | Triggered by synced state or `@rpc("call_local")` events |

### Why client-owned movement?
- Zero input lag with no prediction or reconciliation code, which matters a lot for a first networked game.
- Cost: a cheater could teleport. Mitigation is the **server sanity check** in `server/movement_validator.gd`: every physics tick, for every player, compare the new synced position to the previous one. If `distance > max_speed(role, status) * dt * 1.5 + 0.5`, or if a supervisor is inside a rat-only volume, the server sends `force_position` back to the owner and logs a strike. 10 strikes = kick.
- **Server-imposed movement** (knockback, being carried, teleport to cage) is sent to the owning client as an RPC on its `MovementComponent`: `apply_impulse(v)`, `set_locked(bool)`, `attach_to(path)`, `force_position(p)`. The owner applies it. The validator allows a temporary tolerance window afterwards. These RPCs are `any_peer` (the node's authority is the owner, not the server) and check that the sender is peer 1. Call them through `Player.server_*` helpers, which also open the validator window.
- The **countdown freeze** uses the `LOCKED` status instead: the spawn function applies it on every peer, so the body is frozen from its first frame, and the server clears it when the countdown ends.

If movement cheating or feel becomes a real problem, `MovementComponent` is the only place that needs to change to adopt netfox prediction.

### Intent RPCs (client → server)
Every gameplay action follows the same pattern:
```gdscript
# InteractorComponent (on the player, runs on the owning client)
func _try_interact(target: Interactable) -> void:
    Session.current.interactions.request_interact.rpc_id(1, target.get_path())   # intent only
    # session.gd: `class_name Session` + `static var current: Session` set in _enter_tree()
    # InteractionService exists on server AND clients (see §4), which is required for RPCs

# server side (InteractionService on ServerMain)
@rpc("any_peer", "reliable")
func request_interact(target_path: NodePath) -> void:
    var peer := multiplayer.get_remote_sender_id()
    var player := players.get_by_peer(peer)
    var target := get_node_or_null(target_path) as Interactable
    if target == null or not target.can_interact(player):       # role, distance ≤ reach + 0.75, LOS, cooldown, status
        return
    target.begin(player)                                       # server-side state change → replicated
```
- **Never trust the client**: the server re-checks role, status, distance (with a lag tolerance of +0.75 m), line of sight (raycast), and cooldown, all server-side.
- **Hit checks** (broom, bite) use the server's latest known positions plus that tolerance. No position rewind in v1. Consider a 150 ms history buffer in M9 if playtests show "I clearly hit him" complaints.
- **Hold interactions** keep running on the server while the client keeps sending `request_interact_heartbeat` every 0.25 s. They are cancelled if heartbeats stop for 1 s, the player moves more than 0.5 m, gets a disabling status, fails the reach/LOS/availability re-check (done every tick), disconnects, or the match stops. The server reports every end of a hold the client didn't ask for (completed, cancelled, refused) with `on_hold_ended`; after that the client needs a fresh press of E. Heartbeats are sent **reliable**: unreliable ones were sometimes dropped (they share the ENet channel with reliable traffic) and cancelled valid holds.

### RPC conventions
- `@rpc("any_peer", "reliable")` → **only** on server-side request handlers whose names start with `request_`. Always read `multiplayer.get_remote_sender_id()`.
- `@rpc("authority", "call_local", "reliable")` → server-to-all events (`on_*` names, e.g. `on_rat_caged`).
- `@rpc("authority", "unreliable")` → frequent cosmetic events.
- Guard server-only code with `if not multiplayer.is_server(): return`.

## 4. Scene and node structure
### Runtime tree
Godot RPCs and synchronizers only work when the node exists **at the same path, with the same script, on the server and on every client**. So everything networked lives in one shared scene, `common/Session.tscn`, which the server and clients both instance under the **same name** (`/root/Session`):
```
/root
 ├─ Net, Events, Config, Log, Cli          (autoloads)
 └─ Session (common/Session.tscn; root script session.gd: class_name Session, static var current; typed refs .match, .plant, .interactions…)
     ├─ MatchManager          (shared script; logic guarded by is_server(), synced state readable by clients)
     ├─ PlantSim              (same idea)
     ├─ InteractionService    (request_* RPC handlers; clients only call them)
     ├─ ChatService
     ├─ World (Node3D)
     │   ├─ Plant (levels/plant/Plant.tscn)
     │   │   ├─ POIs (ReactorHall, TurbineHall, …) containing Interactables, hazards, spawn points
     │   │   └─ NavigationRegion3D (later, for bots)
     │   ├─ Players (Node3D)  ← MultiplayerSpawner spawns Player.tscn, named by peer id
     │   └─ Dynamic (Node3D)  ← MultiplayerSpawner for traps, dropped items, hazards
     ├─ ServerOnly (Node)     ← children added at runtime only when is_server():
     │   ├─ HazardDirector, MovementValidator, ServerConsole
     └─ ClientOnly (Node)     ← children added only on clients: HUD, Chat UI, PauseMenu, MinigameHost, SpectatorCam
```
- `server/ServerMain.tscn` = boot logic (read config, `Net.host()`) and then adds `Session` to the root.
- `client/MainMenu.tscn` → on a successful connection it frees the menu and adds `Session` to the root.
- Nodes under `ServerOnly` / `ClientOnly` must **not** be RPC targets, because they don't exist on the other side.

### Player (`entities/player/Player.tscn`)
```
Player (CharacterBody3D, name = str(peer_id))
 ├─ CollisionShape3D          (size set by role)
 ├─ Visual (Node3D)           (role model instanced at spawn: supervisor.tscn / rat.tscn)
 ├─ CameraRig                 (FirstPersonRig or ThirdPersonRig, only active for the local player)
 ├─ MovementComponent         (reads RoleData stats + status modifiers)
 ├─ StatusComponent           (stun, slow, knockdown, carried, caged, eliminated, invulnerable, revealed; server-authoritative)
 ├─ InteractorComponent       (raycast/area focus, hold logic, sends intents)
 ├─ AbilityComponent          (list of AbilityData resources: broom, bite, trap…)
 ├─ Inventory                 (keycard, stolen item, trap charges)
 ├─ AnimationController       (drives AnimationTree from movement + status)
 ├─ NameTag (Label3D)
 ├─ BodySync (MultiplayerSynchronizer, authority = owner peer)
 └─ StatusSync (MultiplayerSynchronizer, authority = 1)
```
- Spawn flow: the server picks a spawn point and calls `MultiplayerSpawner.spawn({peer, role, pos})`. A custom `spawn_function` builds the player, sets `name = str(peer)`, and calls `set_multiplayer_authority(peer)` on the body and BodySync but **not** on StatusSync.
- Only the local player enables `CameraRig`, input processing and HUD binding (`is_multiplayer_authority()`).

### Interactables
`interactables/interactable.gd` (`class_name Interactable extends Area3D`):
```gdscript
@export var allowed_roles: Array[Role.Kind] = []
@export_enum("instant", "hold", "minigame") var kind := "hold"
@export var duration_s := 4.0
@export var prompt := "Sabotage"
signal completed(player: Player)

func can_interact(p: Player) -> bool          # role, status, cooldown, distance, LOS
func begin(p: Player) -> void                 # server
func cancel(p: Player) -> void                # server
func _complete(p: Player) -> void             # server → emits completed
```
- Each interactable builds its own `Sync` MultiplayerSynchronizer in `_ready` (synced `progress` 0..1 and `holder_count`), so no subclass scene can forget it.
- Facing convention: an interactable's +Z points away from its machine, toward where the player stands (`stand_position()`).
- `CriticalLever`: set `partner_path` on one lever of a pair only. That one is the leader and runs the shared progress on the server: it advances only while both levers are held, pauses while one is, and resets when neither is.

Subclasses: `SabotagePoint`, `CriticalLever` (pairs with a partner lever), `RepairPoint`, `Door` / `KeycardDoor`, `Cage`, `CctvCamera`, `ConsoleAction` (control room), `Vent` (rat-only trigger volume), `Pickup` (trap refill, donut, spare keycard).
`SabotagePoint` / `RepairPoint` hold an exported `subsystem_id`, and on `completed` they call `PlantSim.apply_damage(id, amount)` / `apply_repair(...)`.

### Minigames
- These are client-side UI scenes (`minigames/<name>/<Name>.tscn`) with a common base `Minigame` that emits `finished(success: bool)`.
- Flow: the server approves `request_interact` → sends `open_minigame(kind, seed)` to that client → the client plays → `request_minigame_result(success)` → the server checks `elapsed ≥ min_duration` and that the player is still in range → applies the repair.

## 5. Autoloads
| Autoload | Responsibility |
|---|---|
| `Net` | `host(port, max)`, `join(host, port)`, `leave()`, peer connected/disconnected signals, connection errors and timeouts, LAN discovery (UDP broadcast on 7778: the server announces `{name, players, port}` every 2 s) |
| `Events` | Global signal bus for UI/gameplay decoupling: `local_player_spawned`, `plant_alarm_changed`, `chat_message`, `match_state_changed`… |
| `Config` | User settings (`user://settings.cfg`: name, sensitivity, FOV, volumes, keybinds, favourites) and server config loading |
| `Log` | `Log.info/warn/error(tag, msg)` with `[S]`/`[C<id>]` prefixes and timestamps; also writes to a file on the server |
| `Cli` | Parses user command-line args |

## 6. Server systems
### MatchManager (`common/match_manager.gd`)
Its replicated state (`MatchSync`, on change): `state`, `countdown_left` (COUNTDOWN and POST_MATCH), `time_left` (PLAYING), `min_players`, `roster` (peer → name, role preference, ready, role) and `result` (winner, reason, per-player stats, set when POST_MATCH starts). Always assign a modified copy of `roster`, never edit it in place.
```
LOBBY ──ready vote / --debug-start──▶ ROLE_ASSIGN ─▶ COUNTDOWN(10s) ─▶ PLAYING ─▶ POST_MATCH(15s) ─▶ LOBBY
                                                        ▲ players < 2 during ROLE_ASSIGN/COUNTDOWN → abort to LOBBY
```
- Owns `time_left`, `state`, the roles and the stats (sabotages and repairs per player). Checks win conditions each frame with `MatchRulesModel.check_winner`, in this order: meltdown ≥ 100 → rats win; all rats caged, eliminated or gone → supervisors win; all supervisors gone → rats win; `time_left ≤ 0` → supervisors win. A team only counts as "gone" if it had players when PLAYING began, so solo debug matches run until the timer.
- **Late join** during PLAYING: the player becomes a spectator until the next match.
- **Disconnect** during PLAYING: the body is despawned. If a team is empty, the other team wins.

### PlantSim (`common/plant_sim.gd`)
- Subsystems come from `PlantTuning.subsystems` (`data/plant_tuning.tres` lists the six `data/subsystems/*.tres` in order); that order is the index everywhere. Fixed tick of 10 Hz (a `Timer`), using the formulas from [GDD §4](GDD.md#4-plant-simulation).
- Public API (server only): `apply_damage(index, amount, peers)`, `apply_repair(index, amount, peers)`, `reboot(index, peers)`, `reset()`, and the `subsystem_changed` signal that MatchManager uses for stats. Readable everywhere: `health(i)`, `cooldown_left(i)`, `needs_reboot(i)`, `can_sabotage(i)`. Later: `emergency_coolant()`, `scram()`.
- Synced properties (`PlantSync`, on change, checked every 0.2 s): `healths: PackedFloat32Array`, `core_temp`, `meltdown`, `alarm`, `cooldowns` (seconds **left**, not absolute times), `offline_mask` (bit i = needs a reboot).
- **Pure logic lives in `plant_model.gd` (`RefCounted`, no nodes)** so GUT can unit-test it without a scene tree. `PlantSim` is only a thin node wrapper around it. Apply the same split to the match rules (`match_rules_model.gd`).

### HazardDirector (`server/hazard_director.gd`)
Listens to PlantSim health changes and enables or disables each POI's hazard group when its subsystem goes below or above 50. Hazards apply statuses through `StatusComponent.apply(status, duration, source)`, which is server-only.

## 7. Data-driven tuning
All tunables are custom `Resource` classes saved as `.tres`:
```
data/
  match_rules.tres          # MatchRules: duration_s, duration_single_supervisor_s, countdown_s, post_match_s, swarm_bonus…
  roles/supervisor.tres     # RoleData: height, radius, walk, sprint, stamina, jump, abilities[]
  roles/rat.tres
  subsystems/rods.tres …    # SubsystemData: id, display_name, heat_weight, critical, hazard_kind, icon
  abilities/broom.tres …    # AbilityData: range, cone_deg, cooldown, status, status_duration
  plant_tuning.tres         # PlantTuning: the subsystem list, cooling rate, thresholds, meltdown rates, sabotage/repair amounts and hold times
```
The GDD tables and these files must stay in sync. A GUT test (`tests/unit/test_data_sanity.gd`) loads every resource and asserts value ranges.

## 8. Rendering (client only)
- Forward+ renderer on desktop, with a fallback to the Compatibility renderer for weak GPUs (setting in M8).
- `shaders/toon.gdshader`: a stepped diffuse ramp (2–3 bands) plus rim light. `shaders/outline.gdshader`: an inverted-hull outline as a `next_pass` material.
- The server export strips visuals automatically ("Dedicated Server" export mode). Any client-only node must check `DisplayServer.get_name() != "headless"` before doing visual work, or live in client-only scenes.

## 9. Code conventions
- Files are `snake_case.gd`, classes are `PascalCase` via `class_name`, scenes are `PascalCase.tscn`.
- Static typing everywhere. Enable `untyped_declaration` as a warning in project settings.
- One responsibility per component. Components find siblings via `@onready var status: StatusComponent = $"../StatusComponent"` or exported NodePaths.
- No game logic in UI scripts: UI reads synced state and listens to `Events`.
- Server-only code is prefixed or guarded: `if not multiplayer.is_server(): return`.
- Every `@rpc("any_peer")` function starts with `request_` and validates everything.

## 10. Testing strategy
| Level | Tool | What |
|---|---|---|
| Unit | GUT, headless | `plant_model`, `match_rules_model`, status stacking, team balance, data sanity |
| Integration | Shell script launching separate headless processes (`tests/integration/*.sh`) | A server on a random port (`--exit-after-match --result-file`) plus bot clients (`--bot rat\|supervisor`) that connect, pick their role and ready up (the real ready vote, `min_players=2`: `--debug-start` would start before the preferences arrive), go to a sabotage point and complete it (plus a lever-pair variant). The scripts assert the result JSON, the exit code, and that the logs contain no errors. |
| Manual | Run Instances (editor: *Debug → Customize Run Instances*) | 1 instance with `-- --server --debug-start`, 3 instances with `-- --connect 127.0.0.1:7777` |
| Network conditions | `tc netem` on Linux (`sudo tc qdisc add dev lo root netem delay 80ms 20ms loss 1%`) | Play with 80–150 ms latency before calling any PvP feature done |

Commands (from M0):
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
tests/integration/run_match_loop.sh
```

## 11. Build and CI
- Export presets (`export_presets.cfg`, committed **without** credentials): `Linux` (x86_64), `Windows Desktop` (x86_64), `Linux Server` (Dedicated Server mode, custom feature tag `dedicated_server`).
- `.github/workflows/ci.yml`: on push → unit tests. On tag `v*` → integration tests, then the 3 exports, then upload artifacts / GitHub release.
- `Dockerfile` (server): `debian:stable-slim`, copy the server binary and `.pck`, `EXPOSE 7777/udp`, `ENTRYPOINT ["./homersim_server.x86_64", "--headless", "--", "--server", "--config", "/config/server.cfg"]`.
- Windows builds are exported **from Linux** with the official export templates (no Windows machine needed; `rcedit` is optional for the .exe icon). Test them on a real Windows PC or VM before each release.

## 12. Security and robustness checklist
- Validate every `request_*` (sender exists, role, status, distance, LOS, cooldown, rate limit of about 20 requests/s per peer).
- Chat: max 200 characters, rate limit of 1 message/s, strip BBCode.
- An optional server password is checked in a `request_join(name, password, version)` handshake. Reject protocol/version mismatches with a clear message.
- Names are sanitised and unique-ified ("Bob (2)").
- Kick on repeated validator strikes. A `kick`/`ban` console command on the server (stdin) arrives in M9.

## 13. Repository layout
```
homersim/
  project.godot  export_presets.cfg  main.tscn  main.gd
  autoload/        net.gd events.gd config.gd log.gd cli.gd
  common/          Session.tscn session.gd match_manager.gd match_rules_model.gd
                   plant_sim.gd plant_model.gd interaction_service.gd chat_service.gd role.gd
  server/          ServerMain.tscn server_main.gd hazard_director.gd movement_validator.gd server_console.gd
  client/          MainMenu.tscn ServerBrowser.tscn Settings.tscn HUD.tscn Chat.tscn Scoreboard.tscn
                   PostMatch.tscn SpectatorCam.tscn MinigameHost.tscn
  entities/player/ Player.tscn player.gd  supervisor/ rat/   (role visuals + rigs)
  components/      movement/ camera/ status/ interactor/ abilities/ inventory/ animation/
  interactables/   interactable.gd sabotage_point/ critical_lever/ repair_point/ door/ cage/
                   cctv/ console_action/ vent/ pickup/
  minigames/       minigame.gd wrench_rhythm/ breaker_sequence/ valve_rotate/
  hazards/         hazard.gd steam_jet/ electric_puddle/ radiation_zone/ debris/ smoke/
  levels/          test/TestArena.tscn  plant/Plant.tscn + plant/pois/*.tscn
  data/            match_rules.tres plant_tuning.tres roles/ subsystems/ abilities/
                   (scripts: match_rules.gd role_data.gd plant_tuning.gd subsystem_data.gd)
  shaders/         toon.gdshader outline.gdshader
  assets/          third_party/<pack>/  generated/  audio/  fonts/  ui/
  addons/          gut/  (later: netfox/ …)
  tools/blender/   common.py pipe.py tank.py console.py valve.py … export_all.py
  tests/           unit/ integration/ helpers/bot_client.gd
  docs/            GDD.md ARCHITECTURE.md ASSETS.md milestones/
  .github/workflows/ci.yml  Dockerfile  server.cfg.example  CREDITS.md  README.md
```
