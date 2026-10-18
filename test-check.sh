#!/usr/bin/env bash
# Drives deploy/check-identity.sh against a fixture id.gantt.pub and a fixture Pushover sink:
# healthy is silent, an outage / bad discovery / stale or missing backup alarms once, recovery clears.
# Runs through testenv; touches only a temp dir.
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
echo up >"$t/mode"; : >"$t/pushes"

cat >"$t/server.py" <<PY
import http.server, sys
t = "$t"
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); body = self.rfile.read(n).decode(errors="replace")
        title = [l for l in body.split("\r\n") if l and not l.startswith("--") and not l.startswith("Content-")]
        open(t + "/pushes", "a").write(" | ".join(title).replace("\n", "; ") + "\n")
        self.send_response(200); self.end_headers()
    def do_GET(self):
        mode = open(t + "/mode").read().strip()
        if mode == "down": self.send_response(502); self.end_headers(); return
        if self.path.startswith("/.well-known/openid-configuration"):
            if mode == "baddisc": self.send_response(404); self.end_headers(); return
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"issuer":"$base","jwks_uri":"$base/.well-known/jwks.json"}'); return
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
PY
python3 "$t/server.py" & pid=$!
for _ in $(seq 50); do curl -s -o /dev/null "$base/" && break; sleep 0.1; done

printf 'PUSHOVER_TOKEN=tok\nPUSHOVER_USER=usr\n' >"$t/alerts.env"
touch "$t/stamp"
run() {
  ID_BASE=$base BACKUP_STAMP=$t/stamp STATE_DIR=$t/state ALERTS_ENV=${ALERTS_ENV:-$t/alerts.env} \
    PUSHOVER_API_URL=$base/push RETRY_DELAY=0 "$root/deploy/check-identity.sh" >"$t/out" 2>&1
}
pushes() { grep -c . "$t/pushes"; }

run; rc=$?
check "healthy: exit 0, no page" bash -c '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$rc" "$(pushes)"

echo down >"$t/mode"
run; rc=$?
check "site down: exit 1" [ "$rc" = 1 ]
check "site down: one ALARM page naming the site" bash -c '[ "$(grep -c "ALARM" "$1")" = 1 ] && grep -q "answered HTTP 502" "$1"' _ "$t/pushes"
run
check "still down: no repeat page" [ "$(pushes)" = 1 ]

echo up >"$t/mode"
run; rc=$?
check "recovered: exit 0" [ "$rc" = 0 ]
check "recovered: one RECOVERED page" bash -c 'grep -q RECOVERED "$1" && [ "$(grep -c . "$1")" = 2 ]' _ "$t/pushes"
run
check "healthy again: no further page" [ "$(pushes)" = 2 ]

echo baddisc >"$t/mode"
run; rc=$?
check "discovery down (site up): alarms" bash -c '[ "$1" = 1 ] && tail -n1 "$2" | grep -q "OIDC discovery"' _ "$rc" "$t/pushes"
echo up >"$t/mode"; run

touch -d '37 hours ago' "$t/stamp"
run; rc=$?
check "backup 37 h old: alarms" bash -c '[ "$1" = 1 ] && tail -n1 "$2" | grep -q "newest backup is 37 h old"' _ "$rc" "$t/pushes"
touch "$t/stamp"; run; rc=$?
check "fresh backup clears" [ "$rc" = 0 ]

rm "$t/stamp"
run; rc=$?
check "missing backup stamp alarms" bash -c '[ "$1" = 1 ] && tail -n1 "$2" | grep -q "no backup has ever completed"' _ "$rc" "$t/pushes"
touch "$t/stamp"; run

# Unreachable alert channel is a failure, and is retried (nothing recorded).
echo down >"$t/mode"; rm -rf "$t/state"
ALERTS_ENV=/nonexistent run; rc=$?
check "no pushover config: exit 1, says nobody was reached" bash -c '[ "$1" = 1 ] && grep -q "reached nobody" "$2"' _ "$rc" "$t/out"
check "no page state recorded after failed push" [ ! -e "$t/state/alarm" ]

# Unit hygiene.
out=$t/units; "$root/deploy/render.sh" "$out" /cfg
check "timer fires every minute" grep -Fxq 'OnUnitActiveSec=60s' "$out/identity-check.timer"
check "service fenced with CPUQuota" grep -Eq '^CPUQuota=' "$out/identity-check.service"
check "service runs the installed check" grep -Fxq 'ExecStart=%h/.local/lib/identity/check-identity.sh' "$out/identity-check.service"
exit $fail
