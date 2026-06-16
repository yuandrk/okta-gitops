# Architecture

## Repo layout

```text
okta-gitops/
├── main.tf            # provider, backend, locals, module.identity + module.apps
├── variables.tf       # input variables (org_name, base_url, api_token)
├── outputs.tf         # oidc_client_ids, oidc_client_secrets
├── backend.hcl        # S3 backend config — passed via -backend-config
├── groups.yaml        # plain-YAML groups + Okta Expression Language rules
├── apps.yaml          # plain-YAML OIDC app integrations (Headlamp)
├── terraform.tfvars   # real credentials (gitignored — copy from .example)
├── .terraform.lock.hcl
├── modules/
│   ├── identity/      # okta_group + okta_group_rule
│   └── apps/          # okta_app_oauth + sign-on policy/rule + group assignment
├── .github/workflows/
│   ├── plan.yml       # PR-triggered: fmt, init, validate, plan → PR comment
│   └── apply.yml      # main-triggered: apply, gated by GitHub Environment
└── docs/              # this directory
```

A single Terraform root at the repo root — no dev/prod split. For a one-person learning project, a second environment is pure overhead (extra state object, IAM trust scope, duplicate Okta noise). If a real need for staging appears, split then.

## Root vs modules

**Root** (repo root) is the Terraform root: provider config, S3 backend, credentials. It decodes `groups.yaml` / `apps.yaml` and calls the modules — passing `module.identity.group_ids` into `module.apps` so app assignments resolve groups by name.

**Modules** describe *what* Okta resources to manage. They take structured input, produce resources, and export IDs/outputs. They do **not** configure a provider — they inherit from the root.

| File | Purpose |
| --- | --- |
| `main.tf` | Provider config, backend block, module calls |
| `variables.tf` | Input variables (`org_name`, `base_url`, `api_token`) |
| `outputs.tf` | `oidc_client_ids`, `oidc_client_secrets` (re-exported from `module.apps`) |
| `backend.hcl` | S3 backend config — passed via `terraform init -backend-config=…` |
| `groups.yaml` | Plain-YAML groups + Okta Expression Language rules |
| `apps.yaml` | Plain-YAML OIDC app integrations |
| `terraform.tfvars` | Real credentials (gitignored — copy from `.example`) |
| `.terraform.lock.hcl` | Provider version lockfile (committed) |

## Identity module

```text
modules/identity/
├── main.tf       # okta_group + okta_group_rule
├── variables.tf  # var.groups
└── outputs.tf    # group_ids, group_rule_ids
```

Input shape (`var.groups`):

```hcl
groups = [
  { name = "homelab-admins", description = "...", rule = "user.division == \"IT\"" },
]
```

`rule` is optional — a group without one is created but gets no auto-assignment (membership set manually). The module deliberately does **not** manage `okta_user` or `okta_group_memberships` — see [Source of truth](source-of-truth.md).

## Apps module

```text
modules/apps/
├── main.tf       # okta_app_oauth + okta_app_signon_policy(+rule) + okta_app_group_assignment
├── variables.tf  # var.apps, var.group_ids
└── outputs.tf    # client_ids, client_secrets
```

Data-driven via `for_each` over `var.apps`. For each app it creates the OIDC integration, a dedicated sign-on policy + rule, and one group assignment per entry in the app's `groups` list. **Resource addresses must match live state** — apps key on the app name (`okta_app_oauth.oidc["Headlamp"]`); assignments key on `"App:Group"` (`okta_app_group_assignment.oidc["Headlamp:homelab-admins"]`).

The showcase app is **Headlamp** (homelab Kubernetes dashboard): users sign in via Okta OIDC, the `groups` claim carries their membership, and the k3s cluster maps groups to RBAC roles — that `ClusterRoleBinding` lives in the **separate homelab repo**, not here.

## Why this layout

- **Single root, no environments** — environments differ in *data and state*, not in *what resources exist*. For one person, a second env is overhead, not safety. Module/root separation is kept so resources stay reusable if an env split is ever needed.
- **Plain YAML for data** keeps PR diffs human-readable. Group names, rule expressions, and app config are not secrets, so encryption (SOPS, etc.) was removed in favor of clarity.
- **Okta owns identity + app integration, the homelab repo owns RBAC** — the OIDC `groups` claim is the contract between them. Change access by changing group membership in Okta, not by editing cluster YAML per user.
