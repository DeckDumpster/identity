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
    policy_name   = string
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null: dumpstar is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

variable "dumpstar_human_access" {
  type        = string
  default     = "group"
  description = "group, service_only or removed: set once dumpstar signs users in natively against Pocket ID and is verified. See modules/access_app."
}

variable "dumpstar_narrow_domain" {
  type        = string
  default     = ""
  description = "Hostname and path of the narrow service-token application when dumpstar_human_access is service_only."
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
  human_access    = var.dumpstar_human_access
  narrow_domain   = var.dumpstar_narrow_domain
}

import {
  for_each = var.import_existing && var.dumpstar_human_access != "removed" ? toset(["dumpstar"]) : toset([])
  to       = module.dumpstar.cloudflare_zero_trust_access_application.this[0]
  id       = local.import_ids.dumpstar_app
}

import {
  for_each = var.import_existing && var.dumpstar_human_access == "group" ? toset(["dumpstar"]) : toset([])
  to       = module.dumpstar.cloudflare_zero_trust_access_policy.allow[0]
  id       = local.import_ids.dumpstar_policy
}
