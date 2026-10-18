#!/usr/bin/env bash
# Restore a backup into a scratch directory and assert its users and groups match a reference.
# Usage: restore-drill.sh --archive <file> --reference <data-dir-or-db>
#        restore-drill.sh --newest --reference <data-dir-or-db>   (operator identity: lists the bucket)
# --newest fetches the newest object of $IDENTITY_BACKUP_BUCKET; --reference defaults to the live
# volume. With --boot, also starts a scratch Pocket ID on the restored data and waits for health.
# Exit 0 when users and groups match, 1 on a mismatch, 2 on usage or environment errors.
set -euo pipefail

archive= newest=0 reference= boot=0
while [ $# -gt 0 ]; do
  case $1 in
    --archive) archive=${2:?}; shift 2 ;;
    --newest) newest=1; shift ;;
    --reference) reference=${2:?}; shift 2 ;;
    --boot) boot=1; shift ;;
    *) echo "restore-drill.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
command -v sqlite3 >/dev/null || { echo "restore-drill.sh: sqlite3 is required" >&2; exit 2; }
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT

if [ "$newest" = 1 ]; then
  : "${IDENTITY_BACKUP_BUCKET:?IDENTITY_BACKUP_BUCKET is required}"
  key=$(aws s3api list-objects-v2 --bucket "$IDENTITY_BACKUP_BUCKET" --prefix identity- \
    --query 'sort_by(Contents,&LastModified)[-1].Key' --output text --no-cli-pager)
  [ -n "$key" ] && [ "$key" != None ] || { echo "restore-drill.sh: no backups in $IDENTITY_BACKUP_BUCKET" >&2; exit 2; }
  archive=$scratch/$key
  aws s3api get-object --bucket "$IDENTITY_BACKUP_BUCKET" --key "$key" "$archive" --no-cli-pager >/dev/null
  echo "newest backup: $key"
fi
[ -f "$archive" ] || { echo "restore-drill.sh: need --archive <file> or --newest" >&2; exit 2; }
if [ -z "$reference" ]; then
  reference=$(podman volume inspect pocket-id-data --format '{{.Mountpoint}}')
fi
[ -d "$reference" ] && reference=$reference/pocket-id.db
[ -f "$reference" ] || { echo "restore-drill.sh: reference database not found: $reference" >&2; exit 2; }

restored=$scratch/restored
mkdir -p "$restored"
tar -C "$restored" -xzf "$archive"
[ -f "$restored/pocket-id.db" ] || { echo "restore-drill.sh: archive has no pocket-id.db" >&2; exit 1; }

# Users, groups and memberships, by stable names rather than generated ids.
dump() {
  sqlite3 "$1" <<'SQL'
SELECT 'user|' || username || '|' || email FROM users ORDER BY 1;
SELECT 'group|' || name FROM user_groups ORDER BY 1;
SELECT 'member|' || g.name || '|' || u.username
  FROM user_groups_users m
  JOIN user_groups g ON g.id = m.user_group_id
  JOIN users u ON u.id = m.user_id ORDER BY 1;
SQL
}
dump "$restored/pocket-id.db" >"$scratch/restored.txt"
dump "$reference" >"$scratch/reference.txt"
if ! diff -u "$scratch/reference.txt" "$scratch/restored.txt"; then
  echo "restore-drill: FAIL: restored users/groups differ from the reference (--- reference, +++ restored)" >&2
  exit 1
fi
echo "restore-drill: OK: $(grep -c '^user|' "$scratch/restored.txt") users, $(grep -c '^group|' "$scratch/restored.txt") groups, $(grep -c '^member|' "$scratch/restored.txt") memberships match"

if [ "$boot" = 1 ]; then
  # shellcheck source=image.env
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/image.env"
  name=pocket-id-drill-$$
  trap 'podman rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$scratch"' EXIT
  chmod -R a+rwX "$restored"
  podman run -d --name "$name" --rm -v "$restored:/app/data:Z" --env-file "${IDENTITY_CONFIG_DIR:-$HOME/.config/identity}/pocket-id.env" \
    -e APP_URL=http://localhost "$POCKET_ID_IMAGE" >/dev/null
  for _ in $(seq 30); do
    podman exec "$name" /app/pocket-id healthcheck >/dev/null 2>&1 && { echo "restore-drill: scratch instance healthy"; exit 0; }
    sleep 2
  done
  echo "restore-drill: FAIL: scratch instance never became healthy" >&2
  exit 1
fi
