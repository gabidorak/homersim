# M7: Art & audio pass

**Goal**: replace graybox and capsules with the cartoon look: toon shading, CC0 and Blender-script assets, animated characters, VFX, positional audio, and layered alarm music. Keep 60 fps on the target GPU.
**Estimated effort**: 3–4 weeks (it's easy to over-spend here, so time-box each POI).
**Prerequisites**: M6 (gameplay and layout locked; only small layout changes are allowed from here on).
**Design refs**: [ASSETS.md](../ASSETS.md).

## 1. Tasks
### Style foundation (do first, then reuse everywhere)
- [ ] `assets/palette.png`: a 16×16 swatch palette that includes the GDD colour codes.
- [ ] `shaders/toon.gdshader`: a `light()` function with a stepped NdotL ramp (2–3 bands, configurable `ramp` texture), rim light, palette albedo, emissive slot. `shaders/outline.gdshader`: inverted hull (vertex grow along the normal, `cull_front`, unshaded black), set as `next_pass`.
- [ ] `shaders/materials/`: shared `ShaderMaterial` resources (`toon_palette.tres`, `toon_emissive.tres`, `toon_glass.tres`).
- [ ] An **import script** (`tools/godot/toon_import.gd`, an `EditorScenePostImport`) that replaces every imported material with `toon_palette.tres`, keeping the albedo texture or colour, and adds the outline pass. Assign it to all third-party and generated `.glb` imports.

### Blender script pipeline
- [ ] `tools/blender/common.py`: scene reset, palette material (UV to a swatch by colour name), bevel helper, origin-at-base, collision helper (`-col` objects), glTF export.
- [ ] Prop scripts listed in [ASSETS §4](../ASSETS.md#4-claude-generated-props-blender-python): pipe, tank, valve, console, breaker_panel, catwalk, vent, reactor, turbine, cooling_tower, cctv, cage, donut (+ rat fallback).
- [ ] `tools/blender/export_all.py`: regenerates everything into `assets/generated/`. Wire it to a `make assets` target, or `tools/build_assets.sh`.
- [ ] Animatable sub-nodes (valve wheel, levers, rods, cage door, breaker switches) are named consistently, and interactable scripts animate them with `Tween`.

### Third-party assets
- [ ] Choose packs (see ASSETS §3), download them into `assets/third_party/<author>_<pack>/` with their licence file, and add a **CREDITS.md row right away**.
- [ ] Modular walls/floors: pick one kit or generate simple walls by script, and replace the CSG POI by POI. **Time-box: about 1 day per POI.** Order: Control Room → Reactor Hall → Turbine → Pump House → Valve Corridor → Substation → the rest.
- [ ] Set dressing per POI: clutter (barrels, crates, papers, donut boxes, mugs, warning signs) that gives rats hiding spots and readability.

### Characters
- [ ] Supervisor: a CC0 humanoid, recoloured (white shirt, tie, hard hat). Import with `BoneMap` (SkeletonProfileHumanoid) and retarget the Universal Animation Library (or similar CC0) clips: idle, walk, run, jump, swing, carry, interact, knocked down, get up, sit, emote.
- [ ] FP arms + broom: a separate mesh visible only to the local supervisor, with swing / idle / interact / carry animations.
- [ ] Rat: a CC0 model or the generated fallback. Minimum clips: idle, run, jump, bite, gnaw (sabotage loop), stunned, dangling (carried), caged idle, squeak. Procedural extras: tail sway and ear wiggle bones driven by code.
- [ ] `components/animation/animation_controller.gd` + an `AnimationTree` per role: a locomotion blend space (speed), a one-shot for actions (triggered by cosmetic RPCs), and a status state machine (stunned/knocked down/carried).
- [ ] Remote players' animations are driven by their synced velocity and status, so no extra network traffic is needed.

### VFX
- [ ] `GPUParticles3D` effects: steam jets, sparks (sabotage cooldown, grid hazard), electric arcs, radiation glow motes, stun stars, impact puffs (BONK), debris dust, smoke.
- [ ] Emissive glow for the rods, pool and screens, plus `WorldEnvironment` glow.
- [ ] Hit-stop / camera shake on BONK and knockdown (small, with an option to disable).

### Audio
- [ ] Buses: `Master`, `Music`, `SFX`, `UI`, `Ambience`, with a reverb send for big halls (`AudioEffectReverb` on an `Area3D` bus override).
- [ ] Every sound from [ASSETS §6](../ASSETS.md#6-audio-list-v1) implemented, using `AudioStreamPlayer3D` with attenuation tuned per type (footsteps quiet, alarms loud) and `AudioStreamRandomizer` for pitch/volume variation.
- [ ] `client/music_director.gd`: 3 synced stems (calm, warning, critical), crossfaded on `plant_alarm_changed`, plus lobby and win/lose stingers.

### Performance
- [ ] Profile with the Godot profiler and monitors in each POI with 6 players. Targets: < 1500 draw calls, 60 fps on a GTX 1060 / RX 580 class GPU.
- [ ] Use LOD (automatic mesh LOD on import), MultiMesh for repeated clutter, baked occluders, and shadows only on key lights.
- [ ] Optional: a Compatibility-renderer fallback check (does the toon shader still look OK?).

## 2. Done when
- [ ] No placeholder capsules or CSG remain in the plant (except invisible collision volumes).
- [ ] Every gameplay action has animation, VFX and SFX feedback.
- [ ] Screenshots of each POI are in `docs/screenshots/` and look like one coherent game.
- [ ] 60 fps on the target GPU, and the server export still runs (no visual-only code crashing headless).
- [ ] CREDITS.md lists every third-party asset in the repo (check with `ls assets/third_party`).

## 3. Pitfalls
- Changing collision when swapping art: keep gameplay collision as simple separate shapes, not derived from the art meshes.
- Mixing styles: when in doubt, recolour to the palette and add the outline. Consistency beats detail.
- Animation retargeting: rest pose and bone names must match the humanoid profile, so check the BoneMap preview.
- Particles on the server: the headless export ignores them, but don't put *gameplay* logic in particle callbacks.
