# Game Design Document: HomerSim (working title)

> Every number in this document is a **starting value**. They are mirrored 1:1 in the `data/*.tres` resources (see [ARCHITECTURE.md § Data-driven tuning](ARCHITECTURE.md#7-data-driven-tuning)). Tune them there and update this file after each playtest.

## 1. Pitch
It's the night shift at the **"Sunny Acres" Nuclear Plant** (placeholder name; all names and characters are original, nothing borrowed from existing shows). A few underpaid, donut-loving **Supervisors** only have to keep the reactor stable until the shift ends. Meanwhile a gang of **Rats** has moved into the sewers and has *ideas*.

- Genre: asymmetric team PvP, 2–6 players by default (up to 9 when the host picks bigger teams), rounds of 8–10 minutes.
- Feel: slapstick, readable, chaotic. Think Hello Neighbor's look, Chained Together's goofiness, and Dead by Daylight's asymmetry, without the horror.
- Platforms: Windows and Linux. Each match runs on a dedicated server. The game can start one on the player's own computer: **Play solo** (a match against bots that nobody else can join) and **Host a game** (friends join it; the game ends when the host leaves).

## 2. Teams and win conditions
| | Supervisors | Rats |
|---|---|---|
| Count | 1–2 (the host can pick 1–3) | 3–4 (the host can pick 1–6) |
| Camera | First person | Third person |
| Goal | Survive the shift: timer reaches 0 with meltdown < 100% | Fill the meltdown meter to 100% |
| Alternate win | **All rats are caged or eliminated at the same time** | – |

**Swarm bonus** (replaces the "swarm win" in the original plan): if **all** supervisors are knocked down at the same moment, meltdown instantly gets **+15%** (at most once every 45 s). A hard win condition would be far too easy to reach against a single supervisor.

**Team seats**: each team has a number of seats, **2 supervisors and 4 rats** by default (`max_supervisors`, `max_rats`). Whoever starts a game picks them (**1–3 supervisors, 1–6 rats**, the spawn points the plant has): Play solo and Host a game have a row for each, a dedicated server sets them in server.cfg. A match never has more players than seats: the rest spectate.

**Team auto-balance** (when nobody picks): with fewer players than seats, the teams are split in the same proportion as the seats, rounded to the nearest (a half goes to the rats), with at least one player on each team. With the default 2 + 4 seats that gives the table below; with 3 + 6 seats, 6 players are 2 supervisors and 4 rats.

| Players (default seats) | Supervisors | Rats |
|---|---|---|
| 2 | 1 | 1 |
| 3 | 1 | 2 |
| 4 | 1 | 3 |
| 5 | 2 | 3 |
| 6 | 2 | 4 |

When there is a single supervisor, the *match timer* drops to 8 min (otherwise 9 min) to compensate.

**Bots** (M10): a server can fill its matches with AI players (`bot_fill_to` in server.cfg; 0 = off, the default). At role assignment, bots are added until the match has `bot_fill_to` players (never more than the seats), and the auto-balance above sets the team sizes. Play solo and Host a game set `bot_fill_to` to the seats: **bots take every seat nobody fills**, so with bots on every match is exactly the teams the host picked. **Humans always get their slots first**: bots take whatever is left. Bots are only in the match: they aren't in the lobby, don't vote, and leave when it ends. A player who leaves mid-match is not replaced. See [§5.5](#55-bots).
**Play solo** (main menu) is a game with bots on the player's own computer: they pick the role they'd like, the teams (1–3 supervisors, 1–6 rats, themselves included) and the bots' difficulty, and the match starts at once. The game doesn't pause.
A single rat can't do the **critical** sabotages (two levers held at once, §4.3); the setup cards say so when Rats is 1.

## 3. Match flow
1. **Lobby**: players join the server, set a name, and pick a preferred role (Supervisor / Rat / Any). Text chat is available. The match starts when the host-less "ready" vote passes (more than 50% ready and at least 3 players, or 2 when the seats are 1 + 1), or immediately with the `--debug-start` flag. On a server with bots, the vote only counts humans, and a single player is enough.
2. **Role assign** (instant): roles are assigned from preferences plus the team seats and auto-balance above.
3. **Countdown, 10 s**: everyone is spawned and frozen. Supervisors start in the Break Room, rats in the Rat Nest.
4. **Playing, 9:00** (8:00 with one supervisor).
5. **Post-match, 15 s**: winner banner, each team's stats (sabotages, repairs, catches, bites, hazard hits…) and a few fun awards (most bonks, sneakiest rat, donut addict…). Then everyone returns to the lobby.

## 4. Plant simulation
There are six subsystems, each with `health` from 0 to 100 that starts at 100.

| # | Subsystem | Location | `heat_weight` | Sabotage | Hazard when health < 50 |
|---|---|---|---|---|---|
| 1 | Control rods | Reactor Hall | 3.0 | **Critical** (2 rats) | Radiation zone |
| 2 | Coolant pumps | Pump House | 2.5 | Normal | Steam jets |
| 3 | Coolant valves | Valve Corridor | 2.0 | Normal | Steam jets |
| 4 | Turbine | Turbine Hall | 1.5 | **Critical** (2 rats) | Flying debris |
| 5 | Power grid | Substation | 1.5 | Normal | Electrified puddles |
| 6 | Ventilation | Roof | 1.0 | Normal | Smoke (low visibility) |

### 4.1 Core temperature
`core_temp` is an abstract number from 300 to 1000 (300 = nominal).
```
damage_i      = (100 - health_i) / 100                      # 0..1
heat_in       = Σ damage_i * heat_weight_i                  # units/s
heat_in      *= 0.5 if SCRAM active
cooling       = 1.5 if core_temp > 300 else 0               # units/s
core_temp    += (heat_in - cooling) * dt ; clamp(300, 1000)
```
### 4.2 Meltdown meter (0–100%)
```
if core_temp > 700:  meltdown += 1.0 %/s * (core_temp - 700) / 100
if core_temp < 400:  meltdown -= 0.25 %/s           # slow recovery, never below 0
```
Worked check: three systems fully broken (rods + pumps + valves) gives +6 units/s, so 300 → 700 takes about 67 s. At ~800 the meter fills at about 1%/s, so meltdown arrives roughly 2.5–3 min after a sustained heavy assault. With good repairs, supervisors should hover at 500–700.

**Alarm states** drive lights, music and HUD: `NORMAL` < 500 ≤ `WARNING` < 700 ≤ `CRITICAL`.

### 4.3 Sabotage (rats)
- **Normal** sabotage point: hold for **4 s** (cancelled by any movement, stun, or being hit), then **−50 health**.
- **Critical** sabotage (2 levers about 6 m apart): both levers must be held at the same time for **6 s**, then **−100 health**.
- Each subsystem has a **20 s sabotage cooldown** after a successful sabotage (shown as sparks), so rats have to spread out.
- Each subsystem has 2 sabotage points (normal) or 1 lever pair (critical).

### 4.4 Repair (supervisors)
- **Minigame repair** (M6, the default): about 4–6 s of play gives **+50 health**. A failed minigame gives +10 and **jams that repair point for 3 s** (for everyone). Results that arrive less than **3 s** after the minigame opened are refused as a hack. Being bitten, stunned or knocked down, or stepping away (0.5 m), closes the minigame. Esc gives up (no penalty). One supervisor at a time per repair point.
  - *Wrench rhythm* (pumps, turbine): click while the sweeping marker is in the green zone, 3 times in a row (3 misses or 12 s lose).
  - *Breaker sequence* (grid, ventilation): watch 4–5 of 6 breakers flash, then flip them in order (one wrong breaker or 10 s lose).
  - *Valve rotate* (valves, rods): drag in circles to turn the wheel into the green band (1.25–2.5 turns), hold it there 1 s (15 s limit).
  - Difficulty grows with the damage (faster marker, narrower zone, longer sequence, more turns).
- **Hold repair** (accessibility option, the M3 fallback; client flag `--hold-repairs` until the M8 settings toggle): hold for **6 s**, then **+35 health**. The server accepts both.
- Subsystems with health 0 must first be "rebooted": a hold of 3 s before repairs can start (either way).

### 4.5 Control room actions (supervisors)
| Action | Effect | Cooldown | Requirement |
|---|---|---|---|
| Emergency coolant | `core_temp −150` | 90 s | Power grid health ≥ 25 |
| Partial SCRAM | `heat_in × 0.5` for 30 s | 120 s | Costs **+30 s** on the match timer (the shift gets longer). A big red button under a flip cover: the 1st press lifts the cover (it drops after 5 s), the 2nd fires |
| CCTV | View 8 cameras (cycle with Q/E), while the body stays vulnerable in the chair | – | The camera must not be broken |
| Plant status board | Always visible in the room: per-subsystem health and alarm lights, the actions' cooldowns and SCRAM time | – | – |

Each action's console has its own screen with its cooldown. The HUD shows the SCRAM time left and the seconds SCRAM added to the shift under the timer.

## 5. Roles
### 5.1 Supervisor
| Stat | Value |
|---|---|
| Height | 1.8 m (capsule radius 0.35) |
| Walk / sprint | 4.0 / 6.0 m/s |
| Stamina | 5 s of sprint, regenerates in 4 s after a 1 s delay |
| Jump | 1.0 m |
| Carry speed | 3.2 m/s (no sprint) |

Abilities:
- **Broom swing** (LMB): 2.0 m range, 70° cone, 1.2 s cooldown, **stuns a rat for 2.0 s** (rats get 1.5 s of stun immunity after a stun ends).
- **Grab** (E on a stunned rat): carry the rat at carry speed. It escapes on its own after **12 s** (about 38 m: the pumps, the valves and the control rods are one carry from the Reactor Hall's cage), and a single bite from another rat makes the supervisor drop it (so does getting stunned or knocked down). A dropped rat lands at the carrier's feet with **1.5 s of invulnerability**.
- **Cage** (E at a cage while carrying): the rat is caged. See [elimination](#53-capture-and-elimination).
- **Traps** (hold RMB to aim, release to place, Q to switch the kind; 3 snap traps and 3 cheese lures, counted separately: the trap box in Storage refills the snap traps, the cheese box next to it the lures; within 2 m, on the floor, at least 0.6 m apart). Only the placing supervisor sees the aiming preview:
  - *Snap trap*: stuns the rat that steps on it for 3 s and plays a loud SNAP heard by every supervisor. A rat that can't be stunned right then (invulnerable, stun immunity) doesn't set it off.
  - *Cheese lure*: when a rat touches it, that rat is outlined through walls for supervisors for 10 s.
- **Donut** (Break Room counter): the supervisor takes one and carries it (one at a time; the counter has the next one 60 s later). Selecting it in the inventory and pressing E eats it: +20% move speed for 20 s.
- **Inventory**: a hotbar at the bottom of the screen with an icon and a count per item. Supervisors pick a slot with 1 / 2 / 3 or the mouse wheel: snap trap, cheese lure (each shows how many are left; the selected one is what RMB places), donut. The keycard sits on its own to the left (crossed out while a rat has it). A rat's stolen keycard shows there too.
- **Keycard**: opens keycard doors (supervisor shortcuts) for **3 s**. Every supervisor spawns with one. Normal doors open by themselves for anyone nearby (rats push them).

### 5.2 Rat
| Stat | Value |
|---|---|
| Height | 0.5 m (capsule radius 0.2), with a chunky cartoon silhouette |
| Walk / sprint | 5.0 / 7.5 m/s |
| Stamina | 3 s of sprint, regenerates in 3 s after a 1 s delay |
| Jump | 1.6 m (so rats can reach tables, crates and pipe runs) |
| Vents | Can enter vents (0.7 m openings). Supervisors cannot. |

Abilities:
- **Bite** (LMB): 1.2 m range, 2.5 s cooldown. It **slows a supervisor by 30% for 3 s**. **3 bites within 6 s (any rats) = knockdown for 4 s**, followed by 3 s of knockdown immunity.
- **Steal** (E behind a supervisor, 1 s hold): takes the supervisor's keycard (or broom, from M6). The rat carries it and moves 10% slower. If the rat is stunned, it drops the item. A supervisor without a keycard can get a spare from the Storage locker after a 30 s delay.
- **Free a caged rat** (hold E for 4 s at a cage). One hold frees one rat, the one caged first.
- **Break a CCTV camera** (hold E for 2 s). A supervisor fixes it with a 3 s hold.
- **Squeak emote** (Z): purely for fun.

### 5.3 Capture and elimination
- 1st capture: the rat is **caged**. Rats in a cage can't act but can chat and spectate through the cage's camera.
- Freed rats leave the cage with **3 s of invulnerability**.
- 2nd capture: the rat is **eliminated** and becomes a free-cam spectator with access to the **ghost chat** (only eliminated players read it).
- If every rat that isn't eliminated is caged, **supervisors win immediately**.
- Supervisors are never eliminated. A knockdown is their worst state.

### 5.4 Status effects (shared system)
| Status | Source | Effect |
|---|---|---|
| Stunned | Broom, trap, hazards | No movement or actions. Can't be re-applied while active (no stun-lock chains) |
| Slowed (stacks multiply, floor at 40%) | Bite, radiation, puddle | Speed × factor |
| Knocked down | 3 bites, debris | Ragdoll-ish fall, no actions |
| Carried | Grabbed by a supervisor | The rat's position follows the carrier's hand |
| Caged | Cage | Locked in the cage |
| Eliminated | 2nd capture | Spectator |
| Invulnerable | Freed from cage, dropped by a carrier | Ignores stun/bite/knockdown (supervisors get 3 s of knockdown immunity instead; bites during it slow but don't count) |
| Revealed | Cheese lure, radiation | Outline visible to the enemy team through walls |

### 5.5 Bots
AI players fill empty slots (M10, [milestone](milestones/M10-ai-bots.md)). They play like humans:

- **Bot rats** sabotage machines, team up on critical lever pairs (with a human rat too), use the vents and flee from supervisors. They bite, gang up on a busy supervisor, rescue a carried friend, free caged rats, break CCTV cameras, steal keycards and squeak.
- **Bot supervisors** patrol, repair (always the hold repair, never the minigames) and reboot. They chase, bonk, grab and cage rats, set traps and refill them, and answer a SNAP. They also use their keycard, collect a spare when theirs is stolen, eat donuts, sit at the CCTV, fix cameras, and use the coolant and the SCRAM.

**Fair play.** A bot only knows what a human in its seat could know:
- what it sees: within its view range and field of view, with a clear line of sight, after a short reaction time;
- what it hears: footsteps (rats sprinting are louder), bites, squeaks, the SNAP;
- enemies that are Revealed;
- what the HUD and the map show anyone: machine health, cooldowns, cage occupants;
- what the CCTV shows, while it sits in the chair.

Bot teammates share what they see, like a callout. Bots never skip a rule: same speeds, reaches, holds and cooldowns as humans.

**Difficulty** (server.cfg `bot_difficulty`; starting values, tuned in `data/bot_tuning.tres`):

| | Easy | Normal (default) | Hard |
|---|---|---|---|
| Reaction time | 0.7 s | 0.4 s | 0.2 s |
| Aim error | 30° | 15° | 6° |
| Turn rate | 250°/s | 400°/s | 600°/s |
| View range | 15 m | 22 m | 30 m |
| Decisions per second | 3 | 5 | 6 |
| Chance to notice a trap (within 6 m, in sight) | 40% | 75% | 95% |
| Teamwork (lever pairs, gang bites) | off | on | on |

Bots are marked as such on their name tag, in the scoreboard (BOT instead of a ping), on the post-match screen and in the lobby ("Bots fill the match up to N players").

## 6. Hazards
These activate when a subsystem's health drops **below 50**, switch off again once it is back to **60 or more** (hysteresis, so they don't flicker), and **affect both teams**. Numbers live in `data/hazard_tuning.tres`. A hazard hits each body at most once per live window; carried, caged and frozen bodies are never hit. Note that one normal sabotage leaves a subsystem at exactly 50: it takes a second sabotage (or a critical one) to start its hazards.

| Hazard | Behaviour | Effect |
|---|---|---|
| Steam jets (pumps, valves) | Cycle: on for 3 s, off for 3 s, a puff 0.6 s before each blast. 3 jets per POI, taking turns (phases). | Knockback of 6 m/s away from the nozzle (plus 3 m/s up) and a 1 s stun |
| Electrified puddles (grid) | 3 pools of water light up for 2 s every 5 s (a flicker just before) | 1.5 s stun, then 50% slow for 2 s |
| Radiation zone (rods) | Glowing zone around the reactor pool (not the levers); exposure builds 1 s per second inside and drains as fast outside, up to 5 s. Geiger clicks speed up with exposure | Once exposure reaches 5 s: 20% slow while inside, **Revealed** while inside and for 5 s after leaving |
| Turbine debris | A falling bolt or panel every 8 s at a random spot in the Turbine Hall, with a 1 s warning circle | Within 1.5 m: knockdown for 3 s (supervisor) or 2 s stun (rat) |
| Smoke (ventilation) | Fog in the vent network and the Control Room (cosmetic only) | Visibility drops to about 6 m |

## 7. Map: "Sunny Acres" plant
One level, about **104 × 64 m** plus the sewer nest, two floors in places (catwalks, the vent roof). A 2 m grid. Layout v1 (M5, graybox) is drawn in [docs/map/plant_layout_v1.png](map/plant_layout_v1.png), with its rationale and measured paths in [docs/map/README.md](map/README.md).

```
              N
   ┌──────────────────────────────────────────────┬──────────────┐
   │ SUBSTATION │      YARD (outdoor)  COOLING     │  VENT ROOF   │  6 m block:
   │ (fenced)   │      lobby spawns     TOWER      │  (ladder,    │  ladder from the yard,
   ├──────┬─────┴──────────┬────────────────────────┴──┬───────────┤  shaft for rats
   │ PUMP │   REACTOR HALL │       TURBINE HALL        │  STORAGE  │
   │HOUSE │   (10 m, catwalk 4 m)   (8 m, catwalk 3.5 m)├───────────┤
   ├──────┤                │                           │           │
   │      ├────────┬───────┴─────────┬─────────────────┤   CAGE    │
   │VALVE │MAIN HALL WEST  │ CONTROL │ MAIN HALL EAST  │   ROOM    │
   │CORR. ├────────────────┤  ROOM   ├─────────────────┤           │
   │      │  BREAK ROOM    │ (hub)   │  LOCKER ROOM    │           │
   │      ├────────────────┴─────────┴─────────────────┴───────────┤
   │      │                SOUTH CORRIDOR                          │
   └──────┴────────────────────────────────────────────────────────┘
        ▼ vents run outside the walls  ·  RAT NEST (sealed sewer room) to the south
```
| POI | Purpose | Notes |
|---|---|---|
| Control Room | Supervisor hub: status board, CCTV chair, wall screens, remote actions (M6) | 2 doors (west, east) and 1 vent (a one-way drop). Windows overlook the Reactor and Turbine Halls. |
| Reactor Hall | Control rods (critical), a cage | 10 m high, glowing pool, L-shaped catwalk at 4 m. The west cage (M10) stands under the west catwalk: rats caught at the rods, the pumps or the valves are one carry from it |
| Turbine Hall | Turbine (critical) | Long hall, the turbine control desk behind the turbine, catwalk at 3.5 m, crates up for rats |
| Pump House | Coolant pumps | Cramped, pipes for rats to run along |
| Valve Corridor | Coolant valves | A long hall split by a valve rack; keycard shortcut to the Break Room |
| Substation | Power grid | Outdoor, fenced, in the yard (puddles in M6) |
| Vent Roof | Ventilation | Reached by the yard ladder (everyone) or the vent shaft (rats) |
| Break Room | Supervisor spawn, donuts | Coffee and vending machines |
| Storage | Trap box and cheese box (refills), spare keycards | Shelves rats can hide on |
| Cage Room | 2 cages, near two vent openings, far from the nest | The tension spot |
| Locker Room | Connector with a keycard door (to the South Corridor) | Rows of lockers to hide between |
| Main halls, South Corridor | Connectors | The nest's vent comes out in the South Corridor |
| Rat Nest | Rat spawn (sewer south of the plant) | Sealed: the only way out is the vent. Unreachable for supervisors |

**Design rules for the map** (checked by `tests/integration/map_check.sh` on every build)
- Every sabotage point can be reached by rats via ≥ 2 routes, and at least 1 of them is a vent.
- From the Control Room, no sabotage point is more than 25 s away at supervisor walking speed.
- The vent network has 1-way drop exits, so rats can't camp vents forever.
- 8 CCTV cameras cover the key rooms, with blind spots on purpose.

## 8. Controls (defaults, rebindable in Settings → Controls since M8)
Keys are physical positions: on an AZERTY keyboard WASD is ZQSD, and the game shows the keys as printed on the
player's keyboard. Esc can't be rebound (it always opens the menu).

| Action | Key |
|---|---|
| Move / look | WASD / mouse |
| Jump / sprint / crouch* | Space / Shift / Ctrl (*rats: squeeze) |
| Primary (broom / bite) | LMB |
| Secondary (trap / –) | RMB |
| Interact (hold) | E |
| Chat / team chat | Enter / T |
| Scoreboard (hold) | Tab |
| Map (press again to close) | M |
| Menu (frees the mouse; the game keeps running) | Esc |
| Lobby: role preference any / supervisor / rat, ready | 1 / 2 / 3, R |
| Emote | Z |
| CCTV chair: previous / next camera, stand up | Q / E, Space |
| Repair minigames: play / give up | Mouse / Esc |
| Playtest tools: debug overlay, stopwatch | F3, F4 |

## 9. Audio and feedback
- Global alarm music layers: calm, then warning, then critical (crossfade on alarm state). Room lights shift to amber (WARNING) and pulse red (CRITICAL); the HUD's edge tint flashes when the alarm gets worse.
- Every action has an exaggerated SFX: bonk, squeak, SNAP, hiss, and a donut munch.
- HUD: timer, meltdown meter, core temperature gauge, subsystem icons (health colour), status effect icons, and an interaction progress ring.
- Map: a minimap in the top right corner (turns with the camera, names the room you're in) and the full plant map on M. Both show the machines in their health colour, the cages, your own team, and enemies only while they are Revealed (ghosts see everyone). Rats also see the vents, supervisors their pickups. Settings → Gameplay can hide the minimap or keep north up.

## 10. Post-1.0 ideas
- Proximity voice chat (Opus via a Godot addon, or a GDExtension).
- Steam release (GodotSteam lobbies, achievements).
- HTTP master server list plus a matchmaking/orchestration service.
- Client-side prediction with the netfox addon.
- More maps (oil rig, dam), new rat classes (fat rat, tech rat), cosmetics (hats!).
- Bots taking over the slot of a player who leaves mid-match (bots that fill a match at the start: M10, [§5.5](#55-bots)).
