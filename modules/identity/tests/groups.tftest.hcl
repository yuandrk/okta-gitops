# Unit tests — mocked provider, no Okta API calls.
# Run: terraform -chdir=modules/identity init -backend=false && terraform -chdir=modules/identity test

mock_provider "okta" {}

variables {
  groups = [
    { name = "admins", description = "With a rule", rule = "user.division == \"IT\"" },
    { name = "viewers", description = "No rule" },
  ]
}

run "group_with_rule_gets_a_rule" {
  command = plan

  assert {
    condition     = length(okta_group.groups) == 2
    error_message = "Expected one okta_group per entry."
  }

  assert {
    condition     = keys(okta_group_rule.rules) == ["admins"]
    error_message = "Only groups with a rule should get an okta_group_rule."
  }

  assert {
    condition     = okta_group_rule.rules["admins"].name == "auto-assign-admins"
    error_message = "Rule name should be auto-assign-<group>."
  }
}

run "duplicate_group_names_are_rejected" {
  command = plan

  variables {
    groups = [
      { name = "admins", description = "a" },
      { name = "admins", description = "b" },
    ]
  }

  expect_failures = [var.groups]
}
