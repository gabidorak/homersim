# Sunny Acres plant: layout v1 (graybox)

![Top-down plan of layout v1](plant_layout_v1.png)

The plan is drawn by the same script that builds the level, so the two can't drift apart. North is up, the grid is 2 m (bold lines every 10 m), +X is east and +Z is south in Godot.

## How the layout is made
- **Source of truth while it's a graybox: `tools/map/gen_plant.py`.** It holds every room, door, vent, station and camera as numbers, and writes `levels/plant/Plant.tscn`, one scene per POI in `levels/plant/pois/`, the colour-coded materials, the plan the in-game map draws (`levels/plant/PlantMap.tres`), this plan (`plant_layout_v1.png`) and `plant_layout_v1.json` (the pixel/metre mapping `tools/heatmap.py` uses).
  ```bash
  python3 tools/map/gen_plant.py --force     # rebuild the level and the plan after changing a number
  python3 tools/map/gen_plant.py --png-only  # just redraw the plan
  python3 tools/map/gen_plant.py --map-only  # just rewrite the in-game map (PlantMap.tres)
  ```
  `--force` overwrites `levels/plant/`. Once you start editing rooms by hand in the Godot editor, stop running it (or only use `--png-only`, and keep the numbers in the script in sync).
- Rooms are rectangles between wall centre lines. Walls are 0.5 m thick and shared by neighbours (the taller room owns the wall). Openings are cut out of the walls: doors 2.0 × 2.6 m (the size of the M4 `Door` scenes, a little bigger than the 1.4 × 2.4 m in ASSETS §2), archways 3–4 m, windows, and vent holes 0.7 × 0.6 m.
- Everything is additive `CSGBox3D`s in one `CSGCombiner3D` per POI (`Shell`), with collision. The vent network is the one place that uses subtraction (duct shells minus their insides), in `VentNetwork.tscn`.
- Each POI root is a `Poi` node (`levels/poi.gd`) that knows its bounds, so the debug overlay and the heatmap log can name the room you're in.

## Rationale
- **The Control Room is the hub.** It sits in the middle of the south half with doors west and east onto the two main halls, and windows onto the Reactor Hall and the Turbine Hall. Every repair point is within 20 s of it at walking speed (the rule is 25 s). The farthest are the vent roof (ladder) and the substation in the yard.
- **Two loops for supervisors.** Inside: Control Room → Main Hall West → Reactor Hall → Turbine Hall → Main Hall East → back. Outside: the yard behind the halls. Keycard doors (Valve Corridor ↔ Break Room, Locker Room ↔ South Corridor) are supervisor shortcuts; rats have to go around.
- **Rats live in the vents.** The nest is a sealed sewer room south of the plant. Its only exit is a duct that splits three ways: north into the South Corridor, west along the outside of the building (Valve Corridor ×2, Pump House, the substation), and east (South Corridor, Cage Room ×2, Storage, then the climbable shaft up to the vent roof). Two ducts run along the inside of the north walls: Pump House → Reactor Hall and Storage → Turbine Hall. A raised duct crosses over the South Corridor and **drops into the Control Room** (one-way: 2.8 m, too high to jump back), so rats can raid the hub but can't escape that way.
- **Every sabotage point has two rat routes**, one on foot and one through a vent. The map check below measures both (the vent exits are at most 22 m away).
- **The Cage Room is the tension spot.** It's in the east, about 90 m of ducts from the nest (18 s for a rat), next to two vent openings, so freeing a friend is always possible but never free. A third cage stands in the Reactor Hall's west corner, under the catwalk (M10, with the carry raised to 12 s): rats stunned at the rods (9–15 m), the pumps (17–21 m) or the valves (27–28 m) are one carry from it, while the Cage Room's two serve the turbine and Storage. It is off the rats' walk from the nest and away from the supervisors' Break Room, so a carry from the valves is still a chance for a rescue.
- **Two floors.** The Reactor Hall (10 m high) has an L-shaped catwalk at 4 m with stairs, the Turbine Hall (8 m) a catwalk along its north wall at 3.5 m with stairs at both ends. Crates let rats jump up (1.2 m, then 2.4 m), and supervisors use the stairs. The vent roof is a 6 m block reached by the yard ladder (everyone) or the shaft (rats).
- **CCTV:** 8 cameras: Reactor Hall, Turbine Hall, Pump House, Valve Corridor, Substation, Vent Roof, Cage Room and Main Hall West. Their blind spots are on purpose: no camera sees the South Corridor (where the nest's vent comes out), the Storage, the Locker Room or the Break Room, and most cameras see only half of their room. Each camera's junction box is at the foot of the wall below it, so rats can reach it (hold E to break it, supervisors hold E to repair it).
- **Out of bounds:** kill volumes under the map, beyond the yard fence and on every roof put a player back where they last stood.

## Design rules: the automated check
`tests/integration/map_check.sh` (also in CI) bakes a navigation mesh for each role from the level's collision and measures real paths. Ladders, the shaft and the one-way drop are `NavigationLink3D`s in the level. Last run:

<!-- map-check:begin -->
Navigation meshes baked in 1.1 s (level: plant).

### Supervisors (from the Control Room, walking at 4 m/s)

| Target | Path | Time | Rule |
|---|---|---|---|
| BreakRoom Donuts | 30 m | 7.5 s |  |
| CageRoom CageA | 44 m | 11.1 s |  |
| CageRoom CageB | 53 m | 13.1 s |  |
| Camera 1 (Reactor Hall) | 48 m | 12.0 s |  |
| Camera 2 (Turbine Hall) | 42 m | 10.6 s |  |
| Camera 3 (Pump House) | 54 m | 13.6 s |  |
| Camera 4 (Valve Corridor) | 47 m | 11.8 s |  |
| Camera 5 (Substation) | 68 m | 17.0 s |  |
| Camera 6 (Vent Roof) | 83 m | 20.6 s |  |
| Camera 7 (Cage Room) | 54 m | 13.5 s |  |
| Camera 8 (Main Hall West) | 34 m | 8.5 s |  |
| ControlRoom CctvConsole | 2 m | 0.5 s |  |
| KeycardDoor ReaderBack | 44 m | 11.1 s |  |
| KeycardDoor ReaderBack | 39 m | 9.7 s |  |
| KeycardDoor ReaderFront | 41 m | 10.2 s |  |
| KeycardDoor ReaderFront | 43 m | 10.6 s |  |
| ReactorHall CageWest | 39 m | 9.7 s |  |
| Storage SpareKeycard | 47 m | 11.8 s |  |
| Storage LureRefill | 49 m | 12.3 s |  |
| Storage TrapRefill | 51 m | 12.8 s |  |
| grid RepairPoint | 70 m | 17.5 s | ≤ 25 s ok |
| pumps RepairPoint | 54 m | 13.4 s | ≤ 25 s ok |
| rods RepairPoint | 29 m | 7.3 s | ≤ 25 s ok |
| turbine RepairPoint | 52 m | 13.0 s | ≤ 25 s ok |
| valves RepairPoint | 48 m | 12.0 s | ≤ 25 s ok |
| ventilation RepairPoint | 76 m | 19.1 s | ≤ 25 s ok |
| Rat Nest | unreachable | | must be unreachable ok |

### Rats (from the Rat Nest, walking at 5 m/s)

Second route: on foot from the South Corridor with every vent sealed, and the nearest vent exit.

| Target | Path | Time | Rule | On foot | Nearest vent exit |
|---|---|---|---|---|---|
| CageRoom CageA | 90 m | 18.1 s | ≤ 30 s ok |  |  |
| CageRoom CageB | 92 m | 18.4 s | ≤ 30 s ok |  |  |
| Camera 1 (Reactor Hall) | 58 m | 11.6 s |  |  |  |
| Camera 2 (Turbine Hall) | 88 m | 17.7 s |  |  |  |
| Camera 3 (Pump House) | 50 m | 10.1 s |  |  |  |
| Camera 4 (Valve Corridor) | 44 m | 8.9 s |  |  |  |
| Camera 5 (Substation) | 79 m | 15.8 s |  |  |  |
| Camera 6 (Vent Roof) | 119 m | 23.8 s |  |  |  |
| Camera 7 (Cage Room) | 100 m | 20.0 s |  |  |  |
| Camera 8 (Main Hall West) | 41 m | 8.2 s |  |  |  |
| ReactorHall CageWest | 48 m | 9.6 s | ≤ 30 s ok |  |  |
| grid SabotageA | 84 m | 16.9 s |  | 76 m | 8 m |
| grid SabotageB | 89 m | 17.8 s |  | 72 m | 13 m |
| pumps SabotageA | 53 m | 10.5 s |  | 44 m | 4 m |
| pumps SabotageB | 52 m | 10.4 s |  | 43 m | 9 m |
| rods LeverA | 41 m | 8.2 s |  | 32 m | 17 m |
| rods LeverB | 42 m | 8.3 s |  | 32 m | 21 m |
| turbine LeverA | 79 m | 15.8 s |  | 70 m | 6 m |
| turbine LeverB | 73 m | 14.5 s |  | 63 m | 11 m |
| valves SabotageA | 40 m | 8.0 s |  | 31 m | 9 m |
| valves SabotageB | 42 m | 8.3 s |  | 33 m | 5 m |
| ventilation SabotageA | 115 m | 23.0 s |  | 105 m | 13 m |
| ventilation SabotageB | 115 m | 23.0 s |  | 105 m | 14 m |
| Control Room | 53 m | 10.5 s |  |  |  |

Supervisor floor inside vents: none, ok (211 samples)

**All checks passed.**
<!-- map-check:end -->

The 25 s rule assumes walking (4 m/s). Sprinting (6 m/s for 5 s) makes every trip shorter.

## What a playtest still has to confirm
- No stuck spots: walk every wall as a supervisor and as a rat (corners, door frames, duct openings, the stairs, the ladder top).
- Measured walk times with the debug stopwatch (F4) roughly match the table.
- More than 60 fps on the target GPU (F3 shows fps and draw calls).
- Heatmap review: `python3 tools/heatmap.py ~/.local/share/godot/app_userdata/HomerSim/heatmap_*.csv`. Dead rooms nobody visits, or a corridor everyone camps, are layout bugs.
