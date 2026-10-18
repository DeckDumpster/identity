variable "dumpstar" {
  type = object({
    app_id             = string
    allow_policy_id    = string
    allow_precedence   = number
    service_policy_id  = string
    service_precedence = number
  })
  description = "Existing dumpstar Access application and policies (read from the Cloudflare API)."
}

variable "dumpstar_adopt" {
  type = object({
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null: dumpstar is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

module "dumpstar" {
  source = "./modules/access_app"

  account_id      = var.cloudflare_account_id
  name            = "dumpstar"
  domain          = "star.dumpster.cards"
  group           = "dumpstar-users"
  login_method_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
  ids             = var.dumpstar
  adopt           = var.dumpstar_adopt
}

import {
  for_each = var.import_existing ? toset(["dumpstar"]) : toset([])
  to       = module.dumpstar.cloudflare_zero_trust_access_application.this
  id       = "${var.cloudflare_account_id}/${var.dumpstar.app_id}"
}

import {
  for_each = var.import_existing ? toset(["dumpstar"]) : toset([])
  to       = module.dumpstar.cloudflare_zero_trust_access_policy.allow
  id       = "${var.cloudflare_account_id}/${var.dumpstar.allow_policy_id}"
}
