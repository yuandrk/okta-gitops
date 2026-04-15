# Okta API: POST /api/v1/users?activate=false
# Admin Console equivalent: Directory → People → Add Person (set to "Staged")
#
# "STAGED" means the user exists in Okta but has never been activated —
# no welcome email is sent, no password is set. Safe for testing.
resource "okta_user" "users" {
  for_each   = { for u in local.users_list : u.login => u }
  first_name = each.value.first_name
  last_name  = each.value.last_name
  login      = each.value.login # must be unique in the org; acts as the username
  email      = each.value.email # in Okta, login and email are often the same
  status     = each.value.status # STAGED, ACTIVE, DEPROVISIONED, SUSPENDED
}
