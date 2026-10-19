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

variable "magic_human_access" {
  type        = string
  default     = "group"
  description = "group, service_only or removed: set once magic signs users in natively against Pocket ID and is verified. See modules/access_app."
}

variable "magic_narrow_domain" {
  type        = string
  default     = ""
  description = "Hostname and path of the narrow service-token application when magic_human_access is service_only."
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
  human_access    = var.magic_human_access
  narrow_domain   = var.magic_narrow_domain
}

import {
  for_each = var.import_existing && var.magic_human_access != "removed" ? toset(["magic"]) : toset([])
  to       = module.magic.cloudflare_zero_trust_access_application.this[0]
  id       = local.import_ids.magic_app
}

import {
  for_each = var.import_existing && var.magic_human_access == "group" ? toset(["magic"]) : toset([])
  to       = module.magic.cloudflare_zero_trust_access_policy.allow[0]
  id       = local.import_ids.magic_policy
}
