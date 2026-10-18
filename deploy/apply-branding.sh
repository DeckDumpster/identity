#!/usr/bin/env bash
# Set Pocket ID's name, accent colour and logo from deploy/branding/. Idempotent: reads the live
# values first and writes only what differs. Needs an admin API key in $CONFIG_DIR/pocket-id-api-key
# (0600, one line). Prints what it changed; exits 0 with nothing to do.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
config_dir=${1:-$HOME/.config/identity}
base=${POCKET_ID_URL:-http://127.0.0.1:1411}
brand=$here/branding/branding.json
logo=$here/branding/logo.svg
keyfile=$config_dir/pocket-id-api-key
if [ ! -s "$keyfile" ]; then
  echo "apply-branding.sh: $keyfile is missing; Pocket ID's appearance is NOT being applied (see README)" >&2
  exit 3
fi
key=$(tr -d '[:space:]' <"$keyfile")
api() { curl -fsS -H "X-API-KEY: $key" "$@"; }

want_name=$(jq -r .app_name "$brand")
want_accent=$(jq -r .accent_color "$brand")
live=$(api "$base/api/application-configuration/all")
val() { jq -r --arg k "$1" '.[] | select(.key==$k) | .value' <<<"$live"; }
if [ "$(val appName)" != "$want_name" ] || [ "$(val accentColor)" != "$want_accent" ]; then
  # The update endpoint replaces the whole configuration, so send back every live value.
  body=$(jq -n --argjson all "$live" --arg n "$want_name" --arg a "$want_accent" \
    '($all | map({(.key): .value}) | add) + {appName: $n, accentColor: $a}')
  api -X PUT -H 'Content-Type: application/json' --data-binary @- "$base/api/application-configuration" <<<"$body" >/dev/null
  echo "apply-branding.sh: set name '$want_name' and accent $want_accent"
fi

# Pocket ID keeps a light and a dark logo; both get the one file. Each is compared by hash of what
# Pocket ID serves, so a manual change is corrected too.
want_sum=$(sha256sum <"$logo" | cut -d' ' -f1)
for light in true false; do
  have_sum=$(curl -fsS "$base/api/application-images/logo?light=$light&default=false" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
  if [ "$want_sum" != "$have_sum" ]; then
    api -X PUT -F "file=@$logo;type=image/svg+xml" "$base/api/application-images/logo?light=$light" >/dev/null
    echo "apply-branding.sh: uploaded the $light-mode logo"
  fi
done
