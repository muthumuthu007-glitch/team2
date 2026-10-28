#!/usr/bin/env bash
# Team2 deploy — run ON THE SERVER: cd ~/team2-src && ./deploy.sh
#
# Pulls from GitHub, copies to the web root, stamps the build, and repoints the
# app at THIS server's database. The repo keeps the Supabase address so
# index.html stays deployable anywhere; this rewrites it at deploy time.
set -euo pipefail

SRC=~/team2-src
WEB=/var/www/team2
ENV=/opt/supabase/.env

cd "$SRC"

# bash reads a script lazily, by byte offset. git pull can rewrite THIS file
# mid-run, after which bash carries on reading the new file from the old
# offset - skipping lines or running fragments. Re-exec if it changed.
BEFORE=$(md5sum "$0" | cut -d" " -f1)
git pull --ff-only --quiet
AFTER=$(md5sum "$0" | cut -d" " -f1)
if [ "$BEFORE" != "$AFTER" ] && [ -z "${TEAM2_REEXEC:-}" ]; then
  export TEAM2_REEXEC=1
  exec /bin/bash "$0" "$@"
fi

ANON=$(grep '^ANON_KEY=' "$ENV" | cut -d= -f2)
[ -n "$ANON" ] || { echo "ERROR: ANON_KEY not found in $ENV"; exit 1; }

BUILD=$(git rev-parse --short HEAD)
VER=$(grep -oE 'version: "[^"]*"' index.html | head -1 | cut -d'"' -f2)

sudo mkdir -p "$WEB"
sudo cp index.html manifest.webmanifest "$WEB"/
sudo sed -i \
  -e "s|url: \"https://thmszlxepqkrcqavlilq.supabase.co\"|url: \"https://team2.carloo.in\"|" \
  -e "s|key: \"sb_publishable_[^\"]*\"|key: \"$ANON\"|" \
  -e "s|version: \"$VER\"|version: \"$VER+$BUILD\"|" \
  "$WEB/index.html"
sudo chown -R caddy:caddy "$WEB"

# Check for the stamp of THIS build. The url alone proves nothing: the previous
# deploy already wrote it, so a stale file passed that test and the script
# reported success having copied nothing.
grep -q "version: \"$VER+$BUILD\"" "$WEB/index.html" \
  || { echo "ERROR: $WEB/index.html is not the build we just made"; exit 1; }

grep -q 'url: "https://team2.carloo.in"' "$WEB/index.html" \
  || { echo "ERROR: url not rewritten"; exit 1; }

# Server programs. The browser calls these at /functions/v1/<name>, which Caddy
# hands to the Supabase edge runtime. Run functions-install.sh once before this
# works; after that every push keeps them current.
FNDIR=/opt/supabase/volumes/functions
if [ -d "$FNDIR" ]; then
  for d in supabase/functions/*/; do
    f=$(basename "$d")
    [ -f "$d/index.ts" ] || continue
    sudo mkdir -p "$FNDIR/$f"
    sudo cp "$d/index.ts" "$FNDIR/$f/index.ts"
  done
fi

sudo systemctl reload caddy
echo "deployed $VER+$BUILD"
