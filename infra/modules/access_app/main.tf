locals {
  switched = var.adopt == null
}

resource "cloudflare_zero_trust_access_policy" "allow" {
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
  account_id = var.account_id
  name       = var.name
  domain     = var.domain
  type       = "self_hosted"

  allowed_idps              = local.switched ? [var.login_method_id] : var.adopt.allowed_idps
  auto_redirect_to_identity = local.switched ? true : var.adopt.auto_redirect

  policies = concat(
    [{ id = cloudflare_zero_trust_access_policy.allow.id, precedence = var.ids.allow_precedence }],
    var.ids.service_policy_id == "" ? [] : [{ id = var.ids.service_policy_id, precedence = var.ids.service_precedence }],
  )
}
