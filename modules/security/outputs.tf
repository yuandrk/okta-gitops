output "authenticator_ids" {
  description = "Map of authenticator key to its Okta ID"
  value       = { for k, v in okta_authenticator.this : k => v.id }
}

output "enrollment_policy_id" {
  description = "ID of the default authenticator enrollment policy"
  value       = okta_policy_mfa_default.this.id
}
