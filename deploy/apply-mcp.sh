#!/usr/bin/env bash
# Make Pocket ID an OAuth authorization server for the sites' /mcp endpoints, from deploy/mcp/mcp.json:
# the Client ID Metadata Document allowlist (exactly the listed client URLs) and one "API" per /mcp
# resource, with "Allow all metadata document clients" on. Idempotent: reads the live state first and
# writes only what differs. Needs an admin API key in $CONFIG_DIR/pocket-id-api-key (0600, one line).
# Exit 3 when the key is missing.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
config_dir=${1:-$HOME/.config/identity}
base=${POCKET_ID_URL:-http://127.0.0.1:1411}
spec=$here/mcp/mcp.json
keyfile=$config_dir/pocket-id-api-key
if [ ! -s "$keyfile" ]; then
  echo "apply-mcp.sh: $keyfile is missing; the MCP authorization settings are NOT being applied (see README)" >&2
  exit 3
fi
key=$(tr -d '[:space:]' <"$keyfile")
api() { curl -fsS -H "X-API-KEY: $key" "$@"; }
send() { # send <method> <path> <json-on-stdin>
  api -X "$1" -H 'Content-Type: application/json' --data-binary @- "$base$2" >/dev/null
}
py() { python3 -I -c "$@"; }

# 1. The CIMD allowlist. The update endpoint replaces the whole configuration, so send every live
#    value back with ours laid over it; nothing is sent when the live list already equals ours.
live=$(api "$base/api/application-configuration/all")
body=$(py '
import json, sys
cfg = {e["key"]: e["value"] for e in json.loads(sys.argv[1])}
want = sorted(c["url"] for c in json.load(open(sys.argv[2]))["cimd_clients"])
try:
    have = sorted(json.loads(cfg.get("cimdUrlAllowlist") or "[]"))
except ValueError:
    have = None
if have == want:
    sys.exit(0)
cfg["cimdUrlAllowlist"] = json.dumps(want)
print(json.dumps(cfg))
' "$live" "$spec")
if [ -n "$body" ]; then
  send PUT /api/application-configuration <<<"$body"
  echo "apply-mcp.sh: set the metadata-document client allowlist"
fi

# 2. One API per resource.
count=$(py 'import json,sys; print(len(json.load(open(sys.argv[1]))["apis"]))' "$spec")
for ((i = 0; i < count; i++)); do
  item=$(py 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["apis"][int(sys.argv[2])]))' "$spec" "$i")
  resource=$(py 'import json,sys; print(json.loads(sys.argv[1])["resource"])' "$item")
  find='
import json, sys
d = json.loads(sys.argv[1])
items = d.get("data", d) if isinstance(d, dict) else d
for a in items:
    if a["resource"].rstrip("/") == sys.argv[2]:
        print(a["id"]); break
'
  id=$(py "$find" "$(api "$base/api/apis?pagination[limit]=1000")" "$resource")
  if [ -z "$id" ]; then
    py 'import json,sys; a=json.loads(sys.argv[1]); print(json.dumps({"name":a["name"],"resource":a["resource"]}))' "$item" \
      | send POST /api/apis
    id=$(py "$find" "$(api "$base/api/apis?pagination[limit]=1000")" "$resource")
    echo "apply-mcp.sh: created the API for $resource"
  fi
  cur=$(api "$base/api/apis/$id")
  # Permissions: replace the set only when the keys, names or descriptions differ.
  perms=$(py '
import json, sys
a, cur = json.loads(sys.argv[1]), json.loads(sys.argv[2])
def norm(ps): return sorted((p["key"], p["name"], p.get("description", "")) for p in ps)
if norm(a["permissions"]) == norm(cur.get("permissions", [])) and a["name"] == cur.get("name"):
    sys.exit(0)
print(json.dumps({"permissions": a["permissions"]}))
' "$item" "$cur")
  if [ -n "$perms" ]; then
    send PUT "/api/apis/$id/permissions" <<<"$perms"
    echo "apply-mcp.sh: set the permissions of $resource"
    cur=$(api "$base/api/apis/$id")
  fi
  access=$(py '
import json, sys
a, cur = json.loads(sys.argv[1]), json.loads(sys.argv[2])
on = bool(a["allow_cimd_clients"])
ids = sorted(p["id"] for p in cur["permissions"]) if on else []
have = sorted(p["id"] for p in cur["permissions"] if p.get("allowedForCimdClients"))
if bool(cur.get("allowCimdClients")) == on and have == ids:
    sys.exit(0)
print(json.dumps({"enabled": on, "permissionIds": ids}))
' "$item" "$cur")
  if [ -n "$access" ]; then
    send PUT "/api/apis/$id/cimd-access" <<<"$access"
    echo "apply-mcp.sh: set metadata-document client access on $resource"
  fi
done
