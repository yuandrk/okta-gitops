# OIDC client credentials per managed app — consumed when wiring the app's
# relying party (e.g. Headlamp's OIDC config in the homelab repo).
output "oidc_client_ids" {
  description = "Map of app name to OIDC client ID"
  value       = module.apps.client_ids
}

output "oidc_client_secrets" {
  description = "Map of app name to OIDC client secret"
  value       = module.apps.client_secrets
  sensitive   = true
}
