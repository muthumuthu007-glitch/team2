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
git pull --ff-only --quiet

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

grep -q 'url: "https://team2.carloo.in"' "$WEB/index.html" \
  || { echo "ERROR: url not rewritten"; exit 1; }

sudo systemctl reload caddy
echo "deployed $VER+$BUILD"
