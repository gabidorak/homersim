# Credits

## Engine
- [Godot Engine](https://godotengine.org): MIT licence. Copyright (c) Juan Linietsky, Ariel Manzur and Godot Engine contributors.

## Third-party assets
Add one row **at the moment an asset is imported**, including CC0 assets: crediting them is free and keeps provenance clear.

| Asset / pack | Author | Source URL | Licence | Used for | Path in repo |
|---|---|---|---|---|---|
| Prototype Textures 1.0 (5 of the PNGs) | Kenney | https://kenney.nl/assets/prototype-textures | CC0 1.0 | graybox materials of the TestArena test level (the plant uses the palette since M7) | assets/third_party/kenney_prototype/ |
| Mini Characters 1.0 (GLB models) | Kenney | https://kenney.nl/assets/mini-characters | CC0 1.0 | the supervisor (character-male-d, recoloured by tools/blender/supervisor.py) | assets/third_party/kenney_mini-characters/ |
| Furniture Kit (GLB models) | Kenney | https://kenney.nl/assets/furniture-kit | CC0 1.0 | set dressing, converted to the palette by tools/blender/kenney.py (`k_*.glb`) | assets/third_party/kenney_furniture-kit/ |
| Food Kit (GLB models) | Kenney | https://kenney.nl/assets/food-kit | CC0 1.0 | set dressing (mugs, pizza box, cheese…), via tools/blender/kenney.py | assets/third_party/kenney_food-kit/ |
| Factory Kit 3.0 (GLB models) | Kenney | https://kenney.nl/assets/factory-kit | CC0 1.0 | set dressing (boxes, cones, warning posts…), via tools/blender/kenney.py | assets/third_party/kenney_factory-kit/ |
| Survival Kit (GLB models) | Kenney | https://kenney.nl/assets/survival-kit | CC0 1.0 | set dressing (barrel, crate, bucket), via tools/blender/kenney.py | assets/third_party/kenney_survival-kit/ |
| Particle Pack (17 of the transparent PNGs) | Kenney | https://kenney.nl/assets/particle-pack | CC0 1.0 | particle sprites (client/vfx.gd) | assets/third_party/kenney_particle-pack/ |
| Impact Sounds (34 of the OGGs) | Kenney | https://kenney.nl/assets/impact-sounds | CC0 1.0 | footsteps, punches, metal, glass, wood (client/sfx.gd) | assets/third_party/kenney_impact-sounds/ |
| Interface Sounds (selected OGGs) | Kenney | https://kenney.nl/assets/interface-sounds | CC0 1.0 | UI clicks, confirm/error, ticks | assets/third_party/kenney_interface-sounds/ |
| Sci-fi Sounds (selected OGGs) | Kenney | https://kenney.nl/assets/sci-fi-sounds | CC0 1.0 | door slides, the meltdown explosion | assets/third_party/kenney_sci-fi-sounds/ |
| Digital Audio (selected OGGs) | Kenney | https://kenney.nl/assets/digital-audio | CC0 1.0 | keycard beeps, zap, power-up | assets/third_party/kenney_digital-audio/ |
| RPG Audio (selected OGGs) | Kenney | https://kenney.nl/assets/rpg-audio | CC0 1.0 | cage latch, creak | assets/third_party/kenney_rpg-audio/ |

The model packs keep only their GLB files (plus the colormap textures and `License.txt`); a `.gdignore`
in each keeps Godot from importing them, since the game uses the palette versions in
`assets/generated/`.

## Addons
| Addon | Author | Source | Licence |
|---|---|---|---|
| GUT 9.7.1 | bitwes (Butch Wesley) | https://github.com/bitwes/Gut | MIT |

## Generated assets
Models in `assets/generated/` are produced by the scripts in `tools/blender/` and belong to this project
(except the supervisor and the `k_*` models, which are recoloured Kenney CC0 models, see above).
Sounds and music in `assets/audio/` are synthesized from scratch by `tools/audio/` (numpy) and belong to this
project. The colour palette (`assets/palette.png`) comes from `tools/art/palette.py`.
