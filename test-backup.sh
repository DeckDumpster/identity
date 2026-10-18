#!/usr/bin/env bash
# Backs up a fixture Pocket ID data dir, restores it with the drill and checks the drill both
# accepts a faithful restore and refuses a divergent one. Runs through testenv; temp dir only.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

if ! command -v sqlite3 >/dev/null; then
  apt-get update -qq >/dev/null && apt-get install -y -qq sqlite3 >/dev/null || { echo "cannot install sqlite3"; exit 1; }
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
data=$tmp/data; mkdir -p "$data/keys" "$data/uploads"
echo '{"kty":"RSA"}' >"$data/keys/jwk.json"
echo logo >"$data/uploads/logo.png"
sqlite3 "$data/pocket-id.db" <<'SQL'
CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT, email TEXT);
CREATE TABLE user_groups (id TEXT PRIMARY KEY, name TEXT);
CREATE TABLE user_groups_users (user_id TEXT, user_group_id TEXT);
INSERT INTO users VALUES ('u1','ryan','ryan@gantt.pub'),('u2','kim','kim@example.com');
INSERT INTO user_groups VALUES ('g1','admins'),('g2','cubby-parents');
INSERT INTO user_groups_users VALUES ('u1','g1'),('u1','g2'),('u2','g2');
SQL

archive=$(PATH=$PATH "$root/deploy/backup.sh" "$data" "$tmp/out")
check "backup writes one identity-*.tar.gz" bash -c '[[ "$(basename "$1")" =~ ^identity-[0-9]{8}T[0-9]{6}Z\.tar\.gz$ ]] && [ -s "$1" ]' _ "$archive"
check "archive carries db, keys and uploads" bash -c 'l=$(tar -tzf "$1"); grep -q pocket-id.db <<<"$l" && grep -q keys/jwk.json <<<"$l" && grep -q uploads/logo.png <<<"$l"' _ "$archive"

check "drill accepts a faithful restore" "$root/deploy/restore-drill.sh" --archive "$archive" --reference "$data"

for change in "DELETE FROM users WHERE username='kim'" \
              "INSERT INTO user_groups VALUES ('g3','poke-users')" \
              "DELETE FROM user_groups_users WHERE user_id='u2'"; do
  cp -r "$data" "$tmp/live"
  sqlite3 "$tmp/live/pocket-id.db" "$change"
  check "drill refuses divergence: $change" bash -c '! "$@" >/dev/null 2>&1' _ "$root/deploy/restore-drill.sh" --archive "$archive" --reference "$tmp/live"
  rm -rf "$tmp/live"
done

check "drill refuses an archive without a database" bash -c '
  mkdir -p "$1/empty" && tar -C "$1/empty" -czf "$1/empty.tar.gz" . && ! "$2" --archive "$1/empty.tar.gz" --reference "$3" >/dev/null 2>&1' _ "$tmp" "$root/deploy/restore-drill.sh" "$data"

check "backup refuses a data dir with no database" bash -c '! "$1" "$2" "$3" >/dev/null 2>&1' _ "$root/deploy/backup.sh" "$tmp/nope" "$tmp/o2"
check "upload refuses without a bucket" bash -c '! env -u IDENTITY_BACKUP_BUCKET "$1" --upload "$2" >/dev/null 2>&1' _ "$root/deploy/backup.sh" "$data"
exit $fail
