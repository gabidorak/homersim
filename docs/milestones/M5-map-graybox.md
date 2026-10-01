# M5: Map v1 (graybox)

**Goal**: the real "Sunny Acres" plant level, fully playable in graybox (CSG + prototype textures). It has every POI, the vent network, keycard shortcuts, the control room with a working CCTV system and status board, cages, and spawns. The layout is validated by playtests **before** any art goes in.
**Estimated effort**: 2–3 weeks.
**Prerequisites**: M4.
**Design refs**: [GDD §7](../GDD.md#7-map-sunny-acres-plant), [ASSETS §2 scale rules](../ASSETS.md#2-scale-and-modularity-rules-decide-now-and-never-change).

## 1. Tasks
### Layout first (on paper / image)
- [ ] Draw a top-down plan of both floors on a 2 m grid (paper, or a free tool like draw.io / Excalidraw), and save it as `docs/map/plant_layout_v1.png` with a short rationale in `docs/map/README.md`.
- [ ] Check it against the GDD design rules:
  - every sabotage point has ≥ 2 rat routes, at least one through a vent
  - Control Room → any station ≤ 25 s at 4 m/s (≈ 100 m path)
  - Cage Room is far from the Rat Nest exits, but reachable by rats in under 30 s
  - vents have one-way drop exits
  - 8 CCTV positions, with deliberate blind spots

### Build
- [ ] `levels/plant/Plant.tscn` = root + one **sub-scene per POI** in `levels/plant/pois/` (`ControlRoom.tscn`, `ReactorHall.tscn`, `TurbineHall.tscn`, `PumpHouse.tscn`, `ValveCorridor.tscn`, `Substation.tscn`, `VentRoof.tscn`, `BreakRoom.tscn`, `Storage.tscn`, `CageRoom.tscn`, `LockerRoom.tscn`, `RatNest.tscn`, `VentNetwork.tscn`). Separate files mean you can work on one room at a time and keep merge conflicts small.
- [ ] Use CSG (`CSGBox3D`, `CSGCombiner3D`, subtract for doors and vents) with Kenney prototype textures colour-coded per POI. Later, convert finalised CSG to `MeshInstance3D` via *CSG → Bake Mesh Instance* for performance.
- [ ] Move the M3/M4 interactables from TestArena into their POIs, with the subsystem ids correct. Keep `TestArena` working as a sandbox.
- [ ] Spawn points: Supervisors in the Break Room (2), Rats in the Rat Nest (4), plus a lobby area (a small room or the yard).
- [ ] **Status board** (Control Room): a `SubViewport` showing a 2D `Control` scene that reads `PlantSim` synced state (bars, alarm light), rendered onto a quad mesh in the room.
- [ ] **CCTV**: `interactables/cctv/cctv_camera.gd` (8 positioned `Camera3D` nodes, breakable by rats with a 2 s hold, repaired by a supervisor with a 3 s hold) plus a `ConsoleAction` chair in the Control Room. Sitting → the supervisor's view switches to the selected camera (Q/E to cycle). Broken cameras show static. The body stays in the chair and stays vulnerable. **Only render** a CCTV viewport for the player currently using it.
- [ ] Wall screens in the Control Room can show 2 low-res CCTV feeds (`SubViewport` at 256×144, `UPDATE_WHEN_VISIBLE`, refreshed at about 10 fps via a manual update).
- [ ] Ladders (supervisor access to the Vent Roof): an `Area3D` that switches movement to climb mode.
- [ ] Out-of-bounds kill volumes → teleport back to the last safe position.
- [ ] Basic lighting: one `WorldEnvironment`, a few `OmniLight3D`s per room (shadows off for most), and the alarm beacon lights hooked to `Events.plant_alarm_changed`.
- [ ] **Occlusion culling**: enable it in project settings and add `OccluderInstance3D` nodes, baked per POI.

### Playtest instrumentation
- [ ] A debug overlay (F3) with FPS, ping, position, current POI name and draw calls.
- [ ] A server log of position heatmap samples (every 2 s, per role) written to `user://heatmap_<match>.csv`, plus a tiny Python script `tools/heatmap.py` that plots it over the layout image.

## 2. Done when
- [ ] A full match on the plant map with 5–6 players, with no stuck spots for rats or supervisors (do one walk-through per role, hugging every wall).
- [ ] The measured walk times meet the design rules (use a debug stopwatch).
- [ ] CCTV works, broken cameras show static, and the status board reflects the plant state.
- [ ] More than 60 fps in graybox on the target GPU.
- [ ] Playtest notes plus a heatmap review → layout tweaks committed.

## 3. Pitfalls
- Don't polish the graybox. Wrong proportions are cheap to fix now and expensive after the art pass.
- CSG is slow when there are many nodes. Bake finished rooms to meshes.
- Several `SubViewport`s rendering every frame kills performance, so always render on demand.
- Watch out for supervisor-only areas that rats can't reach at all (except deliberately), because that breaks rat counterplay.
