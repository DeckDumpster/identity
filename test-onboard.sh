#!/usr/bin/env bash
# Drives deploy/onboard.sh against a stateful fake Pocket ID admin API: a new email makes one user and
# one membership, a second run changes nothing, a second group keeps the first, --link prints a link
# that redeems, --list shows passkey status. Runs through testenv; temp dir only.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

t=$(mktemp -d); pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
port=$((20000 + RANDOM % 20000))
base=http://127.0.0.1:$port
mkdir -p "$t/cfg"; echo secretkey >"$t/cfg/pocket-id-api-key"

cat >"$t/server.py" <<PY
import http.server, json, re, urllib.parse
users, groups, tokens, writes = {}, {}, {}, []
users["u0"] = {"id": "u0", "username": "ryan", "email": "ryan@gantt.pub", "credentials": [{"id": "c"}]}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, obj, code=200):
        self.send_response(code); self.end_headers(); self.wfile.write(json.dumps(obj).encode())
    def body(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
    def authed(self):
        if self.headers.get("X-API-KEY") != "secretkey": self.send({"error": "no"}, 401); return False
        return True
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        if u.path == "/writes": return self.send(writes)
        if u.path.startswith("/lc/"): return self.send({"ok": u.path[4:] in tokens})
        if not self.authed(): return
        s = q.get("search", [""])[0].lower()
        if u.path == "/api/users":
            return self.send({"data": [x for x in users.values() if s in x["email"].lower()]})
        if u.path == "/api/user-groups":
            return self.send({"data": [x for x in groups.values() if s in x["name"].lower()]})
        m = re.fullmatch(r"/api/user-groups/(\w+)", u.path)
        if m:
            g = groups[m.group(1)]
            return self.send({**g, "users": [users[i] for i in g["members"]]})
        self.send({}, 404)
    def do_POST(self):
        if not self.authed(): return
        b = self.body(); writes.append(self.path)
        if self.path == "/api/users":
            i = "u%d" % (len(users) + 1); users[i] = {**b, "id": i, "credentials": []}; return self.send(users[i])
        if self.path == "/api/user-groups":
            i = "g%d" % (len(groups) + 1); groups[i] = {**b, "id": i, "members": []}; return self.send(groups[i])
        m = re.fullmatch(r"/api/users/(\w+)/one-time-access-token", self.path)
        if m and m.group(1) in users and isinstance(b.get("ttl"), int):
            tok = "tok%d" % len(tokens); tokens[tok] = m.group(1); return self.send({"token": tok})
        self.send({}, 400)
    def do_PUT(self):
        if not self.authed(): return
        b = self.body(); writes.append(self.path)
        m = re.fullmatch(r"/api/user-groups/(\w+)/users", self.path)
        if m: groups[m.group(1)]["members"] = b["userIds"]; return self.send({})
        self.send({}, 404)
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
PY
python3 "$t/server.py" & pid=$!
for _ in $(seq 50); do curl -s -o /dev/null "$base/writes" && break; sleep 0.1; done

ob() { IDENTITY_CONFIG_DIR=$t/cfg POCKET_ID_URL=$base ID_BASE=https://id.example "$root/deploy/onboard.sh" "$@"; }
writes() { curl -s "$base/writes" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
members() { ob --list "$1" 2>&1; }

ob kim@example.com --name Kim --group poke-users >"$t/r1" 2>&1; rc=$?
check "new email onboards" test $rc = 0
check "...creates the user and the group" grep -q 'created user kim@example.com' "$t/r1"
check "...and one membership (user + group + membership = 3 writes)" test "$(writes)" = 3
check "...list shows the member" bash -c 'grep -q "^kim@example.com" <<<"$1" && grep -q "1 member" <<<"$1"' _ "$(members poke-users)"

w=$(writes)
ob kim@example.com --name Kim --group poke-users >"$t/r2" 2>&1
check "second run exits 0" test $? = 0
check "second run changes nothing" test "$(writes)" = "$w"
check "second run says so" grep -q 'already in poke-users' "$t/r2"

ob ana@example.com --group poke-users >/dev/null 2>&1
ob kim@example.com --group magic-users >/dev/null 2>&1
check "second group keeps the first" bash -c 'grep -q "^kim@example.com" <<<"$1"' _ "$(members poke-users)"
check "...and holds the user" bash -c 'grep -q "^kim@example.com" <<<"$1"' _ "$(members magic-users)"
check "adding to a group keeps its existing members" bash -c 'grep -q "^ana@example.com" <<<"$1" && grep -q "2 member" <<<"$1"' _ "$(members poke-users)"

ob kim@example.com --group magic-users --link --ttl 600 >"$t/r3" 2>&1
link=$(sed -n 's/^login link: //p' "$t/r3")
check "--link prints a link and its expiry" bash -c '[[ "$1" == https://id.example/lc/* ]] && grep -q "^expires: 20" "$2"' _ "$link" "$t/r3"
check "...that the server redeems" bash -c '[ "$(curl -s "$1/lc/${2##*/}")" = "{\"ok\": true}" ]' _ "$base" "$link"
check "...and does not mint one without --link" bash -c '! grep -q "login link" "$1"' _ "$t/r2"

check "--list shows passkey status" bash -c 'out=$(IDENTITY_CONFIG_DIR=$1 POCKET_ID_URL=$2 "$3" --list "$4" 2>&1); grep -q "no passkey" <<<"$out"' _ "$t/cfg" "$base" "$root/deploy/onboard.sh" poke-users
curl -s -X PUT -H 'X-API-KEY: secretkey' --data '{"userIds":["u0","u2"]}' "$base/api/user-groups/g1/users" >/dev/null
check "...and 'passkey' for a user who has one" bash -c 'grep -q "^ryan@gantt.pub.passkey" <<<"$1"' _ "$(members poke-users)"

check "refuses a missing key (exit 3)" bash -c 'IDENTITY_CONFIG_DIR=$1/none "$2" a@b.co --group g >/dev/null 2>&1; [ $? = 3 ]' _ "$t" "$root/deploy/onboard.sh"
check "refuses no group (exit 2)" bash -c 'IDENTITY_CONFIG_DIR=$1 "$2" a@b.co >/dev/null 2>&1; [ $? = 2 ]' _ "$t/cfg" "$root/deploy/onboard.sh"
check "refuses a bad email (exit 2)" bash -c 'IDENTITY_CONFIG_DIR=$1 "$2" nope --group g >/dev/null 2>&1; [ $? = 2 ]' _ "$t/cfg" "$root/deploy/onboard.sh"
echo wrong >"$t/cfg/pocket-id-api-key"
check "refuses when the API does (exit 1, no traceback)" bash -c 'IDENTITY_CONFIG_DIR=$1 POCKET_ID_URL=$2 "$3" a@b.co --group g >"$1/o" 2>&1; [ $? = 1 ] && ! grep -q Traceback "$1/o"' _ "$t/cfg" "$base" "$root/deploy/onboard.sh"
exit $fail
