# The zone redirects http to https and sends HSTS without includeSubDomains or preload.
mock_provider "cloudflare" {}

variables {
  cloudflare_zone_id = "zone"
}

run "https_only" {
  command = plan

  assert {
    condition     = cloudflare_zone_setting.always_use_https.value == "on"
    error_message = "always_use_https must be on"
  }

  assert {
    condition     = cloudflare_zone_setting.hsts.value.strict_transport_security.enabled
    error_message = "HSTS must be enabled"
  }

  assert {
    condition     = cloudflare_zone_setting.hsts.value.strict_transport_security.max_age == 31536000
    error_message = "HSTS max_age must be 31536000"
  }

  assert {
    condition     = cloudflare_zone_setting.hsts.value.strict_transport_security.include_subdomains == false
    error_message = "HSTS must not set includeSubDomains"
  }

  assert {
    condition     = cloudflare_zone_setting.hsts.value.strict_transport_security.preload == false
    error_message = "HSTS must not set preload"
  }
}
