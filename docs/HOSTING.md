# Hosting online games (the VPS launcher)

Friends on different networks play through **online games**. A small always-on **launcher** runs on the VPS.
When someone picks **Host a game → Online server**, the launcher starts a fresh dedicated server for that game,
on one UDP port of a small range. Everyone with the **friends key** sees the game in **Join a game → Online**
and joins it. A game keeps going when its creator leaves. It stops by itself a few minutes after the last
player left.

The game looks for the launcher at **https://homersim.mooo.com** (`OnlineApi.DEFAULT_URL` in
`common/online_api.gd`). Caddy serves that address over HTTPS and passes it to the launcher's plain HTTP port
7790. The games' UDP ports (7800–7809) go straight to the container.

```
game ──HTTPS──> Caddy :443 (homersim.mooo.com) ──HTTP──> launcher :7790   (list / start games)
game ──UDP────> homersim.mooo.com:7800-7809 ───────────> one server per game
```

"Host a game → This computer" and "Play solo" don't need any of this. They work as before.

## What you need
- A Linux VPS with Docker and Docker Compose. Each running game is one process: about 120 MB of RAM and a
  tenth of a desktop core in a 6-player match with bots. The launcher alone takes about 150 MB.
- A DNS **A record** for the name the game uses (homersim.mooo.com), pointing to the VPS. UDP has to reach the
  VPS's own address, so the name can't go through a proxy (on Cloudflare: "DNS only", grey cloud).
- Caddy for HTTPS, already running on the VPS.

## Set up
1. Copy the `tools/docker/` folder of this repo to the VPS (for example `~/homersim/`). It holds
   `Dockerfile`, `entrypoint.sh` and `compose.yml`. Put `launcher.cfg.example` next to them as `launcher.cfg`.
2. Make the friends key and put it in `launcher.cfg` (`key="…"`):
   ```bash
   openssl rand -hex 16
   ```
   The other settings in `launcher.cfg` have working defaults: `max_games=4`, game ports `7800-7809`, and
   games stop after `idle_quit_s=180` seconds with nobody in them.
3. Start it:
   ```bash
   cd ~/homersim && docker compose up -d --build
   docker compose logs -f        # "first start: downloading …", then "[launcher] listening on TCP 7790"
   ```
   The image holds no game. On the first start it downloads the newest `homersim-server-linux-x86_64` of the
   `master` branch from the GitHub releases into the `homersim-data` volume, and checks it against the
   release's `build.json`.
4. Tell Caddy about it. Use whichever matches how your Caddy runs:
   - **Caddy on the host** (a system service). `compose.yml` publishes the API on `127.0.0.1:7790` only:
     ```
     homersim.mooo.com {
         reverse_proxy localhost:7790
     }
     ```
   - **Caddy in a container.** Put both containers on one Docker network: uncomment the two `networks`
     blocks at the end of `compose.yml`, set the name of Caddy's network (`docker network ls`), run
     `docker compose up -d` again, then:
     ```
     homersim.mooo.com {
         reverse_proxy homersim:7790
     }
     ```
     You can then delete the `127.0.0.1:7790:7790/tcp` line.
   
   Reload Caddy. It gets the HTTPS certificate by itself.
5. Open **UDP 7800–7809** to the internet in your VPS provider's firewall (its web panel, if it has one).
   Docker opens them on the VPS itself, even past ufw.
6. Check from your own computer:
   ```bash
   curl https://homersim.mooo.com/                                   # {"game":"homersim","version":"…"}
   curl -H "Authorization: Bearer YOUR_KEY" https://homersim.mooo.com/games   # {"games":[],…}
   ```
7. Give the friends key to your friends. They paste it once, in **Join a game → Online** or on the
   **Host a game** card. The game saves it.

## Running it
- **Logs**: `docker compose logs -f`. Lines tagged `[L]` come from the launcher, `[S]` from the games'
  servers. Each game also writes `/data/.local/share/godot/app_userdata/HomerSim/logs/game_<port>.log` in the
  volume (`docker compose exec homersim ls /data/.local/share/godot/app_userdata/HomerSim/logs`).
- **Updates are automatic.** Every push to `master` makes a new build (`.github/workflows/build.yml`). The
  launcher checks every minute and installs it at once, even while games run. Those games finish on their
  build, and new games start on the new one. The launcher restarts itself once no game runs. A player whose
  game is older gets "Different version: restart the game to update it". You never need to rebuild the
  image. To run another branch's builds, set `HOMERSIM_BRANCH` in `compose.yml`.
- **Stop / start**: `docker compose down` / `docker compose up -d`. Running games stop with the launcher.
- **Change the key or the limits**: edit `launcher.cfg`, then `docker compose restart`. The game doesn't
  check for old keys: friends with the old one get "Wrong friends key" and type the new one.
- **Start from a fresh download**: `docker compose down -v` deletes the volume (the binary and the logs).
- **More games at once**: raise `max_games` and widen `game_ports`. Then change the published range in
  `compose.yml` and your provider's firewall to match. Keep a few more ports than games, because a stopped
  game's port isn't reused at once.

## Test it on your own computer first
With Docker on your computer, the same folder works locally (`docker compose up -d --build`, with
`launcher.cfg` next to it). Then point the game at it for one run:
```bash
./homersim-linux-x86_64 -- --online-url http://localhost:7790
```
Without Docker, run a launcher from the editor build or an exported server binary. It reads `launcher.cfg`
from the project folder, or next to the binary:
```bash
godot --headless -- --launcher --config launcher.cfg
```
`tests/integration/online_games.sh` does exactly this, with headless clients that create and join a game.

## How it works (for the code)
- Launcher: `server/launcher/launcher.gd` (games, ports, limits) and `server/launcher/http_server.gd` (a
  minimal HTTP/1.1 server). The API is in `common/online_api.gd`.
- Each game is the normal dedicated server (`server/server_main.gd`) with `--status-file` (players and state,
  for the list), `--idle-quit S` and `--owner-pid` (it stops if the launcher goes). The spawning code is shared
  with Play solo / Host a game (`common/server_process.gd`).
- Game side: `client/online_client.gd`, the Online tab (`client/server_browser.gd`), the Online server choice
  (`client/game_setup.gd`) and `MainMenu.start_online`.
- More in [ARCHITECTURE §2](ARCHITECTURE.md#online-games-the-vps-launcher).
