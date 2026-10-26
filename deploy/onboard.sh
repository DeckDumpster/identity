#!/usr/bin/env bash
# Onboard a person to an app's Pocket ID group through the admin API.
# Usage: onboard.sh <email> [--name <first>] --group <group>... [--link [--ttl <seconds>]]
#        onboard.sh --list <group>
# Creates the user if absent (username is the email's local part), creates each group if absent and
# adds the user to it keeping its existing members; running it again changes nothing. --link mints a
# one-time login link and prints it with its expiry, for the operator to send. --list prints each
# member of a group and whether they have a passkey. Run on the identity host; needs an admin API key
# in $IDENTITY_CONFIG_DIR/pocket-id-api-key (0600, one line) like apply-mcp.sh. Exit 3 when the key is
# missing, 2 on usage errors, 1 when the API refuses a call.
# Environment: POCKET_ID_URL (API, default http://127.0.0.1:1411), ID_BASE (public URL the link points
# at, default https://id.gantt.pub), POCKET_ID_DB (Pocket ID sqlite file, the passkey fallback below).
set -euo pipefail
config_dir=${IDENTITY_CONFIG_DIR:-$HOME/.config/identity}
keyfile=$config_dir/pocket-id-api-key
usage() { echo "usage: onboard.sh <email> [--name <first>] --group <group>... [--link [--ttl <seconds>]] | onboard.sh --list <group>" >&2; exit 2; }
[ $# -gt 0 ] || usage
if [ ! -s "$keyfile" ]; then
  echo "onboard.sh: $keyfile is missing; cannot reach the Pocket ID admin API (see README)" >&2
  exit 3
fi
POCKET_ID_KEY=$(tr -d '[:space:]' <"$keyfile")
export POCKET_ID_KEY
export POCKET_ID_URL=${POCKET_ID_URL:-http://127.0.0.1:1411}
export ID_BASE=${ID_BASE:-https://id.gantt.pub}
exec python3 -I - "$@" <<'PY'
import json, os, re, sqlite3, subprocess, sys, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone

BASE = os.environ["POCKET_ID_URL"].rstrip("/")
KEY = os.environ["POCKET_ID_KEY"]

def die(msg, code=1):
    print("onboard.sh: " + msg, file=sys.stderr); sys.exit(code)

def api(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers={"X-API-KEY": KEY, "Content-Type": "application/json"},
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        die("%s %s failed: HTTP %d %s" % (method, path, e.code, e.read().decode(errors="replace")[:200]))
    except OSError as e:
        die("%s %s failed: %s" % (method, path, e))
    return json.loads(raw) if raw.strip() else None

def items(d):
    return d.get("data", []) if isinstance(d, dict) else (d or [])

def page(path):
    sep = "&" if "?" in path else "?"
    return items(api("GET", path + sep + "pagination[limit]=1000"))

def find_user(email):
    for u in page("/api/users?search=" + urllib.parse.quote(email)):
        if (u.get("email") or "").lower() == email.lower():
            return u

def find_group(name):
    for g in page("/api/user-groups?search=" + urllib.parse.quote(name)):
        if g["name"] == name:
            return g

def group_members(g):
    return api("GET", "/api/user-groups/" + g["id"]).get("users") or []

def passkeys(user):
    if "credentials" in user:
        return len(user["credentials"] or [])
    db = os.environ.get("POCKET_ID_DB")
    if not db:
        try:
            vol = subprocess.run(["podman", "volume", "inspect", "pocket-id-data", "--format", "{{.Mountpoint}}"],
                                 capture_output=True, text=True, timeout=20).stdout.strip()
            db = vol + "/pocket-id.db" if vol else None
        except (OSError, subprocess.SubprocessError):
            db = None
    if db and os.path.isfile(db):
        c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
        try:
            return c.execute("SELECT count(*) FROM webauthn_credentials WHERE user_id=?", (user["id"],)).fetchone()[0]
        finally:
            c.close()
    return None

argv = sys.argv[1:]
if argv[0] == "--list":
    if len(argv) != 2: die("usage: onboard.sh --list <group>", 2)
    g = find_group(argv[1])
    if not g: die("no group named " + argv[1])
    members = group_members(g)
    for u in sorted(members, key=lambda u: u["email"]):
        n = passkeys(u)
        print("%s\t%s" % (u["email"], "unknown" if n is None else ("passkey" if n else "no passkey")))
    print("%d member(s) in %s" % (len(members), argv[1]))
    sys.exit(0)

email = None; name = None; groups = []; link = False; ttl = 3600
i = 0
while i < len(argv):
    a = argv[i]
    if a in ("--name", "--group", "--ttl"):
        if i + 1 >= len(argv): die("%s needs a value" % a, 2)
        v = argv[i + 1]; i += 2
        if a == "--name": name = v
        elif a == "--group": groups.append(v)
        else:
            if not v.isdigit() or int(v) < 1: die("--ttl is a number of seconds", 2)
            ttl = int(v)
    elif a == "--link": link = True; i += 1
    elif a.startswith("-"): die("unknown argument " + a, 2)
    elif email is None: email = a; i += 1
    else: die("unexpected argument " + a, 2)
if not email or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email): die("need a valid <email>", 2)
if not groups: die("need at least one --group", 2)
for g in groups:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", g): die("group names are letters, digits, - and _: " + g, 2)

user = find_user(email)
if user:
    print("user %s exists" % email)
else:
    local = email.split("@")[0]
    username = re.sub(r"[^a-z0-9_.@-]", "", local.lower())
    if not username: die("cannot derive a username from " + email, 2)
    first = name or local.split(".")[0].capitalize()
    user = api("POST", "/api/users", {"username": username, "email": email, "firstName": first, "lastName": "",
                                      "displayName": first, "isAdmin": False, "disabled": False})
    print("created user %s (username %s)" % (email, username))

for gname in groups:
    g = find_group(gname)
    if not g:
        g = api("POST", "/api/user-groups", {"name": gname, "friendlyName": gname})
        print("created group " + gname)
    ids = [u["id"] for u in group_members(g)]
    if user["id"] in ids:
        print("%s already in %s" % (email, gname))
    else:
        api("PUT", "/api/user-groups/%s/users" % g["id"], {"userIds": ids + [user["id"]]})
        print("added %s to %s" % (email, gname))

if link:
    t = api("POST", "/api/users/%s/one-time-access-token" % user["id"], {"ttl": ttl})
    token = (t or {}).get("token")
    if not token: die("no token returned for the login link")
    exp = (datetime.now(timezone.utc) + timedelta(seconds=ttl)).strftime("%Y-%m-%dT%H:%M:%SZ")
    print("login link: %s/lc/%s" % (os.environ["ID_BASE"].rstrip("/"), token))
    print("expires: " + exp)
PY
