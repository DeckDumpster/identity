#!/usr/bin/env bash
# Renders the units and checks the pin, the loopback bind, the tunnel and host refusal.
# Runs through testenv; touches only a temp dir.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
"$root/deploy/render.sh" "$out/units" /cfg || { echo "render failed"; exit 1; }
pc=$out/units/pocket-id.container cf=$out/units/cloudflared-id.container

check "pocket-id image pinned to tag and sha256 digest" \
  grep -Eq '^Image=ghcr\.io/pocket-id/pocket-id:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$pc"
check "cloudflared image pinned to tag and sha256 digest" \
  grep -Eq '^Image=.*:[0-9][^@]*@sha256:[0-9a-f]{64}$' "$cf"
check "no floating :latest tag" bash -c '! grep -q ":latest" "$@"' _ "$pc" "$cf"
check "published on loopback only" grep -Eq '^PublishPort=127\.0\.0\.1:1411:1411$' "$pc"
check "no other published port" bash -c '[ "$(grep -c "^PublishPort=" "$1")" = 1 ]' _ "$pc"
check "APP_URL is https://id.gantt.pub" grep -Fxq 'Environment=APP_URL=https://id.gantt.pub' "$pc"
check "own data volume" grep -Eq '^Volume=pocket-id-data\.volume:/app/data$' "$pc"
check "tunnel shares the host network to reach loopback" grep -Fxq 'Network=host' "$cf"
check "secrets come from env files, not units" \
  bash -c 'grep -q "^EnvironmentFile=/cfg/pocket-id.env$" "$1" && grep -q "^EnvironmentFile=/cfg/cloudflared-id.env$" "$2" && ! grep -Eq "ENCRYPTION_KEY=|TUNNEL_TOKEN=" "$1" "$2"' _ "$pc" "$cf"
check "no unrendered placeholders" bash -c '! grep -q "@[A-Z_]*@" "$@"' _ "$out"/units/*
check "no Access app for id.gantt.pub in repo" \
  bash -c '! grep -rIl "cloudflare_zero_trust_access_application" --exclude=test-deploy.sh "$1" | grep -q .' _ "$root"

# Host refusal: skipped when run on the prod host itself.
have=$(hostname -s); want=$(tr -d '[:space:]' <"$root/deploy/prod-host")
check "prod-host names ubuntu-mini-0" [ "$want" = ubuntu-mini-0 ]
if [ "$have" = "$want" ]; then
  echo "skip host refusal: running on the prod host"
else
  msg=$(HOME=$out/home "$root/deploy/deploy.sh" 2>&1); rc=$?
  check "refuses on $have (exit 2)" [ "$rc" = 2 ]
  check "refusal names the prod host" bash -c 'grep -q ubuntu-mini-0 <<<"$1"' _ "$msg"
  check "refusal wrote nothing" [ ! -e "$out/home" ]
fi
exit $fail
