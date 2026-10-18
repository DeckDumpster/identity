# Plan-only assertions with a mocked provider: no credentials, no network.
mock_provider "cloudflare" {}

variables {
  cloudflare_account_id = "acct"
  cloudflare_zone_id    = "zone"
  credentials_file      = "tests/credentials.fixture.json"
}

run "oidc_login_method_carries_groups" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.pocket_id.type == "oidc"
    error_message = "must be a generic OIDC login method"
  }
  assert {
    condition     = contains(cloudflare_zero_trust_access_identity_provider.pocket_id.config.claims, "groups")
    error_message = "claims must include groups"
  }
  assert {
    condition     = toset(cloudflare_zero_trust_access_identity_provider.pocket_id.config.scopes) == toset(["openid", "email", "profile", "groups"])
    error_message = "scopes must be openid email profile groups"
  }
  assert {
    condition = alltrue([
      cloudflare_zero_trust_access_identity_provider.pocket_id.config.auth_url == "https://id.gantt.pub/authorize",
      cloudflare_zero_trust_access_identity_provider.pocket_id.config.token_url == "https://id.gantt.pub/api/oidc/token",
      cloudflare_zero_trust_access_identity_provider.pocket_id.config.certs_url == "https://id.gantt.pub/.well-known/jwks.json",
    ])
    error_message = "endpoints must derive from https://id.gantt.pub"
  }
  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.pocket_id.config.client_id == "fixture-client-id"
    error_message = "client id must come from the credentials file"
  }
}

run "no_secret_in_outputs" {
  command = apply

  assert {
    condition     = length(regexall("fixture-client-secret", jsonencode(output.login_method_id))) == 0
    error_message = "the client secret must not appear in outputs"
  }
}
