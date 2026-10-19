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
    policy_name   = string
    emails        = list(string)
    allowed_idps  = list(string)
    auto_redirect = bool
  })
  nullable    = true
  description = "Null switches the app to its group. Otherwise the allow policy keeps today's name and email rule and the app keeps today's login methods, so the import plans zero changes."
}

variable "human_access" {
  type        = string
  default     = "group"
  description = "How the app treats human paths. group: Access gates them on the app's group. service_only: the app signs users in itself, so the allow policy goes and only the service-token policy stays attached (on narrow_domain when set). removed: the Access application goes entirely."
  validation {
    condition     = contains(["group", "service_only", "removed"], var.human_access)
    error_message = "human_access must be group, service_only or removed."
  }
  validation {
    condition     = var.human_access != "service_only" || var.ids.service_policy_id != ""
    error_message = "service_only needs a service-token policy to keep; use removed for an app without one."
  }
}

variable "narrow_domain" {
  type        = string
  default     = ""
  description = "Hostname and path the narrow service_only application covers; empty keeps the app's domain."
}
