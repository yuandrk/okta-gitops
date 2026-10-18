# security

The org's security baseline: authenticators, enrollment policies and global session policies, with the break-glass admin's own way in. Fed from [`config/security.yaml`](../../config/security.yaml).

| File | Resources | Keyed by |
| --- | --- | --- |
| `main.tf` | `okta_authenticator`, `okta_policy_mfa_default`, `okta_policy_mfa.break_glass` + rule | authenticator `key`; the policies are singletons |
| `sessions.tf` | `okta_policy_signon.break_glass` / `.everyone` + their rules | singletons |

- Okta never deletes an authenticator. Creating `okta_authenticator` adopts the existing one, and destroying it **deactivates** it, which locks out whoever relies on it. The destroy guard in `plan.yml` flags that.
- `okta_policy_mfa_default` is the org's built-in enrollment policy: it is imported, never created, and can't be deleted.
- The break-glass policies (priority 1) target only its group; its enrollment policy exists only once `break_glass.factor` is set. The `Everyone` session policy comes next, and Okta's Default Policy stays last. Rules can't exclude a group, so the break-glass admin gets policies of its own.
- Authenticator `settings` aren't managed yet; the Console keeps them. Names are (`legacy_ignore_name = false`).

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
| [okta_authenticator.by_key](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/authenticator) | resource |
| [okta_policy_mfa.break_glass](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_mfa) | resource |
| [okta_policy_mfa_default.this](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_mfa_default) | resource |
| [okta_policy_rule_mfa.break_glass](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_rule_mfa) | resource |
| [okta_policy_rule_signon.break_glass](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_rule_signon) | resource |
| [okta_policy_rule_signon.everyone](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_rule_signon) | resource |
| [okta_policy_signon.break_glass](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_signon) | resource |
| [okta_policy_signon.everyone](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/policy_signon) | resource |
| [okta_group.everyone](https://registry.terraform.io/providers/okta/okta/latest/docs/data-sources/group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| authenticators | Authenticators to manage, keyed by `key`. Okta never deletes one: creating it adopts the existing authenticator, and destroying it deactivates it. | <pre>list(object({<br/>    key  = string<br/>    name = string # display name, as in Security → Authenticators<br/>    # INACTIVE fails while any policy still uses the authenticator.<br/>    status = optional(string, "ACTIVE")<br/>  }))</pre> | n/a | yes |
| break\_glass | The break-glass admin's own way in: an enrollment policy and a global session policy for its group, both ahead of everyone else's. | <pre>object({<br/>    group = string # a group from config/groups.yaml<br/>    # Authenticator key the break-glass admin enrolls at first sign-in. Left out:<br/>    # no break-glass enrollment policy yet.<br/>    factor = optional(string)<br/>    # A short session: the account is for emergencies, not for staying signed in.<br/>    session_idle_minutes     = optional(number, 15)<br/>    session_lifetime_minutes = optional(number, 60)<br/>  })</pre> | n/a | yes |
| group\_ids | Map of group name to Okta group ID (from the identity module) — used to resolve break\_glass.group by name. | `map(string)` | n/a | yes |
| session | The global session policy for everyone else, ahead of Okta's Default Policy. | <pre>object({<br/>    idle_minutes     = optional(number, 120)<br/>    lifetime_minutes = optional(number, 720) # 0 = no limit<br/>    persistent       = optional(bool, false) # keep the session cookie after the browser closes<br/>  })</pre> | n/a | yes |
| enrollment | Default authenticator enrollment policy: authenticator key → REQUIRED, OPTIONAL or NOT\_ALLOWED. A key left out isn't set on the policy. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| authenticator\_ids | Map of authenticator key to its Okta ID |
| enrollment\_policy\_id | ID of the default authenticator enrollment policy |
<!-- END_TF_DOCS -->
