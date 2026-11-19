# Zone-wide settings for dumpster.cards. A zone setting always exists, so applying creates
# nothing in Cloudflare: it updates the setting.

# Plain-http requests get a 301 to the same URL on https at the edge, before any tunnel or site.
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# include_subdomains is off: on star.dumpster.cards it would cover only names below it
# (*.star.dumpster.cards), and none exist (the edge certificate covers one label). Only an
# HSTS header sent by the apex would cover sibling hostnames, and the apex has no record.
# Turn it on only once every hostname in the zone is confirmed https. Preload is out of scope.
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 31536000
      include_subdomains = false
      preload            = false
      nosniff            = false
    }
  }
}
