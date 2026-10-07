# HomerSim (working title)

A goofy, cartoon-style **asymmetric multiplayer** game set in a nuclear power plant.

- **1–2 Supervisors** (first person) must keep the plant running until the shift ends.
- **3–4 Rats** (third person) sneak through vents and sabotage the plant until it melts down.
- Whoever starts a game can pick other teams: 1–3 supervisors against 1–6 rats, bots filling the empty seats.
- Supervisors whack, catch and cage rats. Rats bite, trip and rob supervisors. Broken machinery hurts everyone.

Engine: **Godot 4.7.2-stable (GDScript)**, standard build (not .NET), with a dedicated headless server. Targets: **Linux and Windows**.

> Status: **M8 implemented** (M3–M8 still waiting for a playtest). M8 is everything around the gameplay: a main menu over a little 3D diorama, a server browser (LAN discovery with ping, favourites, direct connect, server passwords), settings (video, controls with key rebinding, audio, gameplay, all saved), a polished lobby (player cards, pings, server info), an Esc menu, a Tab scoreboard, an event feed, a post-match screen with awards, How to play with illustrations, first-time hints, a clear message for every way a connection can fail, a cartoon UI theme, and the whole game in English and French. Screenshots in [docs/screenshots/](docs/screenshots/). Earlier: M3 plant simulation, sabotage and repairs, meltdown meter, HUD; M4 PvP (broom, bites, carry and cage, keycards, traps, donuts); M5 the plant layout; M6 hazards, repair minigames, Control Room consoles; M7 the art and audio pass. Next: playtest with friends (notes go in [docs/playtests/](docs/playtests/TEMPLATE.md)), including someone who has never seen the game (M8's last check) and a run at 100 ms of simulated latency, then [M9](docs/milestones/M9-ship-v1.md).

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

## Downloads and auto-update
Every push to any branch builds the game on GitHub Actions and, once the tests pass, replaces that branch's
release ([Releases](https://github.com/gabidorak/homersim/releases): `build-master` is the latest, the other
branches are pre-releases). Download one file:

| File | What |
|---|---|
| `homersim-linux-x86_64` / `homersim-windows-x86_64.exe` | the game (client) |
| `homersim-server-linux-x86_64` / `homersim-server-windows-x86_64.exe` | dedicated server |

On Linux, make it executable first (`chmod +x homersim-linux-x86_64`). The folder must be writable: from then on, the
game and the server update themselves. At each start they download the newest build of their branch, then restart
with the same arguments. The server also checks every 5 minutes while nobody is connected. Clients and servers must
run the exact same build to play together, so keep both updating.
```bash
./homersim-linux-x86_64 -- --branch my-feature    # follow another branch (sticks: that build then follows my-feature)
./homersim-linux-x86_64 -- --no-update            # skip the update check
./homersim-server-linux-x86_64 -- --port 7777     # the server runs as 2 processes: a small supervisor + the real server
```
Builds from source or local exports never update themselves.

## Tests and exports
The generated art and audio are committed (Git LFS), so building the game needs only Godot. Regenerating them
(`tools/build_assets.sh`) also needs Blender 4.2+ (tested with 5.0), Python 3 with numpy and Pillow, and ffmpeg.
```bash
godot --headless --import    # once, or after adding files outside the editor
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
godot --headless --export-release "Linux" build/linux/homersim.x86_64
godot --headless --export-release "Windows Desktop" build/windows/homersim.exe
godot --headless --export-release "Linux Server" build/server/homersim_server.x86_64
godot --headless --export-release "Windows Server" build/server-windows/homersim_server.exe
```
Each export is a single file (the `.pck` is embedded).

## Translations
Every text the player reads goes through `tr()` and lives in [translations/strings.csv](translations/strings.csv)
(`keys,en,fr`; the key is the English text itself, so a missing row still shows English). After adding a text:
add its row (keep `%s` / `%d` in the same order in each language), run the unit tests (`test_translations.gd` lists
any text missing from the CSV), and `godot --headless --import` to rebuild the `.translation` files. A new
language is one more column plus an entry in `Config.LANGUAGES`.

## Running
Start the game with no arguments: the menu asks for a name the first time, then **Join a game** opens the server
browser. Servers on your network show up by themselves (with their ping); others are joined by typing their
address, and can be saved as favourites. Settings and How to play are in the menu, and in game behind Esc.

**Play solo** and **Host a game** need no separate server: the game starts a hidden second copy of itself as a
dedicated server and joins it. Play solo asks for the role you'd like, the bots' difficulty and the match size,
then the match starts at once (nobody else can join, and the game doesn't pause). Host a game asks for a name, a
password, the most players, the bots and the UDP port (7777). Friends on your network see the game in their
server browser. To play over the internet, they type your public address, and UDP 7777 must be forwarded to your
computer on your router. When the host leaves, the game ends for everyone. That server's log is
`user://logs/local_server.log` (same folder as the settings, below).

**Online games** need no port forwarding: on the Host a game card, pick **Online server**. The game then runs on
the VPS (homersim.mooo.com) instead of your computer, friends find it in **Join a game → Online**, and it keeps
going when you leave (it stops a few minutes after the last player left). Both need the **friends key**, typed
once (ask whoever runs the server). Running that server: [docs/HOSTING.md](docs/HOSTING.md).
```bash
# dedicated server (from the editor build or an exported server binary)
godot --headless -- --server --port 7777          # also: --max-players N, --config path, --password X, --no-lan, --debug-start [N]
# client: straight into a server (skips the browser), and/or as someone else for this run
godot -- --connect 127.0.0.1:7777 --name Alice
# server + 3 clients in one go (Ctrl+C stops all)
tools/dev/run_local.sh 3
```
Server settings live in `server.cfg` (copy [server.cfg.example](server.cfg.example): name, password, port,
players, match rules); CLI args override them. A server announces itself on the local network (UDP 7778–7781)
unless started with `--no-lan`. **Windows**: the first time the game or the server runs, Windows asks whether to
allow it through the firewall: allow it on private networks, or LAN servers stay invisible (joining by address
still works if UDP 7777 is open). User settings are saved in `user://settings.cfg`
(`~/.local/share/godot/app_userdata/HomerSim/` on Linux, `%APPDATA%\Godot\app_userdata\HomerSim\` on Windows);
`--settings PATH` uses another file. The language follows the system (English or French) or the Gameplay setting.
In game (default keys, all rebindable in Settings → Controls; the game shows them as printed on your keyboard):
WASD, mouse, Space to jump, Shift to sprint, **hold E** to sabotage (rats) or repair (supervisors), Enter to chat,
T to chat with your team, hold Tab for the scoreboard, M for the map of the plant (a minimap in the corner shows
the rooms around you), Esc for the menu (the game keeps running; a click in the view goes back to it). In the lobby, 1 / 2 / 3 pick the role you would like and R readies you up. Supervisors: LMB
swings the broom, E grabs a stunned rat and cages it, hold RMB then release to place a trap; the inventory at the
bottom of the screen shows what you carry: 1 / 2 / 3 or the mouse wheel select the snap trap, the cheese lure (Q
also switches between the two) or a donut taken at the Break Room counter, which E eats. Rats: LMB bites, hold E behind a supervisor to steal its keycard, hold E at a cage to free a friend.
Supervisors repair with a short mouse minigame (E at a repair point; Esc gives up; Settings → Controls, or
`--hold-repairs`, uses the 6 s hold instead), and use the Control Room consoles (emergency coolant; SCRAM: press
twice, cover then button). Broken subsystems spawn hazards that hit both teams. Eliminated rats spectate (LMB / RMB
cycle players, WASD flies). Z emotes (a whistle, a squeak); camera shake can be turned off in the settings
(or `--no-shake`). Rats win when the meltdown meter hits 100%; supervisors win when the shift timer runs out first.
The match starts when at least 3 players are in and more than half of them are ready; `--debug-start N` on the
server skips the vote once N players joined.

From the editor: *Debug → Customize Run Instances…* → enable multiple instances, set 4. Give instance 1
the arguments `-- --server --headless` and instances 2–4 `-- --connect 127.0.0.1:7777 --name P2` (P3, P4).

Test helpers:
```bash
tests/integration/join_smoke.sh       # headless server + clients: join, full, version mismatch, kill detection
tests/integration/lobby_smoke.sh      # lobby: prefs, ready vote, roles, countdown, chat, validator, team left
tests/integration/run_match_loop.sh   # full match with 2 bots: sabotage, cancels, repair, timer, winner, result JSON
tests/integration/critical_lever.sh   # 2 rat bots on a lever pair, then reboot + repairs
tests/integration/pvp_capture.sh      # broom, grab, carry, cage, free, eliminate, ghost and team chat (3 bots)
tests/integration/pvp_swarm.sh        # bite makes a carrier drop, 3 rats knock down a supervisor, swarm bonus (4 bots)
tests/integration/pvp_items.sh        # steal, keycard door lockout, dropped keycard, traps, donut, spare keycard (~1 min)
tests/integration/pvp_hack.sh         # a "hacked client" sends ~25 bad requests; the server must refuse them all
tests/integration/plant_cctv.sh       # on the plant: CCTV chair + broken camera, ladder, vent shaft, out of bounds
tests/integration/map_check.sh        # navmesh paths on the plant vs the GDD design rules (--update-docs: README table)
tests/integration/hazards.sh          # on the plant: steam jets (both teams, on/off hysteresis), puddle, radiation, debris, smoke
tests/integration/minigames.sh        # on the plant: the 3 repair minigames through the real overlay, a loss, a hacked instant win
tests/integration/control_room.sh     # on the plant: emergency coolant (power, cooldown), SCRAM (cover, timer +30 s)
tests/integration/menus_smoke.sh      # M8, the real menus: LAN discovery + join, password prompt, kicked, lost, timeout, bad address
tests/integration/local_games.sh      # Play solo and Host a game: the client's own server, a LAN friend, the host leaving, busy port, crash
# test-only client flags (debug builds): --pref rat|supervisor|any, --auto-ready, --say TEXT,
#   --auto-move, --debug-speed N (fake speed hack), --screenshot PATH [--screenshot-delay S | --screenshot-times T1,T2,…],
#   --debug-kick-me, --leave-after S; in the menu (M8): --lan-join NAME, --auto-password A,B,…, --dismiss-errors,
#   --solo [any|supervisor|rat], --host-game NAME [--host-port N] [--host-bots N], --local-server-args "…"
# test-only server flags (debug builds): --allow-debug (debug RPCs such as teleport), --test-duration S,
#   --exit-after-match, --result-file PATH
# scripted bot client (debug builds): --bot rat|supervisor [--bot-target ID] [--bot-lever A|B] [--bot-delay S]
#   PvP scenarios: --bot-scenario capture|swarm|items|hack|plant [--bot-part P]; M6: hazards|minigame|control
# level (debug builds, server and clients alike): --level plant (default) | test (the TestArena sandbox)
# server: --no-heatmap   client: --debug-overlay (F3 overlay; F4 = route stopwatch)
godot tests/helpers/MapTour.tscn -- --out /tmp/tour [--alarm]   # windowed: screenshots + fps of every room
godot tests/helpers/HazardTour.tscn -- --out /tmp/hazards        # windowed: every hazard live, consoles, minigames
python3 tools/map/gen_plant.py --force && godot --headless -s tools/godot/bake_shells.gd   # rebuild the plant from the layout numbers
tools/build_assets.sh [models|audio|level|all]   # M7: palette, Blender models, synthesized audio, level, Godot import
godot tests/helpers/MapTour.tscn -- --players 6 --no-vsync   # + animated bodies, uncapped fps (perf check)
godot tests/helpers/CharacterTour.tscn -- --out /tmp/chars   # windowed: every character animation state
godot tests/helpers/ArtGallery.tscn -- --files crate,lever     # windowed: models under the real shaders
godot tests/helpers/UiTour.tscn -- --settings /tmp/tour.cfg --out /tmp/ui [--lang fr|en] [--only NAME]   # windowed: every menu and in-game screen
godot tests/helpers/HowToShots.tscn -- --out /tmp/howto          # windowed: renders the How to play illustrations (copy to assets/ui/howto/)
godot tests/helpers/ItemIcons.tscn -- --out res://assets/ui/items # windowed: renders the hotbar's item icons from the models
godot --headless -s tools/godot/make_theme.gd                    # rebuilds client/ui/theme.tres (fonts, colours, buttons)
python3 tools/heatmap.py ~/.local/share/godot/app_userdata/HomerSim/heatmap_*.csv   # playtest heatmap
godot -- --connect 127.0.0.1:7777 --game-version 0.0.0   # debug builds only: fake an old client
# simulate a bad network on localhost (needs sudo, remove it afterwards!)
sudo tc qdisc add dev lo root netem delay 100ms 20ms loss 1%
sudo tc qdisc del dev lo root
```
