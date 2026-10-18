# Pocket ID's ingress. id.gantt.pub must not have an Access application: Cloudflare and every
# relying app call its OIDC endpoints directly (test-infra.sh fails if one is declared here).
resource "cloudflare_zero_trust_tunnel_cloudflared" "identity" {
  account_id = var.cloudflare_account_id
  name       = "identity"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "identity" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.identity.id

  config = {
    ingress = [
      {
        hostname = var.hostname
        service  = var.origin
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_dns_record" "identity" {
  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.identity.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "identity" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.identity.id
}
