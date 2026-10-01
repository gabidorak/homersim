# M5: Map v1 (graybox)

**Goal**: the real "Sunny Acres" plant level, fully playable in graybox (CSG + prototype textures). It has every POI, the vent network, keycard shortcuts, the control room with a working CCTV system and status board, cages, and spawns. The layout is validated by playtests **before** any art goes in.
**Estimated effort**: 2–3 weeks.
**Prerequisites**: M4.
**Design refs**: [GDD §7](../GDD.md#7-map-sunny-acres-plant), [ASSETS §2 scale rules](../ASSETS.md#2-scale-and-modularity-rules-decide-now-and-never-change).

## 1. Tasks
> Implemented on 2026-10-01. Notes on what differs from the plan are in *italics* under each task. The layout, its rationale and the measured design rules are in [docs/map/README.md](../map/README.md).
### Layout first (on paper / image)
- [x] Draw a top-down plan of both floors on a 2 m grid (paper, or a free tool like draw.io / Excalidraw), and save it as `docs/map/plant_layout_v1.png` with a short rationale in `docs/map/README.md`.
  - *The plan is drawn by `tools/map/gen_plant.py`, the same script that builds the level from the layout numbers, so the plan and the level can't drift apart. Raised floors (catwalks, the vent roof) are hatched on the same image.*
- [x] Check it against the GDD design rules:
  - every sabotage point has ≥ 2 rat routes, at least one through a vent
  - Control Room → any station ≤ 25 s at 4 m/s (≈ 100 m path)
  - Cage Room is far from the Rat Nest exits, but reachable by rats in under 30 s
  - vents have one-way drop exits
  - 8 CCTV positions, with deliberate blind spots
  - *Checked automatically: `tests/integration/map_check.sh` (`tests/helpers/map_check.gd`, also in CI) bakes a navigation mesh per role from the level's collision and measures real paths. Worst cases: 19.7 s to the vent roof repair point; a vent exit within 22 m of every sabotage point plus a route on foot with all vents sealed; the Cage Room 18 s from the nest; supervisors can't reach the nest or stand inside any vent. The one-way drop goes into the Control Room (2.8 m). The table is in docs/map/README.md (`map_check.sh --update-docs` refreshes it).*

### Build
- [x] `levels/plant/Plant.tscn` = root + one **sub-scene per POI** in `levels/plant/pois/` (`ControlRoom.tscn`, `ReactorHall.tscn`, `TurbineHall.tscn`, `PumpHouse.tscn`, `ValveCorridor.tscn`, `Substation.tscn`, `VentRoof.tscn`, `BreakRoom.tscn`, `Storage.tscn`, `CageRoom.tscn`, `LockerRoom.tscn`, `RatNest.tscn`, `VentNetwork.tscn`). Separate files mean you can work on one room at a time and keep merge conflicts small.
  - *Plus `Yard.tscn` (the outdoor yard with the cooling tower, the ladder and the lobby spawns) and `Corridors.tscn` (Main Hall West/East, South Corridor). Each POI root is a `Poi` (`levels/poi.gd`) that knows its bounds, so code can ask which room a position is in. The generator refuses to overwrite `levels/plant/` without `--force`: once rooms are edited by hand in the editor, stop regenerating.*
  - *`Session` now loads the level at runtime: the plant by default, the TestArena with `--level test` (debug builds). The join handshake checks that client and server play the same level. The M4 PvP integration tests stay on the TestArena (their scenarios use its spots).*
- [x] Use CSG (`CSGBox3D`, `CSGCombiner3D`, subtract for doors and vents) with Kenney prototype textures colour-coded per POI. Later, convert finalised CSG to `MeshInstance3D` via *CSG → Bake Mesh Instance* for performance.
  - *Walls are cut around openings with additive boxes (one `CSGCombiner3D` "Shell" per POI), with no subtraction. Only the ducts use subtraction. Materials are in `levels/plant/materials/`. Not baked to meshes yet: the whole plant loads in about a second, even headless.*
- [x] Move the M3/M4 interactables from TestArena into their POIs, with the subsystem ids correct. Keep `TestArena` working as a sandbox.
  - *The stations keep the TestArena arrangement (machine, label, repair point, 2 sabotage points or a lever pair 6 m apart). Cages in the Cage Room, trap refill and spare keycard in Storage, donuts in the Break Room, keycard doors Valve Corridor ↔ Break Room and Locker Room ↔ South Corridor, auto doors on the Control Room and the halls' yard exits. `Interactable.stand_position()` now finds the floor below (catwalks, the roof) instead of assuming y = 0.*
- [x] Spawn points: Supervisors in the Break Room (2), Rats in the Rat Nest (4), plus a lobby area (a small room or the yard).
  - *Lobby: 6 spawns in the yard, east of the cooling tower.*
- [x] **Status board** (Control Room): a `SubViewport` showing a 2D `Control` scene that reads `PlantSim` synced state (bars, alarm light), rendered onto a quad mesh in the room.
  - *`levels/plant/props/status_board.gd` + `status_board_panel.gd` (drawn with `_draw`): healths, OFFLINE / sparks cooldowns, core temperature, meltdown, alarm light, shift clock. Client only, redrawn 5×/s while on screen.*
- [x] **CCTV**: `interactables/cctv/cctv_camera.gd` (8 positioned `Camera3D` nodes, breakable by rats with a 2 s hold, repaired by a supervisor with a 3 s hold) plus a `ConsoleAction` chair in the Control Room. Sitting → the supervisor's view switches to the selected camera (Q/E to cycle). Broken cameras show static. The body stays in the chair and stays vulnerable. **Only render** a CCTV viewport for the player currently using it.
  - *A camera is a junction box at the foot of a wall (reachable by rats) with a lens marker up the wall, not a `Camera3D`: Godot makes a stray camera current by itself. The chair is `interactables/cctv/cctv_console.gd` (`CctvConsole`; M6's `ConsoleAction` is a separate thing). The server pins the seated body (frozen, still bitable) and stands it up on a knockdown, a push off the seat or the match end; Space stands up. `client/cctv_view.gd` switches the main view to a camera at the lens (no extra viewport at all), with static + "NO SIGNAL" for a broken one. Hold times are in `pvp_tuning.tres`. Cameras and the chair reset at every match start (`MatchManager.RESET_GROUP`).*
- [x] Wall screens in the Control Room can show 2 low-res CCTV feeds (`SubViewport` at 256×144, `UPDATE_WHEN_VISIBLE`, refreshed at about 10 fps via a manual update).
  - *`levels/plant/props/cctv_screen.gd`: each screen cycles through 4 cameras every 5 s, rendering `UPDATE_ONCE` 10×/s only while it's on screen (`VisibleOnScreenNotifier3D`).*
- [x] Ladders (supervisor access to the Vent Roof): an `Area3D` that switches movement to climb mode.
  - *`interactables/ladder/ladder.gd`: push toward the ladder to climb (and step off at the top), push away in the air to climb down, no input hangs on, jump lets go. Rats climb too: the vent shaft to the roof is a ladder inside a duct.*
- [x] Out-of-bounds kill volumes → teleport back to the last safe position.
  - *`levels/out_of_bounds.gd` volumes below the map, beyond the yard fence and on every roof. The owner client puts itself back (`MovementComponent`, last spot it stood on, sampled every 0.5 s); the validator ignores that jump.*
- [x] Basic lighting: one `WorldEnvironment`, a few `OmniLight3D`s per room (shadows off for most), and the alarm beacon lights hooked to `Events.plant_alarm_changed`.
  - *Night sky, dim ambient, a faint moon (no shadows), about one omni light per 10 m indoors, floodlights in the yard. `levels/plant/props/AlarmBeacon.tscn`: dark / amber pulse / spinning red.*
- [x] **Occlusion culling**: enable it in project settings and add `OccluderInstance3D` nodes, baked per POI.
  - *Enabled. The generator adds a `BoxOccluder3D` per solid wall piece (and the vent roof block) instead of an editor bake. Rebake in the editor once the walls are final meshes.*

### Playtest instrumentation
- [x] A debug overlay (F3) with FPS, ping, position, current POI name and draw calls.
  - *`client/debug_overlay.gd`. F4 is a stopwatch that also measures the distance walked, to time routes. `--debug-overlay` shows it from the start.*
- [x] A server log of position heatmap samples (every 2 s, per role) written to `user://heatmap_<match>.csv`, plus a tiny Python script `tools/heatmap.py` that plots it over the layout image.
  - *`server/heatmap_recorder.gd` (plant only; the integration tests pass `--no-heatmap`). `tools/heatmap.py` needs Pillow and NumPy, draws one colour per role, and prints the time each role spent per area.*

## 2. Done when
- [ ] A full match on the plant map with 5–6 players, with no stuck spots for rats or supervisors (do one walk-through per role, hugging every wall).
  - *Headless bots play full matches on the plant (`run_match_loop.sh`, `critical_lever.sh`, `plant_cctv.sh`), and the map check proves every target is reachable. A human walk-through is still needed for stuck spots.*
- [ ] The measured walk times meet the design rules (use a debug stopwatch).
  - *The navmesh paths meet them (see the README table); the stopwatch (F4) check by hand is still to do.*
- [ ] CCTV works, broken cameras show static, and the status board reflects the plant state.
  - *`tests/integration/plant_cctv.sh`: sit, a rat breaks camera 1, the view shows it broken, stand up, repair. Check the static, the wall screens and the status board by eye in a windowed client.*
- [ ] More than 60 fps in graybox on the target GPU.
- [ ] Playtest notes plus a heatmap review → layout tweaks committed.

## 3. Pitfalls
- Don't polish the graybox. Wrong proportions are cheap to fix now and expensive after the art pass.
- CSG is slow when there are many nodes. Bake finished rooms to meshes.
- Several `SubViewport`s rendering every frame kills performance, so always render on demand.
- Watch out for supervisor-only areas that rats can't reach at all (except deliberately), because that breaks rat counterplay.
- *Learned: Godot's navigation baker turned a 37 m vent duct into broken polygons (the floor was there, the navmesh wasn't). `edge_max_length = 4` fixed it. The ducts are also cut into 8 m pieces.*
- *Learned: room floors stop at the wall's centre line, so a vent hole in an outer wall had a 0.25 m gap in its floor. The generator now adds a sill under such holes.*
