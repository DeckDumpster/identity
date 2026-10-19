output "application" {
  value = one(cloudflare_zero_trust_access_application.this[*])
}

output "allow_policy" {
  value = one(cloudflare_zero_trust_access_policy.allow[*])
}
