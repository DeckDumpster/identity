#!/usr/bin/env bash
# Snapshot Pocket ID's data and upload it as one object with a write-only credential.
# Pocket ID keeps SQLite, but a write-only key cannot run Litestream (it must read and list its
# replica), so this takes a consistent local snapshot instead (law-off-box-backups-are-private-
# and-write-only): VACUUM INTO for the database, plus every other file under the data dir
# (signing keys, uploads), in one tar.gz named identity-<UTC>.tar.gz.
# Usage: backup.sh <datadir> <outdir>      write the archive locally and print its path
#        backup.sh --upload [datadir]      snapshot then upload to $IDENTITY_BACKUP_BUCKET
set -euo pipefail

db_name=pocket-id.db

snapshot() { # <datadir> <outdir>
  local data=$1 out=$2 stage name
  [ -f "$data/$db_name" ] || { echo "backup.sh: no $db_name in $data" >&2; return 1; }
  command -v sqlite3 >/dev/null || { echo "backup.sh: sqlite3 is required" >&2; return 1; }
  stage=$(mktemp -d)
  mkdir -p "$out"
  sqlite3 "$data/$db_name" "VACUUM INTO '$stage/$db_name'"
  tar -C "$data" --exclude="./$db_name" --exclude="./$db_name-*" -cf - . | tar -C "$stage" -xf -
  name=identity-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
  tar -C "$stage" -czf "$out/$name" .
  rm -rf "$stage"
  echo "$out/$name"
}

if [ "${1:-}" = --upload ]; then
  : "${IDENTITY_BACKUP_BUCKET:?IDENTITY_BACKUP_BUCKET is required}"
  data=${2:-$(podman volume inspect pocket-id-data --format '{{.Mountpoint}}')}
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  archive=$(snapshot "$data" "$tmp")
  # PutObject only: no list, no read, no overwrite (the key is unique per second).
  aws s3api put-object --bucket "$IDENTITY_BACKUP_BUCKET" --key "$(basename "$archive")" \
    --body "$archive" --no-cli-pager >/dev/null
  echo "uploaded $(basename "$archive") to s3://$IDENTITY_BACKUP_BUCKET"
else
  snapshot "${1:?usage: backup.sh <datadir> <outdir> | --upload [datadir]}" "${2:?usage: backup.sh <datadir> <outdir>}"
fi
