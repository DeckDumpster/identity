#!/usr/bin/env bash
# The whole of identity's CI: every tier in .spira/testenv.toml's `default` list, in order,
# stopping at the first failure. Run by a queue.local round on a round VM (ci_entry).
# Dependencies: bash, curl and python3 must be on the VM image (the stock Debian/Ubuntu
# image has them); test-infra.sh downloads terraform itself and apt-installs unzip and
# ca-certificates if missing, so the VM needs network access and apt (or root-less unzip).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

for t in test-deploy test-infra test-check test-breakglass test-backup test-onboard; do
  echo "=== ci.sh: $t ==="
  bash "$t.sh"
done
echo "=== ci.sh: all tiers green ==="
