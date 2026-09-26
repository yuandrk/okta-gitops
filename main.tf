# Groups and the group rules that auto-assign users to them (config/groups.yaml).
module "identity" {
  source = "./modules/identity"
  groups = local.org.groups
}

# OIDC apps and bookmark tiles, assigned to groups by name (config/apps.yaml).
module "apps" {
  source    = "./modules/apps"
  apps      = local.apps.apps
  bookmarks = try(local.apps.bookmarks, [])
  group_ids = module.identity.group_ids
}
