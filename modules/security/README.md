# security

The org's security baseline: authenticators and the default authenticator enrollment policy. Fed from [`config/security.yaml`](../../config/security.yaml).

| File | Resources | Keyed by |
| --- | --- | --- |
| `main.tf` | `okta_authenticator`, `okta_policy_mfa_default` | authenticator `key`; the policy is a singleton |

- Okta never deletes an authenticator. Creating `okta_authenticator` adopts the existing one, and destroying it **deactivates** it, which locks out whoever relies on it. The destroy guard in `plan.yml` flags that.
- `okta_policy_mfa_default` is the org's built-in enrollment policy: it is imported, never created, and can't be deleted.
- Authenticator `settings` aren't managed yet; the Console keeps them.

Keys are state addresses: changing an authenticator's `key` means deactivating one and adopting another.

```bash
terraform -chdir=modules/security init -backend=false
terraform -chdir=modules/security test
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
| [okta_authenticator.this](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/authenticator) | resource |
| [okta_policy_mfa_default.this](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_mfa_default) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| authenticators | Authenticators to manage, keyed by `key`. Okta never deletes one: creating it adopts the existing authenticator, and destroying it deactivates it. | <pre>list(object({<br/>    key  = string<br/>    name = string # display name, as in Security → Authenticators<br/>    # INACTIVE fails while any policy still uses the authenticator.<br/>    status = optional(string, "ACTIVE")<br/>  }))</pre> | n/a | yes |
| enrollment | Default authenticator enrollment policy: authenticator key → REQUIRED, OPTIONAL or NOT\_ALLOWED. A key left out isn't set on the policy. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| authenticator\_ids | Map of authenticator key to its Okta ID |
| enrollment\_policy\_id | ID of the default authenticator enrollment policy |
<!-- END_TF_DOCS -->
