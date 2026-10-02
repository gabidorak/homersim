# M8: Menus & UX

**Goal**: everything around the gameplay feels finished. That covers the main menu, finding servers (direct connect, favourites, LAN), settings with rebinding, polished lobby, chat, scoreboard and end screen, clear error messages, and a short how-to-play.
**Estimated effort**: 2 weeks.
**Prerequisites**: M7 (or run it in parallel with the end of M7).
**Design refs**: [GDD §3, §8](../GDD.md#8-controls-defaults-rebindable-in-m8), [ARCHITECTURE §5 Net](../ARCHITECTURE.md#5-autoloads).

## 1. Tasks
Status: implemented (2026-10-02). Notes in *italics* say where things live or how they differ from the plan.

### UI foundation
- [x] `client/ui/theme.tres`: a Godot `Theme` with the cartoon display font for titles, a readable font for body text, palette colours, and chunky rounded buttons with hover/press SFX. *Built by `tools/godot/make_theme.gd` (Luckiest Guy + Fredoka, toggle switches drawn in code); the sounds come from the `Ui` autoload, which hooks every button.*
- [x] A menu background: the plant exterior with a slow camera drift (reuse the level, rendered without players), or a simple 3D diorama. *A diorama (`client/menu_background.gd`): the real plant needs a running Session.*
- [x] Every screen works with mouse **and** keyboard navigation (focus neighbours set), and scales via containers at 1280×720 → 4K. *`tests/unit/test_menu_focus.gd` walks every screen with the arrow keys; dialogs trap the focus.*

### Screens
- [x] **Main menu**: Play (→ server browser), Settings, How to play, Credits (renders CREDITS.md content), Quit. *Plus the name prompt at the first start.*
- [x] **Server browser** (`client/ServerBrowser.tscn`):
  - [x] Direct connect field (`host:port`) + optional password prompt. *The prompt appears when the server asks for a password, and again after a wrong one.*
  - [x] Favourites list (saved in `user://settings.cfg`): add, remove, rename.
  - [x] **LAN discovery**: the server broadcasts `{"name","players","max","port","version","state"}` over UDP to port 7778 every 2 s (`PacketPeerUDP` with `set_broadcast_enabled(true)`), and the client listens and lists entries (expiring after 6 s). *To ports 7778–7781, plus `id` and `locked`: Godot can't share a UDP port between processes, so each client on a PC takes the first free one (common/lan_discovery.gd).*
  - [x] Ping display: an unreliable `request_ping` round trip after connecting, or a UDP ping packet in the discovery protocol. *Both: a UDP ping in the LAN list, and ENet's round trip per player in the lobby and scoreboard (`MatchManager.pings`).*
- [x] **Lobby** polish: player cards (name, preferred role, ready, ping), the server name and a match settings summary, a countdown banner, chat docked on the side. *Keys 1 / 2 / 3 and R pick a role and ready up without the mouse.*
- [x] **Settings** (`client/Settings.tscn`, persisted by `Config`):
  - [x] Video: window mode, resolution, VSync, max FPS, render scale (FSR), shadow quality, SSAO, glow toggle, renderer (Forward+ / Compatibility; needs a restart).
  - [x] Controls: mouse sensitivity (FP and TP separately), invert Y, FOV, head bob, camera shake, **key rebinding** (via `InputMap`, saved to config), hold-to-repair instead of minigames.
  - [x] Audio: Master / Music / SFX / UI / Ambience volume sliders.
  - [x] Gameplay: name, chat filter, show FPS/ping. *Plus the language and "show the hints again".*
- [x] **In-game**: pause menu (Resume / Settings / Leave, without pausing the network game), scoreboard on Tab (team, name, ping, key stats, caged/eliminated status), kill feed–style event log ("Alice caged Rat Bob!", "Turbine sabotaged!"). *The pause menu also has How to play.*
- [x] **Post-match**: winner animation, per-player stats and fun awards ("Most bonks", "Sneakiest rat", "Donut addict"), and a "Back to lobby" countdown. *New stats: bonks, donuts, caught (common/awards.gd).*
- [x] **How to play**: 2 illustrated cards per role, plus a first-time pop-up hint system (`Config.seen_hints`). *Illustrations rendered by `tests/helpers/HowToShots.tscn`; texts name the player's own keys.*
- [x] **Errors**: a clear modal for every failure (cannot connect, timeout, version mismatch, wrong password, server full, kicked, lost connection) with a "Back to menu" button. *`common/leave_reason.gd`; the server can `Session.kick(peer, reason)` (the console and validator use it in M9).*

### Localization readiness (cheap now, expensive later)
- [x] Wrap every user-facing string in `tr()`, and add a `translations/strings.csv` with an `en` column (plus `fr` if you like). *English text as the keys, full French column; `tests/unit/test_translations.gd` fails on any string missing from the CSV.*

## 2. Done when
- [ ] A new player can launch the game, find a LAN server, join, read how to play, change their keybinds, play a match and return to the lobby **without any CLI args or help**. Test this with someone who has never seen the game. *Every step works (menus_smoke.sh, a windowed run through the real menu), but the test with a newcomer is still to do.*
- [x] Settings persist across restarts, and rebinding works for every action. *test_user_settings.gd (save/load round trip, every rebindable action).*
- [x] Every connection failure path shows a readable message (go through the list in the tasks above one by one). *menus_smoke.sh (password, kicked, lost, timeout, bad address) and join_smoke.sh (full, version).*

## 3. Pitfalls
- LAN broadcast is often blocked on Windows by the firewall. Document this, and make sure the first-launch firewall prompt happens (Godot binaries trigger it on first listen).
- Don't let UI read game internals directly. Use `Events` and synced state (ARCHITECTURE §9).
- Changing the renderer needs a restart: write it to `override.cfg` (`rendering/renderer/rendering_method`).
