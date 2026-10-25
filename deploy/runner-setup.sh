#!/usr/bin/env bash
# Registers the `identity-prod` GitHub Actions runner on ubuntu-mini-0 as a rootless user service
# (user ryangantt), the same way as dumpstar's `dumpstar-prod` runner. Idempotent.
# Usage: runner-setup.sh <registration-token>
#   Token (valid one hour, needs repo admin, so Ryan mints it):
#   gh api -X POST repos/DeckDumpster/identity/actions/runners/registration-token --jq .token
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
want=$(tr -d '[:space:]' <"$here/prod-host")
[ "$(hostname -s)" = "$want" ] || { echo "runner-setup.sh: run on $want" >&2; exit 2; }
[ "$(id -un)" = ryangantt ] || { echo "runner-setup.sh: run as ryangantt" >&2; exit 2; }
token=${1:?usage: runner-setup.sh <registration-token>}
repo_url=https://github.com/DeckDumpster/identity
dir=$HOME/actions-runner-identity
unit=$HOME/.config/systemd/user/identity-runner.service

# The production checkout the workflow fast-forwards: cloned once, moved by the workflow after.
if [ ! -d "$HOME/identity/.git" ]; then
  git clone "$repo_url.git" "$HOME/identity"
fi

if [ ! -x "$dir/run.sh" ]; then
  mkdir -p "$dir"
  ver=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
  curl -fsSL "https://github.com/actions/runner/releases/download/v$ver/actions-runner-linux-x64-$ver.tar.gz" | tar -xz -C "$dir"
fi
if [ ! -f "$dir/.runner" ]; then
  (cd "$dir" && ./config.sh --unattended --url "$repo_url" --token "$token" \
    --name identity-prod --labels identity-prod --work _work --replace)
fi

mkdir -p "$(dirname "$unit")"
cat >"$unit" <<UNIT
[Unit]
Description=GitHub Actions runner (identity-prod)
After=network-online.target

[Service]
WorkingDirectory=$dir
ExecStart=$dir/run.sh
Restart=always
RestartSec=10
CPUQuota=100%

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now identity-runner.service
loginctl show-user "$USER" -p Linger | grep -q yes || echo "runner-setup.sh: run 'loginctl enable-linger $USER' so the runner survives logout" >&2
echo "runner identity-prod registered; check: systemctl --user status identity-runner"
