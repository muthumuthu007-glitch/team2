#!/usr/bin/env bash
# Run ONCE on the server to move Team2's four server programs off Supabase.
#   cd ~/team2-src && git pull && chmod +x functions-install.sh && ./functions-install.sh
#
# After this, deploy.sh keeps them in sync on every push, so this is only needed once.
set -euo pipefail

SRC=~/team2-src
SB=/opt/supabase
FNDIR=$SB/volumes/functions
FNS="team2-admin team2-sms team2-whatsapp team2-email"

[ -d "$FNDIR" ] || { echo "ERROR: $FNDIR not found — is Supabase at $SB?"; exit 1; }

echo "=== what the functions container is told ==="
cd "$SB"
docker compose exec -T functions printenv SUPABASE_URL \
  | sed 's/^/  SUPABASE_URL = /' || echo "  (could not read SUPABASE_URL)"
echo "  VERIFY_JWT   = $(docker compose exec -T functions printenv VERIFY_JWT 2>/dev/null || echo '(unset)')"

# All four functions verify the caller's token themselves, with the service-role
# client, so the gateway must NOT also demand a JWT — that is what verify_jwt:false
# meant on Supabase. Self-hosted, it is one switch for all functions.
NEED_RECREATE=no
if grep -q '^FUNCTIONS_VERIFY_JWT=' .env; then
  CUR=$(grep '^FUNCTIONS_VERIFY_JWT=' .env | cut -d= -f2 | tr -d '[:space:]')
  echo "  FUNCTIONS_VERIFY_JWT in .env = $CUR"
  if [ "$CUR" != "false" ]; then
    sed -i 's/^FUNCTIONS_VERIFY_JWT=.*/FUNCTIONS_VERIFY_JWT=false/' .env
    NEED_RECREATE=yes
    echo "  -> set to false"
  fi
else
  printf '\nFUNCTIONS_VERIFY_JWT=false\n' >> .env
  NEED_RECREATE=yes
  echo "  FUNCTIONS_VERIFY_JWT was missing -> added as false"
fi

echo
echo "=== copying the four programs in ==="
cd "$SRC"
for f in $FNS; do
  [ -f "supabase/functions/$f/index.ts" ] || { echo "ERROR: supabase/functions/$f/index.ts missing"; exit 1; }
  sudo mkdir -p "$FNDIR/$f"
  sudo cp "supabase/functions/$f/index.ts" "$FNDIR/$f/index.ts"
  echo "  $f"
done

if [ "$NEED_RECREATE" = yes ]; then
  echo
  echo "=== restarting the functions container (env changed) ==="
  cd "$SB" && ./run.sh recreate functions
  sleep 8
fi

echo
echo "=== checking each one answers ==="
# No token is sent, so a working function must answer 401 "Not signed in".
# That proves it downloaded its libraries, compiled and ran. 404 means not found.
FAIL=0
for f in $FNS; do
  BODY=$(mktemp)
  CODE=$(curl -s -o "$BODY" -w '%{http_code}' --max-time 90 \
         -X POST "http://127.0.0.1:8000/functions/v1/$f" \
         -H 'Content-Type: application/json' -d '{}' || echo 000)
  printf '  %-16s HTTP %s  %s\n' "$f" "$CODE" "$(head -c 140 "$BODY")"
  [ "$CODE" = "401" ] || FAIL=1
  rm -f "$BODY"
done

echo
if [ "$FAIL" = 0 ]; then
  echo "All four are live on this server. Supabase is no longer needed for them."
else
  echo "Something is not answering 401 — read the lines above before trusting it."
  exit 1
fi
