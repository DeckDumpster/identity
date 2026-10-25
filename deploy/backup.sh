#!/usr/bin/env bash
# Snapshot Pocket ID's data and upload it as one object with a write-only credential.
# Pocket ID keeps SQLite, but a write-only key cannot run Litestream (it must read and list its
# replica), so this takes a consistent local snapshot instead (law-off-box-backups-are-private-
# and-write-only): VACUUM INTO for the database, plus every other file under the data dir
# (signing keys, uploads), in one tar.gz named identity-<UTC>.tar.gz.
# Usage: backup.sh <datadir> <outdir>      write the archive locally and print its path
#        backup.sh --upload [datadir]      snapshot then upload to $IDENTITY_BACKUP_BUCKET
set -euo pipefail
shopt -s inherit_errexit  # a failure inside archive=$(snapshot ...) must stop the run, not be swallowed

db_name=pocket-id.db

snapshot() { # <datadir> <outdir>
  local data=$1 out=$2 stage name
  [ -f "$data/$db_name" ] || { echo "backup.sh: no $db_name in $data" >&2; return 1; }
  command -v sqlite3 >/dev/null || { echo "backup.sh: sqlite3 is required" >&2; return 1; }
  stage=$(mktemp -d)
  mkdir -p "$out"
  sqlite3 "$data/$db_name" "VACUUM INTO '$stage/$db_name'"
  name=identity-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
  # Any unreadable file or tar error fails the run: a partial archive is never produced.
  if ! { tar -C "$data" --exclude="./$db_name" --exclude="./$db_name-*" -cf - . | tar -C "$stage" --no-same-owner -xf -; } \
     || ! tar -C "$stage" -czf "$out/$name" .; then
    rm -rf "$stage" "$out/$name"
    echo "backup.sh: archiving $data failed; nothing written" >&2
    return 1
  fi
  rm -rf "$stage"
  echo "$out/$name"
}

if [ "${1:-}" = --upload ]; then
  : "${IDENTITY_BACKUP_BUCKET:?IDENTITY_BACKUP_BUCKET is required}"
  data=${2:-$(podman volume inspect pocket-id-data --format '{{.Mountpoint}}')}
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  # The rootless volume is owned by the container's user namespace (uploads/ is 100999, mode 700),
  # so the host user cannot read it: archive inside the same namespace via podman unshare.
  # IDENTITY_BACKUP_RUNAS overrides the wrapper (empty = run directly, used by the test).
  read -ra runas <<<"${IDENTITY_BACKUP_RUNAS-podman unshare}"
  archive=$("${runas[@]}" "$0" "$data" "$tmp")
  # PutObject only: no list, no read, no overwrite (the key is unique per second).
  aws s3api put-object --bucket "$IDENTITY_BACKUP_BUCKET" --key "$(basename "$archive")" \
    --body "$archive" --no-cli-pager >/dev/null
  stamp=${IDENTITY_STATE_DIR:-$HOME/.local/state/identity}/last-backup
  mkdir -p "$(dirname "$stamp")" && touch "$stamp"  # read by check-identity.sh for backup age
  echo "uploaded $(basename "$archive") to s3://$IDENTITY_BACKUP_BUCKET"
else
  snapshot "${1:?usage: backup.sh <datadir> <outdir> | --upload [datadir]}" "${2:?usage: backup.sh <datadir> <outdir>}"
fi
