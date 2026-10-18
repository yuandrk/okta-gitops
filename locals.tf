# config/*.yaml are plain text — group names, rule expressions, and app config are
# not secrets. Users are the source of truth and are created in the Admin Console
# (or via SCIM/HRIS); group rules sort them into groups by profile attributes.
locals {
  groups_config   = yamldecode(file("${path.module}/config/groups.yaml"))
  apps_config     = yamldecode(file("${path.module}/config/apps.yaml"))
  security_config = yamldecode(file("${path.module}/config/security.yaml"))

  groups         = local.groups_config.groups
  apps           = local.apps_config.apps
  bookmarks      = try(local.apps_config.bookmarks, []) # optional section
  authenticators = local.security_config.authenticators
  enrollment     = try(local.security_config.enrollment, {})
  break_glass    = local.security_config.break_glass
  session        = local.security_config.session
}
