# HomerSim (working title)

A goofy, cartoon-style **asymmetric multiplayer** game set in a nuclear power plant.

- **1–2 Supervisors** (first person) must keep the plant running until the shift ends.
- **3–4 Rats** (third person) sneak through vents and sabotage the plant until it melts down.
- Supervisors whack, catch and cage rats. Rats bite, trip and rob supervisors. Broken machinery hurts everyone.

Engine: **Godot 4.7.2-stable (GDScript)**, standard build (not .NET), with a dedicated headless server. Targets: **Linux and Windows**.

> Status: **M2 done** (lobby with role preferences and a ready vote, team balance, countdown, first-person supervisors, third-person rats with vents, stamina, chat, movement validator). Next: [M3](docs/milestones/M3-first-playable-loop.md).

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

## Tests and exports
```bash
godot --headless --import    # once, or after adding files outside the editor
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
godot --headless --export-release "Linux" build/linux/homersim.x86_64
godot --headless --export-release "Windows Desktop" build/windows/homersim.exe
godot --headless --export-release "Linux Server" build/server/homersim_server.x86_64
```

## Running
```bash
# dedicated server (from the editor build or an exported server binary)
godot --headless -- --server --port 7777          # also: --max-players N, --config path, --debug-start [N]
# client (or run without args and use the menu)
godot -- --connect 127.0.0.1:7777 --name Alice
# server + 3 clients in one go (Ctrl+C stops all)
tools/dev/run_local.sh 3
```
Server settings live in `server.cfg` (copy [server.cfg.example](server.cfg.example)); CLI args override them.
In game: WASD, mouse, Space to jump, Shift to sprint, Enter to chat. Esc frees the mouse (to click the lobby
buttons), a click captures it again. The match starts when at least 3 players are in and more than half of
them are ready; `--debug-start N` on the server skips the vote once N players joined.

From the editor: *Debug → Customize Run Instances…* → enable multiple instances, set 4. Give instance 1
the arguments `-- --server --headless` and instances 2–4 `-- --connect 127.0.0.1:7777 --name P2` (P3, P4).

Test helpers:
```bash
tests/integration/join_smoke.sh       # headless server + clients: join, full, version mismatch, kill detection
tests/integration/lobby_smoke.sh      # lobby: prefs, ready vote, roles, countdown, chat, validator, abort
# test-only client flags (debug builds): --pref rat|supervisor|any, --auto-ready, --say TEXT,
#   --auto-move, --debug-speed N (fake speed hack), --screenshot PATH [--screenshot-delay S]
godot -- --connect 127.0.0.1:7777 --game-version 0.0.0   # debug builds only: fake an old client
# simulate a bad network on localhost (needs sudo, remove it afterwards!)
sudo tc qdisc add dev lo root netem delay 100ms 20ms loss 1%
sudo tc qdisc del dev lo root
```
