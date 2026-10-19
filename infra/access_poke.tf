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
    policy_name                = string
    emails                     = list(string)
    allowed_idps               = list(string)
    auto_redirect              = bool
    session_duration           = string
    http_only_cookie_attribute = bool
  })
  nullable    = true
  description = "Null: poke is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

variable "poke_human_access" {
  type        = string
  default     = "group"
  description = "group, service_only or removed: set once poke signs users in natively against Pocket ID and is verified. See modules/access_app."
}

variable "poke_narrow_domain" {
  type        = string
  default     = ""
  description = "Hostname and path of the narrow service-token application when poke_human_access is service_only."
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
  human_access    = var.poke_human_access
  narrow_domain   = var.poke_narrow_domain
}

import {
  for_each = var.import_existing && var.poke_human_access != "removed" ? toset(["poke"]) : toset([])
  to       = module.poke.cloudflare_zero_trust_access_application.this[0]
  id       = local.import_ids.poke_app
}

import {
  for_each = var.import_existing && var.poke_human_access == "group" ? toset(["poke"]) : toset([])
  to       = module.poke.cloudflare_zero_trust_access_policy.allow[0]
  id       = local.import_ids.poke_policy
}
