#!/bin/sh
# Docker entrypoint of the launcher of online games (docs/HOSTING.md). The game binary lives in the
# /data volume, not in the image: the first start downloads the newest server build of
# $HOMERSIM_BRANCH (checked against its build.json), and from then on the game's own auto-updater
# replaces it there (autoload/updater.gd), so the image itself never needs rebuilding.
#   HOMERSIM_BRANCH    the branch whose builds to run (default master)
#   HOMERSIM_RELEASES  where the builds are (default the GitHub releases; a local test server works)
# Anything after the image name in `docker run` is added to the game's own arguments.
set -eu
RELEASES=${HOMERSIM_RELEASES:-https://github.com/gabidorak/homersim/releases/download}
BRANCH=${HOMERSIM_BRANCH:-master}
ASSET=homersim-server-linux-x86_64
BIN=/data/bin/$ASSET
TAG=build-$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '-')

if [ ! -x "$BIN" ]; then
	mkdir -p /data/bin
	echo "first start: downloading $ASSET from $RELEASES/$TAG"
	curl -fsSL --retry 3 -o /data/bin/build.json "$RELEASES/$TAG/build.json"
	curl -fSL --retry 3 --progress-bar -o "$BIN.download" "$RELEASES/$TAG/$ASSET"
	want=$(tr -d ' \n\t' < /data/bin/build.json | grep -o "\"$ASSET\":{\"sha256\":\"[0-9a-f]*\"" | grep -o '[0-9a-f]\{64\}' || true)
	got=$(sha256sum "$BIN.download" | cut -d' ' -f1)
	if [ -z "$want" ] || [ "$want" != "$got" ]; then
		echo "the download doesn't match build.json (SHA-256 $got, expected ${want:-none}), giving up" >&2
		rm -f "$BIN.download"
		exit 1
	fi
	chmod 755 "$BIN.download"
	mv "$BIN.download" "$BIN"
	rm -f /data/bin/build.json
fi

if [ ! -f /config/launcher.cfg ]; then
	echo "no /config/launcher.cfg: copy launcher.cfg.example next to compose.yml as launcher.cfg and set key=" >&2
	exit 1
fi

# --branch: follow that branch's builds even before the first update. Godot quits at once on SIGTERM
# (docker stop); the game's servers notice their launcher is gone and stop too.
exec "$BIN" --headless -- --launcher --config /config/launcher.cfg --branch "$BRANCH" \
	--update-url "$RELEASES" --update-interval 60 "$@"
