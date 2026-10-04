# Playtest 2026-10-04: bots-only balance (M10 phase F)

No humans: bots against bots, to tune the AI (M10 phase F: "both teams should win sometimes", tuning
`data/bot_tuning.tres`, not the game rules). Played with `tests/integration/ai_balance.sh` (one headless
server per seed, 8 at a time, `--ai-only --ai-fill 6`: 2 supervisor bots against 4 rat bots, normal
difficulty). The human solo playtests (one person against 5 bots, in both roles) are still to do.

- **Build / commit**: on top of `6dd9340 Bots` (phases A–D), with phase E and F.
- **Players**: 2 supervisor bots, 4 rat bots, normal.
- **Matches played**: see the runs below.

## Runs

Every run: seeds 100–107 (or 200–207), normal difficulty. "240 s" runs end on the timer after 240 s, which
counts as a supervisor win ("the shift is over") although a full shift is 540 s.

| Run | Length | Change before it | Rats | Supervisors | Notes |
|---|---|---|---|---|---|
| A–D build | 200 s | (before phase E) | most | few | Meltdown in 150–200 s. 9 bonks, no capture: a rat had to be stunned within ~20 m of a cage, and every machine but the turbine is 40–100 m from the Cage Room |
| 1 | 240 s | phase E, carry 12 s, west cage in Main Hall West | 0 | 4 | Every rat caught in under a minute. The cage sat on the rats' walk from the nest and next to the supervisors' Break Room; rats ganged up on idle supervisors next to it |
| 2 | 240 s | cage moved to the Reactor Hall; gangs only on busy supervisors, never near a cage | 0 | 4 | Rats walked into the control rods' room at 8 s, where both supervisors were laying traps |
| 3 | 240 s | `danger_at` (rats avoid targets near known supervisors); re-plan on a noticed trap | 2 | 2 | |
| 4 | 540 s | (same) | 1 | 7 | Every rat caught |
| 5 | 240 s | flee radius 7 → 10 m, keep fleeing while chased, lurk inside ducts | 1 | 7 | |
| 6 | 240 s | no supervisor traps (experiment) | 1 | 7 | Traps weren't the cause |
| 7 | 240 s | flee from an idle supervisor close by even when it doesn't move | 0 | 8 | 35 bonks: 14 at lever pairs, 10 on rats already fleeing (into the other supervisor) |
| 8 | 240 s | flee plans around every known supervisor, ducts preferred, Flee interrupts from ~6 m | 1 | 7 | 20 of 33 bonks in the first 30 s, 7 of them at 8–9 s at the rods |
| 9 | 240 s | opening danger: the Break Room area at first (everyone knows supervisors start there) | 2 | 6 | Several supervisor "wins" were the 240 s timer |
| 10 | 540 s | (same) | 2 | 6 | |
| 11 | 540 s ×16 | rats remember supervisors 15 s (`danger_memory_s`), `danger_radius` 12 → 16 m | 5 | 11 | 26 of 36 bonks on rats already fleeing, most within 2 s of starting to run: they noticed too late |
| 12 | 540 s ×16 | footsteps right next to a rat count as a threat; a closing supervisor interrupts at once (reflex 0.75) | 4 | 12 | Longer, closer matches (25–36 sabotages), often 3 of 4 rats caged by the end |
| 13 | 540 s ×16 | rats bolt into the ducts (`World.hideouts`): fleeing to a vent exit left them on the room's floor | 13 | 3 | Rats won by meltdown at 200–250 s: two supervisor bots can't out-repair four free rats (bots use the hold repair) |
| 14 | 540 s ×16 | `sabotage_rest_s` 0 → 8 (a rat lurks 8 s after each sabotage) | 9 | 7 | Matches end between 96 s (every rat caught) and 422 s |
| 15 | 540 s ×16 | the AI's cost brought under budget (cached scores, throttled checks); **fresh seeds 400–407, 500–507** | 6 | 10 | The final build. Over runs 14 and 15: 15 rat wins, 17 supervisor wins |

## What was fun
- Watching a gang of two rats knock down a supervisor at its repair point, and a SNAP pull a supervisor
  across the plant to a stunned rat.

## What was boring or frustrating
- The variance is large: 8 matches on one seed set went 4–4, on the next set 1–7, with the same build.
  Judge the balance on 16 matches or more.
- Supervisor bots are weaker repairers than humans (always the hold repair, +35 in 6 s, against about
  +50 in 5 s for a good minigame): bots-only balance says little about human supervisors.

## Bugs seen
- A rat that jumped onto a supervisor's head and got stunned there rode along when the supervisor walked:
  the movement validator gave it strikes (a stunned body may not move). Fixed in the validator: a body
  standing on another player may also move as fast as it (humans could hit this too).
- Bots kept pressing a rat's GrabHandle every tick while knocked down; caged rat bots kept planning paths.
  Fixed.

## Balance changes made
Note every number changed in `data/*.tres`, and update the GDD to match.

| File | Property | Old | New | Why |
|---|---|---|---|---|
| pvp_tuning.tres | carry_max_s | 8 | 12 | The user's call (with a west cage): a rat stunned anywhere but around the Cage Room could never be caged, by humans or bots |
| levels (gen_plant.py) | CageWest | – | Reactor Hall, under the west catwalk | Rods 9–15 m, pumps 17–21 m, valves 27–28 m from it: one carry |
| bot_tuning.tres | flee_radius | 7 | 10 | A supervisor sprints 6 m/s: at 7 m a rat had under a second |
| bot_tuning.tres | danger_radius, danger_memory_s (new) | – | 16 m, 15 s | Rats walked into rooms where they had just seen a supervisor |
| bot_tuning.tres | opening_danger_s, opening_danger_radius (new) | – | 30 s, 30 m | Rats met both supervisors at the control rods 8 s into every match |
| bot_tuning.tres | gang_cage_radius (new) | – | 12 m | Gangs next to a cage ended in captures |
| bot_tuning.tres | sabotage_rest_s | 0 | 8 | Once the rats could escape, they melted the plant in 200–250 s |

## Ideas for next time
- The human solo playtests (M10 "done when"): one human with `bot_fill_to=6`, as a rat and as a
  supervisor, at each difficulty.
- If human rats find bot supervisors too strong (or too weak), the knobs that moved bots-only matches
  most were the rats' (`flee_radius`, `danger_*`, `sabotage_rest_s`); the supervisors' `chase_radius`
  and `carry_spare_s` are the matching ones on the other side.
