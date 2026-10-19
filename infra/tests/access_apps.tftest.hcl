# Each app: exactly one allow rule (its group), exactly one login method (Pocket ID) with
# instant auth, and the service-token policy still attached. Mocked provider, no network.
mock_provider "cloudflare" {}

variables {
  cloudflare_account_id = "acct"
  cloudflare_zone_id    = "zone"
  import_existing       = false
  access_org_name       = "family"
  access_auth_domain    = "family.cloudflareaccess.com"
  credentials_file      = "tests/credentials.fixture.json"

  dumpstar = {
    app_id             = "app-dumpstar"
    allow_policy_id    = "pol-dumpstar-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-dumpstar-service"
    service_precedence = 2
  }
  dumpstar_adopt = null

  magic = {
    app_id             = "app-magic"
    allow_policy_id    = "pol-magic-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-magic-service"
    service_precedence = 2
  }
  magic_adopt = null

  poke = {
    app_id             = "app-poke"
    allow_policy_id    = "pol-poke-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-poke-service"
    service_precedence = 2
  }
  poke_adopt = null

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
      policy_name   = "dumpstar-allowed-emails"
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
    condition     = module.dumpstar.allow_policy.name != "dumpstar-allow"
    error_message = "adoption keeps the live policy name"
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




run "ssh_on_its_group" {
  command = apply

  assert {
    condition     = length(module.ssh.allow_policy.include) == 1 && toset([for r in module.ssh.allow_policy.include : "${r.oidc.claim_name}=${r.oidc.claim_value}"]) == toset(["groups=ssh-users"])
    error_message = "ssh allow policy must be the single rule groups contains ssh-users"
  }
  assert {
    condition     = toset([for r in module.ssh.allow_policy.include : r.oidc.identity_provider_id]) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "the group rule must come from the Pocket ID login method"
  }
  assert {
    condition     = toset(module.ssh.application.allowed_idps) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "ssh must allow only the Pocket ID login method"
  }
  assert {
    condition     = module.ssh.application.auto_redirect_to_identity == true
    error_message = "ssh must skip identity-provider selection"
  }
  assert {
    condition     = length(module.ssh.application.policies) == 1
    error_message = "ssh has no service-token policy and must get only its allow policy"
  }
  assert {
    condition     = module.ssh.application.domain == "ssh.dumpster.cards"
    error_message = "ssh domain"
  }
}

run "ssh_adopted_keeps_emails" {
  command = apply

  variables {
    ssh_adopt = {
      policy_name   = "only-my-email"
      emails        = ["a@example.com"]
      allowed_idps  = ["idp-old"]
      auto_redirect = false
    }
  }

  assert {
    condition     = length(module.ssh.allow_policy.include) == 1 && toset([for r in module.ssh.allow_policy.include : r.email.email]) == toset(["a@example.com"])
    error_message = "adoption keeps today's email rule"
  }
  assert {
    condition     = module.ssh.allow_policy.name != "ssh-allow"
    error_message = "adoption keeps the live policy name"
  }
  assert {
    condition     = toset(module.ssh.application.allowed_idps) == toset(["idp-old"]) && module.ssh.application.auto_redirect_to_identity == false
    error_message = "adoption keeps today's login methods"
  }
  assert {
    condition     = length(module.ssh.application.policies) == 1
    error_message = "only the allow policy is attached"
  }
}




run "poke_on_its_group" {
  command = apply

  assert {
    condition     = length(module.poke.allow_policy.include) == 1 && toset([for r in module.poke.allow_policy.include : "${r.oidc.claim_name}=${r.oidc.claim_value}"]) == toset(["groups=poke-users"])
    error_message = "poke allow policy must be the single rule groups contains poke-users"
  }
  assert {
    condition     = toset([for r in module.poke.allow_policy.include : r.oidc.identity_provider_id]) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "the group rule must come from the Pocket ID login method"
  }
  assert {
    condition     = toset(module.poke.application.allowed_idps) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "poke must allow only the Pocket ID login method"
  }
  assert {
    condition     = module.poke.application.auto_redirect_to_identity == true
    error_message = "poke must skip identity-provider selection"
  }
  assert {
    condition     = contains([for p in module.poke.application.policies : p.id], "pol-poke-service")
    error_message = "the poke service-token policy must stay attached"
  }
  assert {
    condition     = module.poke.application.domain == "poke.dumpster.cards"
    error_message = "poke domain"
  }
}

run "poke_adopted_keeps_emails" {
  command = apply

  variables {
    poke_adopt = {
      policy_name   = "poke-dumpster-allowed-emails"
      emails        = ["a@example.com"]
      allowed_idps  = ["idp-old"]
      auto_redirect = false
    }
  }

  assert {
    condition     = length(module.poke.allow_policy.include) == 1 && toset([for r in module.poke.allow_policy.include : r.email.email]) == toset(["a@example.com"])
    error_message = "adoption keeps today's email rule"
  }
  assert {
    condition     = module.poke.allow_policy.name != "poke-allow"
    error_message = "adoption keeps the live policy name"
  }
  assert {
    condition     = toset(module.poke.application.allowed_idps) == toset(["idp-old"]) && module.poke.application.auto_redirect_to_identity == false
    error_message = "adoption keeps today's login methods"
  }
  assert {
    condition     = contains([for p in module.poke.application.policies : p.id], "pol-poke-service")
    error_message = "the service-token policy must stay attached"
  }
}




run "magic_on_its_group" {
  command = apply

  assert {
    condition     = length(module.magic.allow_policy.include) == 1 && toset([for r in module.magic.allow_policy.include : "${r.oidc.claim_name}=${r.oidc.claim_value}"]) == toset(["groups=magic-users"])
    error_message = "magic allow policy must be the single rule groups contains magic-users"
  }
  assert {
    condition     = toset([for r in module.magic.allow_policy.include : r.oidc.identity_provider_id]) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "the group rule must come from the Pocket ID login method"
  }
  assert {
    condition     = toset(module.magic.application.allowed_idps) == toset([cloudflare_zero_trust_access_identity_provider.pocket_id.id])
    error_message = "magic must allow only the Pocket ID login method"
  }
  assert {
    condition     = module.magic.application.auto_redirect_to_identity == true
    error_message = "magic must skip identity-provider selection"
  }
  assert {
    condition     = contains([for p in module.magic.application.policies : p.id], "pol-magic-service")
    error_message = "the magic service-token policy must stay attached"
  }
  assert {
    condition     = module.magic.application.domain == "magic.dumpster.cards"
    error_message = "magic domain"
  }
}

run "magic_adopted_keeps_emails" {
  command = apply

  variables {
    magic_adopt = {
      policy_name   = "deck-dumpster-allowed-emails"
      emails        = ["a@example.com"]
      allowed_idps  = ["idp-old"]
      auto_redirect = false
    }
  }

  assert {
    condition     = length(module.magic.allow_policy.include) == 1 && toset([for r in module.magic.allow_policy.include : r.email.email]) == toset(["a@example.com"])
    error_message = "adoption keeps today's email rule"
  }
  assert {
    condition     = module.magic.allow_policy.name != "magic-allow"
    error_message = "adoption keeps the live policy name"
  }
  assert {
    condition     = toset(module.magic.application.allowed_idps) == toset(["idp-old"]) && module.magic.application.auto_redirect_to_identity == false
    error_message = "adoption keeps today's login methods"
  }
  assert {
    condition     = contains([for p in module.magic.application.policies : p.id], "pol-magic-service")
    error_message = "the service-token policy must stay attached"
  }
}




run "dumpstar_native_service_only" {
  command = apply

  variables {
    dumpstar_human_access  = "service_only"
    dumpstar_narrow_domain = "star.dumpster.cards/api"
  }

  assert {
    condition     = module.dumpstar.allow_policy == null
    error_message = "dumpstar signs in natively: no human allow policy"
  }
  assert {
    condition     = [for p in module.dumpstar.application.policies : p.id] == ["pol-dumpstar-service"]
    error_message = "only the dumpstar service-token policy stays attached"
  }
  assert {
    condition     = module.dumpstar.application.domain == "star.dumpster.cards/api"
    error_message = "the narrow dumpstar application covers only the service-token path"
  }
}

run "dumpstar_native_removed" {
  command = apply

  variables {
    dumpstar_human_access = "removed"
  }

  assert {
    condition     = module.dumpstar.application == null && module.dumpstar.allow_policy == null
    error_message = "dumpstar signs in natively: no Access application"
  }
}

run "poke_native_service_only" {
  command = apply

  variables {
    poke_human_access  = "service_only"
    poke_narrow_domain = "poke.dumpster.cards/api"
  }

  assert {
    condition     = module.poke.allow_policy == null
    error_message = "poke signs in natively: no human allow policy"
  }
  assert {
    condition     = [for p in module.poke.application.policies : p.id] == ["pol-poke-service"]
    error_message = "only the poke service-token policy stays attached"
  }
  assert {
    condition     = module.poke.application.domain == "poke.dumpster.cards/api"
    error_message = "the narrow poke application covers only the service-token path"
  }
}

run "poke_native_removed" {
  command = apply

  variables {
    poke_human_access = "removed"
  }

  assert {
    condition     = module.poke.application == null && module.poke.allow_policy == null
    error_message = "poke signs in natively: no Access application"
  }
}

run "magic_native_service_only" {
  command = apply

  variables {
    magic_human_access  = "service_only"
    magic_narrow_domain = "magic.dumpster.cards/api"
  }

  assert {
    condition     = module.magic.allow_policy == null
    error_message = "magic signs in natively: no human allow policy"
  }
  assert {
    condition     = [for p in module.magic.application.policies : p.id] == ["pol-magic-service"]
    error_message = "only the magic service-token policy stays attached"
  }
  assert {
    condition     = module.magic.application.domain == "magic.dumpster.cards/api"
    error_message = "the narrow magic application covers only the service-token path"
  }
}

run "magic_native_removed" {
  command = apply

  variables {
    magic_human_access = "removed"
  }

  assert {
    condition     = module.magic.application == null && module.magic.allow_policy == null
    error_message = "magic signs in natively: no Access application"
  }
}

run "ssh_keeps_group_policy_when_apps_are_native" {
  command = apply

  variables {
    dumpstar_human_access = "removed"
    poke_human_access     = "removed"
    magic_human_access    = "removed"
  }

  assert {
    condition     = toset([for r in module.ssh.allow_policy.include : r.oidc.claim_value]) == toset(["ssh-users"]) && module.ssh.application.domain == "ssh.dumpster.cards"
    error_message = "ssh stays on Access with its group policy"
  }
}

# The provider rejects "<account_id>/<id>"; apps take accounts/<account_id>/<id>, policies <account_id>/<id>, the org <account_id>.
run "import_ids_use_the_providers_format" {
  command = plan

  assert {
    condition = local.import_ids == {
      org             = "acct"
      dumpstar_app    = "accounts/acct/app-dumpstar"
      dumpstar_policy = "acct/pol-dumpstar-allow"
      magic_app       = "accounts/acct/app-magic"
      magic_policy    = "acct/pol-magic-allow"
      poke_app        = "accounts/acct/app-poke"
      poke_policy     = "acct/pol-poke-allow"
      ssh_app         = "accounts/acct/app-ssh"
      ssh_policy      = "acct/pol-ssh-allow"
    }
    error_message = "apps import as accounts/<account_id>/<id>, policies as <account_id>/<id>, the org as <account_id>"
  }
}

# Adopting leaves the live login page alone so the import plans zero changes.
run "org_login_design_untouched_while_adopting" {
  command = plan

  variables {
    import_existing = true
  }

  assert {
    condition     = cloudflare_zero_trust_organization.this.login_design == null
    error_message = "adoption must not rewrite the org login design"
  }
}
