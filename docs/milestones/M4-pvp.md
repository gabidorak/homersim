# M4: PvP

**Goal**: every player-vs-player interaction from the GDD, still with capsule visuals. Broom stun → grab → carry → cage → free / eliminate, bites → slow → knockdown, stealing, traps, donuts, keycard doors, spectating, plus team and ghost chat.
**Estimated effort**: 3 weeks.
**Prerequisites**: M3 (playtested).
**Design refs**: [GDD §5](../GDD.md#5-roles), [ARCHITECTURE §3](../ARCHITECTURE.md#3-authority-model).

## 1. Tasks
> Implemented on 2026-10-01, before the M3 playtest happened. Notes on what differs from the plan are in *italics* under each task.
### Status system (complete it)
- [x] `StatusComponent`: statuses `STUNNED, SLOWED, KNOCKED_DOWN, CARRIED, CAGED, ELIMINATED, INVULNERABLE, REVEALED, LOCKED`, each with an expiry time plus optional data (slow factor, carrier peer). Rules:
  - stun/bite/knockdown are ignored while `INVULNERABLE`
  - rats get 1.5 s of stun immunity after a stun ends; supervisors get 3 s of knockdown immunity
  - slow factors multiply, with a floor at 0.4
  - `can_act()` is false while stunned, knocked down, carried, caged or eliminated
  - *The rules are pure logic in `components/status/status_rules.gd` (`StatusRules`); the component runs them on the server's clock and publishes `flags`, `speed_factor`, `carrier` and `carrying` through StatusSync. Extra status `BOOSTED` (the donut). Speed factors are named sources (`bite`, `donut`, later hazards): slows multiply down to 0.4, boosts apply on top. Two extra rules: a stun or knockdown can't be re-applied while active (otherwise a broom every 1.2 s would stun-lock a rat forever), and bites during knockdown immunity still slow but don't count. Immunity windows live in `RoleData` (`stun_immunity_s`, `knockdown_immunity_s`).*
- [x] `tests/unit/test_status_rules.gd`: stacking, immunity windows, expiry, bite → knockdown counting (3 bites within 6 s).
- [x] Client feedback: placeholder icons above heads (stars for stunned, a snail for slowed, and so on) and HUD status icons for the local player.
  - *Coloured text labels for now ("* STUNNED *", "slowed", "CAGED"…, `StatusComponent.describe()`), in a `StatusTag` above heads and a HUD row. Knocked-down bodies fall flat, stunned ones wobble, a knocked-down supervisor's view drops to the floor. Real icons in M7.*

### Abilities
- [x] `data/ability_data.gd` (`AbilityData`: `id`, `range`, `cone_deg`, `cooldown_s`, `status`, `status_duration`, `extra`) plus `data/abilities/broom.tres`, `bite.tres`, `snap_trap.tres`, `cheese_lure.tres`.
  - *Also `display_name`, `kind` (MELEE_STUN, BITE, TRAP) and `input_action`. Listed per role in `RoleData.abilities`. Numbers that aren't an ability (carry time, invulnerability windows, holds, spare keycard, donut, doors, trap charges) are in `data/pvp_tuning.tres`; the swarm bonus is in `match_rules.tres`.*
- [x] `components/abilities/ability_component.gd`: local input → `request_use_ability(id, aim_dir)`. The server checks the cooldown and `can_act`, then runs the ability's `server_execute()`. Cooldowns are synced for the HUD.
  - *The request handlers live in a new `AbilityService` in Session (RPCs need a node the server owns, like InteractionService). Cooldowns start locally on use and the server sends its own value back (`on_ability_cooldown`); the server forgives 0.1 s of jitter.*
- [x] **Broom**: the server finds rats within range + 0.5 m tolerance and inside the cone (relative to the synced look direction), with a LOS ray to the rat's centre. It applies `STUNNED 2 s` to the nearest one only. The `on_broom_swing(peer)` cosmetic RPC plays to all. A hit makes a BONK sound.
  - *The cone is flat (yaw only) so a rat at your feet still counts (`common/hit_check.gd`, unit-tested). The client's aim is used if it is within 45° of the synced look. Sounds are generated placeholders (`client/sfx.gd`).*
- [x] **Bite**: the nearest supervisor in range + tolerance → `SLOWED 0.7 × 3 s`, and the bite is recorded. 3 bites within 6 s → `KNOCKED_DOWN 4 s`.
- [x] **Swarm bonus** in `MatchManager`: all supervisors `KNOCKED_DOWN` at once → `PlantSim.add_meltdown(15)`, at most once every 45 s.

### Capture chain
- [x] **Grab**: an `Interactable` behaviour on the rat body (supervisor-only, instant, the target must be `STUNNED`). The server sets the rat to `CARRIED(carrier)` and sends `attach_to(carrier/HandSocket)` to the rat's owner. The supervisor gets the carry speed.
  - *`GrabHandle`, added to rat bodies by `Player.setup()`. The capture logic is in a new `CaptureService`. Carried rats lose their collision layer, so the carrier doesn't bump into the rat hanging in front of it.*
- [x] While carried: the rat's client snaps to the hand socket each frame. The server auto-releases after 8 s, or when another rat bites the carrier (then the rat is dropped at the carrier's position, `INVULNERABLE 1.5 s`).
  - *Also released when the carrier is stunned, knocked down or gone (disconnect). Every escape gives the 1.5 s of invulnerability. Other peers draw the carried rat at the hand socket too.*
- [x] **Cage** (`interactables/cage/cage.gd`): a supervisor carrying a rat presses E → the rat goes to `CAGED` and is `force_position`ed inside the cage. `captures[rat] += 1`; on the 2nd capture → `ELIMINATED` instead.
  - *4 slots per cage, two cages in the test arena. An eliminated rat's body is despawned and its roster entry gets `eliminated: true`, so it spectates like a late joiner (the `ELIMINATED` status stays unused for now).*
- [x] **Free**: rat-only hold for 4 s on an occupied cage → the caged rat is released with `INVULNERABLE 3 s` and pushed out of the cage door.
  - *One hold frees one rat, the one caged first.*
- [x] Win check: all non-eliminated rats are caged → supervisors win (already in `check_winner`; now testable).

### Spectating and chat channels
- [x] `client/SpectatorCam.tscn`: a free-fly camera (noclip), or cycle through players with LMB/RMB. Used by eliminated rats and late joiners. Caged rats get a cage camera that orbits the cage.
  - *The cage camera is the rat's own ThirdPersonRig with a longer arm that ignores the cage bars.*
- [x] `ChatService`: `TEAM` channel (T key) and `GHOST` channel (eliminated players only; alive players never receive it). Server-side routing.
  - *`ChatService.route()` is pure and unit-tested. Ghosts (eliminated players and spectators) can't talk to the living: whatever channel they pick becomes GHOST. Team chat only exists during a match.*

### Items, traps, doors, pickups
- [x] `components/inventory/inventory.gd` (server-authoritative, synced): `keycard: bool`, `stolen_item: StringName`, `trap_charges: int`.
  - *Also `spare_wait_left` and `donut_wait_left` (whole seconds, for the prompts). Synced by StatusSync.*
- [x] **Steal**: rat-only, 1 s hold, the target supervisor must be facing away (dot product < 0) → move the keycard to the rat (rat at 0.9× speed). When the carrying rat is stunned → the keycard becomes a dropped pickup (`Dynamic` spawner); any supervisor can pick it up.
  - *`StealHandle` on the supervisor's back; the facing is re-checked every tick, so turning around cancels the steal. Caging a rat also drops what it carries. The items logic is in a new `ItemService`.*
- [x] **Keycard doors** (`interactables/door/keycard_door.gd`): supervisor with a keycard → opens for 3 s (server-synced `open` state, `AnimatableBody3D`). Normal doors open for everyone; rats push them (auto-open on proximity).
  - *`interactables/door/door.gd` (`Door`, `auto_open` on or off) plus a `KeycardReader` interactable on each side of `KeycardDoor.tscn`. The Break Room has one of each.*
- [x] **Traps**: `request_place_trap(kind, pos)` → validate that the position is on the floor within 2 m and the player has charges → spawn via the `Dynamic` spawner. Snap trap: a rat entering its `Area3D` → `STUNNED 3 s` + `on_trap_snap` to supervisors, then the trap is consumed. Cheese lure: rat touch → `REVEALED 10 s`, then consumed.
  - *Hold RMB to see the spot, release to place; Q switches the kind. Also checked: line of sight, 0.6 m between traps, the trap cooldown (1 s). A rat that can't be stunned right then (invulnerable, immune) doesn't set off a snap trap.*
- [x] **Revealed outline**: a client-side outline shader (a second material pass, `depth_test` disabled) shown only to the enemy team for revealed players.
  - *`shaders/reveal_outline.gdshader`, as `material_overlay` on the body's meshes.*
- [x] **Pickups** (`interactables/pickup/pickup.gd`): trap refill (Storage), spare keycard (Storage, 30 s after loss), donut (Break Room, `+20% speed 20 s`, 60 s cooldown per supervisor).
  - *The test arena got a small Storage corner (east wall) and a donut counter in the Break Room.*
- [x] Stats: catches, frees, bites, knockdowns, steals.

## 2. Done when
- [ ] The full capture chain works with 3 clients at **100 ms simulated latency**: swing → stun → grab → carry → cage → teammate frees → 2nd capture → eliminated → spectator with ghost chat.
  - *Without added latency, `tests/integration/pvp_capture.sh` runs this exact chain with 3 headless bots and checks every step. Still to do: the same with `tc netem` (needs sudo) and by hand in windowed clients.*
- [x] 3 rats biting quickly knock a supervisor down. The knockdown immunity prevents perma-stun, and the swarm bonus triggers once.
  - *`tests/integration/pvp_swarm.sh` (also checks that a bite makes a carrier drop its rat).*
- [x] Stealing a keycard locks the supervisor out of keycard doors until it's recovered or the spare arrives.
  - *`tests/integration/pvp_items.sh`, which also covers traps, lures, the donut and the trap refill.*
- [ ] Traps and lures work, and enemies never see their placement outlines.
  - *Traps and lures work (`pvp_items.sh`). The placement preview only exists on the placing client by construction; check it by eye in a windowed session.*
- [x] Nothing can be triggered by a hacked client sending raw RPCs. Test this with a debug console calling `request_*` with bad args, wrong role, or out of range.
  - *`tests/integration/pvp_hack.sh`: two bots send about 25 bad requests (wrong role, unknown ability, NaN arguments, out of range, cooldown spam, no charges, wrong channel) and the test checks that each was refused and nothing happened.*
- [ ] A playtest note was written, and the balance tweaks went into `data/`.

## 3. Pitfalls
- "Carried" breaks the client-owned movement model on purpose. Make sure `MovementValidator` exempts the `CARRIED` and `CAGED` statuses, and that the carried rat's client stops reading input.
- Tolerance-based hit checks feel generous to the attacker. That's fine for a comedy game, so err on that side.
- Make sure every status change is server-side. The client only *displays* it.
- Despawning a carrier on disconnect must also release the carried rat.
- *Learned: a remote body that glides through yours shoves you (it's a kinematic obstacle). Server-imposed jumps over 2 m now snap instead of gliding.*
- *Learned: despawning a body while its owner still sends positions makes Godot log "Ignoring sync data … for missing node" (packets in flight for the freed node). It showed up with 3-4 bots under load. Bodies are now retired in two steps (`Session.retire_bodies`).*
