# Assets: style, sources, pipeline

## 1. Art direction
- **Low-poly cartoon** with chunky shapes, exaggerated proportions (big hands and heads on supervisors, big ears and tails on rats), and no fine detail.
- **Flat colours** sampled from a single **palette texture** (`assets/palette.png`: 8 × 8 named swatches of 16 × 16 px, defined in `tools/art/palette.py`, preview in `docs/art/palette_preview.png`). No detailed textures. Third-party models are recoloured onto the palette, so packs from different authors look like one game.
- **Toon shading** (as built in M7):
  - `shaders/toon_light.gdshaderinc`: the shared `light()`: a stepped ramp (shadow, mid and lit bands, or a ramp texture) per light, and a rim light on the lit side. The ramp is exactly 0 without light (Forward+ evaluates a light only in the screen tiles it touches; leftover light shows as blocks).
  - `shaders/toon.gdshader`: models: palette texture × colour, an emissive slot, and per-instance `tint` / `glow` (instance uniforms: a lamp changes colour without a material copy).
  - `shaders/outline.gdshader`: inverted hull as `next_pass`, grown along **smoothed normals stored in the vertex colour** (alpha 0 marks them; `tools/blender/common.py` writes them), so hard-edged low-poly meshes don't tear at the corners.
  - `shaders/screen_ink.gdshader`: **full-screen ink lines** (Forward+ only), opt-in (the default is the hull above): a screen-covering quad (`common/screen_ink.gd`, added by `Config` next to every WorldEnvironment) inks silhouettes and creases found in the depth and normal buffers, so level surfaces, contact lines (a pillar against a wall, a crate on the floor) and edges inside a model get lines too, all the same width in pixels. The **Outlines** video setting picks full screen, per object (the hull above; also the Compatibility fallback) or none; the hull is switched with the global shader uniform `outline_hull_enabled`.
  - `shaders/toon_world.gdshader`: level surfaces: patterns drawn from the world position (wainscot and panel seams on walls, tiles and checkers on floors, grating, hazard stripes, duct seams), so the baked shells need no UVs. One material per POI with its palette colours (written by `tools/map/gen_plant.py`).
  - `shaders/toon_glass.gdshader`: windows and lenses.
  - Shared materials: `shaders/materials/` (`toon_palette`, `toon_palette_flat`, `toon_emissive`, `toon_glass`, `outline`).
  - **Import script** `tools/godot/toon_import.gd` (set as the scene importer's default in `project.godot`): the materials named `palette`, `palette_emissive` and `glass` become the shared toon materials; any other material becomes a toon material with an outline; character clips in its `LOOPING` list loop.
- **Readability first**: gameplay objects get a **colour code**:

| Meaning | Colour | Examples |
|---|---|---|
| Rat-interactable (sabotage) | Rat green `#7BD389` glow on hover | Sabotage points, levers, vent entrances |
| Supervisor-interactable (repair/console) | Safety yellow `#FFC93C` | Repair panels, consoles, doors |
| Danger / hazard | Alarm red `#E84A5F` and hazard stripes | Steam jets, puddles, radiation |
| Nuclear glow | Radioactive green `#9CFF2E`, emissive | Rods, pool, vials |
| Plant walls and floors | Muted teal, beige, grey | Environment |

- Lighting: warm interior lights, a cool night-time exterior. A WorldEnvironment with glow for emissives, SSAO, a little extra saturation. Only two lights cast shadows (the moon, which also keeps moonlight out of the buildings, and the reactor's glow). The alarm states change light colour and add rotating beacons that also sound the alarm.

## 2. Scale and modularity rules (decide now and never change)
| Thing | Size |
|---|---|
| Grid unit | **2 m** (half-grid 1 m for props) |
| Wall height | 4 m (halls 8–12 m) |
| Door | 1.4 m wide × 2.4 m high |
| Rat vent opening | 0.7 × 0.7 m (supervisor capsule is 0.7 m wide, so it can't pass) |
| Supervisor | 1.8 m tall, capsule radius 0.35 |
| Rat | 0.5 m tall, capsule radius 0.2 |
| Catwalk width | 1.5 m |
| Step / stair rise | 0.25 m (≤ `floor_snap` + step height of the controller) |

Units: 1 Godot unit = 1 m. In Blender, use metric with scale 1.0 and export glTF with **+Y up** (the exporter default). Models face **−Y in Blender** (what you see in Front view), which becomes **+Z in Godot** (`Vector3.MODEL_FRONT`). Rotate them in code with `look_at(target, Vector3.UP, true)` (`use_model_front`).

## 3. Sources (CC0 first)
Each licence must be confirmed on the download page, and a row added to [CREDITS.md](../CREDITS.md) on import. Keep the pack's original `License.txt` in `assets/third_party/<pack>/`.

**Used since M7** (all CC0, all from [Kenney](https://kenney.nl/assets)): Mini Characters (the supervisor), Furniture Kit, Food Kit, Factory Kit and Survival Kit (set dressing, converted by `tools/blender/kenney.py`), Particle Pack (VFX sprites), Impact, Interface, Sci-fi, Digital and RPG audio packs (footsteps, impacts, UI, doors, beeps). Model packs carry a `.gdignore`: Godot only imports their palette versions from `assets/generated/`. Everything else (props, the rat, the first-person arms, every other sound and all the music) is made by the project's own scripts.

| Source | Licence | Look for (candidates; check what currently exists) |
|---|---|---|
| [Kenney](https://kenney.nl/assets) | CC0 | Prototype Textures (graybox), furniture, food (donuts!), industrial/conveyor/space kits for pipes and machines, UI packs, audio packs (impact, interface, sci-fi), Input Prompts |
| [Quaternius](https://quaternius.com) | CC0 | Humanoid characters for supervisors, **Universal Animation Library** (rigged, retargetable), sci-fi / modular buildings, animals (check for a rat or mouse) |
| [KayKit (Kay Lousberg)](https://kaylousberg.itch.io) | CC0 | Characters and "bits" prop packs with a consistent chunky style |
| [Poly Pizza](https://poly.pizza) | **Filter to CC0** (some models are CC-BY, which needs attribution) | Rat/mouse model, specific props (fire extinguisher, barrels) |
| [OpenGameArt](https://opengameart.org) | Check per asset (CC0 / CC-BY / GPL; **avoid GPL/CC-BY-SA** for art) | Music loops, extra SFX |
| [Freesound](https://freesound.org) | Filter to **CC0** | Alarms, steam hiss, squeaks, machinery hum |
| [ambientCG](https://ambientcg.com) / [Poly Haven](https://polyhaven.com) | CC0 | HDRI for the sky, a few textures if needed |
| [Google Fonts](https://fonts.google.com) | OFL / Apache | A cartoony display font (e.g. *Bangers*, *Luckiest Guy*) plus a readable UI font |

## 4. Claude-generated props (Blender Python)
Scripts live in `tools/blender/`. Each builds parametric geometry with `common.Builder` (primitives painted with palette colour **names**: every face's UVs sit at its swatch's centre), and exports `.glb` to `assets/generated/` (never edit those by hand). Every script is a module with `ASSETS = [(out_name, kwargs), ...]` and `build(**kwargs)`; `export_all.py` discovers them.

```bash
tools/build_assets.sh                                   # everything: palette, models, audio, level, Godot import
blender -b -P tools/blender/export_all.py               # all models (Blender 4.2+, tested with 5.0)
blender -b -P tools/blender/export_all.py -- machines   # one script
blender -b -P tools/blender/preview.py -- machines --out /tmp/m.png [--only NAME] [--anim CLIP --frame N]
godot tests/helpers/ArtGallery.tscn -- --files crate,lever [--anim idle]   # the real look (toon, outlines)
```
| Script | Produces |
|---|---|
| `common.py` | The Builder (box, cylinder, sphere, torus, prism, tube; bevels; emissive and glass faces), named child parts with their own pivot, smoothed outline normals, export |
| `crate.py` | Crate (the level stretches it to each crate box) |
| `machines.py` | The six station machines (`machine_<subsystem>`, a 2 × 2 m footprint with flat spots for the repair panel and the junction boxes), generator, pump, transformer; shared helpers (flanges, gauges, hazard stripes, valve wheels, louvres, icons) |
| `plant.py` | Reactor core (rods `Rod1..6`), turbine (`Shaft`), tanks, `pipe_2m`, elbow, `valve_rack_4m` (`Wheel1..4`), roof fan (`Fan`), exhaust stack, vent grille, cooling tower, ladder, floodlight, insulator post |
| `interactables.py` | Sabotage box (+ broken), repair panel, critical lever (`Handle`), cage (`Door`), door panels, keycard reader, CCTV box/conduit/head (+ broken), CCTV chair, alarm beacon (`Reflector`), mousetrap, cheese, trap refill, keycard, console buttons (`Button`, `Cover`) |
| `furniture.py` | Control desks, break-room table and chairs, bench, lockers, vending machine, coffee station, donut counter, shelves, pallet, water cooler, whiteboard, office desk, donut, donut box |
| `dressing.py` | Barrels, junk piles, trash bags, rat beds, cones, signs, mop bucket, fire extinguisher, toolbox, cable spool, papers, clocks, pipe bundles, vial crates |
| `kenney.py` | Kenney CC0 models recoloured onto the palette and rescaled (`k_*`) |
| `supervisor.py`, `rat.py`, `fp_arms.py`, `broom.py` | Characters (§5) |

Animatable parts are **separately named child objects** with their pivot as origin; Godot code finds them by name (`Art.part()`), so mesh names must not collide with gameplay node names. Gameplay collision never comes from the art: the level keeps its layout boxes (`solid()` in `gen_plant.py`) and the interactable scenes their own shapes.

**The level** (`tools/map/gen_plant.py`): each POI's static shell (floors, walls, ceilings, catwalks, ducts) is CSG in `levels/plant/shells/`, baked by `tools/godot/bake_shells.gd` into one mesh and one concave collision shape per POI (`levels/plant/baked/`). Layout boxes become generated models (`model()` / `fill()`), long pipe runs a MultiMesh (`levels/plant/props/prop_multimesh.gd`), moving parts get `PlantProp` (fans, shaft, valve wheels, breakers and rods follow their subsystem's health), and `DRESSING` lists the clutter per room.

## 5. Characters and animation
| Role | Model | Clips |
|---|---|---|
| Supervisor | Kenney Mini Character *male-d* recoloured (white shirt, red tie, navy trousers, boots), a separate `HardHat` mesh (lobby bodies tint it per player), a badge; 1.85 m (`supervisor.py`). Bones: root, leg-left, leg-right, torso, arm-left, arm-right, head | idle, walk, run, jump, fall, swing, carry_idle, place, interact, knocked, get_up (knocked reversed), eat (new), sit, emote, emote_no |
| Broom | `broom.py`, held in the right hand through a BoneAttachment3D (`CharacterVisual`) | – |
| Rat | Generated in the Mini Characters style (`rat.py`): 0.5 m, 2.4k tris, rigid skinning. Bones: root, body, head, jaw, ear_l/r, arm_l/r, leg_l/r, tail_1..4 | idle, run, jump, fall, crawl, bite, gnaw, stunned, dangle, caged, squeak |
| First-person arms | `fp_arms.py`: forearms and broom, origin = the camera; drawn at 35 % scale around the camera (same picture, never through walls) with a thinner outline | idle, swing, interact, carry, eat, place |

- `components/animation/animation_controller.gd` builds the AnimationTree in code: a speed blend space (idle → walk → run, with a time scale so feet keep up), a transition on the body's state (jump, fall, interact, climb, crawl, sit, stunned, knocked, dangle, caged), a carry blend filtered to the arms, and a one-shot for swing / bite / place / eat / get_up / emote. Remote bodies use the same inputs: speed measured from their interpolated motion, statuses from StatusComponent, and `Player.sync_anim` (a few bits in BodySync: airborne, interacting, emoting, climbing, in a vent).
- `components/animation/body_fx.gd`: footsteps paced by distance, landings, the gnaw and vent-crawl loops, wrench clinks, voices (supervisor "ow!", rat squeaks), emote sounds, stun stars, donut crumbs, hit-stop on a BONK.
- Rig convention: every bone's rest frame is axis-aligned, so `rat.py`'s `Animator` writes clips as model-axis rotations; it works on the Kenney rig too.

## 6. Audio list (v1)
| Category | Sounds |
|---|---|
| Plant | Machinery hum (loop per POI), alarm klaxon (warning/critical), steam hiss, electric zap, turbine whine, Geiger clicks |
| Supervisor | Footsteps, broom whoosh, BONK hit, trap place, SNAP, donut munch, "ow!" grunt |
| Rat | Pitter-patter footsteps, squeaks (several), bite chomp, gnawing loop, vent crawl rattle |
| UI | Click, hover, countdown beeps, win/lose stingers |
| Music | Lobby loop, match calm, warning and critical layers (crossfaded) |

As built (M7):
- **Synthesized** by `tools/audio/make_audio.py` (numpy + ffmpeg; `synth.py` has the oscillators, FFT filters, Karplus-Strong plucks and formant voices) into `assets/audio/sfx/` and `assets/audio/music/`: squeaks, chomp, gnawing, rat steps, vent rattle, "ow!" grunts, whoosh, cartoon BONK, SNAP crack, munch, whistle emote, steam hiss and puff, zaps and the puddle buzz, Geiger clicks, falling whistle and rumble, the alarm klaxon and warning chime, SCRAM klaxon, coolant whoosh, machinery hums (room, reactor, turbine, pump, electric, fans), crickets, dripping, sparks, beeps, lever, button, repair and sabotage jingles.
- **Music** (`tools/audio/music.py`): a sneaky A-minor match theme in three stems of exactly 32 s at 120 BPM (calm: pizzicato walking bass, marimba melody, a ticking clock; warning: drums, brass stabs, tremolo strings; critical: fast hats, toms, siren lead, low brass), a lounge loop for the lobby, a win fanfare and the cartoon "wah-wah-wah-waaah" lose stinger.
- **Recorded CC0** (Kenney packs, §3): footsteps, punches, metal and glass impacts, UI clicks, door slides, keycard beeps, the meltdown explosion.
- `client/sfx.gd` is the sound bank: every sound by name with its kind (bus and how far it carries), volume, random pitch (several files become an `AudioStreamRandomizer`) and an optional layered companion. Positional players pick up the hall reverb from audio areas (`PhysicsLayers.AUDIO`, placed by the level generator in the big halls).
- Buses (`default_bus_layout.tres`): Master (hard limiter), Music, SFX, UI, Ambience, HallReverb (sends to SFX).
- `client/music_director.gd` plays the stems in one `AudioStreamSynchronized` and fades them with the alarm, the lobby loop before a match, countdown beeps, the stingers (and the meltdown boom). `levels/ambient_sound.gd` markers loop the hums; `AlarmBeacon` sounds the alarm.

## 7. Poly and texture budgets
| Asset type | Triangles | Textures |
|---|---|---|
| Character | ≤ 6k | Palette only, or ≤ 512² |
| Hero machine (reactor, turbine) | ≤ 15k | Palette + emissive |
| Prop | ≤ 1.5k | Palette |
| Modular wall/floor piece | ≤ 300 | Palette or tiling 512² |

Target: **60 fps at 1080p on a GTX 1060 / RX 580-class GPU** with 6 players.

As built: characters 1.2k (supervisor) and 2.4k (rat); reactor 4.6k, turbine 5.9k; the six station machines
2.8k–5.3k (over the prop budget, but there is one of each); everything else under 1.5k (the donut counter 2.8k).
`tests/helpers/MapTour.tscn -- --players 6 --no-vsync` measured at most ~570 draw calls in normal views (1300
in the frame the CCTV wall screens refresh) and 77+ fps at 720p on an Intel Iris Xe (a weaker GPU than the
target) with six animated bodies in view. Models get automatic LODs on import; long pipe runs are MultiMeshes.

## 8. Folder layout
```
assets/
  palette.png                    (tools/art/make_palette.py)
  third_party/<author>_<pack>/   (original licence file kept inside; model packs have a .gdignore)
  generated/                     (output of tools/blender, never edit by hand)
  audio/{sfx,music}/             (output of tools/audio)
  fonts/
  ui/
shaders/                         toon, outline, screen_ink, toon_world, toon_glass (+ materials/)
levels/plant/shells/             CSG sources of the POI shells (not exported)
levels/plant/baked/              the baked shell meshes and collision (tools/godot/bake_shells.gd)
```
