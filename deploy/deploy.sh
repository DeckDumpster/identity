#!/usr/bin/env bash
# Deploy Pocket ID and its cloudflared tunnel as rootless Quadlet units. Idempotent.
# Refuses to run anywhere but the host named in deploy/prod-host, as user ryangantt.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
want=$(tr -d '[:space:]' <"$here/prod-host")
have=$(hostname -s)
if [ "$have" != "$want" ]; then
  echo "deploy.sh: refusing to run on '$have'; this deploys only to '$want'" >&2
  exit 2
fi
if [ "$(id -un)" != ryangantt ]; then
  echo "deploy.sh: run as user ryangantt, not $(id -un)" >&2
  exit 2
fi

config_dir=$HOME/.config/identity
unit_dir=$HOME/.config/containers/systemd
mkdir -p "$config_dir" "$unit_dir"
chmod 700 "$config_dir"

# Pocket ID's encryption key: generated once, never replaced (replacing it orphans the data).
if [ ! -s "$config_dir/pocket-id.env" ]; then
  (umask 077; printf 'ENCRYPTION_KEY=%s\n' "$(openssl rand -base64 32)" >"$config_dir/pocket-id.env")
  echo "created $config_dir/pocket-id.env"
fi
# Tunnel token: placed by hand (TUNNEL_TOKEN=...), never generated or committed.
if [ ! -s "$config_dir/cloudflared-id.env" ]; then
  echo "deploy.sh: $config_dir/cloudflared-id.env is missing; create it (mode 0600) containing TUNNEL_TOKEN=<token>" >&2
  exit 3
fi
chmod 600 "$config_dir/pocket-id.env" "$config_dir/cloudflared-id.env"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$here/render.sh" "$tmp" "$config_dir"
changed=0
for f in "$tmp"/*; do
  dest=$unit_dir/$(basename "$f")
  if ! cmp -s "$f" "$dest"; then
    install -m 644 "$f" "$dest"
    changed=1
  fi
done
if [ "$changed" = 1 ]; then
  systemctl --user daemon-reload
fi
systemctl --user start pocket-id.service cloudflared-id.service
if [ "$changed" = 1 ]; then
  systemctl --user restart pocket-id.service cloudflared-id.service
fi

cat <<MSG

Deployed. First admin login (for Ryan; mints a one-time code, run once):
  podman exec pocket-id /app/pocket-id one-time-access-token <admin-username-or-email>
Open the printed link and enrol a passkey.
MSG
