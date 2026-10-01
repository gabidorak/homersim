# M0: Setup & learning

**Goal**: a working toolchain, an empty-but-structured Godot project under git with tests and CI, and enough Godot and multiplayer knowledge to start M1 confidently.
**Estimated effort**: 1–2 weeks part-time (mostly learning).
**Prerequisites**: none.

## 1. Learn first (in this order)
1. Godot "Getting started" → *Step by step* (nodes, scenes, scripting, signals): https://docs.godotengine.org/en/stable/getting_started/step_by_step/index.html
2. **"Your first 3D game"** (Squash the Creeps), the complete tutorial: https://docs.godotengine.org/en/stable/getting_started/first_3d_game/index.html
3. GDScript reference + **static typing**: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html
4. **High-level multiplayer**: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
5. Scene replication (MultiplayerSpawner / MultiplayerSynchronizer): https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/
6. Exporting for dedicated servers: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html

**Practice exercise (throwaway, outside this repo)**: make Squash the Creeps multiplayer with 2 players on one machine, using `ENetMultiplayerPeer`, a `MultiplayerSpawner` and a `MultiplayerSynchronizer`. Expect to break it a few times. That's the point.

## 2. Install (Linux)
| Tool | How | Notes |
|---|---|---|
| Godot 4.x stable (standard, not .NET) | Download the official build from https://godotengine.org/download/linux/ into `~/opt/godot/` and symlink it to `~/.local/bin/godot` | Flatpak and Steam builds work too, but CLI and headless use is easier with the plain binary |
| Export templates (same version) | Editor → *Editor → Manage Export Templates → Download* | Needed for the Linux, Windows and server exports |
| Blender 4.x LTS | Official tarball from blender.org, or your distro / snap / flatpak | Only needed from M7 |
| git + git-lfs | `sudo apt install git git-lfs && git lfs install` | |
| Editor (optional) | VS Code + "godot-tools" extension, or Godot's built-in editor | Set Godot → Editor Settings → Text Editor → External if using VS Code |

**Pin the Godot version** (e.g. `4.5.1`) in `README.md`, `docs/ARCHITECTURE.md` and the CI workflow.

## 3. Tasks
- [ ] `git init`, first commit with the docs and the existing `.gitignore` / `.gitattributes` (LFS rules).
- [ ] Create a GitHub (or GitLab) repo and push. Make it private for now.
- [ ] Create the Godot project in the repo root: `project.godot`, Forward+ renderer.
- [ ] Project settings:
  - [ ] *Application → Run → Main Scene* = `res://main.tscn`
  - [ ] *Physics → Common → Physics Ticks per Second* = 60
  - [ ] *Display → Window*: 1280×720, resizable, stretch mode `canvas_items`
  - [ ] *Debug → GDScript → Warnings*: `untyped_declaration` = Warn, `inferred_declaration` = Ignore
  - [ ] *Input Map*: `move_forward/back/left/right`, `jump`, `sprint`, `crouch`, `primary`, `secondary`, `interact`, `chat`, `team_chat`, `scoreboard`, `emote`, `pause`
- [ ] Create the folder structure from [ARCHITECTURE §13](../ARCHITECTURE.md#13-repository-layout) (add a `.gdkeep` in each empty folder).
- [ ] Autoload stubs, registered in Project Settings → Autoload: `autoload/net.gd`, `events.gd`, `config.gd`, `log.gd`, `cli.gd`.
  - `cli.gd`: parse `OS.get_cmdline_user_args()` into a `Dictionary` (`--key value` / `--flag`).
  - `log.gd`: `info/warn/error(tag, msg)` printing `[HH:MM:SS][S|C<id>][tag] msg`.
- [ ] `main.tscn` + `main.gd`: the server/client switch from [ARCHITECTURE §2](../ARCHITECTURE.md#entry-point-maingd), pointing at placeholder `server/ServerMain.tscn` and `client/MainMenu.tscn` scenes that just print a line.
- [ ] Install **GUT** from the Asset Library into `addons/gut/` and enable the plugin. Write `tests/unit/test_cli.gd` to test arg parsing.
- [ ] Export presets: `Linux`, `Windows Desktop`, `Linux Server` (Resources tab → Export Mode = *Export as dedicated server*, Features → custom feature `dedicated_server`). Export each once by hand.
- [ ] `.github/workflows/ci.yml`: a job on `barichello/godot-ci:<pinned version>` that runs `godot --headless --import` (to build the import cache) and then the GUT unit tests.
- [ ] Add GUT to `CREDITS.md`.

## 4. Done when
- [ ] `godot --headless -- --server` prints "server boot" and keeps running. `godot` (no args) opens the placeholder main menu.
- [ ] `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` passes locally **and** in CI.
- [ ] The exported Linux client runs. The exported Windows `.exe` runs under Wine or on a Windows PC. The exported server runs headless.
- [ ] The practice exercise works with 2 instances on the same machine.

## 5. Pitfalls
- The editor version and the export templates' version must match exactly.
- Run `godot --headless --import` once in CI before running tests, otherwise resources are missing.
- Don't commit `.godot/` (already in `.gitignore`).
- LFS: run `git lfs install` **before** the first binary commit, or the binaries end up in normal history.
