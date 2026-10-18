# Admin Console: Security → Authenticators → Setup
# Okta API: /api/v1/authenticators
# Okta never deletes an authenticator. Create adopts one that already exists, and
# destroy only deactivates it, which locks out the users who rely on it.
resource "okta_authenticator" "this" {
  for_each = local.authenticators_by_key

  key    = each.key
  name   = each.value.name
  status = each.value.status

  # The provider's legacy default ignores `name`, which also sends an empty name
  # when it creates an authenticator. Names are managed here.
  legacy_ignore_name = false
}

# The default authenticator enrollment policy: which authenticators users must
# (REQUIRED), may (OPTIONAL) or can't (NOT_ALLOWED) enroll.
# Admin Console: Security → Authenticators → Enrollment → Default Policy
# Okta API: /api/v1/policies?type=MFA_ENROLL (the policy with system = true)
resource "okta_policy_mfa_default" "this" {
  is_oie = true

  okta_password     = local.enroll["okta_password"]
  okta_email        = local.enroll["okta_email"]
  okta_verify       = local.enroll["okta_verify"]
  phone_number      = local.enroll["phone_number"]
  webauthn          = local.enroll["webauthn"]
  google_otp        = local.enroll["google_otp"]
  security_question = local.enroll["security_question"]

  # Enrollment needs the authenticator to exist and be active first.
  depends_on = [okta_authenticator.this]
}

# The break-glass group's own enrollment policy, ahead of the default one: its admin
# enrolls a factor that doesn't hang on anyone's phone (a TOTP secret kept in 1Password).
# Admin Console: Security → Authenticators → Enrollment → Add a policy
# Okta API: POST /api/v1/policies  (type MFA_ENROLL)
resource "okta_policy_mfa" "break_glass" {
  name            = "Break-glass"
  description     = "Managed by Terraform — the break-glass admin enrolls its own factor"
  status          = "ACTIVE"
  priority        = 1
  is_oie          = true
  groups_included = [local.break_glass_group]

  okta_password     = { enroll = "REQUIRED" }
  okta_verify       = local.break_glass_enroll["okta_verify"]
  phone_number      = local.break_glass_enroll["phone_number"]
  webauthn          = local.break_glass_enroll["webauthn"]
  google_otp        = local.break_glass_enroll["google_otp"]
  security_question = local.break_glass_enroll["security_question"]

  depends_on = [okta_authenticator.this]
}

# Okta API: POST /api/v1/policies/{policyId}/rules
resource "okta_policy_rule_mfa" "break_glass" {
  policy_id = okta_policy_mfa.break_glass.id
  name      = "Enroll at sign-in"
  enroll    = "LOGIN"
}
