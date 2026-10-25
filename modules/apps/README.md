# apps

OIDC and SAML app integrations and bookmark tiles, assigned to groups by name. Fed from [`config/apps.yaml`](../../config/apps.yaml).

| File | Resources | Keyed by |
| --- | --- | --- |
| `oidc.tf` | `okta_app_oauth`, `okta_app_signon_policy` + rule, `okta_app_group_assignment.oidc` | app `name`, `"App:Group"` |
| `saml.tf` | `okta_app_saml`, `okta_app_signon_policy.saml` + rule, `okta_app_group_assignment.saml` | app `name`, `"App:Group"` |
| `bookmarks.tf` | `okta_app_bookmark`, `okta_app_group_assignment.bookmark` | `label`, `"Label:Group"` |

- Confidential clients (`client_secret_basic`, `client_secret_post`) and public clients: `native` or `browser` with `token_endpoint_auth_method = "none"` and `pkce_required`. A public client has no secret, so `client_secrets` leaves it out. See [design.md](../../docs/design.md#hermes-retired-2026-10-18).
- SAML apps: NameID = the user's email, response and assertion signed, no tile (the login starts at the SP). `saml_metadata_urls` builds each app's public metadata URL on `okta_url`, the org's custom domain; the provider's own `metadata_url` is an API path that needs a token. See [design.md](../../docs/design.md#fleet-signs-in-with-saml).
- `group_ids` comes from the `identity` module. Validation rejects any group name that isn't in it.

Keys are state addresses: renaming an app or bookmark destroys and recreates it, with a new client ID and secret.

```bash
terraform -chdir=modules/apps init -backend=false
terraform -chdir=modules/apps test
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10 |
| okta | >= 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [okta_app_bookmark.link](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_bookmark) | resource |
| [okta_app_group_assignment.bookmark](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_group_assignment) | resource |
| [okta_app_group_assignment.oidc](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_group_assignment) | resource |
| [okta_app_group_assignment.saml](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_group_assignment) | resource |
| [okta_app_oauth.oidc](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_oauth) | resource |
| [okta_app_saml.saml](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_saml) | resource |
| [okta_app_signon_policy.oidc](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy) | resource |
| [okta_app_signon_policy.saml](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy) | resource |
| [okta_app_signon_policy_rule.allow_password](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy_rule) | resource |
| [okta_app_signon_policy_rule.saml](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| apps | List of OIDC app integrations to manage. Each app gets an okta\_app\_oauth, a dedicated sign-on policy + rule, and group assignments. | <pre>list(object({<br/>    name                      = string<br/>    type                      = optional(string, "web")<br/>    grant_types               = optional(list(string), ["authorization_code"])<br/>    response_types            = optional(list(string), ["code"])<br/>    redirect_uris             = list(string)<br/>    post_logout_redirect_uris = optional(list(string), [])<br/>    refresh_token_leeway      = optional(number, 0)<br/>    consent_method            = optional(string, "TRUSTED")<br/>    issuer_mode               = optional(string, "ORG_URL")<br/>    hide_ios                  = optional(bool, true)<br/>    hide_web                  = optional(bool, true)<br/>    # IdP-initiated sign-on. login_mode DISABLED (default) = no IdP-initiated login;<br/>    # SPEC/OKTA enable it and require login_uri (+ login_scopes for the id_token).<br/>    login_mode   = optional(string, "DISABLED")<br/>    login_scopes = optional(list(string), [])<br/>    login_uri    = optional(string)<br/>    groups       = optional(list(string), [])<br/>    # How the client authenticates at the token endpoint. Some RPs (e.g. Kite) only<br/>    # send client_id/secret in the POST body and need client_secret_post. A public<br/>    # client (native or browser: a desktop app, an SPA) holds no secret: "none" + PKCE.<br/>    token_endpoint_auth_method = optional(string, "client_secret_basic")<br/>    # Proof Key for Code Exchange. Required for public clients.<br/>    pkce_required = optional(bool, false)<br/>    # Groups claim in the ID token (org authorization server). FILTER + REGEX<br/>    # includes every group of the user whose name matches `value`.<br/>    groups_claim = optional(object({<br/>      name        = optional(string, "groups")<br/>      type        = optional(string, "FILTER")<br/>      filter_type = optional(string, "REGEX")<br/>      value       = string<br/>    }))<br/>    signon_policy = object({<br/>      name        = string<br/>      description = string # required by okta_app_signon_policy<br/>      rule_name   = optional(string, "Require MFA")<br/>      # 2FA = password + a second factor (Okta Verify, TOTP, …). Secure by default;<br/>      # set "1FA" only for apps where a password alone is acceptable.<br/>      factor_mode = optional(string, "2FA")<br/>      # How long a sign-in is trusted before Okta asks again (ISO-8601 duration).<br/>      re_authentication_frequency = optional(string, "PT12H")<br/>      # What the second factor must be (an Okta possession constraint), on top of the<br/>      # password. DEVICE_BOUND: Okta Verify or a security key, never SMS, voice or<br/>      # email. PHISHING_RESISTANT: FastPass on the same device, or a security key.<br/>      # Left out: any second factor.<br/>      possession = optional(string)<br/>    })<br/>  }))</pre> | n/a | yes |
| group\_ids | Map of group name to Okta group ID (from the identity module) — used to resolve group assignments by name. | `map(string)` | n/a | yes |
| okta\_url | Base URL that SAML SPs read Okta's metadata from: the org's custom domain if it has one (e.g. https://okta.yuandrk.net), so the SP sends users to the domain that holds their session. | `string` | n/a | yes |
| bookmarks | List of bookmark (link-only) apps. Each produces an okta\_app\_bookmark plus group assignments. | <pre>list(object({<br/>    label  = string<br/>    url    = string<br/>    groups = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| saml\_apps | List of SAML 2.0 app integrations to manage. Each app gets an okta\_app\_saml, a dedicated sign-on policy + rule, and group assignments. | <pre>list(object({<br/>    name = string<br/>    # The SP's Assertion Consumer Service URL, where Okta posts the signed response.<br/>    sso_url = string<br/>    # The SP's entity ID. It must match the SP's own setting exactly.<br/>    audience = string<br/>    groups   = optional(list(string), [])<br/>    # Same shape and defaults as apps[*].signon_policy.<br/>    signon_policy = object({<br/>      name                        = string<br/>      description                 = string<br/>      rule_name                   = optional(string, "Require MFA")<br/>      factor_mode                 = optional(string, "2FA")<br/>      re_authentication_frequency = optional(string, "PT12H")<br/>      possession                  = optional(string)<br/>    })<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client\_ids | Map of app name to its OIDC client ID |
| client\_secrets | Map of app name to its OIDC client secret (confidential clients only: a public client has none) |
| group\_access | Map of group name to the apps (OIDC and SAML) and bookmarks assigned to it (only groups with at least one) |
| saml\_metadata\_urls | Map of SAML app name to its IdP metadata URL on the org's custom domain, for the SP's "Metadata URL" setting |
<!-- END_TF_DOCS -->
