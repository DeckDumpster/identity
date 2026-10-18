#!/usr/bin/env bash
# Break-glass for one Cloudflare Access app, used when Pocket ID is down and not quickly fixable.
#
#   breakglass.sh <app>            switch that app to Cloudflare one-time PIN for ryan@gantt.pub only
#   breakglass.sh --revert <app>   restore the exact policy/login settings saved at switch time
#   breakglass.sh --status         list apps currently in break-glass
#
# <app> is the Access application's exact name or its domain. The Cloudflare token is a 0600 file
# (CLOUDFLARE_API_TOKEN=..., CLOUDFLARE_ACCOUNT_ID=...) in ~/.config/identity/cloudflare-breakglass.env;
# it needs Access: Apps and Policies edit and Access: Identity Providers read. No Terraform, no MFA.
#
# The alarm: a saved state file per active app under STATE_DIR. deploy/check-identity.sh reads
# that directory every minute and pages while any file exists, and again when the last is gone.
# Revert restores the saved app body and deletes the temporary policy, so the next terraform plan
# shows no drift.
set -euo pipefail

CF_API=${CF_API:-https://api.cloudflare.com/client/v4}
TOKEN_FILE=${TOKEN_FILE:-$HOME/.config/identity/cloudflare-breakglass.env}
STATE_DIR=${BREAKGLASS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/identity/breakglass}
BREAKGLASS_EMAIL=${BREAKGLASS_EMAIL:-ryan@gantt.pub}
POLICY_NAME="breakglass: $BREAKGLASS_EMAIL one-time PIN"

die() { echo "breakglass: $*" >&2; exit 1; }

mode=switch
case "${1:-}" in
  --revert) mode=revert; shift ;;
  --status) mode=status; shift ;;
  -h|--help|"") sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
app_arg=${1:-}
[ "$mode" = status ] || [ -n "$app_arg" ] || die "usage: breakglass.sh [--revert] <app>"

if [ "$mode" = status ]; then
  shopt -s nullglob
  for f in "$STATE_DIR"/*.json; do basename "${f%.json}"; done
  exit 0
fi

[ -f "$TOKEN_FILE" ] || die "$TOKEN_FILE is missing (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID; mode 0600)"
[ "$(stat -c %a "$TOKEN_FILE")" = 600 ] || die "$TOKEN_FILE must be mode 0600"
# shellcheck disable=SC1090
. "$TOKEN_FILE"
: "${CLOUDFLARE_API_TOKEN:?not set in $TOKEN_FILE}" "${CLOUDFLARE_ACCOUNT_ID:?not set in $TOKEN_FILE}"

# api <METHOD> <path> [json-body-on-stdin]: prints the result object; dies unless success=true.
api() {
  local method=$1 path=$2 resp
  resp=$(curl -sS --max-time 30 -X "$method" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H 'Content-Type: application/json' --data-binary @- \
    "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/$path") || die "$method $path: request failed"
  printf '%s' "$resp" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("success"):
    sys.exit("breakglass: Cloudflare refused: " + json.dumps(d.get("errors")))
print(json.dumps(d.get("result")))' || exit 1
}
pyj() { python3 -I -c "$1"; } # reads JSON on stdin

find_app() { # find_app <name-or-domain>: prints the app JSON, dies unless exactly one matches
  api GET access/apps </dev/null | python3 -I -c '
import json, sys
want = sys.argv[1]
hits = [a for a in json.load(sys.stdin) if want in (a.get("name"), a.get("domain"))]
if len(hits) != 1:
    sys.exit("breakglass: %d Access apps match %r (need exactly 1)" % (len(hits), want))
print(json.dumps(hits[0]))' "$app_arg"
}

safe=$(printf '%s' "$app_arg" | tr -c 'A-Za-z0-9._-' '_')
state=$STATE_DIR/$safe.json

if [ "$mode" = switch ]; then
  [ ! -e "$state" ] || die "$app_arg is already in break-glass (state: $state); revert it first"
  app=$(find_app)
  app_id=$(printf '%s' "$app" | pyj 'import json,sys; print(json.load(sys.stdin)["id"])')
  pin_id=$(api GET access/identity_providers </dev/null | pyj '
import json, sys
p = [i for i in json.load(sys.stdin) if i.get("type") == "onetimepin"]
if not p: sys.exit("breakglass: no one-time PIN login method on this account")
print(p[0]["id"])') || exit 1

  # Save the original before touching anything; the state file is also the alarm.
  mkdir -p "$STATE_DIR"
  printf '%s' "$app" | pyj '
import json, sys, time
a = json.load(sys.stdin)
print(json.dumps({"saved_at": int(time.time()), "app": a}))' >"$state.tmp"

  policy=$(printf '%s' "{\"name\":\"$POLICY_NAME\",\"decision\":\"allow\",\"include\":[{\"email\":{\"email\":\"$BREAKGLASS_EMAIL\"}}],\"session_duration\":\"1h\"}" \
    | api POST "access/policies") || { rm -f "$state.tmp"; exit 1; }
  policy_id=$(printf '%s' "$policy" | pyj 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 -I - "$state.tmp" "$policy_id" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["policy_id"] = sys.argv[2]
json.dump(d, open(p, "w"))
PY
  mv "$state.tmp" "$state"

  printf '%s' "$app" | python3 -I -c '
import json, sys
a = json.load(sys.stdin)
a["allowed_idps"] = [sys.argv[1]]
a["auto_redirect_to_identity"] = False
a["policies"] = [{"id": sys.argv[2], "precedence": 1}]
print(json.dumps(a))' "$pin_id" "$policy_id" | api PUT "access/apps/$app_id" >/dev/null \
    || die "switch failed after saving state; run '$0 --revert $app_arg' to clean up"
  echo "break-glass ACTIVE for $app_arg: one-time PIN for $BREAKGLASS_EMAIL only. check-identity will page until: $0 --revert $app_arg"
  exit 0
fi

# revert
[ -e "$state" ] || die "$app_arg is not in break-glass (no $state)"
app_id=$(pyj 'import json,sys; print(json.load(sys.stdin)["app"]["id"])' <"$state")
policy_id=$(pyj 'import json,sys; print(json.load(sys.stdin)["policy_id"])' <"$state")
pyj '
import json, sys
a = json.load(sys.stdin)["app"]
# Cloudflare returns policies as objects; send back only what identifies them.
a["policies"] = [{"id": p["id"], "precedence": p.get("precedence")} if isinstance(p, dict) else p
                 for p in a.get("policies", [])]
print(json.dumps(a))' <"$state" | api PUT "access/apps/$app_id" >/dev/null || die "restoring $app_arg failed; state kept at $state"
api DELETE "access/policies/$policy_id" </dev/null >/dev/null || die "restored $app_arg but could not delete policy $policy_id; state kept, rerun --revert"
rm -f "$state"
echo "break-glass cleared for $app_arg; original policy restored"
