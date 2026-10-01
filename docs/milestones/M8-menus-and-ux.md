# M8: Menus & UX

**Goal**: everything around the gameplay feels finished. That covers the main menu, finding servers (direct connect, favourites, LAN), settings with rebinding, polished lobby, chat, scoreboard and end screen, clear error messages, and a short how-to-play.
**Estimated effort**: 2 weeks.
**Prerequisites**: M7 (or run it in parallel with the end of M7).
**Design refs**: [GDD §3, §8](../GDD.md#8-controls-defaults-rebindable-in-m8), [ARCHITECTURE §5 Net](../ARCHITECTURE.md#5-autoloads).

## 1. Tasks
### UI foundation
- [ ] `client/ui/theme.tres`: a Godot `Theme` with the cartoon display font for titles, a readable font for body text, palette colours, and chunky rounded buttons with hover/press SFX.
- [ ] A menu background: the plant exterior with a slow camera drift (reuse the level, rendered without players), or a simple 3D diorama.
- [ ] Every screen works with mouse **and** keyboard navigation (focus neighbours set), and scales via containers at 1280×720 → 4K.

### Screens
- [ ] **Main menu**: Play (→ server browser), Settings, How to play, Credits (renders CREDITS.md content), Quit.
- [ ] **Server browser** (`client/ServerBrowser.tscn`):
  - Direct connect field (`host:port`) + optional password prompt.
  - Favourites list (saved in `user://settings.cfg`): add, remove, rename.
  - **LAN discovery**: the server broadcasts `{"name","players","max","port","version","state"}` over UDP to port 7778 every 2 s (`PacketPeerUDP` with `set_broadcast_enabled(true)`), and the client listens and lists entries (expiring after 6 s).
  - Ping display: an unreliable `request_ping` round trip after connecting, or a UDP ping packet in the discovery protocol.
- [ ] **Lobby** polish: player cards (name, preferred role, ready, ping), the server name and a match settings summary, a countdown banner, chat docked on the side.
- [ ] **Settings** (`client/Settings.tscn`, persisted by `Config`):
  - Video: window mode, resolution, VSync, max FPS, render scale (FSR), shadow quality, SSAO, glow toggle, renderer (Forward+ / Compatibility; needs a restart).
  - Controls: mouse sensitivity (FP and TP separately), invert Y, FOV, head bob, camera shake, **key rebinding** (via `InputMap`, saved to config), hold-to-repair instead of minigames.
  - Audio: Master / Music / SFX / UI / Ambience volume sliders.
  - Gameplay: name, chat filter, show FPS/ping.
- [ ] **In-game**: pause menu (Resume / Settings / Leave, without pausing the network game), scoreboard on Tab (team, name, ping, key stats, caged/eliminated status), kill feed–style event log ("Alice caged Rat Bob!", "Turbine sabotaged!").
- [ ] **Post-match**: winner animation, per-player stats and fun awards ("Most bonks", "Sneakiest rat", "Donut addict"), and a "Back to lobby" countdown.
- [ ] **How to play**: 2 illustrated cards per role, plus a first-time pop-up hint system (`Config.seen_hints`).
- [ ] **Errors**: a clear modal for every failure (cannot connect, timeout, version mismatch, wrong password, server full, kicked, lost connection) with a "Back to menu" button.

### Localization readiness (cheap now, expensive later)
- [ ] Wrap every user-facing string in `tr()`, and add a `translations/strings.csv` with an `en` column (plus `fr` if you like).

## 2. Done when
- [ ] A new player can launch the game, find a LAN server, join, read how to play, change their keybinds, play a match and return to the lobby **without any CLI args or help**. Test this with someone who has never seen the game.
- [ ] Settings persist across restarts, and rebinding works for every action.
- [ ] Every connection failure path shows a readable message (go through the list in the tasks above one by one).

## 3. Pitfalls
- LAN broadcast is often blocked on Windows by the firewall. Document this, and make sure the first-launch firewall prompt happens (Godot binaries trigger it on first listen).
- Don't let UI read game internals directly. Use `Events` and synced state (ARCHITECTURE §9).
- Changing the renderer needs a restart: write it to `override.cfg` (`rendering/renderer/rendering_method`).
