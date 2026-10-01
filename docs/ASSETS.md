# Assets: style, sources, pipeline

## 1. Art direction
- **Low-poly cartoon** with chunky shapes, exaggerated proportions (big hands and heads on supervisors, big ears and tails on rats), and no fine detail.
- **Flat colours** sampled from a single **palette texture** (`assets/palette.png`, 16×16 swatches) wherever possible. Few or no detailed textures. This makes CC0 packs from different authors look like one game.
- **Toon shading**: 2–3 light bands, a soft rim light, and black inverted-hull outlines (`shaders/toon.gdshader` + `shaders/outline.gdshader`). Applied as a **material override on import** so third-party models adopt the style automatically.
- **Readability first**: gameplay objects get a **colour code**:

| Meaning | Colour | Examples |
|---|---|---|
| Rat-interactable (sabotage) | Rat green `#7BD389` glow on hover | Sabotage points, levers, vent entrances |
| Supervisor-interactable (repair/console) | Safety yellow `#FFC93C` | Repair panels, consoles, doors |
| Danger / hazard | Alarm red `#E84A5F` and hazard stripes | Steam jets, puddles, radiation |
| Nuclear glow | Radioactive green `#9CFF2E`, emissive | Rods, pool, vials |
| Plant walls and floors | Muted teal, beige, grey | Environment |

- Lighting: warm interior lights, a cool night-time exterior. A WorldEnvironment with glow (bloom) for emissives, and SSAO on high settings. The alarm states change light colour and add rotating beacons.

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

**Fallbacks**
- No good CC0 rat? Generate a **chunky rat with a Blender script** (primitive body + head + ears + tail, Rigify or a simple hand-built armature, about 2k tris). Or use a CC-BY model with attribution.
- Supervisor: a Quaternius/KayKit humanoid with a recoloured uniform (white shirt, tie, hard hat, as a palette swap).

## 4. Claude-generated props (Blender Python)
Scripts live in `tools/blender/`. Each one builds parametric geometry, assigns palette materials (UVs mapped onto palette swatches), and exports `.glb` to `assets/generated/<name>.glb`.

Run them headless:
```bash
blender -b -P tools/blender/export_all.py            # everything
blender -b -P tools/blender/pipe.py -- --length 4 --radius 0.25 --out assets/generated/pipe_4m.glb
```
| Script | Produces | Parameters |
|---|---|---|
| `common.py` | Shared helpers: palette material, bevel, export, origin at the base, collision mesh `-col` suffix | – |
| `pipe.py` | Straight pipes, 90° elbows, T-junctions, flanges, supports | length, radius, segments |
| `tank.py` | Vertical/horizontal tanks with bands and hazard stripes | radius, height |
| `valve.py` | Valve wheel (separate node so it can be animated) + body | wheel radius, spokes |
| `console.py` | Control desk with screen slots (screens are separate meshes for viewport textures), buttons, levers | width, screen count |
| `breaker_panel.py` | Electrical cabinet with switches (separate nodes) | rows, cols |
| `catwalk.py` | Grated catwalk segments, stairs, railings (2 m grid) | length, with_rail |
| `vent.py` | Vent duct straight/corner/T, grille covers | 0.7 m inner section |
| `reactor.py` | Reactor core vessel, control rod assembly (rods animatable), pool rim | rod count |
| `turbine.py` | Large turbine housing with a spinning shaft | length |
| `cooling_tower.py` | Hyperboloid tower (landmark, outside the playable area) | height |
| `cctv.py` | Wall-mounted camera (+ broken variant) | – |
| `cage.py` | Rat cage with a door hinge node | – |
| `donut.py` | Donut + box (pink icing, sprinkles) | – |
| `rat.py` | *(fallback)* chunky rat body and armature | – |

Godot import conventions (automatic thanks to name suffixes): `-col` → static collision, `-colonly` → collision only, `-noimp` → skip. Animatable parts (valve wheel, rods, levers, doors) are **separately named child nodes**, so code can rotate them without skeletal animation.

## 5. Characters and animation
| Role | Model | Required animations |
|---|---|---|
| Supervisor | CC0 humanoid (Quaternius/KayKit), recoloured | idle, walk, run, jump, broom swing, carry idle/walk, place trap, interact loop, knocked down, get up, eat donut, sit (CCTV), emote |
| Rat | CC0 or generated | idle, run, jump, crawl (vent), bite, sabotage loop (gnaw/pull), stunned (stars), carried (dangling), caged idle, squeak emote |

- Use the **Universal Animation Library** (or Mixamo-like CC0 sets) retargeted with Godot's **Retarget / BoneMap** import (SkeletonProfileHumanoid) for the humanoid. The rat gets a small set of hand-made animations (Blender, or code-driven procedural bobbing at first).
- First-person view: the supervisor's camera shows **separate FP arms + broom** (a simple mesh with 3–4 animations), and other players see the full body.
- An `AnimationTree` with a state machine and blend spaces is driven by `AnimationController` from movement speed and status (see ARCHITECTURE §4).

## 6. Audio list (v1)
| Category | Sounds |
|---|---|
| Plant | Machinery hum (loop per POI), alarm klaxon (warning/critical), steam hiss, electric zap, turbine whine, Geiger clicks |
| Supervisor | Footsteps, broom whoosh, BONK hit, trap place, SNAP, donut munch, "ow!" grunt |
| Rat | Pitter-patter footsteps, squeaks (several), bite chomp, gnawing loop, vent crawl rattle |
| UI | Click, hover, countdown beeps, win/lose stingers |
| Music | Lobby loop, match calm, warning and critical layers (crossfaded) |

Use positional `AudioStreamPlayer3D` with sensible attenuation, and buses `Master / Music / SFX / UI`.

## 7. Poly and texture budgets
| Asset type | Triangles | Textures |
|---|---|---|
| Character | ≤ 6k | Palette only, or ≤ 512² |
| Hero machine (reactor, turbine) | ≤ 15k | Palette + emissive |
| Prop | ≤ 1.5k | Palette |
| Modular wall/floor piece | ≤ 300 | Palette or tiling 512² |

Target: **60 fps at 1080p on a GTX 1060 / RX 580-class GPU** with 6 players.

## 8. Folder layout
```
assets/
  palette.png
  third_party/<author>_<pack>/   (original licence file kept inside)
  generated/                     (output of tools/blender, never edit by hand)
  audio/{sfx,music}/
  fonts/
  ui/
```
