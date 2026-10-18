# Plan/apply assertions with a mocked provider: no credentials, no network.
mock_provider "cloudflare" {}

variables {
  cloudflare_account_id = "acct"
  cloudflare_zone_id    = "zone"
  import_existing       = false
  access_org_name       = "family"
  access_auth_domain    = "family.cloudflareaccess.com"
  credentials_file      = "tests/credentials.fixture.json"

  dumpstar = {
    app_id             = "app-dumpstar"
    allow_policy_id    = "pol-dumpstar-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-dumpstar-service"
    service_precedence = 2
  }
  dumpstar_adopt = null

  magic = {
    app_id             = "app-magic"
    allow_policy_id    = "pol-magic-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-magic-service"
    service_precedence = 2
  }
  magic_adopt = null

  poke = {
    app_id             = "app-poke"
    allow_policy_id    = "pol-poke-allow"
    allow_precedence   = 1
    service_policy_id  = "pol-poke-service"
    service_precedence = 2
  }
  poke_adopt = null

  ssh = {
    app_id             = "app-ssh"
    allow_policy_id    = "pol-ssh-allow"
    allow_precedence   = 1
    service_policy_id  = ""
    service_precedence = 2
  }
  ssh_adopt = null
}

run "tunnel_routes_the_hostname_to_pocket_id" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared.identity.config_src == "cloudflare"
    error_message = "the tunnel must be remotely managed"
  }
  assert {
    condition = anytrue([
      for r in cloudflare_zero_trust_tunnel_cloudflared_config.identity.config.ingress :
      try(r.hostname == "id.gantt.pub" && r.service == "http://127.0.0.1:1411", false)
    ])
    error_message = "ingress must route id.gantt.pub to http://127.0.0.1:1411"
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.identity.config.ingress[length(cloudflare_zero_trust_tunnel_cloudflared_config.identity.config.ingress) - 1].service == "http_status:404"
    error_message = "the last ingress rule must be the 404 catch-all"
  }
}

run "dns_is_a_proxied_cname_to_the_tunnel" {
  command = apply

  assert {
    condition = alltrue([
      cloudflare_dns_record.identity.type == "CNAME",
      cloudflare_dns_record.identity.name == "id.gantt.pub",
      cloudflare_dns_record.identity.proxied == true,
      cloudflare_dns_record.identity.zone_id == "zone",
      cloudflare_dns_record.identity.content == "${cloudflare_zero_trust_tunnel_cloudflared.identity.id}.cfargotunnel.com",
    ])
    error_message = "id.gantt.pub must be a proxied CNAME to <tunnel id>.cfargotunnel.com"
  }
}

run "tunnel_token_is_sensitive" {
  command = apply

  assert {
    condition     = output.tunnel_token == data.cloudflare_zero_trust_tunnel_cloudflared_token.identity.token
    error_message = "tunnel_token must expose the tunnel's token"
  }
}
