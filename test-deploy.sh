#!/usr/bin/env bash
# Renders the units and checks the pin, the loopback bind, the tunnel and host refusal.
# Runs through testenv; touches only a temp dir.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
"$root/deploy/render.sh" "$out/units" /cfg || { echo "render failed"; exit 1; }
pc=$out/units/pocket-id.container cf=$out/units/cloudflared-id.container

check "pocket-id image pinned to tag and sha256 digest" \
  grep -Eq '^Image=ghcr\.io/pocket-id/pocket-id:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$pc"
check "cloudflared image pinned to tag and sha256 digest" \
  grep -Eq '^Image=.*:[0-9][^@]*@sha256:[0-9a-f]{64}$' "$cf"
check "no floating :latest tag" bash -c '! grep -q ":latest" "$@"' _ "$pc" "$cf"
check "published on loopback only" grep -Eq '^PublishPort=127\.0\.0\.1:1411:1411$' "$pc"
check "no other published port" bash -c '[ "$(grep -c "^PublishPort=" "$1")" = 1 ]' _ "$pc"
check "APP_URL is https://id.gantt.pub" grep -Fxq 'Environment=APP_URL=https://id.gantt.pub' "$pc"
check "own data volume" grep -Eq '^Volume=pocket-id-data\.volume:/app/data$' "$pc"
check "tunnel shares the host network to reach loopback" grep -Fxq 'Network=host' "$cf"
check "secrets come from env files, not units" \
  bash -c 'grep -q "^EnvironmentFile=/cfg/pocket-id.env$" "$1" && grep -q "^EnvironmentFile=/cfg/cloudflared-id.env$" "$2" && ! grep -Eq "ENCRYPTION_KEY=|TUNNEL_TOKEN=" "$1" "$2"' _ "$pc" "$cf"
check "no unrendered placeholders" bash -c '! grep -q "@[A-Z_]*@" "$@"' _ "$out"/units/*
# (an Access app on id.gantt.pub is refused by test-infra.sh, by domain)

# Branding: one palette shared by Cloudflare's login page (Terraform) and Pocket ID (apply-branding.sh).
b=$root/deploy/branding
bj() { python3 -I -c 'import json,re,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$b/branding.json" "$1"; }
check "branding.json carries every field" \
  bj 'all(isinstance(d.get(k),str) and d[k] for k in ["app_name","header_text","footer_text","accent_color","background_color","text_color"])'
check "branding colours are hex" \
  bj 'all(re.fullmatch(r"#[0-9a-fA-F]{6}", d[k]) for k in ["accent_color","background_color","text_color"])'
check "app name fits Pocket ID's 30 character limit" bj 'len(d["app_name"]) <= 30' 
check "logo is an svg" grep -q '<svg' "$b/logo.svg"
check "deploy applies the branding" grep -q 'apply-branding.sh' "$root/deploy/deploy.sh"
# apply-branding.sh against a fake Pocket ID: first run writes, second run changes nothing.
fake=$out/fake; mkdir -p "$fake/bin" "$fake/cfg"; printf 'k\n' >"$fake/cfg/pocket-id-api-key"
cat >"$fake/bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_LOG"
case "$*" in
  *application-configuration/all*) cat "$FAKE_STATE/config.json" ;;
  *"-X PUT"*"application-configuration"*) cat >"$FAKE_STATE/put.json"; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump([{"key":k,"value":v} for k,v in d.items()], open(sys.argv[2],"w"))' "$FAKE_STATE/put.json" "$FAKE_STATE/config.json" ;;
  *"-X PUT"*"application-images/logo?light="*) a="$*"; l=${a##*light=}; l=${l%% *}; cp "$FAKE_LOGO" "$FAKE_STATE/logo-$l" ;;
  *application-images/logo?light=*) a="$*"; l=${a##*light=}; l=${l%%&*}; cat "$FAKE_STATE/logo-$l" 2>/dev/null ;;
esac
FAKE
chmod +x "$fake/bin/curl"
echo '[{"key":"appName","value":"Pocket ID"},{"key":"accentColor","value":"default"},{"key":"sessionDuration","value":"60"}]' >"$fake/config.json"
export FAKE_LOG=$fake/log FAKE_STATE=$fake FAKE_LOGO=$b/logo.svg
mv "$fake/config.json" "$fake/config.json.in"; cp "$fake/config.json.in" "$fake/config.json"
PATH=$fake/bin:$PATH "$root/deploy/apply-branding.sh" "$fake/cfg" >"$fake/run1" 2>&1
check "branding first run writes name, accent and both logos" \
  bash -c 'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if (d[\"appName\"],d[\"accentColor\"],d[\"sessionDuration\"])==(\"Gantt family\",\"#3b82f6\",\"60\") else 1)" "$1/put.json" && cmp -s "$1/logo-true" "$2" && cmp -s "$1/logo-false" "$2"' _ "$fake" "$b/logo.svg"
: >"$fake/log"
PATH=$fake/bin:$PATH "$root/deploy/apply-branding.sh" "$fake/cfg" >"$fake/run2" 2>&1
check "branding second run writes nothing" bash -c '! grep -q -- "-X PUT" "$1" && [ ! -s "$2" ]' _ "$fake/log" "$fake/run2"
check "branding without an API key says so and exits 3" \
  bash -c 'PATH=$1/bin:$PATH "$2/deploy/apply-branding.sh" "$1/none" >/dev/null 2>&1; [ $? = 3 ]' _ "$fake" "$root"

# apply-mcp.sh against a stateful fake Pocket ID: first run writes the allowlist, the API, its
# permission and the CIMD access; the second run changes nothing.
m=$root/deploy/mcp/mcp.json
mj() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$m" "$1"; }
check "mcp.json allowlist is exactly the two Claude client URLs, each with a source" \
  mj 'sorted(c["url"] for c in d["cimd_clients"])==["https://claude.ai/oauth/claude-code-client-metadata","https://claude.ai/oauth/mcp-oauth-client-metadata"] and all(c["source"] for c in d["cimd_clients"])'
check "mcp.json declares the dumpstar API with the /mcp URL as its resource and CIMD access on" \
  mj 'any(a["resource"]=="https://star.dumpster.cards/mcp" and a["allow_cimd_clients"] and a["permissions"] for a in d["apis"])'
check "deploy applies the MCP settings" grep -q 'apply-mcp.sh' "$root/deploy/deploy.sh"
mf=$out/mcpfake; mkdir -p "$mf/bin"
cat >"$mf/bin/curl" <<'FAKE'
#!/usr/bin/env python3
import json, os, sys
st = os.environ["FAKE_STATE"] + "/state.json"
s = json.load(open(st))
a = sys.argv[1:]
method = a[a.index("-X") + 1] if "-X" in a else "GET"
url = [x for x in a if x.startswith("http")][0].split("://127.0.0.1:1411")[1]
# Real curl globs [ ] in a URL unless -g/--globoff is given (error 3, "bad range").
if ("[" in url or "]" in url) and not any(x == "--globoff" or (x.startswith("-") and not x.startswith("--") and "g" in x) for x in a):
    sys.stderr.write("curl: (3) bad range in URL position 1\n"); sys.exit(3)
body = sys.stdin.read() if "--data-binary" in a else ""
open(os.environ["FAKE_LOG"], "a").write(method + " " + url + "\n")
path = url.split("?")[0]
out = None
if path == "/api/application-configuration/all":
    out = [{"key": k, "value": v} for k, v in s["cfg"].items()]
elif path == "/api/application-configuration" and method == "PUT":
    s["cfg"] = json.loads(body)
elif path == "/api/apis" and method == "GET":
    out = {"data": s["apis"]}
elif path == "/api/apis" and method == "POST":
    d = json.loads(body)
    s["apis"].append({"id": "api%d" % (len(s["apis"]) + 1), "name": d["name"], "resource": d["resource"], "permissions": [], "allowCimdClients": False})
else:
    parts = path.split("/")
    api = [x for x in s["apis"] if x["id"] == parts[3]][0]
    if len(parts) == 4:
        out = api
    elif parts[4] == "permissions":
        api["permissions"] = [dict(p, id="p-" + p["key"], allowedForCimdClients=False) for p in json.loads(body)["permissions"]]
    elif parts[4] == "cimd-access":
        d = json.loads(body)
        api["allowCimdClients"] = d["enabled"]
        for p in api["permissions"]:
            p["allowedForCimdClients"] = p["id"] in d["permissionIds"]
json.dump(s, open(st, "w"))
if out is not None:
    print(json.dumps(out))
FAKE
chmod +x "$mf/bin/curl"
mkdir -p "$mf/cfg"; printf 'k\n' >"$mf/cfg/pocket-id-api-key"
echo '{"cfg":{"appName":"x","cimdUrlAllowlist":"[]"},"apis":[]}' >"$mf/state.json"
export FAKE_STATE=$mf FAKE_LOG=$mf/log
PATH=$mf/bin:$PATH "$root/deploy/apply-mcp.sh" "$mf/cfg" >"$mf/run1" 2>&1
check "mcp first run sets the allowlist, creates the API and opens it to metadata clients" \
  python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1]+"/state.json")); a=s["apis"][0]; sys.exit(0 if sorted(json.loads(s["cfg"]["cimdUrlAllowlist"]))==["https://claude.ai/oauth/claude-code-client-metadata","https://claude.ai/oauth/mcp-oauth-client-metadata"] and s["cfg"]["appName"]=="x" and a["resource"]=="https://star.dumpster.cards/mcp" and a["allowCimdClients"] and [p["allowedForCimdClients"] for p in a["permissions"]]==[True] else 1)' "$mf"
: >"$mf/log"
PATH=$mf/bin:$PATH "$root/deploy/apply-mcp.sh" "$mf/cfg" >"$mf/run2" 2>&1
check "mcp second run writes nothing" bash -c '! grep -Eq "^(PUT|POST) " "$1" && [ ! -s "$2" ]' _ "$mf/log" "$mf/run2"
check "mcp run fails loudly, naming the call, when the API list comes back empty" \
  bash -c 'printf "#!/usr/bin/env bash\nexit 0\n" >"$1/bin/curl2"; chmod +x "$1/bin/curl2"; mkdir -p "$1/empty"; cp "$1/bin/curl2" "$1/empty/curl"; PATH=$1/empty:$PATH "$2/deploy/apply-mcp.sh" "$1/cfg" >"$1/run3" 2>&1; rc=$?; [ $rc != 0 ] && [ $rc != 3 ] && grep -q "GET .*application-configuration/all failed or returned nothing" "$1/run3" && ! grep -q Traceback "$1/run3"' _ "$mf" "$root"
check "deploy.sh fails on an apply-mcp failure and allows only exit 3" \
  bash -c 'grep -q "exit \"\$rc\"" "$1/deploy/deploy.sh" && grep -q "= 3" "$1/deploy/deploy.sh"' _ "$root"
check "mcp without an API key says so and exits 3" \
  bash -c 'PATH=$1/bin:$PATH "$2/deploy/apply-mcp.sh" "$1/none" >/dev/null 2>&1; [ $? = 3 ]' _ "$mf" "$root"

# Deploy workflow and smoke.
w=$root/.github/workflows/deploy.yml
check "workflow runs on the identity-prod runner" grep -Fq 'runs-on: [self-hosted, identity-prod]' "$w"
check "workflow refuses any ref but main" grep -Fq "github.ref == 'refs/heads/main'" "$w"
check "workflow does not cancel a running deploy" grep -Fq 'cancel-in-progress: false' "$w"
check "workflow runs deploy.sh and smoke.sh" bash -c 'grep -q "deploy/deploy.sh" "$1" && grep -q "deploy/smoke.sh" "$1"' _ "$w"
check "runner-setup.sh and smoke.sh parse" bash -c 'bash -n "$1/deploy/runner-setup.sh" && bash -n "$1/deploy/smoke.sh"' _ "$root"
check "smoke fails when nothing serves" bash -c 'SMOKE_BASE=http://127.0.0.1:9 SMOKE_TRIES=1 "$1/deploy/smoke.sh" >/dev/null 2>&1; [ $? = 1 ]' _ "$root"

# Host refusal: skipped when run on the prod host itself.
have=$(hostname -s); want=$(tr -d '[:space:]' <"$root/deploy/prod-host")
check "prod-host names ubuntu-mini-0" [ "$want" = ubuntu-mini-0 ]
if [ "$have" = "$want" ]; then
  echo "skip host refusal: running on the prod host"
else
  msg=$(HOME=$out/home "$root/deploy/deploy.sh" 2>&1); rc=$?
  check "refuses on $have (exit 2)" [ "$rc" = 2 ]
  check "refusal names the prod host" bash -c 'grep -q ubuntu-mini-0 <<<"$1"' _ "$msg"
  check "refusal wrote nothing" [ ! -e "$out/home" ]
fi
exit $fail
