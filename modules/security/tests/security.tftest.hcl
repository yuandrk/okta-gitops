# Unit tests — mocked provider, no Okta API calls.
# Run: terraform -chdir=modules/security init -backend=false && terraform -chdir=modules/security test

mock_provider "okta" {}

variables {
  authenticators = [
    { key = "okta_password", name = "Password" },
    { key = "okta_verify", name = "Okta Verify" },
    { key = "phone_number", name = "Phone", status = "INACTIVE" },
  ]

  enrollment = {
    okta_password = "REQUIRED"
    okta_verify   = "OPTIONAL"
  }
}

run "authenticators_are_keyed_by_key" {
  command = plan

  assert {
    condition     = toset(keys(okta_authenticator.this)) == toset(["okta_password", "okta_verify", "phone_number"])
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
