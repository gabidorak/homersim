# M10: AI bots ("the AI update")

**Goal**: a match is never short of players. When there aren't enough humans, the dedicated server fills the match with **AI rats and supervisors** that walk the plant and do everything a human can do. Bots play fair: they only know what a human in their seat could know. One person alone can now play a full match against bots.
**Estimated effort**: 5–7 weeks (A 1 week, B 1–1.5, C 1, D 1, E 1.5–2, F ongoing).
**Prerequisites**: M8 and the in-game map. M9 is not needed, and the bots make M9's balance playtests easier.
**Design refs**: [GDD §2 Bots, §5.5](../GDD.md#55-bots), [ARCHITECTURE §6 AI bots](../ARCHITECTURE.md#ai-bots-m10-serverai).

## 0. Key decisions
These were agreed when the milestone was planned (2026-10-03).
- **Fill rule.** At role assignment, the server adds bots until the match reaches `bot_fill_to` players (`[match]` in server.cfg; 0 = no bots, the default). The GDD §2 balance table sets the team sizes, and **humans always get their slots first**. Bots exist only during a match: they are not in the lobby and don't vote. When the match ends they leave. A player who leaves mid-match is not replaced (optional task in phase F).
- **Solo play.** When bots are on, the ready vote needs a single human.
- **Full feature set**, with three difficulty presets (easy, normal, hard).
- **Bots run inside the dedicated server.** Their bodies are owned by the server (multiplayer authority 1), which runs the same `MovementComponent` physics a player's game runs. `BodySync` then replicates them server → clients, so clients need no new code to see them. Headless bot *client* processes were rejected: they cost 100–200 MB each, take player slots, and the server would have to manage the processes.
- **Ids.** Bots get **negative ids** (−1001, −1002, …), because ENet ids are always positive. Bots live in `MatchManager.roster` with `"bot": true` and are **never** in `Session.players`. That keeps chat, the event feed, pings, the FULL check, the LAN player count and the updater's "server empty" check correct.
- **Naming.** Code and CLI say **"ai"** (`server/ai/`, `AiDirector`, `--ai-*`), because "bot" already means the test clients (`--bot`, `BotClient`, `InteractorComponent.bot_hold`). Players see "Bot".
- **Decision model.** Bots use **utility scoring**: every goal gets a score about 5 times a second, and the bot does the best one. Each goal is a small state machine, and a blackboard per team handles coordination. Every decision can be one log line (`Gus: SupRepair(pumps) 0.82 > SupPatrol 0.30`), which keeps it easy to debug.

## 1. Tasks

### A. Plumbing (bot bodies that exist, can be hit and caged, and leave cleanly)
- [x] `data/match_rules.gd/.tres`: `bot_fill_to := 0`, `bot_difficulty := 1` (0 easy, 1 normal, 2 hard). Both can be overridden in `[match]` like every other key. Add commented examples to `server.cfg.example`.
- [x] `data/bot_tuning.gd` + `data/bot_skill.gd` + `data/bot_tuning.tres`: the AI numbers (think rate, hearing radii, memory time, commitment bonus, claim TTLs…), the three `BotSkill` presets (section 2.6), and the bot name list (original, goofy, no "Bot" in the name). Add the file to `tests/unit/test_data_sanity.gd`: 3 skills, values in range and monotonic from easy to hard, unique non-empty names, and `bot_fill_to` either 0 or in 2..6.
- [x] `common/match_rules_model.gd` (pure):
  - `bots_needed(humans, rules) -> int`: 0 if `bot_fill_to < 2`; otherwise the target is `mini(bot_fill_to, supervisors_for(bot_fill_to) + max_rats)` and the result is `maxi(0, target − humans)`.
  - `effective_min_players(rules)`: 1 when bots are on, `min_players` otherwise.
  - `assign_roles(prefs, rules, rng, fillers: Array[int] = [])`: only humans are shuffled. Supervisor slots go to human SUP, then human ANY, then **fillers**, then human RAT. Rat slots go to human RAT, ANY, SUP, then **fillers**. Fillers left over are dropped, never made spectators. With no fillers the result is exactly today's.
- [x] `common/session.gd`:
  - `static func is_ai_id(id) -> bool` (`id < 0`).
  - `name_of(peer)` falls back to the roster name.
  - `spawn_body` adds `"name"` and `"bot"` to the spawn data, so it no longer reads `players[peer].name`.
  - `_spawn_player` sets `player.is_bot` and `set_multiplayer_authority(1 if bot else peer)`.
  - `retire_bodies`: turn a bot's `BodySync` visibility off right away and keep it in the despawn grace wait. Otherwise in-flight server → client sync packets log "Ignoring sync data".
  - The server adds `AiDirector` under ServerOnly; add `var ai_ready := false`.
- [x] `entities/player/player.gd`:
  - `var is_bot := false`.
  - `color_for_peer` uses `fposmod` (a negative id gave a negative hue).
  - `server_force_position / apply_impulse / set_locked / attach_to` call `movement.do_*()` directly for a bot instead of `rpc_id`.
  - `local_player_spawned` is emitted only off the server.
  - On clients the name tag shows a "Bot" badge.
- [x] `components/movement/movement_component.gd`:
  - `var intent: MoveIntent` (new `common/move_intent.gd`: world direction, sprint, one-shot jump, `face_yaw`, `turn_rate`). When it is set, the input block reads it instead of `Input`.
  - Each server → owner RPC is split into the guarded `@rpc` plus a plain `do_*` method.
- [x] Skip owner-only setup on the server: `CameraRig` (no camera, no mouse capture), `InteractorComponent` and `AbilityComponent` processing (`and not Net.is_server`).
- [x] `components/animation/animation_controller.gd`: move the flag logic into a static `flags_for(body, interacting, emoting, in_vent)`. `local_flags()` calls it, and the AI driver uses it to fill `sync_anim`, so bot bodies animate on clients.
- [x] Server API for the AI (the existing internal functions, made public):
  - `InteractionService`: `ai_start(peer, target) -> String`, `ai_heartbeat(peer)`, `ai_stop(peer)`, and `signal hold_ended(peer, path, reason)`.
  - `AbilityService.ai_use(peer, id, aim)`.
  - `ItemService`: `ai_place_trap(peer, id, pos)` and `signal snap_heard(pos)`.
  - `CctvConsole.stand_up(peer)`.
  - `DebrisZone.pending_impacts()`.
  - `Cage._name_of` uses `Session.name_of`.
- [x] **Guard every `rpc_id(peer)` that can reach a bot**: `on_ability_cooldown` (ability and item services), `on_trap_snap`, `ChatService.tell`, the refusal paths of `on_hold_ended` / `on_minigame_closed`. Re-grep `rpc_id(` afterwards. In Godot a **negative** target id means "everyone except", so an unguarded call doesn't just fail, it goes to the wrong players.
- [x] `common/match_manager.gd`:
  - The ready vote and the min-players rule count **humans** (`_human_count()`). When bots are wanted, wait for `session.ai_ready`. `recheck_start()` is called by AiDirector after the bake.
  - `_start_match` creates the bot entries `{name, pref: NONE, ready: false, role, eliminated: false, bot: true}` and passes them to `assign_roles` as fillers.
  - When no humans are left in a running match (spectators count as humans), log it and go back to the lobby, unless `--ai-only`.
  - `request_debug_done` and `_min_to_continue` skip bots.
  - `_back_to_lobby` drops the bot entries before respawning lobby bodies.
  - Stats rows carry `"bot": true`, and the test result JSON gets an `"ai"` section (`AiDirector.report()`).
- [x] UI (in the cartoon theme, see the existing scoreboard / post-match styles):
  - Scoreboard: the ping cell says BOT, and the footer counts humans.
  - Post-match: a Bot badge.
  - Lobby: a line "Bots fill the match up to %d players" (`server_info.bot_fill_to`).
  - Add the new texts to `translations/strings.csv` (en + fr).
- [x] `server/ai/ai_director.gd` + a trivial `AiBot` that turns and walks in short legs through `MoveIntent`.
- [x] Debug server flags (debug builds only, like the other test flags): `--ai-only` (start with 0 humans), `--ai-fill N`, `--ai-seed S`, `--ai-log`.

### B. Navigation and movement
- [x] `server/ai/ai_nav.gd` (`AiNav`): move the bake out of `tests/helpers/map_check.gd`, and make the map check use it, so it validates exactly the meshes the bots walk on.
  - Same agent specs:
    - supervisor: radius 0.35, height 1.8, climb 0.3, cell 0.175;
    - rat: radius 0.2, height 0.5, climb 0.6, cell 0.1;
    - both: cell height 0.05, slope 45°, `edge_max_length` 4.
  - Parse the static colliders on `PhysicsLayers.WORLD` with the auto doors left out. The keycard doors stay closed.
  - Copy the level's `NavigationLink3D`s per role layer (yard ladder, vent shaft, one-way Control Room drop).
  - Add **one link per keycard door** on navigation layer 4 (KEYCARD). Supervisors query with `1 | 4` while they hold a keycard and with `1` without one.
  - Bake asynchronously at server boot, after 2 physics frames. Log the time it takes (about 0.8 s today). Free every RID on exit.
  - Paths come from `NavigationServer3D.query_path` with link metadata, so the follower knows which segments are ladders, drops or keycard doors.
  - Check that the map-check tables don't change. If ignoring the door panels by layer gives different results, keep map_check's move-the-panels method.
- [x] `server/ai/ai_path_follower.gd` (pure, unit tested):
  - Advance to the next waypoint within 0.3 m (rat) or 0.4 m (supervisor) and |dy| < 1, and slow to walking speed over the final 1.5 m.
  - **Ladders**: steer along `Ladder.up_direction()` until the top, then keep pushing to step off.
  - **Drops**: walk off.
  - **Steps and jumps**: CharacterBody3D has no step-up. Jump when the next point is 0.15–1.4 m higher within 1.5 m, or when blocked against a wall.
  - **Keycard links**: stop, press the `KeycardReader`, then cross within the door's 3 s. If the keycard is lost on the way, repath without layer 4.
  - **Auto doors**: allow 1 s of grace while a door opens.
- [x] Stuck handling: every 0.5 s, compare the progress. Less than 0.15 m while the bot wants to move escalates in steps:
  1. jump;
  2. sidestep 0.5 s and jump;
  3. repath from the closest navmesh point;
  4. after 6 s, the goal fails and its target is blacklisted for 10–15 s.

  Bots **never teleport**. Log every hard-stuck spot to the log and to `user://ai_stuck.csv`.
- [x] Local avoidance kept simple: a teammate within 0.8 m ahead shifts the steering 0.4 m sideways; anything worse is left to the stuck handling.
- [x] `server/ai/ai_driver.gd`, the actions a goal can ask for:
  - `go_to(pos)`, `face(pos)`.
  - `hold(target)`: wait until the bot moves slower than 0.2 m/s (a hold cancels after 0.5 m of movement), `ai_start`, then `ai_heartbeat` every 0.25 s.
  - `press(target)`, `use(ability, aim)`, `place_trap(kind, spot)`, `emote()`, `stand_up()`.

  The driver also writes `sync_anim`. Physics order: `AiBot` at priority −10, then `MovementComponent` at 0, then `Player` at 10.
- [x] Debug flag `--ai-scenario tour`: every bot visits its share of all the targets of its role (sabotage points, levers, repair points, cages, pickups, consoles, cameras, vent exits).

### C. Rat brain
- [x] `server/ai/ai_senses.gd`: fair perception, and the **only** code that reads enemy positions (grep for this in review).
  - **Sight**: within the skill's view range, inside the field of view (supervisor 110°, rat 220° for its third-person camera), with a line-of-sight ray from the eyes on `PhysicsLayers.WORLD`. An enemy only counts after `reaction_s` of continuous sight. In active smoke the view range drops to 6 m.
  - **Hearing**: moving enemies within the hearing radius (rats walking 3 m, sprinting 8 m; supervisors 10 m), bites within 10 m and squeaks within 12 m. A sound gives a position with ±2 m of noise.
  - **Always known**: REVEALED enemies (the outline through walls), what the HUD and the map show (machine health, offline machines, sabotage cooldowns, cage occupants), and the bot's own statuses and inventory.
  - **Memory**: an enemy's last known position is kept for 8 s, then becomes a "search this area". Teammate bots share their sightings with a 1 s delay, like a callout.
- [x] `server/ai/ai_blackboard.gd` (one per team):
  - Claims with a TTL: `repair:<sub>`, `sabotage:<sub>`, `lever:<sub>:A|B`, `free:<cage>`, `chase:<rat>`, `camera:<n>`, `cctv_chair`, `steal:<sup>`, `trap_spot:<cell>`. A claim is released when its bot is removed.
  - The lever-pairing handshake.
  - The gang target.
  - Events (SNAP positions, the last bite on each supervisor).
  - **Human teammates count**: a machine a human is repairing (`holder_count > 0` or `minigame_user`) is skipped, and a lever a human holds alone is a standing request for a partner.
- [x] `server/ai/ai_scoring.gd` (pure static functions, unit tested) and `goals/ai_goal.gd` (`score`, `start`, `tick` → RUNNING / DONE / FAILED, `stop`, `label`). The running goal gets a commitment bonus (+0.15) so bots don't flip-flop. **Reflexes** act at once: flee, rescue a carried friend, bite a carrier.
- [x] Rat goals:

  | Goal | Score | Actions |
  |---|---|---|
  | Sabotage | `heat_weight × health/100`, extra when the hit drops health below 50 (that starts the hazards), divided by the path time. Lower when a known supervisor is near the point. 0 on cooldown or when claimed | Go to `stand_position(RAT)`, stop, hold 4 s. Sometimes squeak afterwards |
  | LeverPair | Critical subsystem value × a partner being available | Claim a lever, hold it. The first bot there waits for its partner (15 s at most); both levers held together for 6 s |
  | Flee | A known supervisor within 6–8 m and closing, or a broom swing heard | Pick from up to 6 candidates (vent exits and vents within 20 m, spots away from the threat) the one with the best "their path − my path" margin, and sprint there |
  | RescueCarried | A teammate is CARRIED | Chase the carrier and bite it: one bite makes it drop the rat |
  | Harass | A supervisor busy and standing still (repairing, in the CCTV chair) | Approach from behind, bite when ready, keep 3 m away while on cooldown |
  | FreeCaged | Someone is in a cage and no supervisor is known within 10 m of it | Hold 4 s at the cage |
  | Lurk | The default | Wait in a vent near the next target until its cooldown ends; squeak now and then |

### D. Supervisor brain
- [x] Supervisor goals:

  | Goal | Score | Actions |
  |---|---|---|
  | Repair | `(100 − health) × heat_weight`, ×2 when offline, scaled by the alarm level and the distance. Skipped when claimed or when a human is fixing it | Go to `stand_position(SUPERVISOR)`, reboot (3 s), then hold-repair (6 s) again while it needs it. Waits out a lockout. Bots never play the minigames: the server accepts the hold repair whatever the setting |
  | Chase | A known rat within 12 m. Very high when the rat is busy sabotaging (it stands still); low when it is fleeing more than 6 m away (rats are faster) | Steer toward where the rat is heading; the broom comes from the reflex |
  | Capture | A known STUNNED rat within reach, and a non-full cage reachable before the 8 s carry runs out at 3.2 m/s (with 1.5 s spare) | Press the rat's `GrabHandle`, walk to the cage, press it |
  | GuardCages | A cage has someone in it | Patrol the Cage Room's approaches |
  | Patrol | The default | Tour the machine rooms, weighted by `heat_weight × time since the last visit` |

- [x] Combat reflex: a supervisor that isn't carrying swings the broom when a known rat is within range + 0.2 m, inside 30° of its facing, and the broom is ready. Bitten, it turns toward the biter. Aim error and turn rate come from the skill. The server clamps the aim to 45° of the facing direction, so the bot must **face** first.
- [x] Debug flags `--ai-roles rat,rat,supervisor` and `--ai-goals role:goal,…` (only these goals) for focused tests.

### E. Advanced behaviours (the rest of the feature set)
- [ ] **Traps.**
  - Supervisors place snap traps at the rats' stand spots of valuable machines and levers, and cheese lures at vent exits near targets and on the cage approaches (`ai_place_trap`: within 2 m, on the floor, 0.6 m apart).
  - They refill at Storage when their charges run out and things are calm.
  - They go to a SNAP (`snap_heard`) within 25 m.
  - Rats notice a trap within 6 m with line of sight, with the skill's `trap_notice` chance, and walk around it.
- [ ] **Keycards.**
  - Rats steal from a supervisor that stands still and faces away (go behind, hold the `StealHandle` 1 s, flee to a vent).
  - A supervisor whose keycard was stolen chases a known thief, picks up a dropped keycard, or collects a spare at Storage once `spare_ready()`.
- [ ] **Donuts**: a supervisor eats one when it's ready and the Break Room is on the way or before a long trip.
- [ ] **CCTV.**
  - Supervisors sit in the chair when the plant is calm and the chair is free (claim). Each unbroken camera then reveals rats within 15 m of its lens with line of sight. They stand up after 20 s at most, when they spot a rat, or when the plant is damaged.
  - Rats break cameras near their route, especially while someone sits in the chair (hold 2 s). Supervisors fix broken cameras on their way (hold 3 s).
- [ ] **Control Room.**
  - Emergency coolant when `core_temp > 650`, it's ready and the grid is at 25 or more.
  - SCRAM (cover, then button, within 5 s) only when `core_temp > 760` or meltdown > 50 %, because it costs +30 s of shift.
- [ ] **Gang bites**: when 2 or more rat bots are within 12 m of the same supervisor, they bite together, going for the knockdown (3 bites in 6 s) and the swarm bonus.
- [ ] **Hazards.**
  - Wait at the edge of a live steam jet or puddle for its off phase (`Hazard.is_live(Net.server_time())`), and never start a hold inside a live hazard.
  - Step away from `DebrisZone.pending_impacts()` (humans see the warning circle).
  - Limit the time spent in the radiation zone.

### F. Difficulty, tuning, watch mode
- [ ] Difficulty presets in `BotSkill` (the starting values in GDD §5.5). The presets are picked with `bot_difficulty`.
- [ ] Optional: `--ai-labels` shows each bot's current goal under its name tag for a spectating debug client (an unreliable 2 Hz RPC on MatchManager, sent only with the flag).
- [ ] A 30 s AI summary line in the server log for each bot: goal times, distance, stuck counts, path failures. Also the physics time per frame, with a budget under 0.3 ms per bot.
- [ ] Solo playtests against bots on normal, in both roles. Bots-only matches over many seeds: **both teams should win sometimes** (tune `bot_tuning.tres`, not the game rules). Write notes in `docs/playtests/`.
- [ ] Optional: mid-match backfill. A bot takes over the role (not the body) of a human who left, at their team's spawn.

### Status (2026-10-03): phases A to D built
Everything above E is in place and tested (unit tests, `ai_fill.sh`, `ai_target.sh`, `ai_nav_tour.sh`,
`ai_lever.sh`, `ai_capture.sh`, `ai_match.sh`). Where the build differs from the plan:
- **Steps.** A bot jumps when the next point is **0.35**–1.4 m higher (not 0.15), or when it is blocked
  against a wall. Jumping at every 0.15 m rise landed rats on top of the duct mouths; lower steps are now
  tried on foot first.
- **Scraps of mesh.** The navigation mesh also covers the tops of props (a duct crossing the Reactor Hall,
  crates). A bot that ends up on one (knocked there, or a jump) finds that no path leads anywhere from
  it, and walks off it before planning again (`AiDriver`). Path ends must also match the destination's
  height within 0.6 m, so no goal ever targets one.
- **Failed goals rest.** A goal that just failed sits out 1.5 s, so a bot with nowhere to go doesn't
  re-plan every tick.
- **Chase** ignores a rat whose known spot is off the supervisors' mesh (a rat in a vent).
- **Teammate bots pass through each other** (collision exceptions between bot bodies of the same team,
  on the server). The ducts and the shaft are one rat wide: two rat bots meeting head-on there blocked each
  other for good, which the planned sideways shift can't solve. Humans still bump into everyone.
- **Ladders**: a bot lines up with the ladder (its foot and direction come with the link) before
  climbing, and climbs down until it touches the floor (pushing sideways in the air hung on the ladder).
- **Debugging tools** added on the way: `--ai-trace NAME|all`, `--ai-scenario path:A:B[:…]`, the client's
  `--spectate NAME|first` (watch mode), and `tests/integration/ai_soak.sh` (manual: matches back to back,
  memory sampled; 8 matches were stable at 207 MB).
- **Map check.** The tables are unchanged except two keycard-reader rows (supervisors now cross keycard
  doors through `AiNav`'s keycard links: up to 1 m and 0.2 s longer).
- **Tests.** The `ai_target` scenario has its own script (`ai_target.sh`, on the TestArena). `--ai-goals
  rat:none` gives a bot no goals at all (it stands still), and `--ai-scenario capture` puts the bots in
  the Cage Room when PLAYING starts (`ai_capture.sh`). With `--ai-only`, humans who join watch as
  spectators.
- **Balance** is phase F: in bots-only matches the rats are strong (meltdown 30–90 % after 150 s), and
  supervisor bots rarely catch anyone (a rat must be stunned within about 20 m of a cage).
- Measured: the AI costs 0.08–0.14 ms per bot per physics tick (budget 0.3 ms). `ai_fill.sh` passes
  against an exported Linux Server build (`SERVER_BIN=…`).

## 2. Done when
- [ ] With `bot_fill_to=6`, **one human** readies up alone and plays a full match against bots, as a rat and as a supervisor, and sees the bots do every action in the feature list.
- [ ] Bots-only matches (`ai_match.sh`, 5 seeds) finish without errors, with sabotages and repairs by both teams, and with each team winning at least once over 10 matches.
- [x] No bot gets hard-stuck in the nav tour or in a 10-match soak (`--ai-only`, matches back to back, no `--exit-after-match`). Memory stays stable. (`ai_nav_tour.sh` 5 seeds; `ai_soak.sh` 10 matches, 202.8 → 203.1 MB.)
- [x] Bots never cheat: a review of `server/ai/` finds no enemy position read outside `AiSenses`. (Outside it, the AI reads only its own body, its teammates and the level.)
- [x] Bots are clearly labelled: name tag badge, scoreboard, post-match screen, lobby line. (`UiTour --bots`, watch mode `--spectate first`.)
- [x] With `bot_fill_to=0`, every existing unit and integration test passes unchanged.
- [x] `ai_fill.sh` passes against an exported Linux Server build (release builds ignore the `--ai-*` test flags, so that run uses `bot_fill_to` from a config file).

## 3. Tests
- **Unit (GUT)**:
  - `test_bot_fill.gd`: `bots_needed` for every human count, fill and cap; `assign_roles` with fillers (human preferences honoured, a human is never a spectator while a bot plays, 1 human + fill 6 → 2 supervisors and 4 rats, no fillers → same result as today with a fixed seed).
  - `test_ai_scoring.gd`, `test_ai_path_follower.gd` (waypoints, link types, the stuck escalation fed with fake position samples).
  - `test_ai_blackboard.gd` (claim TTLs, release, the lever handshake).
  - `test_ai_senses.gd` (a pure `can_notice(...)`).
- **Integration** (`tests/integration/ai_*.sh`, built like `run_match_loop.sh`, with `--no-lan --no-heatmap`):
  - `ai_fill.sh` (A): one test client + 5 bots, the roles, the no-humans rule when the client quits, no bots in the lobby.
  - A `pvp_bot.gd` scenario `ai_target` (A): a scripted supervisor client stuns, grabs and cages an AI rat. This proves the direct `attach_to` / `force_position` paths.
  - `ai_nav_tour.sh` (B): every target reached, `ai.tour.failed == []`.
  - `ai_match.sh` (D): `--ai-only --ai-fill 6 --test-duration 150`. Asserts at least one sabotage and one repair, more than 100 m walked per bot, no stall over 8 s, no hard stuck, no validator strikes, no `ERROR` / `SCRIPT ERROR` in the logs.
  - `ai_lever.sh`, `ai_capture.sh`, `ai_items.sh`, `ai_control.sh` (C–E; `--ai-scenario` sets the plant state at PLAYING).
- Loop each new script **5 times with different `--ai-seed` values** before calling it done, and keep the thresholds loose.
- **Watch mode** (windowed): start a debug server with `--headless -- --server --ai-only --ai-fill 6 --ai-log`, then a client with `-- --connect 127.0.0.1:7777 --spectate first` (follow a bot; clicks cycle through the others). It joins mid-match as a spectator: the free camera plus the map, with everyone shown. `tools/heatmap.py` on the server's position log and `user://ai_stuck.csv` show where bots dwell or get stuck.

## 4. Pitfalls
- **`rpc_id` to a bot.** A negative target id means "everyone except |id|". Guard every owner-targeted RPC whose peer can be a bot; the integration tests' "no ERROR" check is the safety net. Check this behaviour on 4.7.2 in phase A.
- **Bots aren't in `Session.players`.** Any `players[peer]` for a body crashes (fixed: `spawn_body`, `Cage._name_of`). Use `name_of`.
- **`is_local()` is true on the server for a bot body** (it is the authority). Every `is_multiplayer_authority()` branch needs a look: camera rig, interactor, ability component, `local_player_spawned`. `MovementComponent` must keep running.
- **Physics order.** The AI writes the intent before `MovementComponent` reads it, and `Player` copies the position into `sync_position` afterwards (priorities −10, 0, 10). Never put AI logic inside `Player`.
- **Holds cancel after 0.5 m of movement** (leftover sliding is about 0.3 m). Stop first, keep a zero intent while holding, and plan again after a knockback.
- **Aim is clamped to 45° of `look_direction()`.** Turn toward the target before swinging or biting.
- **`assign_roles` must put fillers last** in both orderings, or a human loses a slot to a bot.
- **Roster counts.** `request_debug_done` and `_min_to_continue` count roster entries: leave bots out, or tests hang and matches with no humans left never end.
- **Release builds** ignore the `--ai-*` flags; `bot_fill_to` from server.cfg still works. Dedicated Server exports strip meshes, so the bake must parse **static colliders** only.
- **New `class_name`s** (`AiNav`, `AiBot`, `MoveIntent`, `BotTuning`…) need `godot --headless --import` before the tests see them.
- **Headless.** There is no `AnimationController`, camera or Art on the server: the driver fills `sync_anim`, and AI code never reads `Visual` nodes.
- **Setup order.** `MatchManager._ready` runs before `Session._ready`, so reach AiDirector lazily; AiDirector calls `recheck_start()` after the bake. Stand positions and the bake need registered physics shapes: wait 2 physics frames.
- **NavigationServer RIDs** must be freed when the Session exits, or the tests flag the leaks at exit.
- **Clocks.** Synced cooldowns (`ConsoleAction.ready_at`, `RepairPoint.lockout_until`, hazards) use `Net.server_time()`; the AI's own timers use `Time.get_ticks_msec()`. Don't mix them, and don't speed tests up with `Engine.time_scale`.
- **Determinism.** Each bot has its own `RandomNumberGenerator`, seeded from `--ai-seed` + its id. Never call the global `randf()`.
- **Short windows.** A keycard door stays open only 3 s: press the reader within about 1.5 m of the door. A carried rat escapes after 8 s: grab only when a cage is reachable in time.
- **Log volume.** Per-decision lines only with `--ai-log`: the server writes its log to a file.
- **Updater.** `Updater._server_empty()` sees a bots-only match as empty. That's harmless (`--ai-only` is debug only, and real matches end when the humans leave), but keep it in mind.
