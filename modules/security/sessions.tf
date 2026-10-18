# Global session policies decide how an Okta session starts and how long it lasts; each
# app's sign-on policy then decides that app's factors. Okta evaluates the policies by
# priority, and the first one whose groups include the user applies. Rules can only
# exclude users by ID, so the break-glass group gets a policy of its own, ahead of the
# one for everyone. Okta's Default Policy stays last, as the fallback.
# Admin Console: Security → Global Session Policy
# Okta API: POST /api/v1/policies  (type OKTA_SIGN_ON), then /policies/{policyId}/rules

data "okta_group" "everyone" {
  name = "Everyone"
  type = "BUILT_IN"
}

resource "okta_policy_signon" "break_glass" {
  name            = "Break-glass"
  description     = "Managed by Terraform — the break-glass admin's own session rules"
  status          = "ACTIVE"
  priority        = 1
  groups_included = [local.break_glass_group]
}

resource "okta_policy_rule_signon" "break_glass" {
  policy_id          = okta_policy_signon.break_glass.id
  name               = "Any factor, short session"
  access             = "ALLOW"
  primary_factor     = "PASSWORD_IDP_ANY_FACTOR" # whatever the app sign-on policy asked for
  mfa_required       = false
  session_idle       = var.break_glass.session_idle_minutes
  session_lifetime   = var.break_glass.session_lifetime_minutes
  session_persistent = false
}

resource "okta_policy_signon" "everyone" {
  name            = "Everyone"
  description     = "Managed by Terraform — session limits for everyone else"
  status          = "ACTIVE"
  priority        = 2
  groups_included = [data.okta_group.everyone.id]

  # Created after the break-glass policy, so the two priorities don't race.
  depends_on = [okta_policy_signon.break_glass]
}

resource "okta_policy_rule_signon" "everyone" {
  policy_id          = okta_policy_signon.everyone.id
  name               = "Any factor"
  access             = "ALLOW"
  primary_factor     = "PASSWORD_IDP_ANY_FACTOR"
  mfa_required       = false # app sign-on policies decide on MFA
  session_idle       = var.session.idle_minutes
  session_lifetime   = var.session.lifetime_minutes
  session_persistent = var.session.persistent
}
