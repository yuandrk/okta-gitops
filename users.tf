# Okta API: POST /api/v1/users?activate=false
# Admin Console equivalent: Directory → People → Add Person (set to "Staged")
#
# "STAGED" means the user exists in Okta but has never been activated —
# no welcome email is sent, no password is set. Safe for testing.
resource "okta_user" "test_engineer" {
  first_name = "Test"
  last_name  = "Engineer"
  login      = "test.engineer@example.com" # must be unique in the org; acts as the username
  email      = "test.engineer@example.com" # in Okta, login and email are often the same

  status = "STAGED" # other values: ACTIVE, DEPROVISIONED, SUSPENDED
}
