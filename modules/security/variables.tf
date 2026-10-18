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

variable "break_glass" {
  description = "The break-glass admin's own way in: an enrollment policy and a global session policy for its group, both ahead of everyone else's."
  type = object({
    group  = string # a group from config/groups.yaml
    factor = string # authenticator key the break-glass admin enrolls at first sign-in
    # A short session: the account is for emergencies, not for staying signed in.
    session_idle_minutes     = optional(number, 15)
    session_lifetime_minutes = optional(number, 60)
  })

  validation {
    condition     = contains(keys(var.group_ids), var.break_glass.group)
    error_message = "break_glass.group must be a group defined in config/groups.yaml."
  }

  validation {
    condition     = contains([for a in var.authenticators : a.key if a.status == "ACTIVE" && !contains(["okta_password", "okta_email"], a.key)], var.break_glass.factor)
    error_message = "break_glass.factor must be an ACTIVE authenticator in the list, other than okta_password and okta_email."
  }

  validation {
    condition     = var.break_glass.session_idle_minutes > 0 && var.break_glass.session_lifetime_minutes >= var.break_glass.session_idle_minutes
    error_message = "break_glass session minutes must be positive, with the lifetime at least the idle time."
  }
}

variable "session" {
  description = "The global session policy for everyone else, ahead of Okta's Default Policy."
  type = object({
    idle_minutes     = optional(number, 120)
    lifetime_minutes = optional(number, 720) # 0 = no limit
    persistent       = optional(bool, false) # keep the session cookie after the browser closes
  })

  validation {
    condition     = var.session.idle_minutes > 0 && (var.session.lifetime_minutes == 0 || var.session.lifetime_minutes >= var.session.idle_minutes)
    error_message = "session.idle_minutes must be positive, and lifetime_minutes 0 (no limit) or at least the idle time."
  }
}

variable "group_ids" {
  description = "Map of group name to Okta group ID (from the identity module) — used to resolve break_glass.group by name."
  type        = map(string)
}
