locals {
  switched     = var.adopt == null
  keep_app     = var.human_access != "removed"
  keep_allow   = var.human_access == "group"
  narrow       = var.human_access == "service_only"
  app_domain   = local.narrow && var.narrow_domain != "" ? var.narrow_domain : var.domain
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  count = local.keep_allow ? 1 : 0

  account_id = var.account_id
  name       = "${var.name}-allow"
  decision   = "allow"

  include = local.switched ? [{
    oidc = {
      claim_name           = "groups"
      claim_value          = var.group
      identity_provider_id = var.login_method_id
    }
  }] : [for email in var.adopt.emails : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_application" "this" {
  count = local.keep_app ? 1 : 0

  account_id = var.account_id
  name       = var.name
  domain     = local.app_domain
  type       = "self_hosted"

  allowed_idps              = local.switched ? [var.login_method_id] : var.adopt.allowed_idps
  auto_redirect_to_identity = local.switched ? true : var.adopt.auto_redirect

  policies = concat(
    local.keep_allow ? [{ id = cloudflare_zero_trust_access_policy.allow[0].id, precedence = var.ids.allow_precedence }] : [],
    var.ids.service_policy_id == "" ? [] : [{ id = var.ids.service_policy_id, precedence = var.ids.service_precedence }],
  )
}
