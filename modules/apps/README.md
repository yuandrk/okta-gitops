# apps

OIDC app integrations and bookmark tiles, assigned to groups by name. Fed from [`config/apps.yaml`](../../config/apps.yaml).

| File | Resources | Keyed by |
| --- | --- | --- |
| `oidc.tf` | `okta_app_oauth`, `okta_app_signon_policy` + rule, `okta_app_group_assignment.oidc` | app `name`, `"App:Group"` |
| `bookmarks.tf` | `okta_app_bookmark`, `okta_app_group_assignment.bookmark` | `label`, `"Label:Group"` |

- Only confidential web apps are modelled. Public/native PKCE clients (e.g. Hermes Dashboard) aren't; see [design.md](../../docs/design.md).
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
| [okta_app_oauth.oidc](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_oauth) | resource |
| [okta_app_signon_policy.oidc](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy) | resource |
| [okta_app_signon_policy_rule.allow_password](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_signon_policy_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| apps | List of OIDC app integrations to manage. Each app gets an okta\_app\_oauth, a dedicated sign-on policy + rule, and group assignments. | <pre>list(object({<br/>    name                      = string<br/>    type                      = optional(string, "web")<br/>    grant_types               = optional(list(string), ["authorization_code"])<br/>    response_types            = optional(list(string), ["code"])<br/>    redirect_uris             = list(string)<br/>    post_logout_redirect_uris = optional(list(string), [])<br/>    refresh_token_leeway      = optional(number, 0)<br/>    consent_method            = optional(string, "TRUSTED")<br/>    issuer_mode               = optional(string, "ORG_URL")<br/>    hide_ios                  = optional(bool, true)<br/>    hide_web                  = optional(bool, true)<br/>    # IdP-initiated sign-on. login_mode DISABLED (default) = no IdP-initiated login;<br/>    # SPEC/OKTA enable it and require login_uri (+ login_scopes for the id_token).<br/>    login_mode   = optional(string, "DISABLED")<br/>    login_scopes = optional(list(string), [])<br/>    login_uri    = optional(string)<br/>    groups       = optional(list(string), [])<br/>    signon_policy = object({<br/>      name        = string<br/>      description = string # required by okta_app_signon_policy<br/>      rule_name   = optional(string, "Require MFA")<br/>      # 2FA = password + a second factor (Okta Verify, TOTP, …). Secure by default;<br/>      # set "1FA" only for apps where a password alone is acceptable.<br/>      factor_mode = optional(string, "2FA")<br/>      # How long a sign-in is trusted before Okta asks again (ISO-8601 duration).<br/>      re_authentication_frequency = optional(string, "PT12H")<br/>    })<br/>  }))</pre> | n/a | yes |
| group\_ids | Map of group name to Okta group ID (from the identity module) — used to resolve group assignments by name. | `map(string)` | n/a | yes |
| bookmarks | List of bookmark (link-only) apps. Each produces an okta\_app\_bookmark plus group assignments. | <pre>list(object({<br/>    label  = string<br/>    url    = string<br/>    groups = optional(list(string), [])<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client\_ids | Map of app name to its OIDC client ID |
| client\_secrets | Map of app name to its OIDC client secret |
<!-- END_TF_DOCS -->
