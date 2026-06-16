output "client_ids" {
  description = "Map of app name to its OIDC client ID"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_id }
}

output "client_secrets" {
  description = "Map of app name to its OIDC client secret"
  value       = { for k, v in okta_app_oauth.oidc : k => v.client_secret }
  sensitive   = true
}
