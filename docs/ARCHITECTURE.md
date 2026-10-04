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
- The server **does not play**. It has no camera and no player body of its own. The one exception (M10) is AI bots: their bodies are owned and moved by the server (§6 AI bots).
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
- Since M4: `--bot-scenario capture|swarm|items|hack [--bot-part P]` runs a PvP scenario instead (`tests/helpers/pvp_bot.gd`); bots of one test coordinate only through replicated state and find each other by name.
- Since M6: client `--hold-repairs` (any build: repairs use the 6 s hold instead of the minigame, until M8's settings toggle). `--bot-scenario hazards|minigame|control` (on the plant) runs an M6 scenario (`tests/helpers/m6_bot.gd`). Test-only RPC `Session.request_debug_plant(what, id, value)` (server `--allow-debug`): set a subsystem's health or the core temperature.
- Since M5: `--level plant|test` (debug builds; server and clients must match, the join handshake checks it) picks the level, default the plant. The M4 PvP tests use `--level test` (TestArena). `--bot-scenario plant` (CCTV, ladder, shaft, out of bounds). Server: `--no-heatmap` (no position log). Client, any build: `--debug-overlay` (F3 overlay on from the start).
- M10, AI bots: `bot_fill_to` and `bot_difficulty` are `[match]` keys (any build). Test-only server flags (debug builds): `--ai-only` (bots-only matches, back to back; humans who join spectate), `--ai-fill N` (overrides `bot_fill_to`), `--ai-seed S`, `--ai-roles rat,rat,supervisor` (exactly these bots), `--ai-goals role:Goal,…` (only these goals; `rat:none` = a bot that stands still), `--ai-scenario NAME` (`tour`: every bot walks to its share of its role's targets; `capture`: the bots start in the Cage Room; `path:X,Y,Z:X,Y,Z[:…]`: the first bot starts at the first point and walks to the others, for debugging a spot; `hot`, `steal`, `cctv`: the phase E tests' set-ups), `--ai-log` (one log line per change of goal), `--ai-trace NAME|all` (a bot's position, intent and path 4 times a second), `--ai-labels` (each bot's goal under its name tag on spectating clients). Client, test-only: `--spectate NAME|first` (spectating, follow that body: watch mode).
- Since M8: server `--password X` (overrides server.cfg), `--no-lan` (no LAN announcements; every integration test but menus_smoke uses it). Client, any build: `--settings PATH` (another settings file; the UI tour uses a throwaway one). `--connect` and `--name` still work but are no longer needed. Test-only (debug builds): client `--debug-kick-me`, `--screenshot-times T1,T2,…`; in the main menu (`client/menu_test_hooks.gd`) `--lan-join NAME`, `--auto-password A,B,…`, `--dismiss-errors`.

### `server.cfg` (ConfigFile/INI)
```ini
[server]
port=7777
max_players=6
name="Sunny Acres #1"   ; shown in the server browser and the lobby
password=""            ; M8: "" = open; otherwise checked by request_join
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
| AI bot body (M10) | Server (authority 1; the bot's id is negative and has no peer) | The same `BodySync`, sent by the server; clients treat it like any remote body |
| Player status and items (status flags, speed factor, carry links, keycard, stolen item, trap charges) | Server | `StatusSync` MultiplayerSynchronizer, authority = 1 (reliable "on change"); it covers `StatusComponent` and `Inventory` |
| Plant state (healths, core_temp, meltdown, alarm) | Server | `PlantSync` on PlantSim (~5 Hz, plus on change) |
| Match state, timer, scores | Server | `MatchSync` plus `@rpc` events (`match_started`, `match_ended`) |
| Interactable state (progress, cooldowns, door open) | Server | One synchronizer per interactable, or events |
| Hazards | Server | Static level nodes (placed by the map generator) with a `Sync` child: `active` and `start_time` (server clock). Cycles are computed from the start time, so clients animate without per-frame sync. Debris impacts are an RPC with the spot and the impact time. |
| Cosmetic effects (particles, sounds) | Every client, locally | Triggered by synced state or `@rpc("call_local")` events |

### Why client-owned movement?
- Zero input lag with no prediction or reconciliation code, which matters a lot for a first networked game.
- Cost: a cheater could teleport. Mitigation is the **server sanity check** in `server/movement_validator.gd`: every physics tick, for every player, compare the new synced position to the previous one. If `distance > max_speed(role, status) * dt * 1.5 + 0.5`, or if a supervisor is inside a rat-only volume, the server sends `force_position` back to the owner and logs a strike. 10 strikes = kick.
- **Server-imposed movement** (knockback, being carried, teleport to cage) is sent to the owning client as an RPC on its `MovementComponent`: `apply_impulse(v)`, `set_locked(bool)`, `attach_to(path)`, `force_position(p)`. The owner applies it. The validator allows a temporary tolerance window afterwards. These RPCs are `any_peer` (the node's authority is the owner, not the server) and check that the sender is peer 1. Call them through `Player.server_*` helpers, which also open the validator window.
- A **carried** rat's owner follows the carrier's `HandSocket` (`attach_to`); every other peer draws it there too (`Player.carried_anchor()`), and it has no collision layer while carried. The validator skips carried and caged bodies, and any status change opens a grace window (the owner may still be moving at the old speed until StatusSync reaches it).
- Remote bodies glide toward their synced position, except for jumps over 2 m (teleports, cage, release), which snap: gliding would sweep the body through bars and shove other players.
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
     ├─ ChatService           (ALL / TEAM / GHOST routing, server-side)
     ├─ AbilityService        (broom and bite: request_use_ability, cosmetic on_* events, cooldowns)
     ├─ CaptureService        (grab, carry, cage, free, eliminate; server logic)
     ├─ ItemService           (request_place_trap, steal, dropped keycards, the Dynamic spawn function)
     ├─ MinigameService       (M6: request_minigame_start/result/cancel, on_open_minigame, on_minigame_closed)
     ├─ World (Node3D)
     │   ├─ Plant (levels/plant/Plant.tscn, added by Session._enter_tree; TestArena with --level test)
     │   │   ├─ WorldEnvironment, Moon
     │   │   ├─ POIs (Yard, ReactorHall, TurbineHall, …, VentNetwork): Poi roots with the baked shell (M7),
     │   │   │   props + PropCollision boxes, lights, Interactables, cameras, ladders, spawn points, occluders,
     │   │   │   NavigationLink3Ds, hazards (M6), ambient sounds and reverb areas (M7)
     │   │   ├─ OutOfBounds (kill volumes)
     │   │   ├─ OverviewPoint (where the camera looks from with no body)
     │   │   └─ Map (MapInfo → PlantMap.tres, the plan the in-game map draws)
     │   ├─ Players (Node3D)  ← MultiplayerSpawner spawns Player.tscn, named by peer id
     │   └─ Dynamic (Node3D)  ← DynamicSpawner (MultiplayerSpawner) for traps, dropped keycards, later hazards
     ├─ ServerOnly (Node)     ← children added at runtime only when is_server():
     │   ├─ MovementValidator, HeatmapRecorder (M5), HazardDirector (M6), LanAnnouncer (M8), AiDirector (M10: navmeshes,
     │   │   one AiBot per bot, the team blackboards); later ServerConsole
     └─ ClientOnly (Node)     ← children added only on clients: OverviewCamera, SpectatorCam, CombatFeedback (sounds + VFX), HUD, Lobby, PostMatch, Chat UI, CctvView, DebugOverlay (M5), MinigameHost, AlarmEffects (M6), MusicDirector (M7), EventFeed, Hints, Scoreboard, PauseMenu (M8), MapOverlay (the minimap + the full map)
```
- `server/ServerMain.tscn` = boot logic (read config, `Net.host()`) and then adds `Session` to the root.
- `client/MainMenu.tscn` → `connect_to()` adds `Session` to the root, connects, and frees the menu once the server accepts the join. Any end of a session (refused, kicked, lost, left) goes through `Session._leave_to_menu(LeaveReason.Code, detail)`: if the menu is still open (a failed join) it just explains, otherwise the menu scene is loaded again and explains (see §4 Menus).
- Nodes under `ServerOnly` / `ClientOnly` must **not** be RPC targets, because they don't exist on the other side.

### Player (`entities/player/Player.tscn`)
```
Player (CharacterBody3D, name = str(peer_id))
 ├─ CollisionShape3D          (size set by role)
 ├─ Visual (Node3D)           (RoleData.visual_scene: a CharacterVisual with the role's generated model, turned to face -Z; the supervisor's broom on a BoneAttachment3D)
 ├─ CameraRig                 (FirstPersonRig or ThirdPersonRig, only active for the local player)
 ├─ MovementComponent         (reads RoleData stats + status modifiers)
 ├─ StatusComponent           (server-authoritative; rules in StatusRules, pure logic: expiry, immunity windows, speed factors, bite counting)
 ├─ InteractorComponent       (raycast/area focus, hold logic, sends intents)
 ├─ AbilityComponent          (RoleData.abilities: LMB primary, RMB trap preview + place, Q switch; cooldowns)
 ├─ Inventory                 (keycard, stolen item, trap charges, spare-keycard and donut waits; server-authoritative)
 ├─ AnimationController       (M7, clients: builds the AnimationTree, see below; fills sync_anim for the owner)
 ├─ BodyFx                    (M7, windowed clients: footsteps, loops, voices, stun stars, hit-stop)
 ├─ GrabHandle / StealHandle  (added by setup(): rats get a GrabHandle, supervisors a StealHandle on their back)
 ├─ HandSocket (Node3D)       (supervisors: where a carried rat hangs)
 ├─ NameTag, StatusTag (Label3D)
 ├─ BodySync (MultiplayerSynchronizer, authority = owner peer)
 └─ StatusSync (MultiplayerSynchronizer, authority = 1)
```
- Spawn flow: the server picks a spawn point and calls `MultiplayerSpawner.spawn({peer, role, pos})`. A custom `spawn_function` builds the player, sets `name = str(peer)`, and calls `set_multiplayer_authority(peer)` on the body and BodySync but **not** on StatusSync, StatusComponent or Inventory.
- Only the local player enables `CameraRig`, input processing and HUD binding (`is_multiplayer_authority()`).
- BodySync replicates `sync_position`, `sync_yaw`, `sync_pitch` and (M7) `sync_anim`: `AnimationController.FLAG_*` bits (airborne, rising, interacting, emoting, climbing, in a vent). Everyone's animations come from that, the body's interpolated motion (speed) and its synced statuses; one-shots come from the cosmetic RPCs (broom swing, bite) and synced changes (a donut eaten). No other traffic.
- AnimationController's tree: `loco` (BlendSpace1D on speed) → `loco_rate` (TimeScale) → `state` (Transition: ground, jump, fall, interact, climb, crawl, sit, stunned, knocked, dangle, caged) → `carry` (Blend2 filtered to the arms) → `action` (OneShot whose clip is swapped before each fire) → output. Clip names per role: `AnimationController.ROLE_CLIPS`.
- First person (FirstPersonRig): the arms model (`fp_arms.glb`) at the camera, scaled to 35 % so it never pokes through walls, playing idle / swing / interact / carry / eat / place.

### Interactables
`interactables/interactable.gd` (`class_name Interactable extends Area3D`):
```gdscript
@export var allowed_roles: Array[Role.Kind] = []
@export_enum("instant", "hold", "minigame") var kind := "hold"
@export var duration_s := 4.0
@export var prompt := "Sabotage"
signal completed(player: Player)

func can_interact(p: Player) -> bool          # role, status, cooldown, distance, LOS
func kind_for(p: Player) -> String            # per role: a cage is instant for supervisors, a hold for rats
func begin(p: Player) -> void                 # server
func cancel(p: Player) -> void                # server
func _complete(p: Player) -> void             # server → emits completed
```
- Each interactable builds its own `Sync` MultiplayerSynchronizer in `_ready` (synced `progress` 0..1 and `holder_count`, plus whatever `_synced_properties()` adds, like a cage's `occupants`), so no subclass scene can forget it. Interactables without a progress ring (instant ones, the handles on player bodies) set `needs_sync = false`; the steal ring is a local estimate.
- Instant interactions need a fresh press of E for each use.
- Facing convention: an interactable's +Z points away from its machine, toward where the player stands (`stand_position()`).
- `CriticalLever`: set `partner_path` on one lever of a pair only. That one is the leader and runs the shared progress on the server: it advances only while both levers are held, pauses while one is, and resets when neither is.

Subclasses: `SabotagePoint`, `CriticalLever` (pairs with a partner lever), `RepairPoint`, `GrabHandle` and `StealHandle` (on player bodies), `Cage`, `KeycardReader` (on a keycard `Door`), `Pickup` (trap refill, donut, spare keycard, dropped keycard), `CctvCamera` (a junction box at the foot of a wall with a lens marker above; rats break it, supervisors repair it; synced `broken`), `CctvConsole` (the CCTV chair: synced `user`, the server pins the seated body, `request_stand_up`), `ConsoleAction` (M6, Control Room: `coolant` or `scram`, instant, synced `ready_at` and `cover_open_until` on the server clock; SCRAM needs two presses, cover then button). Not interactables: `Door` (a `Node3D` with a server-owned `open` and an `AnimatableBody3D` panel; normal doors open for anyone nearby), `Trap` (an `Area3D` the server watches), `VentVolume`, `Ladder` (an `Area3D`: MovementComponent climbs while inside), `OutOfBounds` (kill volumes: the owner puts its body back on the last safe spot).
- Nodes in the `MatchManager.RESET_GROUP` group get `reset_for_match()` on the server at every match start (cameras, the CCTV chair, console actions, repair points).
- `RepairPoint` (M6): E opens the subsystem's minigame when the player wants minigames (`Config.minigame_repairs`, `RepairPoint.prefers_minigame`), otherwise it is the M3 hold; the server accepts both. Synced `lockout_until` (a lost or hacked minigame jams the point for 3 s) and `minigame_user`.

### Levels
- `levels/plant/Plant.tscn` and its POI scenes are written by `tools/map/gen_plant.py` from the layout numbers in that script, which also draws `docs/map/plant_layout_v1.png`. See [docs/map/README.md](map/README.md). Each POI root is a `Poi` (`levels/poi.gd`) with world-space bounds; `Poi.name_at(tree, pos)` names the room at a position.
- The in-game map: the same script writes `levels/plant/PlantMap.tres`, a `LevelMap` (`levels/level_map.gd`: rooms with names, colours and label spots, walls, doors, keycard doors, windows, ducts, vent exits, ladders, the cooling tower, all as `Vector2(x, z)` metres), and puts a `MapInfo` node in Plant.tscn that points at it (`MapInfo.plan_in(tree)`; a level without one has no map). On clients `MapOverlay` (ClientOnly, layer 4) shows a minimap in the top right corner (follows the player, turns with the camera unless `Config.minimap_rotate` is off; hidden with `Config.show_minimap` off, at the CCTV chair, in the lobby and after the match), the name of the room the player is in under it, and the full map on the `map` key (M by default, a keycode rather than a physical key so it is M on AZERTY too; toggled, it doesn't free the mouse). Both are `MapView`s (`client/map_view.gd`), which draw the plan plus what they read from the level each frame: machines (`StationLabel` group, health colours), cages (occupants), pickups (supervisors) and bodies. They show the player's own team, enemies only while REVEALED, everyone to ghosts and in the lobby, and the vents to everyone but supervisors. The event feed starts under the minimap (`MapOverlay.feed_top()`).
- Client-only props build their visuals in `_ready` and skip the headless server: `CctvScreen` and `StatusBoard` (a `SubViewport` rendered on demand, only while on screen), `AlarmBeacon`.
- M7: each POI's static shell is one baked mesh + one concave collision shape (`levels/plant/baked/`, from the CSG sources in `levels/plant/shells/`, see `tools/godot/bake_shells.gd`); props are generated models placed on the layout boxes, which stay as the gameplay collision (`PropCollision`). `PlantProp` animates machine parts from subsystem health, `PropMultiMesh` draws long pipe runs, `AmbientSound` markers loop the hums, and `Area3D` reverb zones (layer `PhysicsLayers.AUDIO`) send the big halls' sounds to the HallReverb bus.
- The CCTV view (`client/cctv_view.gd`) switches the main view to a temporary camera at the selected lens instead of rendering a second viewport. The level itself has no `Camera3D` nodes: Godot makes a stray camera current on its own.
`SabotagePoint` / `RepairPoint` hold an exported `subsystem_id`, and on `completed` they call `PlantSim.apply_damage(id, amount)` / `apply_repair(...)`.

### Minigames
- These are client-side UI scenes (`minigames/<name>/<Name>.tscn`: `WrenchRhythm`, `BreakerSequence`, `ValveRotate`) with a common base `Minigame` that emits `finished(success: bool)`. Which one a subsystem uses is `SubsystemData.minigame`.
- Rules: lay out from `size` (any window size), advance with real time (`advance(delta)`), seed the puzzle from the server's seed, and expose the player's actions as methods (`press()`, `press_breaker(i)`, `rotate_by(rad)`) that input, GUT tests and `autoplay()` (test bots) all call.
- Flow: E on a repair point → `MinigameService.request_minigame_start(path)` → the server validates (reach, LOS, status, not jammed, nobody else playing it) and sends `on_open_minigame(path, kind, seed, difficulty)` → `MinigameHost` (ClientOnly overlay: frees the mouse, sets `PlayerInput.blocked`) plays it → `request_minigame_result(success)` → the server checks a game is open, `elapsed ≥ minigame_min_s` (3 s, faster = refused and jammed), the player is still in range and can act → +50, or +10 and a 3 s jam. The host reports a win no sooner than 3.3 s after opening. The server closes a game (`on_minigame_closed`) on a bite (`interrupt`), a stun, a 0.5 m move, nothing left to repair, 30 s, or the end of the match. Esc → `request_minigame_cancel`.

### Menus and UI (M8)
- **Screens**: `MainMenu` (home + `MenuBackground`, a 3D diorama built from the generated models) opens `ServerBrowser`, `Settings`, `HowToPlay` and `Credits` (renders `CREDITS.md`, exported with the client) in its `Screens` node; each emits `closed`. Settings and How to play are reused by the in-game `PauseMenu` (`in_game = true` dims the game behind them). Skeleton layouts are `.tscn` files (editable in the editor), rows and lists are built in code.
- **Joining**: the browser only emits `join_requested(address, name, locked)`; `MainMenu.connect_to()` connects and shows "Connecting…" with Cancel. A locked LAN server asks for the password first; any other server that answers `PASSWORD_REQUIRED` / `WRONG_PASSWORD` brings the prompt back and retries. Every failure is a `LeaveReason.Code` (`common/leave_reason.gd`): cannot connect, timeout, lost, version, full, password, level, kicked, bad address, each with a translated title and message for the error box and an English line for logs. `Session.kick(peer, reason)` tells the player why before dropping it.
- **LAN discovery** (`common/lan_discovery.gd`, protocol + server list; `server/lan_announcer.gd`; `client/lan_browser.gd`): JSON announcements every 2 s to UDP 7778–7781 on 255.255.255.255 and 127.0.0.1; a client listens on the first free port of that range (Godot can't share a UDP port between processes, and several clients on one PC each need one), pings the address an announcement came from (`ping`/`pong` packets) and forgets servers after 6 s. Malformed packets are dropped and names cleaned (anyone on the LAN can send anything).
- **Settings** (`Config`, below): `Settings.tscn` generates its rows from the settings; `Config.set_value()` cleans, applies, saves (debounced) and emits `changed`. Key bindings are stored by physical key (`Keys.encode`: `key:69`, `mouse:1`) and shown as printed on the player's layout (`Keys.label`: Z Q S D on AZERTY); `Keys.GROUPS` defines which actions conflict. Esc is not rebindable. HUD, hints, lobby and How to play texts all use `Keys.label()`.
- **In game**: `PauseMenu` owns Esc (open/close; it frees the mouse and the game keeps running; a click in the 3D view recaptures the mouse, which closes it); the chat and the minigames take Esc first in `_input`. `Scoreboard` (hold Tab) and `EventFeed` (top right, `MatchManager.feed` → `Events.feed_event`) only read replicated state. `Hints` shows each first-time tip once (`Config.seen_hints`) and drops a tip once its moment has passed. The lobby docks the chat on the left and takes 1 / 2 / 3 / R.
- **Theme**: `client/ui/theme.tres`, generated by `tools/godot/make_theme.gd` (Luckiest Guy for titles, Fredoka for text; Fredoka is a variable font whose weight must be set by its numeric OpenType tag), set as the project theme. Type variations: AccentButton, DangerButton, FlatButton, TitleLabel, HeaderLabel, SubheaderLabel, MutedLabel, HudLabel, CardPanel, HudPanel, DimPanel. `MessageDialog` (`client/ui/message_dialog.gd`) is the one modal box (inform, confirm, ask), with the keyboard focus trapped inside.
- **Localization**: every user-facing text goes through `tr()` (`TranslationServer.translate()` in static functions); the keys are the English texts, in `translations/strings.csv` (`keys,en,fr`, imported into `.translation` files that are not committed). Texts the server sends are English format strings plus arguments, translated by each client (`ChatService.format`, `ConsoleAction.on_used`, `MatchManager.feed`, `LeaveReason`). Headless processes stay in English (tests read their logs). Scene texts translate automatically; nodes showing runtime text set `auto_translate_mode = 2`. `tests/unit/test_translations.gd` fails on any text missing from the CSV.
- **Known quirk** (Godot 4.7 release builds only): when a client's multiplayer peer resets with nodes still in the engine's node cache, the engine logs "Attempt to disconnect a nonexistent connection … tree_exited". `Session._teardown` leaves the tree before dropping the peer, which leaves one such line (for `Net`); a lost connection still logs one per cached node, because the engine resets its cache inside its own poll. Harmless; debug builds don't log it.

## 5. Autoloads
| Autoload | Responsibility |
|---|---|
| `Net` | `host(port, max)`, `join(host, port)`, `leave()`, peer connected/disconnected signals, connection errors and timeouts, `ping_ms()` / `peer_ping_ms(peer)` (ENet round trips). LAN discovery is in `LanAnnouncer` / `LanBrowser` (§4 Menus). Server clock (M6): `server_time()` is the server's clock on every machine. After connecting, a client sends `request_clock_sync` 5 times (0.2 s apart, then every 10 s) and keeps the answer with the shortest round trip: offset = server time + RTT/2 − local time |
| `Events` | Global signal bus for UI/gameplay decoupling: `local_player_spawned`, `plant_alarm_changed`, `chat_message`, `match_state_changed`… |
| `Config` | User settings (M8, `user://settings.cfg`, or `--settings PATH`): video, controls and key bindings, audio volumes on top of the bus mix, gameplay (name, language, chat filter, FPS/ping), favourites, seen hints; `set_value()` applies and saves. Only windowed clients read or write the file (headless processes run on defaults, in English). The renderer goes to `user://override.cfg` (`application/config/project_settings_override`). Also server config loading (`[server]` name, port, max_players, password) |
| `Ui` | Client UI services (M8, `client/ui/ui.gd`): hover / click sounds for every button and slider, the FPS + ping corner |
| `Log` | `Log.info/warn/error(tag, msg)` with `[S]`/`[C<id>]` prefixes and timestamps; also writes to a file on the server |
| `Cli` | Parses user command-line args |

## 6. Server systems
### MatchManager (`common/match_manager.gd`)
Its replicated state (`MatchSync`, on change): `state`, `countdown_left` (COUNTDOWN and POST_MATCH), `time_left` (PLAYING), `min_players`, `roster` (peer → name, role preference, ready, role) and `result` (winner, reason, per-player stats, set when POST_MATCH starts). Since M8 also `server_info` (name, max players, durations, min players, locked), `pings` (peer → ms, every 2 s) and `live_stats` (the stats so far, at most once a second, for the scoreboard). Always assign a modified copy of `roster`, never edit it in place.
- `feed(kind, a, b)` (M8) sends a line to everyone's event feed: cages, eliminations, rescues, bonks, knockdowns, traps, stolen keycards, sabotages, machines offline / repaired / back online, the swarm bonus. Gameplay events no longer go to the chat.
```
LOBBY ──ready vote / --debug-start──▶ ROLE_ASSIGN ─▶ COUNTDOWN(10s) ─▶ PLAYING ─▶ POST_MATCH(15s) ─▶ LOBBY
                                                        ▲ players < 2 during ROLE_ASSIGN/COUNTDOWN → abort to LOBBY
```
- Owns `time_left`, `state`, the roles and the stats (`STAT_KEYS`: sabotages, repairs, catches, frees, bites, knockdowns, steals, hazard hits, and since M8 bonks, donuts, caught per player; services call `add_stat`). The post-match awards come from these (`common/awards.gd`). Checks win conditions each frame with `MatchRulesModel.check_winner`, in this order: meltdown ≥ 100 → rats win; all rats caged, eliminated or gone → supervisors win; all supervisors gone → rats win; `time_left ≤ 0` → supervisors win. A team only counts as "gone" if it had players when PLAYING began, so solo debug matches run until the timer.
- **Late join** during PLAYING: the player becomes a spectator until the next match.
- **Body swaps** (lobby → role bodies, back to the lobby, elimination) go through `Session.retire_bodies(peers)`: each owner is first told to stop sending positions (`on_retire_body`, which turns its BodySync off) and the bodies are despawned once all owners confirm (or after 1 s) plus 0.1 s. Despawning straight away let in-flight BodySync packets reach a freed node ("Ignoring sync data … for missing node"). The state machine pauses during a swap; a swap overtaken by another (a player leaves mid-swap) stops after its await.
- **Elimination** (CaptureService, a rat's 2nd capture): `eliminate(peer)` sets the roster entry's `eliminated` flag and despawns the body. Eliminated players and spectators are *ghosts* (`is_ghost`): SpectatorCam, ghost chat only.
- **Swarm bonus**: every supervisor body knocked down at once → `PlantSim.add_meltdown(swarm_bonus)`, on the rising edge, at most once per `swarm_cooldown_s`.
- **Disconnect** during PLAYING: the body is despawned. If a team is empty, the other team wins.

### PlantSim (`common/plant_sim.gd`)
- Subsystems come from `PlantTuning.subsystems` (`data/plant_tuning.tres` lists the six `data/subsystems/*.tres` in order); that order is the index everywhere. Fixed tick of 10 Hz (a `Timer`), using the formulas from [GDD §4](GDD.md#4-plant-simulation).
- Public API (server only): `apply_damage(index, amount, peers)`, `apply_repair(index, amount, peers)`, `reboot(index, peers)`, `reset()`, `emergency_coolant()`, `scram()` (M6; the ConsoleAction checks cooldowns and the grid requirement), and the `subsystem_changed` signal that MatchManager uses for stats. Readable everywhere: `health(i)`, `cooldown_left(i)`, `needs_reboot(i)`, `can_sabotage(i)`.
- Synced properties (`PlantSync`, on change, checked every 0.2 s): `healths: PackedFloat32Array`, `core_temp`, `meltdown`, `alarm`, `cooldowns` (seconds **left**, not absolute times), `offline_mask` (bit i = needs a reboot), `scram_left` (M6).
- `MatchManager.extend_time(s)` (SCRAM's penalty) moves the end of the match and adds to the synced `time_added`, which the HUD shows.
- **Pure logic lives in `plant_model.gd` (`RefCounted`, no nodes)** so GUT can unit-test it without a scene tree. `PlantSim` is only a thin node wrapper around it. Apply the same split to the match rules (`match_rules_model.gd`).

### HazardDirector (`server/hazard_director.gd`) and hazards (`hazards/`)
Every 0.1 s it reads PlantSim's healths and calls `set_active` on each subsystem's hazard group (`hazard_<id>`): on below 50, off again at 60 or more (`HazardRules.next_active`), everything off outside PLAYING. Polling rather than listening covers resets and anything else that moves health.
- `Hazard` (`hazards/hazard.gd`, `Area3D`): exported `subsystem_id`, `size`, `phase`; synced `active` and `start_time` (server clock, 0.5 s after switching on). `is_live(Net.server_time())` gives the same answer everywhere (`HazardRules.cycle_live`). Only the server monitors overlaps; a body is hit at most once per live window (`HazardRules.cycle_index`); carried, caged, locked and eliminated bodies are skipped (`Hazard.can_hit`). Effects go through `StatusComponent` and `Player.server_apply_impulse` (which opens the validator's grace window). Each hit is logged (`PumpHouse/SteamJet hit RatBot`), counted (`hazard_hits` stat) and sent to clients (`on_hit`, a banner for the victim). Clients only draw (`_build_look` / `_update_look`, skipped headless).
- `SteamJet` (frustum along +Z, knockback via `HazardRules.knockback`), `ElectricPuddle`, `RadiationZone` (per-body exposure on the server, a local estimate on the client for the Geiger clicks), `DebrisZone` (the server picks a random floor spot, `on_debris_warning(pos, at)` to clients, resolves the impact by distance at `at`), `Smoke` (a `FogVolume`; the first active one turns the environment's volumetric fog on; cosmetic, no server work).

### AI bots (M10, `server/ai/`)
Planned in [milestones/M10-ai-bots.md](milestones/M10-ai-bots.md); the gameplay rules are in [GDD §5.5](GDD.md#55-bots).

**Identity**
- Bots are roster entries with `"bot": true` and **negative** ids (−1001, −1002, …). They are never in `Session.players`, so nothing that loops over the connected peers (chat, feed, pings, FULL, the LAN count, the updater) sees them.
- `Session.is_ai_id(id)` tells a bot from a player, and `name_of` reads a bot's name from the roster.

**Fill**
- `MatchRulesModel.bots_needed(humans, rules)` gives the number of bots to add.
- `assign_roles(prefs, rules, rng, fillers)` hands out the roles: humans are placed first, fillers last, and leftover fillers are dropped.
- Bots are created in `_start_match` and removed in `_back_to_lobby`. When a running match has no humans left, the server goes back to the lobby.

**Bodies**
- The spawn data carries `bot`. `_spawn_player` gives the body authority 1, so on the server `is_local()` is true for it and `MovementComponent` runs there.
- Teammate bots don't collide with each other (collision exceptions, server side): the ducts and the shaft are one rat wide, and two bots meeting there head-on would block each other for good. Humans still bump into everyone.
- The owner-only setup (camera rig, interactor and ability input, `local_player_spawned`) is skipped on the server.
- `Player.server_*` helpers call `MovementComponent.do_*` directly for a bot. Every `rpc_id(peer)` that could reach a bot is guarded, because a negative id means "everyone except".

**Tick order (server physics)**
1. `AiBot` (priority −10) thinks at about 5 Hz, staggered across bots, and writes the body's `MoveIntent` (`common/move_intent.gd`) every tick.
2. `MovementComponent` (0) reads the intent instead of `Input`.
3. `Player` (10) fills `sync_position`/`yaw`/`pitch`. The driver fills `sync_anim` with `AnimationController.flags_for()`.

**Actions**
- Bots go through the same server checks as players, without RPCs:
  - `InteractionService.ai_start` / `ai_heartbeat` / `ai_stop`, and the `hold_ended` signal;
  - `AbilityService.ai_use`;
  - `ItemService.ai_place_trap`;
  - `CctvConsole.stand_up`.
- Bots never use minigames: the hold repair is always accepted.

**Navigation**
- `AiNav` bakes one navmesh per role from the level's static colliders when the server boots. The map check uses the same code.
- The level's `NavigationLink3D`s are added, plus a keycard link per keycard door on navigation layer 4; supervisors use that layer only while they hold a keycard.
- `AiPathFollower` handles ladders, drops, keycard doors, jumps and getting unstuck. Bots never teleport.
- Hazards (`AiHazards`, phase E) are handled by `AiDriver` for every goal: a bot waits at the edge of a
  live steam jet or puddle (or one that switches on before it could get through), never starts a hold
  inside one, steps out of a debris warning circle and waits there until the impact, and leaves the
  radiation zone once its exposure passes `radiation_limit_s` unless it is walking through. The hazard
  clocks are `Net.server_time()`.
- Rats plan around the traps they noticed: a path segment that runs over one gets a waypoint beside it,
  and a stand spot with a trap on it is swapped for one beside it, still in reach (`AiContext.stand_for`).

**Brains**
- Utility-scored goals (`server/ai/goals/`, `AiGoal`), each a small state machine; `AiScoring` holds the
  scores (pure, unit tested). A goal's `score()` picks a target that `start()` takes over, so the running
  goal keeps its own target while it is scored again. A goal that fails sits out 1.5 s.
  - Rats: Flee, RescueCarried (reflexes), Gang (bite a busy supervisor together, never next to a cage),
    Sabotage, LeverPair, Steal (a keycard, from behind), Harass, BreakCamera, FreeCaged, Lurk. Their
    targets are less appealing the closer a known supervisor is (`AiContext.danger_at`).
  - Supervisors: Capture, Chase (a known keycard thief counts more), Console (coolant, SCRAM), Repair,
    Investigate (a SNAP, a rat heard or called out or seen on the CCTV, an old trace), Keycard (a dropped
    one, the spare), Donut, FixCamera, PlaceTrap, Refill, Cctv (sit while the plant is calm), GuardCages,
    Patrol.
- Reflexes in `AiBot`: a rat bites the carrier of a teammate next to it; a supervisor swings the broom at
  a rat it sees in reach and in front, and turns toward whoever bit it.
- `AiSenses` is the only code that reads enemy positions: sight, hearing, Revealed, and the CCTV while
  seated (rats near an unbroken camera's lens, in its view, in sight of it). Sounds (bites, broom swings)
  reach it through `AiDirector.sound_events`, a SNAP through `ItemService.snap_heard`, a keycard theft
  (seen by a supervisor that sees the thief) through `ItemService.keycard_stolen`. It also notices things:
  traps (rats: within 6 m, in sight, the skill's `trap_notice` chance, one roll each), which cameras are
  broken (supervisors: close up, on the Control Room's screens, from the chair) and dropped keycards.
- `AiBlackboard` (one per team) holds claims, the lever pairing, the gang (which rat bots are close to
  which supervisor), shared traps and thieves (callouts), and accounts for human teammates.
- `AiContext` is what a goal works with (body, driver, senses, blackboard, the level's targets in
  `AiDirector.World`, the bot's own `RandomNumberGenerator`, cached path lengths).
- The numbers live in `data/bot_tuning.tres`.

**Watching and measuring (phase F)**
- Every 30 s of a match the server log gets a summary line per bot (time per goal, distance, stuck
  counts, path failures, cost per tick split into senses / think / goal / driver) and the AI's total
  cost per physics frame against a budget of 0.3 ms per bot. The test result's `ai` section has the
  worst frame.
- Keeping it cheap: strategic goals score at most every `AiGoal.STRATEGIC_RESCORE_S` (reactive ones at
  every think), navmesh closest points go through `AiNav.snap` (cached on a 0.25 m grid: the meshes never
  change in a match), path lengths are cached per target, and the driver looks at hazards and doors 10
  times a second.
- `--ai-labels` (debug builds) sends each bot's current goal to every client twice a second
  (`MatchManager.on_ai_labels`, unreliable); a spectating client shows it under the bot's name tag.
- `tests/integration/ai_balance.sh` (manual) plays many bots-only matches in parallel and prints who won
  and the team stats: the tuning target is that both teams win sometimes.

## 7. Data-driven tuning
All tunables are custom `Resource` classes saved as `.tres`:
```
data/
  match_rules.tres          # MatchRules: duration_s, duration_single_supervisor_s, countdown_s, post_match_s, swarm_bonus…
  roles/supervisor.tres     # RoleData: height, radius, walk, sprint, stamina, jump, abilities[]
  roles/rat.tres
  subsystems/rods.tres …    # SubsystemData: id, display_name, heat_weight, critical, hazard_kind, icon
  abilities/broom.tres …    # AbilityData: id, kind, input_action, range, cone_deg, cooldown_s, status, status_duration, extra
  pvp_tuning.tres           # PvpTuning: carry time, invulnerability windows, free/steal holds, spare keycard delay, donut, doors, trap charges
  plant_tuning.tres         # PlantTuning: the subsystem list, cooling rate, thresholds, meltdown rates, sabotage/repair amounts and hold times,
                            #   minigame amounts/lockout/min duration, control room actions (coolant, SCRAM)
  hazard_tuning.tres        # HazardTuning (M6): activation hysteresis, steam / puddle / radiation / debris / smoke numbers
  bot_tuning.tres           # BotTuning (M10): AI think rate, hearing, memory, claims, the easy/normal/hard BotSkill presets, bot names
                            #   (bot_fill_to and bot_difficulty are MatchRules keys, so server.cfg [match] can set them)
```
The GDD tables and these files must stay in sync. A GUT test (`tests/unit/test_data_sanity.gd`) loads every resource and asserts value ranges.

## 8. Rendering and audio (client only)
- Forward+ renderer on desktop, with a fallback to the Compatibility renderer for weak GPUs (setting in M8).
- Toon look (M7, details in [ASSETS.md §1](ASSETS.md#1-art-direction)): `shaders/toon.gdshader` (+ `toon_light.gdshaderinc`) for models, `outline.gdshader` as their `next_pass`, `toon_world.gdshader` for the level surfaces, `toon_glass.gdshader`. The glTF import script `tools/godot/toon_import.gd` puts the shared materials on every model.
- `common/art.gd` (`Art`): load a generated model, find its named parts, tint them or set their glow per instance. `client/vfx.gd` (`Vfx`): GPU particle effects (puffs, sparks, BONK stars, steam, arcs, radiation motes, dust, stun stars) and the camera shake (`Config.camera_shake`, `--no-shake`). Every factory returns null on a headless process.
- Audio: `client/sfx.gd` (`Sfx`) is the sound bank (names → files, bus, distance, pitch variation); buses in `default_bus_layout.tres`; `client/music_director.gd` plays the alarm-driven music stems (an `AudioStreamSynchronized`). Sfx and Vfx keep small caches that Session clears when it leaves, and do nothing headless (a cache still holding resources at exit is an error the integration tests catch).
- The server export strips visuals automatically ("Dedicated Server" export mode). Any client-only node must check `DisplayServer.get_name() != "headless"` before doing visual work, or live in client-only scenes. Code that bots need (sync_anim) runs on headless clients too; only the visuals are skipped.

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
| Unit | GUT, headless | `plant_model`, `match_rules_model`, status stacking, team balance, data sanity, hazard rules (hysteresis, cycles), the minigames' rules, the clock offset |
| Integration | Shell script launching separate headless processes (`tests/integration/*.sh`) | A server on a random port (`--exit-after-match --result-file`) plus bot clients (`--bot rat\|supervisor`) that connect, pick their role and ready up (the real ready vote, `min_players=2`: `--debug-start` would start before the preferences arrive), go to a sabotage point and complete it (plus a lever-pair variant). Since M4, `pvp_*.sh` run PvP scenarios: the capture chain, bites and the swarm bonus, items and traps, and a "hacked client" sending bad `request_*` calls. The scripts assert the result JSON, the exit code, the server log, and that the logs contain no errors. Since M5 the match tests run on the plant, the PvP ones on the TestArena; `plant_cctv.sh` covers the CCTV, the ladder, the shaft and the kill volumes. Since M6, on the plant: `hazards.sh` (every hazard hits, both teams, hysteresis), `minigames.sh` (wins, a loss, a hacked instant win, walking away), `control_room.sh` (coolant, SCRAM, cooldowns, the timer penalty). |
| Menus (M8) | `test_user_settings.gd` (clean values, save/load round trip, rebinding), `test_menus_logic.gd` (key text, LAN packets and list, awards, chat filter), `test_menu_focus.gd` (arrow keys through every screen), `test_translations.gd` (every text in the CSV, both languages, same placeholders); `tests/integration/menus_smoke.sh` (the real menus, headless: LAN discovery and join, the password prompt, kicked, lost, timeout, bad address) | Run with the other tests |
| Assets (M7) | `tests/unit/test_assets.gd` | Every sound file, music stem, model and named part the code uses exists; the characters have every clip the AnimationController plays; no CSG left in the plant |
| Visual (M7, windowed) | `tests/helpers/MapTour.tscn` (`--players 6 --no-vsync` for the performance numbers), `CharacterTour.tscn` (every animation state), `ArtGallery.tscn` (models under the real shaders), `HazardTour.tscn`; M8: `UiTour.tscn` (every menu and in-game screen with made-up data, `--lang fr`), `HowToShots.tscn` (the How to play illustrations) | Screenshots to look at; not run in CI |
| Map check | `tests/integration/map_check.sh` (`tests/helpers/MapCheck.tscn`) | Bakes a navigation mesh per role from the level's collision and checks the GDD §7 rules: reachability, walk times, two rat routes per sabotage point, supervisors kept out of the vents and the nest. `--update-docs` refreshes the table in docs/map/README.md. From M10 the bake is `AiNav`'s, the same one the bots use. |
| AI bots (M10) | GUT: `test_bot_fill.gd`, `test_ai_scoring.gd`, `test_ai_path_follower.gd`, `test_ai_blackboard.gd`, `test_ai_senses.gd`. Integration (`ai_lib.sh` helpers, `SEED=N`): `ai_fill.sh` (one client + 5 bots; also against an exported server, `SERVER_BIN=`), `ai_target.sh` (a client cages an AI rat), `ai_nav_tour.sh`, `ai_match.sh` (a bots-only match: sabotages, repairs, distance walked, nobody stuck, no strikes or errors), `ai_lever.sh`, `ai_capture.sh`, `ai_items.sh` (traps, refill, donut), `ai_steal.sh` (keycard, spare), `ai_control.sh` (coolant, SCRAM), `ai_cctv.sh` (chair, cameras); `test_ai_hazards.gd`. Manual: `ai_soak.sh`, `ai_balance.sh` | Loop each one 5× with different seeds. Watch mode: a `--ai-only` server plus a windowed client that joins as a spectator |
| Manual | Run Instances (editor: *Debug → Customize Run Instances*) | 1 instance with `-- --server --debug-start`, 3 instances with `-- --connect 127.0.0.1:7777`. A server started without `--headless` turns V-Sync and rendering off in its window: on Wayland a hidden window is throttled to about 1 frame/s, which slowed the whole server |
| Network conditions | `tc netem` on Linux (`sudo tc qdisc add dev lo root netem delay 80ms 20ms loss 1%`) | Play with 80–150 ms latency before calling any PvP feature done |

Commands (from M0):
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
tests/integration/run_match_loop.sh
```

## 11. Build and CI
- Export presets (`export_presets.cfg`, committed **without** credentials): `Linux` (x86_64), `Windows Desktop` (x86_64), `Linux Server` and `Windows Server` (Dedicated Server mode, custom feature tag `dedicated_server`). All embed the `.pck`, so every build is a single file.
- `.github/workflows/build.yml`: on every push to any branch → the tests from `ci.yml` (unit + integration) → the 4 exports → the branch's rolling GitHub release `build-<branch>` is replaced (master: "Latest", other branches: pre-release). The release holds the binaries plus `build.json` (build number = workflow run number, commit, SHA-256 of each binary). CI writes `common/build_info.gd` (repo, branch, build number, commit) before exporting.
- `.github/workflows/ci.yml`: pull requests, and called by `build.yml`. `delete-branch-build.yml`: deleting a branch deletes its release.
- Auto-update (`autoload/updater.gd`, exported CI builds only): at startup, read `build.json` of the followed branch (the build's own branch, or `--branch NAME`); if it is newer or from another branch, download the matching binary, check its SHA-256, rename the running executable to `<exe>.old-<time>` (deleted at a later start), move the new one in, and restart with the same arguments. The client shows the progress (Esc skips). The server's first process only supervises: it runs the real server as a child with `--update-supervisor PID`, restarts it when it exits with code 75, and the child stops when the supervisor is gone (Godot starts children in their own session, so Ctrl+C would not reach a plain relaunch). The child checks again every 5 min while nobody is connected. `Session.game_version()` adds `+<branch>.<number>` in CI builds, so clients only join a server running the very same build.
- `Dockerfile` (server): `debian:stable-slim`, copy the server binary, `EXPOSE 7777/udp`, `ENTRYPOINT ["./homersim_server.x86_64", "--headless", "--", "--server", "--config", "/config/server.cfg"]`.
- Windows builds are exported **from Linux** with the official export templates (no Windows machine needed; `rcedit` is optional for the .exe icon). Test them on a real Windows PC or VM before each release.

## 12. Security and robustness checklist
- Validate every `request_*` (sender exists, role, status, distance, LOS, cooldown, rate limit of about 20 requests/s per peer).
- Chat: max 200 characters, rate limit of 1 message/s, strip BBCode.
- An optional server password is checked in the `request_join(name, version, level, password)` handshake (M8). Protocol/version mismatches, a full server and a wrong password are refused with a `LeaveReason.Code` the client turns into a clear message.
- Names are sanitised and unique-ified ("Bob (2)").
- Kick on repeated validator strikes. A `kick`/`ban` console command on the server (stdin) arrives in M9.

## 13. Repository layout
```
homersim/
  project.godot  export_presets.cfg  main.tscn  main.gd
  autoload/        net.gd events.gd config.gd log.gd cli.gd
  common/          Session.tscn session.gd match_manager.gd match_rules_model.gd
                   plant_sim.gd plant_model.gd interaction_service.gd chat_service.gd role.gd
                   ability_service.gd capture_service.gd item_service.gd minigame_service.gd hit_check.gd rate_limiter.gd
                   keys.gd leave_reason.gd lan_discovery.gd awards.gd (M8)
  server/          ServerMain.tscn server_main.gd hazard_director.gd movement_validator.gd heatmap_recorder.gd lan_announcer.gd
                   ai/ (M10: ai_director.gd ai_nav.gd ai_bot.gd ai_driver.gd ai_path_follower.gd ai_senses.gd
                        ai_blackboard.gd ai_scoring.gd ai_context.gd goals/)
                   (later server_console.gd)
  translations/    strings.csv (keys = English, en, fr)
  client/          MainMenu.tscn menu_background.gd ServerBrowser.tscn lan_browser.gd Settings.tscn HowToPlay.tscn
                   Credits.tscn HUD.tscn Chat.tscn chat_filter.gd Lobby.tscn PostMatch.tscn pause_menu.gd scoreboard.gd
                   event_feed.gd hints.gd map_overlay.gd map_view.gd SpectatorCam.tscn minigame_host.gd alarm_effects.gd
                   menu_test_hooks.gd
                   sfx.gd (sound bank) vfx.gd music_director.gd stun_stars.gd
                   ui/ (theme.tres, ui.gd autoload, message_dialog.gd)
  entities/player/ Player.tscn player.gd character_visual.gd  supervisor/ rat/ LobbyVisual.tscn (role visuals)
  components/      movement/ camera/ status/ interactor/ abilities/ inventory/
                   animation/ (animation_controller.gd body_fx.gd)
  interactables/   interactable.gd sabotage_point/ critical_lever/ repair_point/ door/ cage/
                   cctv/ console_action/ vent/ ladder/ pickup/ trap/ body_handles/
  minigames/       minigame.gd wrench_rhythm/ breaker_sequence/ valve_rotate/
  hazards/         hazard.gd hazard_rules.gd steam_jet/ electric_puddle/ radiation_zone/ debris/ smoke/
  levels/          poi.gd spawn_point.gd out_of_bounds.gd level_map.gd map_info.gd  test/TestArena.tscn
                   plant/Plant.tscn + plant/PlantMap.tres + plant/pois/*.tscn + plant/materials/ + plant/shells/
                   (generated by tools/map/gen_plant.py)
                   plant/baked/ (tools/godot/bake_shells.gd)  plant/props/ (alarm beacon, CCTV screens, status board,
                   plant_prop.gd, prop_multimesh.gd)  ambient_sound.gd
  data/            match_rules.tres plant_tuning.tres roles/ subsystems/ abilities/
                   (scripts: match_rules.gd role_data.gd plant_tuning.gd subsystem_data.gd)
  shaders/         toon.gdshader toon_light.gdshaderinc outline.gdshader toon_world.gdshader toon_glass.gdshader materials/
  assets/          palette.png  third_party/<pack>/  generated/  audio/{sfx,music}/  fonts/ (Luckiest Guy, Fredoka)
                   ui/howto/ (How to play illustrations)
  default_bus_layout.tres  (audio buses)
  addons/          gut/  (later: netfox/ …)
  tools/blender/   common.py export_all.py preview.py + one script per family (machines, plant, interactables,
                   furniture, dressing, kenney, supervisor, rat, fp_arms, broom, crate)
  tools/art/       palette.py make_palette.py   tools/audio/ make_audio.py synth.py music.py
  tools/godot/     toon_import.gd (glTF import script) bake_shells.gd make_theme.gd (UI theme)   tools/build_assets.sh (all of it)
  tools/map/       gen_plant.py (the graybox plant + its plan)   tools/heatmap.py (playtest position logs)
  tests/           unit/ integration/ helpers/bot_client.gd helpers/pvp_bot.gd helpers/m6_bot.gd
                   helpers/{MapTour,CharacterTour,ArtGallery,HazardTour}.tscn (windowed visual checks)
  docs/            GDD.md ARCHITECTURE.md ASSETS.md milestones/ map/ playtests/ screenshots/ art/
  .github/workflows/ci.yml  Dockerfile  server.cfg.example  CREDITS.md  README.md
```
