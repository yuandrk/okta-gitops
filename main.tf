# Groups and the group rules that auto-assign users to them (config/groups.yaml).
module "identity" {
  source = "./modules/identity"
  groups = local.groups
}

# OIDC apps and bookmark tiles, assigned to groups by name (config/apps.yaml).
module "apps" {
  source    = "./modules/apps"
  apps      = local.apps
  bookmarks = local.bookmarks
  group_ids = module.identity.group_ids
}

# Authenticators, enrollment and global session policies, and the break-glass
# admin's way in (config/security.yaml).
module "security" {
  source         = "./modules/security"
  authenticators = local.authenticators
  enrollment     = local.enrollment
  break_glass    = local.break_glass
  session        = local.session
  group_ids      = module.identity.group_ids
}
