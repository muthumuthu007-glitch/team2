#!/usr/bin/env bash
# Team2 deploy — run ON THE SERVER: cd ~/team2-src && ./deploy.sh
#
# Pulls the latest code from GitHub, copies it to the web root, and repoints the
# app at THIS server's database. The repo keeps the Supabase address so the file
# stays deployable anywhere; this script rewrites it at deploy time.
set -euo pipefail

SRC=~/team2-src
WEB=/var/www/team2
ENV=/opt/supabase/.env

cd "$SRC"
echo "== pulling =="
git pull --ff-only

ANON=$(grep '^ANON_KEY=' "$ENV" | cut -d= -f2)
[ -n "$ANON" ] || { echo "ERROR: ANON_KEY not found in $ENV"; exit 1; }

echo "== deploying =="
sudo mkdir -p "$WEB"
sudo cp index.html manifest.webmanifest "$WEB"/
sudo sed -i \
  -e "s|url: \"https://thmszlxepqkrcqavlilq.supabase.co\"|url: \"https://team2.carloo.in\"|" \
  -e "s|key: \"sb_publishable_[^\"]*\"|key: \"$ANON\"|" \
  "$WEB/index.html"
sudo chown -R caddy:caddy "$WEB"

grep -q 'url: "https://team2.carloo.in"' "$WEB/index.html" \
  || { echo "ERROR: url not rewritten — check the pattern in deploy.sh"; exit 1; }

sudo systemctl reload caddy
echo "== live =="
grep -Eo 'version: "[^"]*"|url: "[^"]*"' "$WEB/index.html" | head -2
