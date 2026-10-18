# identity

Central sign-in for every app Ryan exposes through Cloudflare Access: one self-hosted OIDC
provider (Pocket ID at `id.gantt.pub`, on ubuntu-mini-0) and per-app groups, so adding or removing
a person never touches an Access policy, Terraform or an MFA code.

- Design (approved 2026-10-18): `docs/design/central-identity-hld-2026-10-18.md`
- Production host: ubuntu-mini-0 (user `ryangantt`); nothing here runs on the Spira box.

## Deploy

`deploy/deploy.sh` installs Pocket ID and a cloudflared tunnel as rootless Quadlet units for
user `ryangantt` on the host named in `deploy/prod-host` (ubuntu-mini-0). It exits 2 anywhere
else, and is idempotent: it rewrites a unit and restarts only when its rendered text changed.
Merging does not deploy; the Concierge runs it from a production checkout on ubuntu-mini-0.

- Images are pinned by tag and digest in `deploy/image.env` (Pocket ID v2.18.0
  `sha256:323e7ef5…b5165`, cloudflared 2026.10.1 `sha256:a15a3b50…b2d5`). Bump the tag and
  digest together.
- Pocket ID listens on `127.0.0.1:1411` only, with data in the `pocket-id-data` volume and
  `APP_URL=https://id.gantt.pub`.
- Secrets are 0600 files in `~/.config/identity/`, never in git. `pocket-id.env`
  (`ENCRYPTION_KEY`) is generated on first deploy and never replaced. `cloudflared-id.env`
  (`TUNNEL_TOKEN=<token>`) must be placed by hand first; deploy exits 3 without it.
- The tunnel's public hostname `id.gantt.pub` -> `http://127.0.0.1:1411` is set on the tunnel
  itself (it is remotely managed by the token). `id.gantt.pub` must **not** have a Cloudflare
  Access application; `test-deploy.sh` fails if this repo declares one.
- `deploy/render.sh <dir>` renders the units anywhere; `test-deploy.sh` checks the pins, the
  loopback bind and the host refusal (`testenv --suites test-deploy`).

## First admin login

A fresh Pocket ID has no users. Complete the first-run setup at `https://id.gantt.pub/setup`
immediately after the first deploy (the page is open to whoever reaches it first), creating
Ryan's admin account. To enrol a passkey on a new device, or after losing one, mint a one-time
login code on ubuntu-mini-0:

    podman exec pocket-id /app/pocket-id one-time-access-token <username-or-email>

Open the link it prints and register the passkey.

## Groups claim

Verified in Pocket ID v2.18.0 source (`backend/internal/oidc/claims_service.go`): the claim is
`groups`, a JSON array of the user's group **names**. It is emitted only when the client
requests the `groups` scope (alongside `openid profile email`), so the Cloudflare OIDC login
method must list `groups` in its scopes and `groups` in its claims. It appears in the ID token
and the userinfo response. Cloudflare matches the names exactly, so group names (`cubby-parents`,
`poke-users`, ...) must match the policies. A client may also be restricted to allowed user
groups inside Pocket ID.

<<<<<<< HEAD
## Apply (the Concierge, with an MFA session and a Cloudflare token)

`infra/` registers Pocket ID as a Cloudflare Access generic OIDC login method (state key
`identity/infra/terraform.tfstate` in the shared state bucket). It outputs `login_method_id`
for app policies. Checked by `testenv --suites test-infra` (fmt, validate, mocked-provider test:
claims include `groups`, scopes are `openid email profile groups`, no secret in outputs).

1. In Pocket ID, create an OIDC client with redirect URL
   `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`. Put its id and secret in a
   0600 file, never in chat or git:

       install -m 600 /dev/null ~/.config/identity/pocket-id-oidc.json
       # {"client_id": "...", "client_secret": "..."}

2. Confirm `auth_url`, `token_url`, `certs_url` in `infra/main.tf` against
   `https://id.gantt.pub/.well-known/openid-configuration`.
3. Plan and apply:

       export CLOUDFLARE_API_TOKEN=...   # Access: Identity Providers edit
       cd infra
       terraform init -backend-config="bucket=<StateBucketName>" \
         -backend-config="assume_role={role_arn=\"<DeployRoleArn>\"}"
       terraform plan -out=identity.tfplan -var cloudflare_account_id=<id> \
         -var credentials_file=$HOME/.config/identity/pocket-id-oidc.json
       terraform apply identity.tfplan

   Expect `Plan: 1 to add, 0 to change, 0 to destroy`.
4. In Cloudflare Zero Trust, Settings > Authentication > Pocket ID > Test, and confirm a
   `groups` claim for Ryan. The client secret is stored in Terraform state (the provider
   requires it there); it is never an output.
=======
## Monitoring

`deploy/check-identity.sh` runs every minute (`identity-check.timer`, CPU-fenced) on ubuntu-mini-0.
It alarms through Pushover (credentials in `~/.config/pkdump/alerts.env`, as the other services do)
once when `https://id.gantt.pub`, its `/.well-known/openid-configuration`, or the backup goes bad,
and once more when everything clears. Backup freshness is the mtime of
`~/.local/state/identity/last-backup`, which the backup job (Litestream, bead 2) must `touch` after
each successful upload; a missing or >36 h old stamp alarms. Tested by `test-check.sh`.
>>>>>>> 60c3117 (sp-khwi4f: identity check (site, OIDC discovery, backup age) with Pushover alarm, fenced timer and fixture test)
