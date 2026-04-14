# Admin Console equivalent: Directory → Groups → Engineering → Manage People → Add
#
# okta_group_memberships manages the full set of members for a group as a unit.
# If you remove a user from the `users` set, Terraform will call DELETE /api/v1/groups/{groupId}/users/{userId}.
resource "okta_group_memberships" "engineering_members" {
  group_id = okta_group.engineering.id # reference to the group created in groups.tf

  users = [
    okta_user.test_engineer.id # reference to the user created in users.tf
  ]
}
