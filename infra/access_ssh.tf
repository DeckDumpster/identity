variable "ssh" {
  type = object({
    app_id             = string
    allow_policy_id    = string
    allow_precedence   = number
    service_policy_id  = string
    service_precedence = number
  })
  description = "Existing ssh Access application and policies (read from the Cloudflare API)."
}

variable "ssh_adopt" {
  type = object({
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null: ssh is on its group. Otherwise today's email rule and login methods, for the zero-change adoption plan."
}

module "ssh" {
  source = "./modules/access_app"

  account_id      = var.cloudflare_account_id
  name            = "ssh"
  domain          = "ssh.dumpster.cards"
  group           = "ssh-users"
  login_method_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
  ids             = var.ssh
  adopt           = var.ssh_adopt
}

import {
  for_each = var.import_existing ? toset(["ssh"]) : toset([])
  to       = module.ssh.cloudflare_zero_trust_access_application.this[0]
  id       = local.import_ids.ssh_app
}

import {
  for_each = var.import_existing ? toset(["ssh"]) : toset([])
  to       = module.ssh.cloudflare_zero_trust_access_policy.allow[0]
  id       = local.import_ids.ssh_policy
}
