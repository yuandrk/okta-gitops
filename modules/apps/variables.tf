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
    # SPEC/CUSTOM enable it and require login_uri (+ login_scopes for the id_token).
    login_mode   = optional(string, "DISABLED")
    login_scopes = optional(list(string), [])
    login_uri    = optional(string)
    groups       = optional(list(string), [])
    signon_policy = object({
      name        = string
      description = optional(string)
      rule_name   = optional(string, "Allow password")
    })
  }))
}

variable "group_ids" {
  description = "Map of group name to Okta group ID (from the identity module) — used to resolve group assignments by name."
  type        = map(string)
}
