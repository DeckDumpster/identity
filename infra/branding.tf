variable "access_org_name" {
  type        = string
  description = "Name of the Zero Trust organization (its team name), kept as it is today."
}

variable "access_auth_domain" {
  type        = string
  description = "The organization's <team>.cloudflareaccess.com domain, kept as it is today."
}

locals {
  # One palette and one set of words for both sign-in screens: deploy/branding/branding.json is
  # read here and by deploy/apply-branding.sh, which sets Pocket ID's appearance from it.
  branding = jsondecode(file("${path.module}/../deploy/branding/branding.json"))
}

# The Access login page is served by Cloudflare and cannot be skipped, so it is branded to match.
# The logo is the one Pocket ID serves (uploaded from deploy/branding/logo.svg), so both screens
# show the same file.
resource "cloudflare_zero_trust_organization" "this" {
  account_id  = var.cloudflare_account_id
  name        = var.access_org_name
  auth_domain = var.access_auth_domain

  login_design = {
    logo_path        = "${var.issuer}/api/application-images/logo"
    header_text      = local.branding.header_text
    footer_text      = local.branding.footer_text
    background_color = local.branding.background_color
    text_color       = local.branding.text_color
  }
}

import {
  for_each = var.import_existing ? toset(["org"]) : toset([])
  to       = cloudflare_zero_trust_organization.this
  id       = local.import_ids.org
}
