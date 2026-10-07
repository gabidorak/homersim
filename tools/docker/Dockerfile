# The launcher of online games (docs/HOSTING.md): starts one dedicated server per online game.
# The image holds no game: entrypoint.sh downloads the newest server build into the /data volume on
# the first start, and the game's own auto-updater keeps it up to date there.
FROM debian:stable-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --create-home --home-dir /data --uid 1000 --shell /usr/sbin/nologin homersim

COPY --chmod=755 entrypoint.sh /usr/local/bin/homersim-entrypoint

# HOME: Godot keeps its user:// files (logs, the games' settings) under $HOME/.local/share/godot.
ENV HOME=/data
USER homersim
WORKDIR /data
VOLUME /data
# 7790/tcp: the launcher's HTTP API (behind Caddy). 7800-7809/udp: the games (launcher.cfg game_ports).
EXPOSE 7790/tcp 7800-7809/udp
ENTRYPOINT ["homersim-entrypoint"]
