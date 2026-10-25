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
scratch=$(mktemp -d); name=
# The scratch container writes files as a subuid the host user cannot remove: delete them from
# inside the user namespace, on every exit path.
cleanup() {
  [ -z "$name" ] || podman rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$scratch" 2>/dev/null || podman unshare rm -rf "$scratch" 2>/dev/null || true
}
trap cleanup EXIT

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
  # The snapshot was taken under a live Pocket ID, so its francis_hosts table (the embedded actor
  # runtime, capped at one host) still lists that instance; a booting copy refuses to start while
  # the row is fresh (the health-check deadline is 90s). Clear it in the restored copy only.
  if [ -n "$(sqlite3 "$restored/pocket-id.db" "SELECT name FROM sqlite_master WHERE name='francis_hosts'")" ]; then
    sqlite3 "$restored/pocket-id.db" "PRAGMA foreign_keys=ON; DELETE FROM francis_hosts;"
  fi
  chmod -R a+rwX "$restored"
  # No --rm: a container that dies at start must stay inspectable so its logs can be printed.
  podman run -d --name "$name" -v "$restored:/app/data:Z" --env-file "${IDENTITY_CONFIG_DIR:-$HOME/.config/identity}/pocket-id.env" \
    -e APP_URL=http://localhost "$POCKET_ID_IMAGE" >/dev/null
  for _ in $(seq 30); do
    podman exec "$name" /app/pocket-id healthcheck >/dev/null 2>&1 && { echo "restore-drill: scratch instance healthy"; exit 0; }
    sleep 2
  done
  echo "restore-drill: FAIL: scratch instance never became healthy; container state and last log lines:" >&2
  podman inspect "$name" --format 'status={{.State.Status}} exit={{.State.ExitCode}}' >&2 || true
  podman logs --tail 40 "$name" >&2 || true
  exit 1
fi
