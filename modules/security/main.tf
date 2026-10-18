# Admin Console: Security → Authenticators → Setup
# Okta API: /api/v1/authenticators
# Okta never deletes an authenticator. Create adopts one that already exists, and
# destroy only deactivates it, which locks out the users who rely on it.
resource "okta_authenticator" "this" {
  for_each = local.authenticators_by_key

  key    = each.key
  name   = each.value.name
  status = each.value.status
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
