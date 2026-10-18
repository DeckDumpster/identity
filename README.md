# identity

Central sign-in for every app Ryan exposes through Cloudflare Access: one self-hosted OIDC
provider (Pocket ID at `id.gantt.pub`, on ubuntu-mini-0) and per-app groups, so adding or removing
a person never touches an Access policy, Terraform or an MFA code.

- Design (approved 2026-10-18): `docs/design/central-identity-hld-2026-10-18.md`
- Production host: ubuntu-mini-0 (user `ryangantt`); nothing here runs on the Spira box.
