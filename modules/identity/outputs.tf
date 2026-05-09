output "group_ids" {
  description = "Map of group name to Okta group ID"
  value       = { for k, v in okta_group.groups : k => v.id }
}

output "group_rule_ids" {
  description = "Map of group name to its group-rule ID (only for groups with a rule)"
  value       = { for k, v in okta_group_rule.rules : k => v.id }
}
