variable "apps" {
  description = "List of OIDC app integrations to manage. Each app gets an okta_app_oauth, a dedicated sign-on policy + rule, and group assignments."
  type = list(object({
    name                      = string
    type                      = optional(string, "web")
    grant_types               = optional(list(string), ["authorization_code"])
    response_types            = optional(list(string), ["code"])
    redirect_uris             = list(string)
    post_logout_redirect_uris = optional(list(string), [])
    refresh_token_leeway      = optional(number, 0)
    consent_method            = optional(string, "TRUSTED")
    issuer_mode               = optional(string, "ORG_URL")
    hide_ios                  = optional(bool, true)
    hide_web                  = optional(bool, true)
    # IdP-initiated sign-on. login_mode DISABLED (default) = no IdP-initiated login;
    # SPEC/OKTA enable it and require login_uri (+ login_scopes for the id_token).
    login_mode   = optional(string, "DISABLED")
    login_scopes = optional(list(string), [])
    login_uri    = optional(string)
    groups       = optional(list(string), [])
    # How the client authenticates at the token endpoint. Some RPs (e.g. Kite) only
    # send client_id/secret in the POST body and need client_secret_post.
    token_endpoint_auth_method = optional(string, "client_secret_basic")
    # Groups claim in the ID token (org authorization server). FILTER + REGEX
    # includes every group of the user whose name matches `value`.
    groups_claim = optional(object({
      name        = optional(string, "groups")
      type        = optional(string, "FILTER")
      filter_type = optional(string, "REGEX")
      value       = string
    }))
    signon_policy = object({
      name        = string
      description = string # required by okta_app_signon_policy
      rule_name   = optional(string, "Require MFA")
      # 2FA = password + a second factor (Okta Verify, TOTP, …). Secure by default;
      # set "1FA" only for apps where a password alone is acceptable.
      factor_mode = optional(string, "2FA")
      # How long a sign-in is trusted before Okta asks again (ISO-8601 duration).
      re_authentication_frequency = optional(string, "PT12H")
    })
  }))

  validation {
    condition     = length(distinct([for a in var.apps : a.name])) == length(var.apps)
    error_message = "App names must be unique — the name is the for_each key (state address)."
  }

  validation {
    condition     = alltrue([for a in var.apps : contains(["web", "native", "browser", "service"], a.type)])
    error_message = "App type must be one of: web, native, browser, service."
  }

  validation {
    condition     = alltrue([for a in var.apps : contains(["ORG_URL", "CUSTOM_URL", "DYNAMIC"], a.issuer_mode)])
    error_message = "issuer_mode must be one of: ORG_URL, CUSTOM_URL, DYNAMIC."
  }

  validation {
    condition     = alltrue([for a in var.apps : contains(["DISABLED", "SPEC", "OKTA"], a.login_mode)])
    error_message = "login_mode must be one of: DISABLED, SPEC, OKTA."
  }

  validation {
    condition     = alltrue([for a in var.apps : contains(["client_secret_basic", "client_secret_post"], a.token_endpoint_auth_method)])
    error_message = "token_endpoint_auth_method must be client_secret_basic or client_secret_post (the module manages confidential clients only)."
  }

  validation {
    condition     = alltrue([for a in var.apps : contains(["1FA", "2FA"], a.signon_policy.factor_mode)])
    error_message = "signon_policy.factor_mode must be one of: 1FA, 2FA."
  }

  validation {
    condition     = alltrue([for a in var.apps : can(regex("^PT[0-9]+[HM]$", a.signon_policy.re_authentication_frequency))])
    error_message = "signon_policy.re_authentication_frequency must be an ISO-8601 duration in hours or minutes, e.g. PT12H or PT30M."
  }

  validation {
    condition     = alltrue([for a in var.apps : a.login_mode == "DISABLED" || a.login_uri != null])
    error_message = "login_uri is required when login_mode is not DISABLED (IdP-initiated login needs a target)."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.apps : [for g in a.groups : contains(keys(var.group_ids), g)]
    ]))
    error_message = "Every group in apps[*].groups must be a group defined in config/groups.yaml. Unknown: ${join(", ", distinct(flatten([for a in var.apps : [for g in a.groups : "${a.name} → ${g}" if !contains(keys(var.group_ids), g)]])))}."
  }
}

variable "group_ids" {
  description = "Map of group name to Okta group ID (from the identity module) — used to resolve group assignments by name."
  type        = map(string)
}

# Bookmark apps are plain dashboard tiles — a label and a URL, no OIDC, no secrets.
# Used when an app can't get a tile of its own: Okta only offers IdP-initiated login
# (and therefore a tile) to Web/SPA OIDC apps, so a `native` public client like the
# Hermes dashboard is invisible on the end-user dashboard no matter how it's configured.
# A bookmark sidesteps that without touching the real app's type or credentials.
variable "bookmarks" {
  description = "List of bookmark (link-only) apps. Each produces an okta_app_bookmark plus group assignments."
  type = list(object({
    label  = string
    url    = string
    groups = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for b in var.bookmarks : b.label])) == length(var.bookmarks)
    error_message = "Bookmark labels must be unique — the label is the for_each key (state address)."
  }

  validation {
    condition     = alltrue([for b in var.bookmarks : startswith(b.url, "https://")])
    error_message = "Bookmark url must start with https://."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.bookmarks : [for g in b.groups : contains(keys(var.group_ids), g)]
    ]))
    error_message = "Every group in bookmarks[*].groups must be a group defined in config/groups.yaml. Unknown: ${join(", ", distinct(flatten([for b in var.bookmarks : [for g in b.groups : "${b.label} → ${g}" if !contains(keys(var.group_ids), g)]])))}."
  }
}
