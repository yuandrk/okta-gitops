terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 6.0"
    }
  }
}

# Admin Console equivalent: Directory → Groups → Add Group
# Okta API: POST /api/v1/groups
resource "okta_group" "groups" {
  for_each    = { for g in var.groups : g.name => g }
  name        = each.value.name
  description = each.value.description
}

# Admin Console equivalent: Directory → Groups → Rules → Add Rule
# Okta API: POST /api/v1/groups/rules
# A rule auto-adds matching users to the target group based on profile attributes
# (e.g. user.userType, user.division). Users are the source of truth — they are
# created in the Admin Console (or via SCIM/HRIS), and rules sort them into groups.
resource "okta_group_rule" "rules" {
  for_each          = { for g in var.groups : g.name => g if g.rule != null }
  name              = "auto-assign-${each.value.name}"
  status            = "ACTIVE"
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = each.value.rule
  group_assignments = [okta_group.groups[each.key].id]
}
