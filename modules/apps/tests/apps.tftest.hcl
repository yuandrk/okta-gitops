# Unit tests — mocked provider, no Okta API calls.
# Run: terraform -chdir=modules/apps init -backend=false && terraform -chdir=modules/apps test

mock_provider "okta" {}

variables {
  group_ids = {
    "admins"  = "00gADMINS"
    "viewers" = "00gVIEWERS"
  }

  apps = [{
    name          = "Grafana"
    redirect_uris = ["https://grafana.example.com/callback"]
    groups        = ["admins", "viewers"]
    signon_policy = { name = "Grafana Sign-On Policy", description = "test" }
  }]

  bookmarks = [{
    label  = "Wiki"
    url    = "https://wiki.example.com"
    groups = ["viewers"]
  }]
}

run "oidc_app_gets_policy_and_one_assignment_per_group" {
  command = plan

  assert {
    condition     = keys(okta_app_oauth.oidc) == ["Grafana"]
    error_message = "OIDC apps must be keyed by name."
  }

  assert {
    condition     = keys(okta_app_signon_policy.oidc) == ["Grafana"] && keys(okta_app_signon_policy_rule.allow_password) == ["Grafana"]
    error_message = "Each app needs its own sign-on policy and rule."
  }

  assert {
    condition     = toset(keys(okta_app_group_assignment.oidc)) == toset(["Grafana:admins", "Grafana:viewers"])
    error_message = "Assignments must be keyed \"App:Group\"."
  }

  assert {
    condition     = okta_app_group_assignment.oidc["Grafana:viewers"].group_id == "00gVIEWERS"
    error_message = "Group names must resolve through var.group_ids."
  }
}

run "signon_rule_defaults_to_mfa" {
  command = plan

  assert {
    condition     = okta_app_signon_policy_rule.allow_password["Grafana"].factor_mode == "2FA" && okta_app_signon_policy_rule.allow_password["Grafana"].re_authentication_frequency == "PT12H"
    error_message = "An app that doesn't set factor_mode must get 2FA with a 12h re-auth."
  }
}

run "invalid_factor_mode_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d", factor_mode = "MFA" }
    }]
  }

  expect_failures = [var.apps]
}

run "bookmark_gets_its_own_assignment" {
  command = plan

  assert {
    condition     = keys(okta_app_bookmark.link) == ["Wiki"] && keys(okta_app_group_assignment.bookmark) == ["Wiki:viewers"]
    error_message = "Bookmark and its assignment must be keyed by label."
  }
}

run "unknown_group_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      groups        = ["typo-admins"]
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "invalid_issuer_mode_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      issuer_mode   = "CUSTOM"
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "idp_initiated_login_without_uri_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      login_mode    = "SPEC"
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "bookmark_with_unknown_group_is_rejected" {
  command = plan

  variables {
    bookmarks = [{ label = "Wiki", url = "https://wiki.example.com", groups = ["nobody"] }]
  }

  expect_failures = [var.bookmarks]
}
