output "application" {
  value = cloudflare_zero_trust_access_application.this
}

output "allow_policy" {
  value = cloudflare_zero_trust_access_policy.allow
}
