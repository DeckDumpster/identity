terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }
  }

  # Shared state bucket, S3-native locking, deploy role. The bucket and role are per-account,
  # so they come from -backend-config (see README).
  backend "s3" {
    key          = "identity/infra/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "cloudflare" {
  # api_token comes from CLOUDFLARE_API_TOKEN.
}
