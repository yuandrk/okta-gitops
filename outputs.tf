# Who gets what, per managed group: the rule that fills it and the apps/tiles it
# unlocks. `terraform output inventory` — the Terraform half of README's org table.
output "inventory" {
  description = "Per group: the auto-assign rule expression (null if none), and the apps (OIDC and SAML) and bookmarks assigned to it"
  value = {
    for g in keys(module.identity.group_ids) : g => {
      rule      = lookup(module.identity.rules, g, null)
      apps      = try(module.apps.group_access[g].apps, [])
      bookmarks = try(module.apps.group_access[g].bookmarks, [])
    }
  }
}

# OIDC client credentials per managed app — consumed when wiring the app's
# relying party (the app's OIDC config in the homelab repo).
output "oidc_client_ids" {
  description = "Map of app name to OIDC client ID"
  value       = module.apps.client_ids
}

output "oidc_client_secrets" {
  description = "Map of app name to OIDC client secret"
  value       = module.apps.client_secrets
  sensitive   = true
}

# SAML metadata per managed SAML app, on the custom domain: what the SP's "Metadata URL"
# setting takes (Fleet: Settings → Integrations → Authentication (SSO)). Not a secret.
output "saml_metadata_urls" {
  description = "Map of SAML app name to its IdP metadata URL"
  value       = module.apps.saml_metadata_urls
}
