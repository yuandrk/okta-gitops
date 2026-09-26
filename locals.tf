# config/*.yaml are plain text — group names, rule expressions, and app config are
# not secrets. Users are the source of truth and are created in the Admin Console
# (or via SCIM/HRIS); group rules sort them into groups by profile attributes.
locals {
  org  = yamldecode(file("${path.module}/config/groups.yaml"))
  apps = yamldecode(file("${path.module}/config/apps.yaml"))
}
