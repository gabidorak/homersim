# M4: PvP

**Goal**: every player-vs-player interaction from the GDD, still with capsule visuals. Broom stun → grab → carry → cage → free / eliminate, bites → slow → knockdown, stealing, traps, donuts, keycard doors, spectating, plus team and ghost chat.
**Estimated effort**: 3 weeks.
**Prerequisites**: M3 (playtested).
**Design refs**: [GDD §5](../GDD.md#5-roles), [ARCHITECTURE §3](../ARCHITECTURE.md#3-authority-model).

## 1. Tasks
### Status system (complete it)
- [ ] `StatusComponent`: statuses `STUNNED, SLOWED, KNOCKED_DOWN, CARRIED, CAGED, ELIMINATED, INVULNERABLE, REVEALED, LOCKED`, each with an expiry time plus optional data (slow factor, carrier peer). Rules:
  - stun/bite/knockdown are ignored while `INVULNERABLE`
  - rats get 1.5 s of stun immunity after a stun ends; supervisors get 3 s of knockdown immunity
  - slow factors multiply, with a floor at 0.4
  - `can_act()` is false while stunned, knocked down, carried, caged or eliminated
- [ ] `tests/unit/test_status_rules.gd`: stacking, immunity windows, expiry, bite → knockdown counting (3 bites within 6 s).
- [ ] Client feedback: placeholder icons above heads (stars for stunned, a snail for slowed, and so on) and HUD status icons for the local player.

### Abilities
- [ ] `data/ability_data.gd` (`AbilityData`: `id`, `range`, `cone_deg`, `cooldown_s`, `status`, `status_duration`, `extra`) plus `data/abilities/broom.tres`, `bite.tres`, `snap_trap.tres`, `cheese_lure.tres`.
- [ ] `components/abilities/ability_component.gd`: local input → `request_use_ability(id, aim_dir)`. The server checks the cooldown and `can_act`, then runs the ability's `server_execute()`. Cooldowns are synced for the HUD.
- [ ] **Broom**: the server finds rats within range + 0.5 m tolerance and inside the cone (relative to the synced look direction), with a LOS ray to the rat's centre. It applies `STUNNED 2 s` to the nearest one only. The `on_broom_swing(peer)` cosmetic RPC plays to all. A hit makes a BONK sound.
- [ ] **Bite**: the nearest supervisor in range + tolerance → `SLOWED 0.7 × 3 s`, and the bite is recorded. 3 bites within 6 s → `KNOCKED_DOWN 4 s`.
- [ ] **Swarm bonus** in `MatchManager`: all supervisors `KNOCKED_DOWN` at once → `PlantSim.add_meltdown(15)`, at most once every 45 s.

### Capture chain
- [ ] **Grab**: an `Interactable` behaviour on the rat body (supervisor-only, instant, the target must be `STUNNED`). The server sets the rat to `CARRIED(carrier)` and sends `attach_to(carrier/HandSocket)` to the rat's owner. The supervisor gets the carry speed.
- [ ] While carried: the rat's client snaps to the hand socket each frame. The server auto-releases after 8 s, or when another rat bites the carrier (then the rat is dropped at the carrier's position, `INVULNERABLE 1.5 s`).
- [ ] **Cage** (`interactables/cage/cage.gd`): a supervisor carrying a rat presses E → the rat goes to `CAGED` and is `force_position`ed inside the cage. `captures[rat] += 1`; on the 2nd capture → `ELIMINATED` instead.
- [ ] **Free**: rat-only hold for 4 s on an occupied cage → the caged rat is released with `INVULNERABLE 3 s` and pushed out of the cage door.
- [ ] Win check: all non-eliminated rats are caged → supervisors win (already in `check_winner`; now testable).

### Spectating and chat channels
- [ ] `client/SpectatorCam.tscn`: a free-fly camera (noclip), or cycle through players with LMB/RMB. Used by eliminated rats and late joiners. Caged rats get a cage camera that orbits the cage.
- [ ] `ChatService`: `TEAM` channel (T key) and `GHOST` channel (eliminated players only; alive players never receive it). Server-side routing.

### Items, traps, doors, pickups
- [ ] `components/inventory/inventory.gd` (server-authoritative, synced): `keycard: bool`, `stolen_item: StringName`, `trap_charges: int`.
- [ ] **Steal**: rat-only, 1 s hold, the target supervisor must be facing away (dot product < 0) → move the keycard to the rat (rat at 0.9× speed). When the carrying rat is stunned → the keycard becomes a dropped pickup (`Dynamic` spawner); any supervisor can pick it up.
- [ ] **Keycard doors** (`interactables/door/keycard_door.gd`): supervisor with a keycard → opens for 3 s (server-synced `open` state, `AnimatableBody3D`). Normal doors open for everyone; rats push them (auto-open on proximity).
- [ ] **Traps**: `request_place_trap(kind, pos)` → validate that the position is on the floor within 2 m and the player has charges → spawn via the `Dynamic` spawner. Snap trap: a rat entering its `Area3D` → `STUNNED 3 s` + `on_trap_snap` to supervisors, then the trap is consumed. Cheese lure: rat touch → `REVEALED 10 s`, then consumed.
- [ ] **Revealed outline**: a client-side outline shader (a second material pass, `depth_test` disabled) shown only to the enemy team for revealed players.
- [ ] **Pickups** (`interactables/pickup/pickup.gd`): trap refill (Storage), spare keycard (Storage, 30 s after loss), donut (Break Room, `+20% speed 20 s`, 60 s cooldown per supervisor).
- [ ] Stats: catches, frees, bites, knockdowns, steals.

## 2. Done when
- [ ] The full capture chain works with 3 clients at **100 ms simulated latency**: swing → stun → grab → carry → cage → teammate frees → 2nd capture → eliminated → spectator with ghost chat.
- [ ] 3 rats biting quickly knock a supervisor down. The knockdown immunity prevents perma-stun, and the swarm bonus triggers once.
- [ ] Stealing a keycard locks the supervisor out of keycard doors until it's recovered or the spare arrives.
- [ ] Traps and lures work, and enemies never see their placement outlines.
- [ ] Nothing can be triggered by a hacked client sending raw RPCs. Test this with a debug console calling `request_*` with bad args, wrong role, or out of range.
- [ ] A playtest note was written, and the balance tweaks went into `data/`.

## 3. Pitfalls
- "Carried" breaks the client-owned movement model on purpose. Make sure `MovementValidator` exempts the `CARRIED` and `CAGED` statuses, and that the carried rat's client stops reading input.
- Tolerance-based hit checks feel generous to the attacker. That's fine for a comedy game, so err on that side.
- Make sure every status change is server-side. The client only *displays* it.
- Despawning a carrier on disconnect must also release the carried rat.
