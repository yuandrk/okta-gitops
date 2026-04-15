# Admin Console equivalent: Directory → Groups → Add Group
# Okta API: POST /api/v1/groups
resource "okta_group" "groups" {
  for_each    = { for g in local.groups_list : g.name => g }
  name        = each.value.name
  description = each.value.description
}
