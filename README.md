# HomerSim (working title)

A goofy, cartoon-style **asymmetric multiplayer** game set in a nuclear power plant.

- **1–2 Supervisors** (first person) must keep the plant running until the shift ends.
- **3–4 Rats** (third person) sneak through vents and sabotage the plant until it melts down.
- Supervisors whack, catch and cage rats. Rats bite, trip and rob supervisors. Broken machinery hurts everyone.

Engine: **Godot 4 (GDScript)**, with a dedicated headless server. Targets: **Linux and Windows**.

> Status: **planning**. No game code yet. Start with [M0](docs/milestones/M0-setup-and-learning.md).

## Documents
| Doc | What's inside |
|---|---|
| [docs/GDD.md](docs/GDD.md) | Game design: rules, roles, plant simulation, map, all balance numbers |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Technical architecture: client/server, networking, scenes, components, testing, CI |
| [docs/ASSETS.md](docs/ASSETS.md) | Art style, asset sources and licences, Blender-script pipeline, scale rules |
| [CREDITS.md](CREDITS.md) | Third-party asset attribution (fill in as assets are added) |

## Roadmap
| # | Milestone | Plan |
|---|---|---|
| M0 | Setup & learning | [M0-setup-and-learning.md](docs/milestones/M0-setup-and-learning.md) |
| M1 | Networked graybox | [M1-networked-graybox.md](docs/milestones/M1-networked-graybox.md) |
| M2 | Roles & controllers | [M2-roles-and-controllers.md](docs/milestones/M2-roles-and-controllers.md) |
| M3 | **First playable loop** | [M3-first-playable-loop.md](docs/milestones/M3-first-playable-loop.md) |
| M4 | PvP | [M4-pvp.md](docs/milestones/M4-pvp.md) |
| M5 | Map v1 (graybox) | [M5-map-graybox.md](docs/milestones/M5-map-graybox.md) |
| M6 | Hazards & minigames | [M6-hazards-and-minigames.md](docs/milestones/M6-hazards-and-minigames.md) |
| M7 | Art & audio pass | [M7-art-and-audio.md](docs/milestones/M7-art-and-audio.md) |
| M8 | Menus & UX | [M8-menus-and-ux.md](docs/milestones/M8-menus-and-ux.md) |
| M9 | Ship v1 | [M9-ship-v1.md](docs/milestones/M9-ship-v1.md) |

Post-1.0 ideas (proximity voice, Steam, master server, more maps, client prediction) are listed at the end of the [GDD](docs/GDD.md#10-post-10-ideas).

## Running (available from M1 onwards)
```bash
# dedicated server (from the editor build or an exported server binary)
godot --headless -- --server --port 7777
# client
godot -- --connect 127.0.0.1:7777 --name Alice
```
