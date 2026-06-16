# Architecture

## Repo layout

```text
okta-gitops/
├── main.tf            # provider config, backend block, module call
├── variables.tf       # input variables (org_name, base_url, api_token)
├── backend.hcl        # S3 backend config — passed via -backend-config
├── groups.yaml        # plain-YAML list of groups + Okta Expression Language rules
├── terraform.tfvars   # real credentials (gitignored — copy from .example)
├── .terraform.lock.hcl
├── modules/
│   └── identity/      # okta_group + okta_group_rule
├── .github/workflows/
│   ├── plan.yml       # PR-triggered: fmt, init, validate, plan → PR comment
│   └── apply.yml      # main-triggered: apply, gated by GitHub Environment
└── docs/              # this directory
```

A single Terraform root at the repo root — no dev/prod split. For a one-person learning project managing a handful of groups, a second environment is pure overhead (extra state object, IAM trust scope, duplicate Okta noise). If a real need for staging appears, split then.

## Root vs module

**Root** (repo root) is the Terraform root: provider config, S3 backend, credentials, and the call into the identity module with data decoded from `groups.yaml`.

**Module** (`modules/identity/`) describes *what* Okta resources to manage. It takes structured input (a list of groups), produces `okta_group` + `okta_group_rule`, and exports IDs via `outputs.tf`. It does **not** configure a provider — it inherits from the root.

| File | Purpose |
| --- | --- |
| `main.tf` | Provider config, backend block, module call |
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
    name        = "homelab-admins"
    description = "Full kube-admin access to homelab k3s via Headlamp (Okta OIDC)."
    rule        = "user.division == \"IT\""
  },
]
```

`rule` is optional. Groups without a rule (e.g. `homelab-viewers`) are created but get no auto-assignment — membership is set manually.

The module deliberately does **not** manage `okta_user` or `okta_group_memberships` — see [Source of truth](source-of-truth.md) for why.

## How groups map to access

The groups are the IAM layer for a homelab k3s cluster. Okta sends group membership in the OIDC `groups` claim; the cluster binds each group to a Kubernetes role via a `ClusterRoleBinding`. That binding lives in the **separate homelab repo**, not here — this repo owns only the Okta side.

| Okta group | k8s role | Assignment |
| --- | --- | --- |
| `homelab-admins` | `cluster-admin` | rule: `user.division == "IT"` |
| `homelab-viewers` | `view` (read-only) | manual membership |

## Why this layout

- **Single root, no environments** — environments differ in *data and state*, not in *what resources exist*. For one person and a couple of groups, a second env is overhead, not safety. Module/root separation is kept so resources stay reusable if an env split is ever needed.
- **Plain YAML for group/rule data** keeps PR diffs human-readable. Group names and rule expressions are not secrets, so encryption (SOPS, etc.) was removed in favor of clarity.
- **Okta owns identity, the homelab repo owns RBAC** — the OIDC `groups` claim is the contract between them. Change access by changing group membership in Okta, not by editing cluster YAML per user.
