#!/usr/bin/env bash
# Render the Quadlet units into a directory. Pure: touches nothing else, runs on any host.
# Usage: render.sh <outdir> [config-dir]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${1:?usage: render.sh <outdir> [config-dir]}
config_dir=${2:-%h/.config/identity}
port=1411
# shellcheck source=image.env
. "$here/image.env"
mkdir -p "$out"
for tpl in "$here"/units/*.in; do
  name=$(basename "${tpl%.in}")
  sed -e "s|@POCKET_ID_IMAGE@|$POCKET_ID_IMAGE|g" \
      -e "s|@CLOUDFLARED_IMAGE@|$CLOUDFLARED_IMAGE|g" \
      -e "s|@CONFIG_DIR@|$config_dir|g" \
      -e "s|@PORT@|$port|g" "$tpl" >"$out/$name"
done
