# identity

Okta groups and the group rules that auto-assign users to them. Fed from [`config/groups.yaml`](../../config/groups.yaml).

- One `okta_group` per entry, keyed by `name`.
- One `okta_group_rule` (`auto-assign-<name>`, ACTIVE) per entry that has a `rule`, written in [Okta Expression Language](https://developer.okta.com/docs/reference/okta-expression-language/).
- Users are not managed here. They're created in the Admin Console, and the rules sort them into groups.

Keys are state addresses: renaming a group destroys and recreates it.

```bash
terraform -chdir=modules/identity init -backend=false
terraform -chdir=modules/identity test
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
| [okta_group.groups](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/group) | resource |
| [okta_group_rule.rules](https://registry.terraform.io/providers/okta/okta/latest/docs/resources/group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| groups | List of groups to create in Okta. Each entry may include an Okta Expression Language rule that auto-assigns matching users. | <pre>list(object({<br/>    name        = string<br/>    description = string<br/>    rule        = optional(string)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| group\_ids | Map of group name to Okta group ID |
| group\_rule\_ids | Map of group name to its group-rule ID (only for groups with a rule) |
<!-- END_TF_DOCS -->
