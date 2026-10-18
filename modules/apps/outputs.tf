output "group_access" {
  description = "Map of group name to the OIDC apps and bookmarks assigned to it (only groups with at least one)"
  value = {
    for g in distinct([for p in concat(values(local.app_group_pairs), values(local.bookmark_group_pairs)) : p.group]) : g => {
      apps      = sort([for p in values(local.app_group_pairs) : p.app if p.group == g])
      bookmarks = sort([for p in values(local.bookmark_group_pairs) : p.app if p.group == g])
    }
  }
}

output "client_ids" {
  description = "Map of app name to its OIDC client ID"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_id }
}

output "client_secrets" {
  description = "Map of app name to its OIDC client secret"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_secret }
  sensitive   = true
}
