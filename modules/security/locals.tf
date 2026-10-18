locals {
  # Identity Engine authenticator keys this module handles. Each is also an argument
  # of okta_policy_mfa_default.
  authenticator_keys = ["okta_password", "okta_email", "okta_verify", "phone_number", "webauthn", "google_otp", "security_question"]

  authenticators_by_key = { for a in var.authenticators : a.key => a }

  # okta_policy_mfa_default takes one map per authenticator, e.g.
  # okta_verify = { enroll = "REQUIRED" }. A key missing from var.enrollment stays null.
  enroll = { for k in local.authenticator_keys : k => (contains(keys(var.enrollment), k) ? { enroll = var.enrollment[k] } : null) }

  # The break-glass enrollment policy requires exactly one extra factor besides the password.
  break_glass_enroll = { for k in local.authenticator_keys : k => (k == var.break_glass.factor ? { enroll = "REQUIRED" } : null) }
  break_glass_group  = var.group_ids[var.break_glass.group]
}
