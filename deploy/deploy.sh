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
sys_dir=$HOME/.config/systemd/user
lib_dir=$HOME/.local/lib/identity
mkdir -p "$config_dir" "$unit_dir" "$sys_dir" "$lib_dir"
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
  case "$f" in
    *.service|*.timer) dest=$sys_dir/$(basename "$f") ;;
    *) dest=$unit_dir/$(basename "$f") ;;
  esac
  if ! cmp -s "$f" "$dest"; then
    install -m 644 "$f" "$dest"
    changed=1
  fi
done
if [ "$changed" = 1 ]; then
  systemctl --user daemon-reload
fi
install -m 755 "$here/check-identity.sh" "$lib_dir/check-identity.sh"
install -m 755 "$here/breakglass.sh" "$lib_dir/breakglass.sh"
systemctl --user enable --now identity-check.timer
systemctl --user start pocket-id.service cloudflared-id.service
# Backups: the write-only credential (from Secrets Manager identity/backup) is placed by hand in
# backup.env as AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION and
# IDENTITY_BACKUP_BUCKET. The timer is enabled only once it exists.
if [ -s "$config_dir/backup.env" ]; then
  chmod 600 "$config_dir/backup.env"
  systemctl --user enable --now identity-backup.timer
else
  echo "deploy.sh: $config_dir/backup.env is missing; backups are NOT running (see README)" >&2
fi
if [ "$changed" = 1 ]; then
  systemctl --user restart pocket-id.service cloudflared-id.service
fi

# Pocket ID's name, accent colour and logo come from deploy/branding/. Needs an admin API key
# (pocket-id-api-key); without one it says so and the rest of the deploy stands.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS -o /dev/null http://127.0.0.1:1411/healthz 2>/dev/null && break
  sleep 3
done
"$here/apply-branding.sh" "$config_dir" || echo "deploy.sh: Pocket ID branding was not applied" >&2
# The CIMD allowlist and the per-site /mcp APIs come from deploy/mcp/mcp.json.
"$here/apply-mcp.sh" "$config_dir" || echo "deploy.sh: Pocket ID MCP authorization settings were not applied" >&2

cat <<MSG

Deployed. First admin login (for Ryan; mints a one-time code, run once):
  podman exec pocket-id /app/pocket-id one-time-access-token <admin-username-or-email>
Open the printed link and enrol a passkey.
MSG
