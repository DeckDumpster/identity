variable "account_id" {
  type = string
}

variable "name" {
  type = string
}

variable "domain" {
  type = string
}

variable "group" {
  type        = string
  description = "Pocket ID group whose members may reach the app; matched exactly against the groups claim."
}

variable "login_method_id" {
  type        = string
  description = "The Pocket ID login method: the only one the app allows once switched."
}

variable "ids" {
  type = object({
    app_id             = string
    allow_policy_id    = string
    allow_precedence   = number
    service_policy_id  = string
    service_precedence = number
  })
  description = "Existing Access objects. service_policy_id is empty for an app with no service-token policy; that policy is referenced, never managed."
}

variable "adopt" {
  type = object({
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null switches the app to its group. Otherwise the allow policy keeps today's email rule and the app keeps today's login methods, so the import plans zero changes."
}
