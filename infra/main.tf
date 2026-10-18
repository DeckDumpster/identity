locals {
  credentials = jsondecode(file(pathexpand(var.credentials_file)))
}

# Endpoints are Pocket ID's discovery values (https://id.gantt.pub/.well-known/openid-configuration);
# the Concierge confirms them against the live document before applying (README).
resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = var.cloudflare_account_id
  name       = var.login_method_name
  type       = "oidc"

  config = {
    client_id     = local.credentials.client_id
    client_secret = local.credentials.client_secret
    auth_url      = "${var.issuer}/authorize"
    token_url     = "${var.issuer}/api/oidc/token"
    certs_url     = "${var.issuer}/.well-known/jwks.json"
    scopes        = var.scopes
    claims        = var.claims
  }
}
