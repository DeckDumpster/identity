variable "cloudflare_account_id" {
  type = string
}

variable "issuer" {
  type        = string
  default     = "https://id.gantt.pub"
  description = "Pocket ID base URL; the endpoints below derive from it."
}

variable "credentials_file" {
  type        = string
  description = "Path to a 0600 JSON file {\"client_id\": ..., \"client_secret\": ...} for the Pocket ID OIDC client. Read at plan/apply time, never committed."
}

variable "login_method_name" {
  type    = string
  default = "Pocket ID"
}

variable "scopes" {
  type        = list(string)
  default     = ["openid", "email", "profile", "groups"]
  description = "Pocket ID emits the groups claim only when the groups scope is requested."
}

variable "claims" {
  type        = list(string)
  default     = ["groups"]
  description = "Extra OIDC claims Cloudflare keeps for policies; exact group names are matched."
}
