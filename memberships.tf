# Admin Console equivalent: Directory → Groups → <group> → Manage People → Add
# Okta API: PUT /api/v1/groups/{groupId}/users/{userId}
#
# okta_group_memberships manages the full set of members for a group as a unit.
# If you remove a user from the `users` set, Terraform will call DELETE /api/v1/groups/{groupId}/users/{userId}.
# Only creates a resource for groups that have at least one member.
resource "okta_group_memberships" "memberships" {
  for_each = {
    for g in local.groups_list : g.name => g
    if length(local.group_member_logins[g.name]) > 0
  }
  group_id = okta_group.groups[each.key].id
  users    = [for login in local.group_member_logins[each.key] : okta_user.users[login].id]
}
