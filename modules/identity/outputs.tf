output "group_ids" {
  description = "Map of group name to Okta group ID"
  value       = { for k, v in okta_group.groups : k => v.id }
}

output "user_ids" {
  description = "Map of user login to Okta user ID"
  value       = { for k, v in okta_user.users : k => v.id }
  sensitive   = true
}
