# Admin Console: Applications → Create App Integration → SAML 2.0
# Okta API: POST /api/v1/apps  (signOnMode SAML_2_0)
resource "okta_app_saml" "saml" {
  for_each = local.saml_apps_by_name

  label = each.value.name

  # SAML Settings → General. Okta posts the signed response to the SP's ACS URL
  # ("Use this for Recipient URL and Destination URL").
  sso_url     = each.value.sso_url
  recipient   = each.value.sso_url
  destination = each.value.sso_url
  audience    = each.value.audience # Audience URI (SP Entity ID); the SP checks it

  # Name ID format EmailAddress, Application username Email: SPs like Fleet match
  # their own accounts on the user's email.
  subject_name_id_format   = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
  subject_name_id_template = "$${user.userName}"
  user_name_template       = "$${source.email}"

  # What the Console sets for a new SAML app: response and assertion signed, SHA-256.
  response_signed         = true
  assertion_signed        = true
  signature_algorithm     = "RSA_SHA256"
  digest_algorithm        = "SHA256"
  honor_force_authn       = true
  authn_context_class_ref = "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport"
  idp_issuer              = "http://www.okta.com/$${org.externalKey}"

  # SP-initiated only. A dashboard tile would start an IdP-initiated login: a response
  # the SP never asked for, so it can't tie it to a sign-in of its own.
  hide_ios = true
  hide_web = true

  # Bind the app to its dedicated sign-on (authentication) policy.
  authentication_policy = okta_app_signon_policy.saml[each.key].id
}

# Same Okta API and Console screens as the OIDC policy and rule in oidc.tf.
resource "okta_app_signon_policy" "saml" {
  for_each = local.saml_apps_by_name

  name        = each.value.signon_policy.name
  description = each.value.signon_policy.description
}

resource "okta_app_signon_policy_rule" "saml" {
  for_each = local.saml_apps_by_name

  policy_id = okta_app_signon_policy.saml[each.key].id
  name      = each.value.signon_policy.rule_name

  access                      = "ALLOW"
  factor_mode                 = each.value.signon_policy.factor_mode
  network_connection          = "ANYWHERE"
  re_authentication_frequency = each.value.signon_policy.re_authentication_frequency
  priority                    = 1

  constraints = each.value.signon_policy.possession == null ? null : [jsonencode({
    knowledge  = { required = true, types = ["password"] }
    possession = local.possession_constraints[each.value.signon_policy.possession]
  })]
}

# Admin Console: Applications → <app> → Assignments → Assign to Groups
# Okta API: PUT /api/v1/apps/{appId}/groups/{groupId}
resource "okta_app_group_assignment" "saml" {
  for_each = local.saml_app_group_pairs

  app_id   = okta_app_saml.saml[each.value.app].id
  group_id = var.group_ids[each.value.group]
}
