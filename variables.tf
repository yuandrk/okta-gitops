variable "org_name" {
  description = "Okta org subdomain (everything before .okta.com)"
  type        = string
}

variable "base_url" {
  description = "Okta domain — 'okta.com' for production orgs, 'oktapreview.com' for preview"
  type        = string
  default     = "okta.com"
}

variable "api_token" {
  description = "Okta API token — generate in Admin Console → Security → API → Tokens"
  type        = string
  sensitive   = true # prevents the value from appearing in plan/apply output and state diffs
}
