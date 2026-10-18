# Each app: exactly one allow rule (its group), exactly one login method (Pocket ID) with
# instant auth, and the service-token policy still attached. Mocked provider, no network.
mock_provider "cloudflare" {}

variables {
  cloudflare_account_id = "acct"
  import_existing       = false
  credentials_file      = "tests/credentials.fixture.json"

  dumpstar = {
    app_id             = "app-dumpstar"
    allow_policy_id    = "pol-dumpstar-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-dumpstar-service"
    service_precedence = 2
  }
  dumpstar_adopt = null

  ssh = {
    app_id             = "app-ssh"
    allow_policy_id    = "pol-ssh-allow"
    allow_precedence   = 1
    service_policy_id  = ""
    service_precedence = 2
  }
  ssh_adopt = null
}

run "dumpstar_on_its_group" {
  command = apply

  assert {
    condition     = length(module.dumpstar.allow_policy.include) == 1 && toset([for r in module.dumpstar.allow_policy.include : "${r.oidc.claim_name}=${r.oidc.claim_value}"]) == toset(["groups=dumpstar-users"])
    error_message = "dumpstar allow policy must be the single rule groups contains dumpstar-users"
  }
  assert {
    condition     = toset([for r in module.dumpstar.allow_policy.include : r.oidc.identity_provider_id]) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "the group rule must come from the Pocket ID login method"
  }
  assert {
    condition     = toset(module.dumpstar.application.allowed_idps) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "dumpstar must allow only the Pocket ID login method"
  }
  assert {
    condition     = module.dumpstar.application.auto_redirect_to_identity == true
    error_message = "dumpstar must skip identity-provider selection"
  }
  assert {
    condition     = contains([for p in module.dumpstar.application.policies : p.id], "pol-dumpstar-service")
    error_message = "the dumpstar service-token policy must stay attached"
  }
  assert {
    condition     = module.dumpstar.application.domain == "star.dumpster.cards"
    error_message = "dumpstar domain"
  }
}

run "dumpstar_adopted_keeps_emails" {
  command = apply

  variables {
    dumpstar_adopt = {
      emails        = ["a@example.com"]
      allowed_idps  = ["idp-old"]
      auto_redirect = false
    }
  }

  assert {
    condition     = length(module.dumpstar.allow_policy.include) == 1 && toset([for r in module.dumpstar.allow_policy.include : r.email.email]) == toset(["a@example.com"])
    error_message = "adoption keeps today's email rule"
  }
  assert {
    condition     = toset(module.dumpstar.application.allowed_idps) == toset(["idp-old"]) && module.dumpstar.application.auto_redirect_to_identity == false
    error_message = "adoption keeps today's login methods"
  }
  assert {
    condition     = contains([for p in module.dumpstar.application.policies : p.id], "pol-dumpstar-service")
    error_message = "the service-token policy must stay attached"
  }
}

