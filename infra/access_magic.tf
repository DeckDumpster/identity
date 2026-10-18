variable "magic" {
  type = object({
    app_id             = string
    allow_policy_id    = string
    allow_precedence   = number
    service_policy_id  = string
    service_precedence = number
  })
  description = "Existing magic Access application and policies (read from the Cloudflare API)."
}

variable "magic_adopt" {
  type = object({
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null: magic is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

module "magic" {
  source = "./modules/access_app"

  account_id      = var.cloudflare_account_id
  name            = "magic"
  domain          = "magic.dumpster.cards"
  group           = "magic-users"
  login_method_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
  ids             = var.magic
  adopt           = var.magic_adopt
}

import {
  for_each = var.import_existing ? toset(["magic"]) : toset([])
  to       = module.magic.cloudflare_zero_trust_access_application.this
  id       = "${var.cloudflare_account_id}/${var.magic.app_id}"
}

import {
  for_each = var.import_existing ? toset(["magic"]) : toset([])
  to       = module.magic.cloudflare_zero_trust_access_policy.allow
  id       = "${var.cloudflare_account_id}/${var.magic.allow_policy_id}"
}
