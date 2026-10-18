#!/usr/bin/env bash
# Drives deploy/breakglass.sh against a mocked Cloudflare API: switch puts the app on one-time PIN
# for ryan@gantt.pub only, check-identity alarms while it is active, revert restores the original
# app body byte-for-byte and deletes the temporary policy. Touches only a temp dir.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
not() { ! "$@"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

t=$(mktemp -d); pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
port=$((20000 + RANDOM % 20000))
base=http://127.0.0.1:$port

cat >"$t/server.py" <<PY
import http.server, json, copy
t = "$t"
ORIG = {"id": "app1", "name": "Cubby", "domain": "cubby.gantt.pub", "type": "self_hosted",
        "allowed_idps": ["pocket-idp"], "auto_redirect_to_identity": True,
        "session_duration": "24h", "policies": [{"id": "pol-group", "precedence": 1}]}
apps = {"app1": copy.deepcopy(ORIG), "app2": {"id": "app2", "name": "Other", "domain": "o.gantt.pub",
        "allowed_idps": ["pocket-idp"], "policies": [{"id": "pol-o", "precedence": 1}]}}
policies = {}
log = open(t + "/calls", "a")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, ok, result=None, code=200):
        self.send_response(code); self.end_headers()
        self.wfile.write(json.dumps({"success": ok, "errors": [] if ok else [{"message": "denied"}], "result": result}).encode())
    def body(self):
        n = int(self.headers.get("Content-Length", 0)); return json.loads(self.rfile.read(n) or b"null")
    def handle_any(self, m):
        if self.headers.get("Authorization") != "Bearer tok": return self.reply(False, code=403)
        p = self.path.split("/accounts/acct/", 1)[1]
        log.write(m + " " + p + "\n"); log.flush()
        if m == "GET" and p == "access/apps": return self.reply(True, list(apps.values()))
        if m == "GET" and p == "access/identity_providers":
            return self.reply(True, [{"id": "pocket-idp", "type": "oidc"}, {"id": "pin-idp", "type": "onetimepin"}])
        if m == "POST" and p == "access/policies":
            b = self.body(); b["id"] = "pol-bg"; policies["pol-bg"] = b
            json.dump(b, open(t + "/policy.json", "w")); return self.reply(True, b)
        if p.startswith("access/apps/") and m == "PUT":
            b = self.body(); apps[p.split("/")[2]] = b; json.dump(apps, open(t + "/apps.json", "w")); return self.reply(True, b)
        if p.startswith("access/policies/") and m == "DELETE":
            policies.pop(p.split("/")[2], None); json.dump(policies, open(t + "/policies.json", "w")); return self.reply(True, {})
        self.reply(False, code=404)
    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PUT(self): self.handle_any("PUT")
    def do_DELETE(self): self.handle_any("DELETE")
json.dump(apps, open(t + "/apps.json", "w")); json.dump(policies, open(t + "/policies.json", "w"))
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
PY
python3 "$t/server.py" 2>"$t/server.err" & pid=$!
for _ in $(seq 50); do curl -s -o /dev/null "$base/" && break; sleep 0.1; done

mkdir -p "$t/cfg"
printf 'CLOUDFLARE_API_TOKEN=tok\nCLOUDFLARE_ACCOUNT_ID=acct\n' >"$t/cfg/cf.env"; chmod 600 "$t/cfg/cf.env"
bg() { CF_API=$base TOKEN_FILE=$t/cfg/cf.env BREAKGLASS_DIR=$t/bg "$root/deploy/breakglass.sh" "$@" >"$t/out" 2>&1; }
app() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]], sort_keys=True))' "$t/apps.json" "$1"; }
before=$(app app1); other=$(app app2)

check "token file with loose mode is refused" bash -c 'chmod 644 "$1"; CF_API=$2 TOKEN_FILE=$1 BREAKGLASS_DIR=$3 "$4" Cubby >/dev/null 2>&1; rc=$?; chmod 600 "$1"; [ $rc != 0 ]' _ "$t/cfg/cf.env" "$base" "$t/bg" "$root/deploy/breakglass.sh"
check "unknown app is refused" not bg nope
bg Cubby; rc=$?
check "switch: exit 0" [ "$rc" = 0 ]
check "switch: allowed_idps is only the one-time PIN method" bash -c 'python3 -I -c "import json,sys; a=json.load(open(sys.argv[1]))[\"app1\"]; sys.exit(a[\"allowed_idps\"]!=[\"pin-idp\"] or a[\"auto_redirect_to_identity\"])" "$1"' _ "$t/apps.json"
check "switch: only the break-glass policy applies" bash -c 'python3 -I -c "import json,sys; a=json.load(open(sys.argv[1]))[\"app1\"]; sys.exit([p[\"id\"] for p in a[\"policies\"]]!=[\"pol-bg\"])" "$1"' _ "$t/apps.json"
check "switch: policy allows ryan@gantt.pub and nobody else" bash -c 'python3 -I -c "import json,sys; p=json.load(open(sys.argv[1])); sys.exit(p[\"include\"]!=[{\"email\":{\"email\":\"ryan@gantt.pub\"}}] or p[\"decision\"]!=\"allow\")" "$1"' _ "$t/policy.json"
check "switch: other apps untouched" [ "$(app app2)" = "$other" ]
check "switch: second switch is refused" not bg Cubby

# The alarm: check-identity pages while a state file exists, using a fixture alert sink.
printf 'PUSHOVER_TOKEN=tok\nPUSHOVER_USER=usr\n' >"$t/alerts.env"; touch "$t/stamp"
cat >"$t/sink.py" <<PY
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self): self.send_response(200); self.end_headers(); self.wfile.write(b'{"issuer":"http://127.0.0.1:$((port+1))","jwks_uri":"x"}')
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); b = self.rfile.read(n).decode(errors="replace")
        open("$t/pushes", "a").write(b.replace("\r\n", " ") + "\n"); self.send_response(200); self.end_headers()
http.server.HTTPServer(("127.0.0.1", $((port+1))), H).serve_forever()
PY
: >"$t/pushes"; python3 "$t/sink.py" & spid=$!; trap 'kill $spid 2>/dev/null; [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
sbase=http://127.0.0.1:$((port+1))
for _ in $(seq 50); do curl -s -o /dev/null "$sbase/" && break; sleep 0.1; done
chk() { ID_BASE=$sbase BACKUP_STAMP=$t/stamp STATE_DIR=$t/state ALERTS_ENV=$t/alerts.env PUSHOVER_API_URL=$sbase/push RETRY_DELAY=0 BREAKGLASS_DIR=$t/bg "$root/deploy/check-identity.sh" >"$t/chkout" 2>&1; }
chk; rc=$?
check "alarm while active: check exits 1 and pages naming Cubby" bash -c '[ "$1" = 1 ] && grep -q "BREAK-GLASS ACTIVE for Cubby" "$2"' _ "$rc" "$t/pushes"

bg --revert Cubby; rc=$?
check "revert: exit 0" [ "$rc" = 0 ]
check "revert: app is byte-identical to the original (no terraform drift)" [ "$(app app1)" = "$before" ]
check "revert: temporary policy deleted" bash -c '[ "$(cat "$1")" = "{}" ]' _ "$t/policies.json"
check "revert: other apps untouched" [ "$(app app2)" = "$other" ]
check "revert: a second revert is refused" not bg --revert Cubby
chk; rc=$?
check "alarm clears after revert: exit 0 and RECOVERED page" bash -c '[ "$1" = 0 ] && tail -n1 "$2" | grep -q RECOVERED' _ "$rc" "$t/pushes"
exit $fail
