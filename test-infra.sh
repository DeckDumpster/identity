#!/usr/bin/env bash
# fmt, validate and the mocked-provider tests for infra/. Runs through testenv; no credentials.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tf_version=1.13.3
tf_sha256=71fc43d92ea09907be5d416d2405a6a9c2d1ceaed633f5e175c0af26e8c4b365
if ! command -v terraform >/dev/null 2>&1; then
  dir=$(mktemp -d)
  { command -v curl && command -v unzip; } >/dev/null || { apt-get update -qq && apt-get install -y -qq curl ca-certificates unzip >/dev/null; }
  curl -fsSL -o "$dir/tf.zip" "https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_amd64.zip"
  echo "${tf_sha256}  $dir/tf.zip" | sha256sum -c -
  unzip -q -o "$dir/tf.zip" terraform -d "$dir"
  export PATH="$dir:$PATH"
fi
cd "$root/infra"
terraform fmt -check -recursive
{ terraform init -backend=false -input=false || { sleep 5; terraform init -backend=false -input=false; }; }
terraform validate
terraform test
# No Access application may cover id.gantt.pub (it would gate the OIDC endpoints Cloudflare itself calls).
! grep -rIEn 'domain[[:space:]]*=[[:space:]]*"(https?://)?id\.gantt\.pub' --include='*.tf' . || { echo "infra/ must not declare an Access application on id.gantt.pub" >&2; exit 1; }
# The backups root is a separate Terraform root (own state key, AWS only).
(
  cd "$root/infra-backups"
  terraform fmt -check -recursive
  { terraform init -backend=false -input=false || { sleep 5; terraform init -backend=false -input=false; }; }
  terraform validate
  terraform test
)
