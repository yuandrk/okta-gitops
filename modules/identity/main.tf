terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 6.0"
    }
  }
}

locals {
  # group_name => list of user logins that belong to it
  group_member_logins = {
    for g in var.groups : g.name => [
      for u in var.users : u.login
      if contains(u.groups, g.name)
    ]
  }
}

# Admin Console equivalent: Directory → Groups → Add Group
# Okta API: POST /api/v1/groups
resource "okta_group" "groups" {
  for_each    = { for g in var.groups : g.name => g }
  name        = each.value.name
  description = each.value.description
}

# Okta API: POST /api/v1/users?activate=false
# Admin Console equivalent: Directory → People → Add Person (set to "Staged")
resource "okta_user" "users" {
  for_each   = { for u in var.users : u.login => u }
  first_name = each.value.first_name
  last_name  = each.value.last_name
  login      = each.value.login  # immutable unique key — changing it forces destroy + recreate
  email      = each.value.email
  status     = each.value.status # STAGED | ACTIVE | DEPROVISIONED | SUSPENDED
}

# Admin Console equivalent: Directory → Groups → <group> → Manage People
# Okta API: PUT /api/v1/groups/{groupId}/users/{userId}
# okta_group_memberships is authoritative — members added manually in the Admin Console
# will be removed on the next apply.
resource "okta_group_memberships" "memberships" {
  for_each = {
    for g in var.groups : g.name => g
    if length(local.group_member_logins[g.name]) > 0
  }
  group_id = okta_group.groups[each.key].id
  users    = [for login in local.group_member_logins[each.key] : okta_user.users[login].id]
}
