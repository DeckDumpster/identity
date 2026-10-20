#!/usr/bin/env bash
# Synthetic check for id.gantt.pub: the site, its OIDC discovery document and the age of the
# newest backup, and that discovery advertises Client ID Metadata Document support (MCP sign-in). Raises one Pushover alarm when the set of problems changes and one "recovered"
# when it clears. Run every minute by identity-check.timer on ubuntu-mini-0.
#
# The alert path is the one the other product services on this host use: Pushover, credentials
# from ~/.config/pkdump/alerts.env. Unconfigured or failing to push is a FAILURE (exit 1), never a
# silent no-op, and nothing is recorded unless the push succeeded, so a dropped page is retried.
#
# Backup freshness reads BACKUP_STAMP, a file whose mtime the backup job touches after every
# successful replication/upload. A missing stamp is a problem, not a pass.
#
# It also alarms while any app is in break-glass (state files from deploy/breakglass.sh).
#
# Exit: 0 healthy, 1 unhealthy or could not alert.
set -uo pipefail

ID_BASE=${ID_BASE:-https://id.gantt.pub}
BACKUP_STAMP=${BACKUP_STAMP:-$HOME/.local/state/identity/last-backup}
MAX_BACKUP_AGE=${MAX_BACKUP_AGE:-129600} # 36 h
STATE_DIR=${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/identity/check}
ALERTS_ENV=${ALERTS_ENV:-$HOME/.config/pkdump/alerts.env}
RETRY_DELAY=${RETRY_DELAY:-5}
BREAKGLASS_DIR=${BREAKGLASS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/identity/breakglass}
PUSHOVER_API_URL=${PUSHOVER_API_URL:-https://api.pushover.net/1/messages.json}

if [ -r "$ALERTS_ENV" ]; then
  # shellcheck disable=SC1090
  . "$ALERTS_ENV"
fi

probe() { # probe <url> <body-file>: prints the HTTP status, 000 on transport failure
  curl -sS -o "$2" -w '%{http_code}' --max-time 10 "$1" 2>/dev/null || true
}

site_problem() {
  local body=$1 code
  code=$(probe "$ID_BASE/" "$body")
  case "$code" in 2??|3??) return 0 ;; esac
  echo "$ID_BASE answered HTTP $code"
}

discovery_problem() {
  local body=$1 url="$ID_BASE/.well-known/openid-configuration" code
  code=$(probe "$url" "$body")
  if [ "$code" != 200 ]; then
    echo "OIDC discovery answered HTTP $code"
  elif ! grep -Eq "\"issuer\" *: *\"$ID_BASE\"" "$body" || ! grep -Eq '"jwks_uri"' "$body"; then
    echo "OIDC discovery is not a valid document for $ID_BASE"
  elif ! grep -Eq '"client_id_metadata_document_supported" *: *true' "$body"; then
    echo "OIDC discovery does not advertise client_id_metadata_document_supported (MCP clients cannot sign in; deploy/apply-mcp.sh)"
  fi
}

backup_problem() {
  local now mtime age
  if [ ! -e "$BACKUP_STAMP" ]; then
    echo "no backup has ever completed ($BACKUP_STAMP is missing)"
    return
  fi
  now=$(date +%s)
  mtime=$(stat -c %Y "$BACKUP_STAMP")
  age=$((now - mtime))
  if [ "$age" -gt "$MAX_BACKUP_AGE" ]; then
    echo "newest backup is $((age / 3600)) h old (limit $((MAX_BACKUP_AGE / 3600)) h)"
  fi
}

# deploy/breakglass.sh leaves one <app>.json here per Access app switched to one-time PIN.
breakglass_problem() {
  local f
  for f in "$BREAKGLASS_DIR"/*.json; do
    [ -e "$f" ] || continue
    echo "BREAK-GLASS ACTIVE for $(basename "${f%.json}"): one-time PIN is on; run breakglass.sh --revert"
  done
}

collect() {
  local tmp
  tmp=$(mktemp)
  { site_problem "$tmp"; discovery_problem "$tmp"; backup_problem; breakglass_problem; } 2>&1
  rm -f "$tmp"
}

problems=$(collect)
if [ -n "$problems" ]; then
  # Retry once so a single dropped request is not a page.
  sleep "$RETRY_DELAY"
  problems=$(collect)
fi

push() { # push <title> <message>
  if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ] \
     || [ "$PUSHOVER_TOKEN" = CHANGE_ME ] || [ "$PUSHOVER_USER" = CHANGE_ME ]; then
    echo "check-identity: PUSHOVER_TOKEN/USER unset; this alert reached nobody: $1" >&2
    return 1
  fi
  curl -sS -f --max-time 15 -o /dev/null \
    --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USER" \
    --form-string "title=$1" --form-string "message=$2" "$PUSHOVER_API_URL"
}

mkdir -p "$STATE_DIR"
state=$STATE_DIR/alarm

if [ -n "$problems" ]; then
  echo "$problems" >&2
  if [ "$(cat "$state" 2>/dev/null)" != "$problems" ]; then
    push "ALARM: identity (id.gantt.pub)" "$problems" || exit 1
    printf '%s\n' "$problems" >"$state.tmp" && mv "$state.tmp" "$state"
  fi
  exit 1
fi

if [ -e "$state" ]; then
  push "RECOVERED: identity (id.gantt.pub)" "All checks pass again." || exit 1
  rm -f "$state"
fi
echo "identity healthy"
