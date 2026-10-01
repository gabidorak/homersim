# M9: Ship v1

**Goal**: a balanced, stable v1.0 that strangers can download for Linux and Windows and host with a documented dedicated server (binary or Docker).
**Estimated effort**: 2–3 weeks, plus ongoing playtests.
**Prerequisites**: M8.

## 1. Tasks
### Balance and playtesting
- [ ] Run at least **5 full playtest sessions** with different groups and player counts (3, 4, 5, 6), and write notes in `docs/playtests/`.
- [ ] Server match telemetry: at the end of each match, append a row to `user://matches.csv` with duration, winner, player counts, final meltdown, sabotages/repairs per subsystem, catches, bites, knockdowns and hazard hits. Add `tools/balance_report.py` to summarise win rates by player count.
- [ ] Target: a win rate of 45–55% for each team at 4 and 6 players. Tune **only** through `data/*.tres`, and update the GDD tables to match.
- [ ] Optional: a 150 ms position-history buffer for hit validation, if playtests show unfair-feeling misses (see ARCHITECTURE §3).

### Robustness
- [ ] Bug bash checklist: join and leave at every match state, a host with 2 players, every role leaving mid-carry/mid-cage/mid-minigame, a long session (10 matches back to back), packet loss of 5%.
- [ ] `MovementValidator`: enable kicking (10 strikes), and review the false positives in the logs.
- [ ] `server/server_console.gd`: stdin commands `status`, `players`, `kick <id|name>`, `ban <name>` (IP ban list in `user://bans.txt`), `say <msg>`, `start`, `end`, `set <rule> <value>`.
- [ ] Rate limits on every `request_*` (about 20/s per peer, chat 1/s). Drop and log anything over the limit.
- [ ] Crash and log handling: the server writes rotating logs, and clients keep the last log in `user://logs/`.

### Packaging
- [ ] Set the version in project settings (`application/config/version = "1.0.0"`). It's used by the join handshake.
- [ ] Exports: `Linux` (x86_64, `.x86_64` + `.pck` zipped), `Windows Desktop` (x86_64 `.exe`, embedded pck, icon via rcedit optional), `Linux Server` (dedicated server mode).
- [ ] `Dockerfile` (see ARCHITECTURE §11) + `docker-compose.yml` example (UDP port mapping, config volume). Document `docker run -p 7777:7777/udp -v ./config:/config homersim-server`.
- [ ] `docs/HOSTING.md`: running the server binary or Docker, opening and forwarding **UDP 7777**, the `server.cfg` reference, console commands, running several servers on different ports.
- [ ] `.github/workflows/release.yml`: on tag `v*` → unit + integration tests → exports → GitHub Release with the 3 zips + checksums → optional itch.io upload via **butler** (`butler push build/linux user/homersim:linux`).
- [ ] Test the Windows build on a real Windows 10/11 machine (firewall prompt, fullscreen, controller-free input, paths with spaces).

### Release
- [ ] Final CREDITS.md audit: every file under `assets/third_party/` is covered, and no non-commercial or share-alike licences slipped in.
- [ ] Name check: make sure the final game title doesn't clash with existing trademarks, and avoid any references to existing shows in names and art.
- [ ] itch.io page: description, 5 screenshots, a short trailer GIF, Linux and Windows downloads, the server download, and a hosting guide link.
- [ ] Tag `v1.0.0`.

## 2. Done when
- [ ] Release artifacts are downloadable, and a friend on Windows plus a friend on Linux join your Docker-hosted server over the internet and play 3 matches without a crash.
- [ ] The balance report shows 45–55% win rates at 4 and 6 players over at least 20 matches.
- [ ] HOSTING.md has been followed successfully by someone other than you.

## 3. After v1.0
See [GDD §10](../GDD.md#10-post-10-ideas): proximity voice, Steam (GodotSteam), master server list, netfox prediction, more maps and rat classes, bots, cosmetics.
