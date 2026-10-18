# Unit tests — mocked provider, no Okta API calls.
# Run: terraform -chdir=modules/security init -backend=false && terraform -chdir=modules/security test

mock_provider "okta" {
  mock_data "okta_group" {
    defaults = { id = "00gEVERYONE" }
  }
}

variables {
  authenticators = [
    { key = "okta_password", name = "Password" },
    { key = "okta_verify", name = "Okta Verify" },
    { key = "google_otp", name = "Google Authenticator" },
    { key = "phone_number", name = "Phone", status = "INACTIVE" },
  ]

  enrollment = {
    okta_password = "REQUIRED"
    okta_verify   = "OPTIONAL"
  }

  group_ids = { "break-glass" = "00gBREAKGLASS" }

  break_glass = { group = "break-glass", factor = "google_otp" }

  session = {}
}

run "authenticators_are_keyed_by_key" {
  command = plan

  assert {
    condition     = toset(keys(okta_authenticator.this)) == toset(["okta_password", "okta_verify", "google_otp", "phone_number"])
    error_message = "Authenticators must be keyed by their key."
  }

  assert {
    condition     = okta_authenticator.this["okta_verify"].status == "ACTIVE" && okta_authenticator.this["phone_number"].status == "INACTIVE"
    error_message = "status must default to ACTIVE and pass through when set."
  }
}

run "enrollment_sets_only_listed_authenticators" {
  command = plan

  assert {
    condition     = okta_policy_mfa_default.this.is_oie && okta_policy_mfa_default.this.okta_password.enroll == "REQUIRED" && okta_policy_mfa_default.this.okta_verify.enroll == "OPTIONAL"
    error_message = "Each enrollment entry must become { enroll = <value> } on the OIE default policy."
  }

  assert {
    condition     = okta_policy_mfa_default.this.webauthn == null && okta_policy_mfa_default.this.google_otp == null
    error_message = "An authenticator left out of enrollment must stay unset."
  }
}

run "duplicate_authenticator_keys_are_rejected" {
  command = plan

  variables {
    authenticators = [
      { key = "okta_verify", name = "Okta Verify" },
      { key = "okta_verify", name = "Okta Verify again" },
    ]
  }

  expect_failures = [var.authenticators]
}

run "unknown_authenticator_key_is_rejected" {
  command = plan

  variables {
    authenticators = [{ key = "okta_verfy", name = "Typo" }]
  }

  expect_failures = [var.authenticators]
}

run "invalid_status_is_rejected" {
  command = plan

  variables {
    authenticators = [{ key = "okta_verify", name = "Okta Verify", status = "DISABLED" }]
  }

  expect_failures = [var.authenticators]
}

run "invalid_enrollment_value_is_rejected" {
  command = plan

  variables {
    enrollment = { okta_verify = "MANDATORY" }
  }

  expect_failures = [var.enrollment]
}

run "unknown_enrollment_key_is_rejected" {
  command = plan

  variables {
    enrollment = { yubikey = "OPTIONAL" }
  }

  expect_failures = [var.enrollment]
}

run "break_glass_gets_its_own_enrollment_policy" {
  command = plan

  assert {
    condition     = okta_policy_mfa.break_glass.groups_included == toset(["00gBREAKGLASS"]) && okta_policy_mfa.break_glass.priority == 1
    error_message = "The break-glass enrollment policy must target only its group, ahead of the default."
  }

  assert {
    condition     = okta_policy_mfa.break_glass.google_otp.enroll == "REQUIRED" && okta_policy_mfa.break_glass.okta_password.enroll == "REQUIRED" && okta_policy_mfa.break_glass.okta_verify == null
    error_message = "Break-glass must require the password and its own factor, and nothing else."
  }

  assert {
    condition     = okta_policy_rule_mfa.break_glass.enroll == "LOGIN"
    error_message = "Break-glass must be asked to enroll at sign-in."
  }
}

run "session_policies_put_break_glass_first" {
  command = plan

  assert {
    condition     = okta_policy_signon.break_glass.priority == 1 && okta_policy_signon.break_glass.groups_included == toset(["00gBREAKGLASS"])
    error_message = "The break-glass session policy must come first and target only its group."
  }

  assert {
    condition     = okta_policy_signon.everyone.priority == 2 && okta_policy_signon.everyone.groups_included == toset(["00gEVERYONE"])
    error_message = "The session policy for everyone must come second and target the Everyone group."
  }

  assert {
    condition = (
      okta_policy_rule_signon.break_glass.session_lifetime == 60 && !okta_policy_rule_signon.break_glass.session_persistent &&
      okta_policy_rule_signon.everyone.session_idle == 120 && okta_policy_rule_signon.everyone.session_lifetime == 720 &&
      !okta_policy_rule_signon.everyone.session_persistent && okta_policy_rule_signon.everyone.primary_factor == "PASSWORD_IDP_ANY_FACTOR"
    )
    error_message = "Session defaults: break-glass 15/60 min, everyone 120/720 min, no persistent cookies, any factor."
  }
}

run "break_glass_unknown_group_is_rejected" {
  command = plan

  variables {
    break_glass = { group = "breakglass", factor = "google_otp" }
  }

  expect_failures = [var.break_glass]
}

run "break_glass_factor_must_be_active" {
  command = plan

  variables {
    break_glass = { group = "break-glass", factor = "phone_number" }
  }

  expect_failures = [var.break_glass]
}

run "session_lifetime_below_idle_is_rejected" {
  command = plan

  variables {
    session = { idle_minutes = 120, lifetime_minutes = 60 }
  }

  expect_failures = [var.session]
}
