#!/usr/bin/env bash
# Post-deploy smoke: Pocket ID answers on loopback and serves its OIDC discovery document.
# Retries for up to a minute (the container restarts on a changed unit). Exit 0 healthy, 1 not.
# SMOKE_BASE overrides http://127.0.0.1:1411, SMOKE_TRIES the attempt count.
set -uo pipefail
base=${SMOKE_BASE:-http://127.0.0.1:1411}
tries=${SMOKE_TRIES:-30}
for _ in $(seq 1 "$tries"); do
  if curl -fsS -o /dev/null "$base/healthz" 2>/dev/null &&
     curl -fsS "$base/.well-known/openid-configuration" 2>/dev/null | grep -q '"issuer"'; then
    echo "smoke: ok ($base)"
    exit 0
  fi
  sleep 2
done
echo "smoke: $base did not serve healthz and OIDC discovery" >&2
exit 1
