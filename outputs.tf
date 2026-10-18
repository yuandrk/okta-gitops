# Who gets what, per managed group: the rule that fills it and the apps/tiles it
# unlocks. `terraform output inventory` — the Terraform half of README's org table.
output "inventory" {
  description = "Per group: the auto-assign rule expression (null if none), and the OIDC apps and bookmarks assigned to it"
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
