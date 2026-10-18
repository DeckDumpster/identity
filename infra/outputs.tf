output "login_method_id" {
  description = "Pocket ID login method id, for app policies' allowed_idps and OIDC claim rules."
  value       = cloudflare_zero_trust_access_identity_provider.pocket_id.id
}

output "tunnel_token" {
  description = "cloudflared token for the identity tunnel; goes into ~/.config/identity/cloudflared-id.env."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.identity.token
  sensitive   = true
}
