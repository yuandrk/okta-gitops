# Admin Console: Applications → Create App Integration → OIDC → Web
# Okta API: POST /api/v1/apps  (signOnMode OPENID_CONNECT)
resource "okta_app_oauth" "oidc" {
  for_each = local.apps_by_name

  label                     = each.value.name
  type                      = each.value.type
  grant_types               = each.value.grant_types
  response_types            = each.value.response_types
  redirect_uris             = each.value.redirect_uris
  post_logout_redirect_uris = each.value.post_logout_redirect_uris
  consent_method            = each.value.consent_method
  issuer_mode               = each.value.issuer_mode
  hide_ios                  = each.value.hide_ios
  hide_web                  = each.value.hide_web

  # IdP-initiated login (Okta dashboard tile / initiate_login_uri).
  login_mode   = each.value.login_mode
  login_scopes = each.value.login_scopes
  login_uri    = each.value.login_uri

  # Bind the app to its dedicated sign-on (authentication) policy.
  authentication_policy = okta_app_signon_policy.oidc[each.key].id

  # Refresh-token settings (values mirror the live app).
  refresh_token_rotation = "STATIC"
  refresh_token_leeway   = each.value.refresh_token_leeway
  wildcard_redirect      = "DISABLED"
}

# Admin Console: Security → Authentication Policies → Add policy
# Okta API: POST /api/v1/policies  (type ACCESS_POLICY)
resource "okta_app_signon_policy" "oidc" {
  for_each = local.apps_by_name

  name        = each.value.signon_policy.name
  description = each.value.signon_policy.description
}

# Admin Console: the policy's rule. Okta API: POST /api/v1/policies/{id}/rules
# The resource name `allow_password` predates MFA support. It's a state address,
# so it stays; the rule's behaviour comes from signon_policy.factor_mode.
resource "okta_app_signon_policy_rule" "allow_password" {
  for_each = local.apps_by_name

  policy_id = okta_app_signon_policy.oidc[each.key].id
  name      = each.value.signon_policy.rule_name

  access                      = "ALLOW"
  factor_mode                 = each.value.signon_policy.factor_mode
  network_connection          = "ANYWHERE"
  re_authentication_frequency = each.value.signon_policy.re_authentication_frequency
  priority                    = 1
}

# Admin Console: Applications → <app> → Assignments → Assign to Groups
# Okta API: PUT /api/v1/apps/{appId}/groups/{groupId}
resource "okta_app_group_assignment" "oidc" {
  for_each = local.app_group_pairs

  app_id   = okta_app_oauth.oidc[each.value.app].id
  group_id = var.group_ids[each.value.group]
}
