# Groups and the group rules that auto-assign users to them (config/groups.yaml).
module "identity" {
  source = "./modules/identity"
  groups = local.groups
}

# The org's own URLs. Okta API: GET /.well-known/okta-organization (public).
# `alternate` is the custom domain, okta.yuandrk.net, where users' sessions live.
data "okta_org_metadata" "this" {}

# OIDC and SAML apps and bookmark tiles, assigned to groups by name (config/apps.yaml).
module "apps" {
  source    = "./modules/apps"
  apps      = local.apps
  saml_apps = local.saml_apps
  bookmarks = local.bookmarks
  group_ids = module.identity.group_ids
  okta_url  = coalesce(data.okta_org_metadata.this.domains.alternate, data.okta_org_metadata.this.domains.organization)
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
