# Unit tests — mocked provider, no Okta API calls.
# Run: terraform -chdir=modules/apps init -backend=false && terraform -chdir=modules/apps test

mock_provider "okta" {}

variables {
  okta_url = "https://login.example.com"

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

  saml_apps = [{
    name          = "Fleet"
    sso_url       = "https://fleet.example.com/api/v1/fleet/sso/callback"
    audience      = "https://fleet.example.com"
    groups        = ["admins"]
    signon_policy = { name = "Fleet Sign-On Policy", description = "test" }
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

  assert {
    condition     = okta_app_signon_policy_rule.allow_password["Grafana"].constraints == null
    error_message = "Without signon_policy.possession, the rule must not constrain the second factor."
  }
}

run "device_bound_possession_becomes_a_constraint" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d", possession = "DEVICE_BOUND" }
    }]
  }

  assert {
    condition = jsondecode(okta_app_signon_policy_rule.allow_password["Grafana"].constraints[0]) == {
      knowledge  = { required = true, types = ["password"] }
      possession = { required = true, deviceBound = "REQUIRED" }
    }
    error_message = "DEVICE_BOUND must become password + a required device-bound possession factor."
  }
}

run "unknown_possession_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d", possession = "HARDWARE" }
    }]
  }

  expect_failures = [var.apps]
}

run "possession_with_1fa_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d", factor_mode = "1FA", possession = "DEVICE_BOUND" }
    }]
  }

  expect_failures = [var.apps]
}

run "auth_method_and_groups_claim_are_passed_through" {
  command = plan

  variables {
    apps = [{
      name                       = "Grafana"
      redirect_uris              = ["https://grafana.example.com/callback"]
      token_endpoint_auth_method = "client_secret_post"
      groups_claim               = { value = "admins" }
      signon_policy              = { name = "p", description = "d" }
    }]
  }

  assert {
    condition     = okta_app_oauth.oidc["Grafana"].token_endpoint_auth_method == "client_secret_post"
    error_message = "token_endpoint_auth_method must reach the app."
  }

  assert {
    condition     = okta_app_oauth.oidc["Grafana"].groups_claim[0].name == "groups" && okta_app_oauth.oidc["Grafana"].groups_claim[0].filter_type == "REGEX" && okta_app_oauth.oidc["Grafana"].groups_claim[0].value == "admins"
    error_message = "groups_claim must default to name=groups, FILTER/REGEX."
  }
}

run "native_public_client_with_pkce_is_accepted" {
  command = plan

  variables {
    apps = [
      {
        name          = "Grafana"
        redirect_uris = ["https://grafana.example.com/callback"]
        signon_policy = { name = "p", description = "d" }
      },
      {
        name                       = "Hermes"
        type                       = "native"
        redirect_uris              = ["https://hermes.example.com/callback"]
        token_endpoint_auth_method = "none"
        pkce_required              = true
        signon_policy              = { name = "q", description = "d" }
      },
    ]
  }

  assert {
    condition     = okta_app_oauth.oidc["Hermes"].token_endpoint_auth_method == "none" && okta_app_oauth.oidc["Hermes"].pkce_required
    error_message = "A public client must reach the app with auth method none and PKCE on."
  }

  assert {
    condition     = keys(nonsensitive(output.client_secrets)) == ["Grafana"]
    error_message = "client_secrets must leave out public clients, which have no secret."
  }
}

run "public_client_without_pkce_is_rejected" {
  command = plan

  variables {
    apps = [{
      name                       = "Hermes"
      type                       = "native"
      redirect_uris              = ["https://hermes.example.com/callback"]
      token_endpoint_auth_method = "none"
      signon_policy              = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "public_web_client_is_rejected" {
  command = plan

  variables {
    apps = [{
      name                       = "Grafana"
      redirect_uris              = ["https://grafana.example.com/callback"]
      token_endpoint_auth_method = "none"
      pkce_required              = true
      signon_policy              = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "unsupported_auth_method_is_rejected" {
  command = plan

  variables {
    apps = [{
      name                       = "Grafana"
      redirect_uris              = ["https://grafana.example.com/callback"]
      token_endpoint_auth_method = "client_secret_jwt"
      signon_policy              = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
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

run "duplicate_app_names_are_rejected" {
  command = plan

  variables {
    apps = [
      { name = "Grafana", redirect_uris = ["https://a.example.com/cb"], signon_policy = { name = "p", description = "d" } },
      { name = "Grafana", redirect_uris = ["https://b.example.com/cb"], signon_policy = { name = "q", description = "d" } },
    ]
  }

  expect_failures = [var.apps]
}

run "invalid_app_type_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      type          = "spa"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.apps]
}

run "non_iso_reauth_frequency_is_rejected" {
  command = plan

  variables {
    apps = [{
      name          = "Grafana"
      redirect_uris = ["https://grafana.example.com/callback"]
      signon_policy = { name = "p", description = "d", re_authentication_frequency = "12h" }
    }]
  }

  expect_failures = [var.apps]
}

run "duplicate_bookmark_labels_are_rejected" {
  command = plan

  variables {
    bookmarks = [
      { label = "Wiki", url = "https://wiki.example.com" },
      { label = "Wiki", url = "https://wiki2.example.com" },
    ]
  }

  expect_failures = [var.bookmarks]
}

run "plain_http_bookmark_is_rejected" {
  command = plan

  variables {
    bookmarks = [{ label = "Wiki", url = "http://wiki.example.com" }]
  }

  expect_failures = [var.bookmarks]
}

run "group_access_lists_apps_and_bookmarks_per_group" {
  command = plan

  assert {
    condition = (
      toset(keys(output.group_access)) == toset(["admins", "viewers"]) &&
      output.group_access["admins"].apps == tolist(["Fleet", "Grafana"]) &&
      length(output.group_access["admins"].bookmarks) == 0 &&
      output.group_access["viewers"].apps == tolist(["Grafana"]) &&
      output.group_access["viewers"].bookmarks == tolist(["Wiki"])
    )
    error_message = "group_access must map each assigned group to its apps (OIDC and SAML) and bookmarks."
  }
}

run "saml_app_gets_policy_and_one_assignment_per_group" {
  command = plan

  assert {
    condition     = keys(okta_app_saml.saml) == ["Fleet"] && keys(okta_app_signon_policy.saml) == ["Fleet"] && keys(okta_app_signon_policy_rule.saml) == ["Fleet"]
    error_message = "Each SAML app needs its own sign-on policy and rule, keyed by name."
  }

  assert {
    condition     = keys(okta_app_group_assignment.saml) == ["Fleet:admins"] && okta_app_group_assignment.saml["Fleet:admins"].group_id == "00gADMINS"
    error_message = "SAML assignments must be keyed \"App:Group\" and resolve groups through var.group_ids."
  }
}

run "saml_app_sends_the_email_to_its_acs_url" {
  command = plan

  assert {
    condition = (
      okta_app_saml.saml["Fleet"].recipient == "https://fleet.example.com/api/v1/fleet/sso/callback" &&
      okta_app_saml.saml["Fleet"].destination == "https://fleet.example.com/api/v1/fleet/sso/callback" &&
      okta_app_saml.saml["Fleet"].audience == "https://fleet.example.com"
    )
    error_message = "Recipient and Destination must be the ACS URL, and the audience the SP's entity ID."
  }

  assert {
    condition     = okta_app_saml.saml["Fleet"].subject_name_id_format == "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress" && okta_app_saml.saml["Fleet"].user_name_template == "$${source.email}"
    error_message = "The NameID must be the user's email."
  }

  assert {
    condition     = okta_app_saml.saml["Fleet"].response_signed && okta_app_saml.saml["Fleet"].assertion_signed
    error_message = "Okta must sign both the response and the assertion."
  }

  assert {
    condition     = okta_app_saml.saml["Fleet"].hide_web && okta_app_saml.saml["Fleet"].hide_ios
    error_message = "A SAML app must have no tile: its login starts at the SP."
  }
}

run "saml_signon_rule_defaults_to_mfa" {
  command = plan

  assert {
    condition     = okta_app_signon_policy_rule.saml["Fleet"].factor_mode == "2FA" && okta_app_signon_policy_rule.saml["Fleet"].re_authentication_frequency == "PT12H" && okta_app_signon_policy_rule.saml["Fleet"].constraints == null
    error_message = "A SAML app that doesn't set factor_mode must get 2FA with a 12h re-auth and no factor constraint."
  }
}

run "saml_device_bound_possession_becomes_a_constraint" {
  command = plan

  variables {
    saml_apps = [{
      name          = "Fleet"
      sso_url       = "https://fleet.example.com/api/v1/fleet/sso/callback"
      audience      = "https://fleet.example.com"
      signon_policy = { name = "p", description = "d", possession = "DEVICE_BOUND" }
    }]
  }

  assert {
    condition = jsondecode(okta_app_signon_policy_rule.saml["Fleet"].constraints[0]) == {
      knowledge  = { required = true, types = ["password"] }
      possession = { required = true, deviceBound = "REQUIRED" }
    }
    error_message = "DEVICE_BOUND must become password + a required device-bound possession factor, for SAML apps too."
  }
}

run "plain_http_acs_url_is_rejected" {
  command = plan

  variables {
    saml_apps = [{
      name          = "Fleet"
      sso_url       = "http://fleet.example.com/api/v1/fleet/sso/callback"
      audience      = "https://fleet.example.com"
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.saml_apps]
}

run "saml_app_named_like_an_oidc_app_is_rejected" {
  command = plan

  variables {
    saml_apps = [{
      name          = "Grafana"
      sso_url       = "https://grafana.example.com/saml/acs"
      audience      = "https://grafana.example.com"
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.saml_apps]
}

run "duplicate_saml_app_names_are_rejected" {
  command = plan

  variables {
    saml_apps = [
      { name = "Fleet", sso_url = "https://a.example.com/acs", audience = "a", signon_policy = { name = "p", description = "d" } },
      { name = "Fleet", sso_url = "https://b.example.com/acs", audience = "b", signon_policy = { name = "q", description = "d" } },
    ]
  }

  expect_failures = [var.saml_apps]
}

run "saml_app_with_unknown_group_is_rejected" {
  command = plan

  variables {
    saml_apps = [{
      name          = "Fleet"
      sso_url       = "https://fleet.example.com/api/v1/fleet/sso/callback"
      audience      = "https://fleet.example.com"
      groups        = ["nobody"]
      signon_policy = { name = "p", description = "d" }
    }]
  }

  expect_failures = [var.saml_apps]
}

run "okta_url_with_trailing_slash_is_rejected" {
  command = plan

  variables {
    okta_url = "https://login.example.com/"
  }

  expect_failures = [var.okta_url]
}

# Last, because it applies (against the mock): the entity key is known only after apply.
run "saml_metadata_url_is_on_okta_url" {
  command = apply

  assert {
    condition     = startswith(output.saml_metadata_urls["Fleet"], "https://login.example.com/app/") && endswith(output.saml_metadata_urls["Fleet"], "/sso/saml/metadata")
    error_message = "The metadata URL must be the public /app/<entity key>/sso/saml/metadata path on okta_url."
  }
}
