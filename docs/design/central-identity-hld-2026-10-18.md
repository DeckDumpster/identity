---
type: note
created: 2026-10-18
updated: 2026-10-18
tags: [design, identity, cloudflare-access, home-network]
status: approved
sources:
  - https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/generic-oidc/
  - https://developers.cloudflare.com/cloudflare-one/policies/filtering/identity-selectors/
  - https://pocket-id.org/docs/
---

# Central identity for every Cloudflare Access app (HLD)

Every app Ryan exposes through Cloudflare Access carries its own hand-managed email list.
Adding a person means editing each app's policy, and for apps whose Access config is in
Terraform (Cubby), an AWS MFA session as well, because Terraform state lives in the CI
account's state bucket. On 2026-10-18 adding Kim to Cubby took a Terraform change, a deploy,
an MFA code and an apply (per Ryan, 2026-10-18: *"i have hand-managed cloudflare access lists
for all of my applications. it's annoying."*).

## Intent

One place to decide who may reach which app. Ryan adds or removes a person, or changes what
they can reach, in a single identity provider's admin UI, in under a minute. Cloudflare Access,
Terraform and MFA are never involved. Every Access app keeps working as today for the people
already allowed. Measured by: after the migration, adding a new person to Cubby, dumpstar and
poke takes one admin action per app group, and no Access policy, Terraform file or MFA code.

## Scope

- **Identity provider:** one self-hosted OIDC provider (default **Pocket ID**) holding users and
  groups, with passkey sign-in.
- **Cloudflare:** registered as a generic OIDC login method in Cloudflare Access, in Terraform.
- **Policies:** each Access app's allow policy rewritten once, from an email list to "member of
  group `<app>-users`" (Cubby: `cubby-parents`), in Terraform.
- **Migration:** every existing app moved one at a time (see recon), each keeping its service
  token policies.
- **Break-glass:** Ryan can still sign in when the identity provider is down.
- **Operations:** backups and a restore drill for the identity provider, off-box in the CI
  account (`law-product-backups-live-in-the-ci-account`), plus monitoring.

## Non-goals

- **Apps deciding authorization themselves.** Cubby keeps its own family check: the group says
  "may reach /parent", the registry says which family. Nothing else moves into apps.
- **A hosted provider** (Google Workspace, Entra, Auth0, Okta).
  - Cost: Google Workspace is about $7 a user each month and moves mail ownership questions
    onto Google; Auth0 and Okta free tiers cap features and add a vendor dependency.
  - Buys: no server to run.
  - Out because the self-hosted provider is one small container on a host that already runs
    products, and it keeps the user list on Ryan's hardware. Revisit if keeping it up proves
    costly.
- **Tailscale identity (tsidp or Tailscale headers).**
  - Cost: every person must join Ryan's tailnet, and `tsidp` must be exposed with Funnel
    before Cloudflare can complete the OIDC exchange. Roughly 3 beads plus tailnet invites
    for each person.
  - Buys: identity tied to devices.
  - Out because Kim and future users would need Tailscale for a kids' video site, and it
    couples app access to network membership.
- **Keycloak or Authentik.** Full-featured, but a JVM or multi-container stack to run and
  patch, for a dozen users. Out on operating cost; Pocket ID or Authelia is enough.
- **SCIM provisioning into Cloudflare.** Cloudflare can sync groups over SCIM and revoke
  sessions on change. Pocket ID's docs list SCIM provisioning, but it is unverified here.
  Out for v1; a removed person's access ends when their Access session expires (see Open
  questions).
- **SSH and non-HTTP apps beyond what Access already fronts.** `ssh.dumpster.cards` moves
  like the others; nothing new is put behind Access.

## Background / recon

Cloudflare Access apps on the account (read through the API on 2026-10-18):

| App | Domain | Allow rules today | Other policy |
|---|---|---|---|
| cubby-parent | cubby.gantt.pub/parent | 2 emails (Ryan, Kim), in Terraform | — |
| cubby-public | cubby.gantt.pub/watch… | bypass for everyone (device token instead) | — |
| dumpstar | star.dumpster.cards | 1 email | service token |
| poke | poke.dumpster.cards | 3 emails | service token |
| magic | magic.dumpster.cards | 4 emails | service token |
| ssh | ssh.dumpster.cards | 1 email | — |

- **Login methods:** poke, magic and ssh pin a single login method
  (`292fe014-f659-443f-bea4-3cad9e43e9ca`). The others allow every configured method. Listing
  identity providers returned nothing with the Cubby token, so which method that is (likely
  one-time PIN) is unconfirmed.
- **Cloudflare side** (docs): a generic OIDC provider is configured with `client_id`,
  `client_secret`, `auth_url`, `token_url` and `certs_url`, plus `claims` (e.g. `["groups"]`)
  and `scopes`. Group-based policies need the provider to send a `groups` claim, matched by
  exact name. Policies use the OIDC claims selector, and partial claim-value matching is not
  supported.
- **Pocket ID** (docs): passkey-only sign-in, with an admin-issued one-time login code to
  enrol a first passkey. It has user groups that gate which users may use which OIDC client,
  and tokens carry name, email and groups. Its docs list REST API and SCIM provisioning pages,
  not read here. It ships as a single container or binary.
- **Hosting:** product services run on ubuntu-mini-0 as `ryangantt`, behind Cloudflare
  tunnels (`law-no-product-service-runs-on-the-spira-host`).

## Design

1. **Identity provider: Pocket ID at `id.gantt.pub`.**
   - One Quadlet container on ubuntu-mini-0, pinned version.
   - Data in its own volume, replicated by Litestream (if SQLite) to an `id-*` bucket in the
     CI account, with a dedicated write-only credential.
   - Served through a Cloudflare tunnel. `id.gantt.pub` is **not** behind Access, since a
     login page behind its own login can never be reached.
   - Admin UI restricted to Ryan's account inside Pocket ID.
2. **Cloudflare login method** (Terraform, new `infra/` root, say `identity`, in a new
   `identity` repo).
   - A generic OIDC provider pointing at Pocket ID's endpoints, requesting the `groups` claim.
   - The Pocket ID client secret goes into Terraform from a 0600 credential file, never through
     chat.
3. **Groups**, one per app: `cubby-parents`, `dumpstar-users`, `poke-users`, `magic-users`,
   `ssh-users`, plus `admins` (Ryan).
4. **Policies.**
   - Each app's allow policy becomes "OIDC claim `groups` contains `<group>`, via the Pocket ID
     login method", in Terraform.
   - Service-token policies stay as they are.
   - `cubby-public` stays a bypass.
5. **No Cloudflare chrome for users.** Each app allows exactly one login method, Pocket ID, with
   instant auth (skip identity-provider selection), so Cloudflare redirects straight to
   `id.gantt.pub` and users never see Cloudflare's login page (per Ryan, 2026-10-18: *"i don't
   want users to see the cloudflare login chrome at all. break glass should follow a different
   route"*).
   **Break-glass takes a separate route, outside the Access login flow:**
   - *Lost passkey:* ssh to ubuntu-mini-0 over the tailnet and mint a one-time login code with
     Pocket ID's CLI.
   - *Pocket ID down:* ssh in, restart it or restore from the CI-account backup (the same
     procedure the restore drill exercises).
   - *Down and not quickly fixable:* `breakglass.sh <app>` switches that app to Cloudflare
     one-time PIN for `ryan@gantt.pub` only, raises an alarm while it is active, and
     `breakglass.sh --revert <app>` restores it. It uses a Cloudflare token kept 0600 on the
     host, with no Terraform or MFA, and a reconcile check reports the drift until it is
     reverted.
6. **Migration, app by app.**
   - Create the users, put them in the app's group, flip that app's policy, then verify every
     listed person can sign in.
   - Cubby first (2 people), then dumpstar, ssh, poke, magic.
   - The old email rules are removed only after each app's verification.
7. **Cubby specifics.** The deploy-time `parent_emails` variable from `sp-qerw0g` is replaced
   by the group. Cubby's `family add-parent` still binds an email to a family. Optionally,
   later, Cubby reads the `groups` claim to skip that step.

## Work breakdown

| # | Title | Type | P | Depends on | Acceptance criteria |
|---|---|---|---|---|---|
| 1 | Pocket ID on ubuntu-mini-0 at id.gantt.pub (Quadlet, pinned, tunnel, admin restricted) | feature | P1 | — | Ryan signs in with a passkey; healthcheck green; not behind Access |
| 2 | Identity backups: Litestream to a CI-account bucket + restore drill | feature | P1 | 1 | Drill restores users and groups on a scratch instance |
| 3 | Terraform: Pocket ID as a Cloudflare generic OIDC login method, groups claim | feature | P1 | 1 | Cloudflare's login-method Test shows a `groups` claim for Ryan |
| 4 | Cubby Access policy to group `cubby-parents` with Ryan break-glass | task | P1 | 3 | Kim and Ryan sign in through Pocket ID; a non-member is refused |
| 5 | dumpstar, ssh, poke, magic policies to groups (one change, each verified) | task | P2 | 4 | Every currently listed email still signs in; old email rules removed |
| 6 | Monitoring: an alarm when id.gantt.pub or its OIDC discovery fails | feature | P2 | 1 | Synthetic check alarms within 5 min of an outage |
| 7 | Break-glass: runbook + `breakglass.sh <app>` / `--revert` (one-time PIN for Ryan only), alarm while active | feature | P2 | 4 | Drill: flip Cubby to break-glass, sign in by PIN, revert; alarm raised and cleared |

## Test strategy

- **Terraform test** for each policy: exactly one allow rule (the app's group), exactly one
  allowed login method (Pocket ID) and instant auth on, as Cubby's guarantee test does today.
- **Restore drill:** restore the newest backup into a scratch instance and assert it has the
  same users and groups.
- **Live verification for each app migrated:** a Playwright login through Access with a test
  Pocket ID user in the group, and a refusal for a test user outside it. The test user's login
  code comes from Pocket ID's admin API, never a real person's passkey.
- **Cubby:** the existing walk (`concierge-tools/cubby-uitest`) keeps passing.

## Decisions

- **Pocket ID over Authelia** (per Ryan, 2026-10-18: *"pocket id, although i do like TOTPs, i think the simplicity and passkey option proves more effectively secure"*). Authelia keeps users in a
  YAML file or LDAP with no admin UI, which would move hand-managed lists rather than remove them;
  Pocket ID has a user and group admin UI. Accepted cost: every user needs a passkey-capable device.
- **Kim on passkeys, enrolled with a one-time login code** (default taken, per Ryan 2026-10-18).
- **Removal takes effect at Access session expiry (24h), with manual revoke for urgent cases**
  (default taken).
- **A new `identity` repo** (default taken).
- **Break-glass kept, but on a separate route** (Ryan): never a second login method on the app.
- **Apps sign users in themselves (native OIDC), dropping Access for human paths** (per Ryan,
  2026-10-18, after the first sign-in still showed Cloudflare's interstitial: *"don't hesitate to
  make the bigger OIDC change per app"*). Each app runs the OIDC authorization-code flow (PKCE)
  against Pocket ID with its own client, checks the `groups` claim, and keeps its own session
  cookie. The Access application for its human paths is then removed in Terraform. Service-token
  paths keep an Access application, or move to app-level bearer tokens, so automation is unaffected.
  `ssh.dumpster.cards` stays on Access, since SSH cannot do browser OIDC. The three dumpster sites
  share the implementation through dumpster-kit.

## Open questions (all resolved 2026-10-18; kept for the record)

1. **Pocket ID or Authelia?**
   - Default: Pocket ID, the smaller of the two, passkey-native, with groups in tokens.
   - Authelia supports passwords and TOTP, if anyone can't use passkeys.
2. **Kim on passkeys:** fine for her phone? Default: yes. A Pocket ID one-time login code
   enrols her first passkey.
3. **Removal latency:** with no SCIM, removing someone from a group takes effect when their
   Access session expires (Cubby's is 24h). Acceptable, or shorten the session to 8h? Default:
   keep 24h, and manually revoke the session for an urgent removal.
4. **Where the code lives:** a new `identity` repo, or `infra/` in an existing one? Default: a
   new repo, since it spans every app.
5. **Break-glass:** keep Ryan's one-time PIN rule on every app permanently? Default: yes.
