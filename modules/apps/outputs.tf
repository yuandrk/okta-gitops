output "group_access" {
  description = "Map of group name to the apps (OIDC and SAML) and bookmarks assigned to it (only groups with at least one)"
  value = {
    for g in distinct([for p in concat(values(local.app_group_pairs), values(local.saml_app_group_pairs), values(local.bookmark_group_pairs)) : p.group]) : g => {
      apps      = sort([for p in concat(values(local.app_group_pairs), values(local.saml_app_group_pairs)) : p.app if p.group == g])
      bookmarks = sort([for p in values(local.bookmark_group_pairs) : p.app if p.group == g])
    }
  }
}

output "client_ids" {
  description = "Map of app name to its OIDC client ID"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_id }
}

output "client_secrets" {
  description = "Map of app name to its OIDC client secret (confidential clients only: a public client has none)"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_secret if local.apps_by_name[k].token_endpoint_auth_method != "none" }
  sensitive   = true
}

# Not the provider's metadata_url: that's the API path /api/v1/apps/{id}/sso/saml/metadata,
# which wants an API token. This one is public, on the custom domain.
output "saml_metadata_urls" {
  description = "Map of SAML app name to its IdP metadata URL on the org's custom domain, for the SP's \"Metadata URL\" setting"
  value       = { for k, v in okta_app_saml.saml : k => "${var.okta_url}/app/${v.entity_key}/sso/saml/metadata" }
}
