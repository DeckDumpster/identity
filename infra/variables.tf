variable "cloudflare_account_id" {
  type = string
}

variable "issuer" {
  type        = string
  default     = "https://id.gantt.pub"
  description = "Pocket ID base URL; the endpoints below derive from it."
}

variable "credentials_file" {
  type        = string
  description = "Path to a 0600 JSON file {\"client_id\": ..., \"client_secret\": ...} for the Pocket ID OIDC client. Read at plan/apply time, never committed."
}

variable "login_method_name" {
  type    = string
  default = "Pocket ID"
}

variable "scopes" {
  type        = list(string)
  default     = ["openid", "email", "profile", "groups"]
  description = "Pocket ID emits the groups claim only when the groups scope is requested."
}

variable "claims" {
  type        = list(string)
  default     = ["groups"]
  description = "Extra OIDC claims Cloudflare keeps for policies; exact group names are matched."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone id of gantt.pub."
}

variable "hostname" {
  type        = string
  default     = "id.gantt.pub"
  description = "Public hostname of Pocket ID."
}

variable "origin" {
  type        = string
  default     = "http://127.0.0.1:1411"
  description = "Where cloudflared reaches Pocket ID on ubuntu-mini-0."
}

variable "import_existing" {
  type        = bool
  description = "True while adopting the existing Access apps and policies (import blocks active). False once they are in state; the mocked-provider tests cannot import."
}

locals {
  # The provider's import ID for an account-scoped resource is "accounts/<account_id>/<id>"; the bare
  # "<account_id>/<id>" is rejected as an invalid ID. The organization's ID is "accounts/<account_id>".
  account_scope = "accounts/${var.cloudflare_account_id}"
  import_ids = {
    org             = local.account_scope
    dumpstar_app    = "${local.account_scope}/${var.dumpstar.app_id}"
    dumpstar_policy = "${local.account_scope}/${var.dumpstar.allow_policy_id}"
    magic_app       = "${local.account_scope}/${var.magic.app_id}"
    magic_policy    = "${local.account_scope}/${var.magic.allow_policy_id}"
    poke_app        = "${local.account_scope}/${var.poke.app_id}"
    poke_policy     = "${local.account_scope}/${var.poke.allow_policy_id}"
    ssh_app         = "${local.account_scope}/${var.ssh.app_id}"
    ssh_policy      = "${local.account_scope}/${var.ssh.allow_policy_id}"
  }
}
