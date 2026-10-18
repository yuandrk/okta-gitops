variable "authenticators" {
  description = "Authenticators to manage, keyed by `key`. Okta never deletes one: creating it adopts the existing authenticator, and destroying it deactivates it."
  type = list(object({
    key  = string
    name = string # display name, as in Security → Authenticators
    # INACTIVE fails while any policy still uses the authenticator.
    status = optional(string, "ACTIVE")
  }))

  validation {
    condition     = length(distinct([for a in var.authenticators : a.key])) == length(var.authenticators)
    error_message = "Authenticator keys must be unique — the key is the for_each key (state address)."
  }

  validation {
    condition     = alltrue([for a in var.authenticators : contains(local.authenticator_keys, a.key)])
    error_message = "Authenticator key must be one of: ${join(", ", local.authenticator_keys)}."
  }

  validation {
    condition     = alltrue([for a in var.authenticators : contains(["ACTIVE", "INACTIVE"], a.status)])
    error_message = "Authenticator status must be ACTIVE or INACTIVE."
  }
}

variable "enrollment" {
  description = "Default authenticator enrollment policy: authenticator key → REQUIRED, OPTIONAL or NOT_ALLOWED. A key left out isn't set on the policy."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.enrollment) : contains(local.authenticator_keys, k)])
    error_message = "Enrollment keys must be authenticator keys: ${join(", ", local.authenticator_keys)}."
  }

  validation {
    condition     = alltrue([for v in values(var.enrollment) : contains(["REQUIRED", "OPTIONAL", "NOT_ALLOWED"], v)])
    error_message = "Enrollment values must be REQUIRED, OPTIONAL or NOT_ALLOWED."
  }
}
