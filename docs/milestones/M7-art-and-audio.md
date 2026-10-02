# M7: Art & audio pass

**Goal**: replace graybox and capsules with the cartoon look: toon shading, CC0 and Blender-script assets, animated characters, VFX, positional audio, and layered alarm music. Keep 60 fps on the target GPU.
**Estimated effort**: 3–4 weeks (it's easy to over-spend here, so time-box each POI).
**Prerequisites**: M6 (gameplay and layout locked; only small layout changes are allowed from here on).
**Design refs**: [ASSETS.md](../ASSETS.md).

## 1. Tasks
### Style foundation (do first, then reuse everywhere)
- [x] `assets/palette.png`: a 16×16 swatch palette that includes the GDD colour codes. *(8 × 8 named swatches of 16 px, from `tools/art/palette.py`; preview `docs/art/palette_preview.png`.)*
- [x] `shaders/toon.gdshader`: a `light()` function with a stepped NdotL ramp (2–3 bands, configurable `ramp` texture), rim light, palette albedo, emissive slot. `shaders/outline.gdshader`: inverted hull (vertex grow along the normal, `cull_front`, unshaded black), set as `next_pass`.
- [x] `shaders/materials/`: shared `ShaderMaterial` resources (`toon_palette.tres`, `toon_emissive.tres`, `toon_glass.tres`). *(Plus `toon_world.gdshader` for the level surfaces, patterns from the world position.)*
- [x] An **import script** (`tools/godot/toon_import.gd`, an `EditorScenePostImport`) that replaces every imported material with `toon_palette.tres`, keeping the albedo texture or colour, and adds the outline pass. Assign it to all third-party and generated `.glb` imports.

### Blender script pipeline
- [x] `tools/blender/common.py`: scene reset, palette material (UV to a swatch by colour name), bevel helper, origin-at-base, collision helper (`-col` objects), glTF export.
- [x] Prop scripts listed in [ASSETS §4](../ASSETS.md#4-claude-generated-props-blender-python): pipe, tank, valve, console, breaker_panel, catwalk, vent, reactor, turbine, cooling_tower, cctv, cage, donut (+ rat fallback).
- [x] `tools/blender/export_all.py`: regenerates everything into `assets/generated/`. Wire it to a `make assets` target, or `tools/build_assets.sh`. *(`tools/build_assets.sh` also runs the palette, the audio and the level, then Godot's import.)*
- [x] Animatable sub-nodes (valve wheel, levers, rods, cage door, breaker switches) are named consistently, and interactable scripts animate them with `Tween`.

### Third-party assets
- [x] Choose packs (see ASSETS §3), download them into `assets/third_party/<author>_<pack>/` with their licence file, and add a **CREDITS.md row right away**.
- [x] Modular walls/floors: pick one kit or generate simple walls by script, and replace the CSG POI by POI. **Time-box: about 1 day per POI.** Order: Control Room → Reactor Hall → Turbine → Pump House → Valve Corridor → Substation → the rest.
- [x] Set dressing per POI: clutter (barrels, crates, papers, donut boxes, mugs, warning signs) that gives rats hiding spots and readability.

### Characters
- [x] Supervisor: a CC0 humanoid, recoloured (white shirt, tie, hard hat). Import with `BoneMap` (SkeletonProfileHumanoid) and retarget the Universal Animation Library (or similar CC0) clips: idle, walk, run, jump, swing, carry, interact, knocked down, get up, sit, emote. *(Done differently: Kenney's CC0 Mini Characters come rigged with all these clips, so `supervisor.py` recolours one in Blender instead of retargeting; get_up and eat are authored there.)*
- [x] FP arms + broom: a separate mesh visible only to the local supervisor, with swing / idle / interact / carry animations.
- [x] Rat: a CC0 model or the generated fallback. Minimum clips: idle, run, jump, bite, gnaw (sabotage loop), stunned, dangling (carried), caged idle, squeak. Procedural extras: tail sway and ear wiggle bones driven by code.
- [x] `components/animation/animation_controller.gd` + an `AnimationTree` per role: a locomotion blend space (speed), a one-shot for actions (triggered by cosmetic RPCs), and a status state machine (stunned/knocked down/carried).
- [x] Remote players' animations are driven by their synced velocity and status, so no extra network traffic is needed. *(Plus a few action bits in BodySync's `sync_anim`, as ARCHITECTURE §3 planned "anim state" there.)*

### VFX
- [x] `GPUParticles3D` effects: steam jets, sparks (sabotage cooldown, grid hazard), electric arcs, radiation glow motes, stun stars, impact puffs (BONK), debris dust, smoke.
- [x] Emissive glow for the rods, pool and screens, plus `WorldEnvironment` glow.
- [x] Hit-stop / camera shake on BONK and knockdown (small, with an option to disable). *(`Config.camera_shake`, `--no-shake` until the M8 settings menu.)*

### Audio
- [x] Buses: `Master`, `Music`, `SFX`, `UI`, `Ambience`, with a reverb send for big halls (`AudioEffectReverb` on an `Area3D` bus override).
- [x] Every sound from [ASSETS §6](../ASSETS.md#6-audio-list-v1) implemented, using `AudioStreamPlayer3D` with attenuation tuned per type (footsteps quiet, alarms loud) and `AudioStreamRandomizer` for pitch/volume variation.
- [x] `client/music_director.gd`: 3 synced stems (calm, warning, critical), crossfaded on `plant_alarm_changed`, plus lobby and win/lose stingers.

### Performance
- [x] Profile with the Godot profiler and monitors in each POI with 6 players. Targets: < 1500 draw calls, 60 fps on a GTX 1060 / RX 580 class GPU.
- [x] Use LOD (automatic mesh LOD on import), MultiMesh for repeated clutter, baked occluders, and shadows only on key lights.
- [x] Optional: a Compatibility-renderer fallback check (does the toon shader still look OK?). *(Yes. It caps shader instance uniforms at 4096 slots, hence `toon_tintable.gdshader` for the few parts that change colour; the smoke fog volumes don't render there.)*

## 2. Done when
- [x] No placeholder capsules or CSG remain in the plant (except invisible collision volumes). *(The POI shells are baked meshes; `tests/unit/test_assets.gd` fails if a POI scene still has a CSG node. The TestArena test level keeps its graybox.)*
- [ ] Every gameplay action has animation, VFX and SFX feedback. *(Covered: moving, jumping, landing, sabotage (gnaw, sparks), repair (wrench, chime), levers, swing/BONK, bite, grab/carry/dangle, cage/free, traps, donuts, doors and keycards, CCTV, consoles, every hazard, emotes, the alarm, countdown and match end. The menus' UI sounds wait for M8 (the sound bank has them). Not yet checked by a human: whether each one reads well in play.)*
- [x] Screenshots of each POI are in `docs/screenshots/` and look like one coherent game. *(`poi_*`, `characters_*`, `hazard_*`, made with the MapTour, CharacterTour and HazardTour helpers.)*
- [ ] 60 fps on the target GPU, and the server export still runs (no visual-only code crashing headless). *(No GTX 1060 here: on this laptop's Intel Iris Xe, a weaker GPU, the tour with 6 animated players gives 77+ fps at 720p, and ≤ 570 draw calls (1300 in the frame the CCTV screens refresh). Every integration test runs the headless server and bots with the new code and passes, and the exported `Linux Server` binary runs a match on the plant with no errors (the exported client starts too). Still to do: a 1080p run on a GTX 1060-class GPU.)*
- [x] CREDITS.md lists every third-party asset in the repo (check with `ls assets/third_party`).

## Notes from the implementation
- Pipeline: `tools/build_assets.sh` (palette → Blender models → synthesized audio → level generation + shell bake → Godot import). Details in [ASSETS.md](../ASSETS.md).
- The level: `gen_plant.py` keeps the M5 layout and collision (layout boxes become `PropCollision` shapes), writes each POI shell as CSG into `levels/plant/shells/`, and `tools/godot/bake_shells.gd` bakes it into one mesh + one concave collision shape. Navigation checks (`map_check.sh`) pass unchanged.
- Audio is all project-made (numpy synthesis, `tools/audio/`) except the Kenney CC0 recordings. Nobody has listened to it yet: the levels, the music mix and the stingers need a listen.
- Visual checks (windowed): `tests/helpers/MapTour.tscn` (`--players 6`, `--no-vsync`, `--alarm`), `CharacterTour.tscn` (every animation state), `ArtGallery.tscn` (models under the real shaders), `HazardTour.tscn`.
- The three helper agents that were meant to model in parallel were stopped early; their partial scripts (`machines.py`, `dressing.py`, `rat.py`, `broom.py`) were finished and kept, the rest written directly.

## 3. Pitfalls
- Changing collision when swapping art: keep gameplay collision as simple separate shapes, not derived from the art meshes.
- Mixing styles: when in doubt, recolour to the palette and add the outline. Consistency beats detail.
- Animation retargeting: rest pose and bone names must match the humanoid profile, so check the BoneMap preview.
- Particles on the server: the headless export ignores them, but don't put *gameplay* logic in particle callbacks.
