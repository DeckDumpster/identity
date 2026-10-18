variable "poke" {
  type = object({
    app_id             = string
    allow_policy_id    = string
    allow_precedence   = number
    service_policy_id  = string
    service_precedence = number
  })
  description = "Existing poke Access application and policies (read from the Cloudflare API)."
}

variable "poke_adopt" {
  type = object({
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null: poke is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

module "poke" {
  source = "./modules/access_app"

  account_id      = var.cloudflare_account_id
  name            = "poke"
  domain          = "poke.dumpster.cards"
  group           = "poke-users"
  login_method_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
  ids             = var.poke
  adopt           = var.poke_adopt
}

import {
  for_each = var.import_existing ? toset(["poke"]) : toset([])
  to       = module.poke.cloudflare_zero_trust_access_application.this
  id       = "${var.cloudflare_account_id}/${var.poke.app_id}"
}

import {
  for_each = var.import_existing ? toset(["poke"]) : toset([])
  to       = module.poke.cloudflare_zero_trust_access_policy.allow
  id       = "${var.cloudflare_account_id}/${var.poke.allow_policy_id}"
}
