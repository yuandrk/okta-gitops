# Architecture

## Repo layout

```text
okta-gitops/
├── modules/
│   ├── identity/   # okta_group + okta_group_rule
│   ├── policies/   # scaffolded — sign-on, password, MFA policies
│   └── apps/       # scaffolded — SAML/OIDC app integrations
├── environments/
│   ├── prod/       # active Terraform root
│   └── dev/        # read-only showcase (not wired to CI or live state)
├── .github/workflows/
│   ├── plan.yml    # PR-triggered: fmt, init, validate, plan → PR comment
│   └── apply.yml   # main-triggered: apply, gated by GitHub Environment
└── docs/           # this directory
```

## Modules vs environments

**Modules** (`modules/<name>/`) describe *what* Okta resources to manage and how they relate to each other. They take structured input (e.g. a list of groups), produce Okta resources, and export IDs via `outputs.tf`. Modules do **not** configure providers — they inherit the provider from the calling environment.

**Environments** (`environments/<env>/`) are independent Terraform roots. Each env has its own backend, its own state object, its own credentials, and calls modules with env-specific data. Today there is exactly one active environment (`prod`); `dev/` is kept as a documentation-grade copy of the wiring (provider config, module call, S3 backend) so a reader can see the structure without diving into prod state.

| File in `environments/<env>/` | Purpose |
| --- | --- |
| `main.tf` | Provider config, backend block, module calls |
| `variables.tf` | Input variables (`org_name`, `base_url`, `api_token`) |
| `backend.hcl` | S3 backend config — passed via `terraform init -backend-config=…` |
| `groups.yaml` | Plain-YAML list of groups + Okta Expression Language rules |
| `terraform.tfvars` | Real credentials (gitignored — copy from `.example`) |
| `.terraform.lock.hcl` | Provider version lockfile (committed) |

## Identity module

The only module with real resources today.

```text
modules/identity/
├── main.tf       # okta_group + okta_group_rule
├── variables.tf  # var.groups
└── outputs.tf    # group_ids, group_rule_ids
```

Input shape (`var.groups`):

```hcl
groups = [
  {
    name        = "Engineering"
    description = "All engineering staff"
    rule        = "user.division == \"Engineering\""
  },
]
```

`rule` is optional. Groups without a rule are created but get no auto-assignment.

The module deliberately does **not** manage `okta_user` or `okta_group_memberships` — see [Source of truth](source-of-truth.md) for why.

## Future modules (scaffolded, no resources yet)

- **`modules/policies/`** — `okta_policy_password`, `okta_policy_mfa`, `okta_policy_signon`, plus rules
- **`modules/apps/`** — `okta_app_saml`, `okta_app_oauth`, `okta_app_group_assignments`, `okta_trusted_origin`. Likely shape: one sub-module per concrete app (no premature generic abstraction).

## Why this layout

- **Modules ≠ environments** is the standard Terraform convention. Environments differ in *data and state*, not in *what resources exist*. Putting both behind the same module call lets you promote changes from dev → prod by editing data, not code.
- **Plain YAML for group/rule data** keeps PR diffs human-readable. Names of groups and rule expressions are not secrets, so encryption (SOPS, etc.) was removed in favor of clarity.
- **One env active, one dormant showcase** matches the reality of a learning project. Spinning up a second live env is not free (state object, IAM trust scope, costs of duplicate Okta noise) — when there's a real reason, dev gets re-activated.
