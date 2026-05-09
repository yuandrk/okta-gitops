# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Hands-on learning project for the [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) Terraform provider (~> 6.0) against a real Okta developer org. Goal is practical IAM understanding — each resource block includes a comment mapping it to the underlying Okta Management API call and Admin Console equivalent.

## Target org

`integrator-7752059.okta.com` (developer org, safe to experiment)

## Credentials

Never hardcode secrets. Supply via:

- `terraform.tfvars` (gitignored, inside the environment directory) for local work
- `TF_VAR_api_token` env var for CI or shell sessions

Variable names: `org_name`, `base_url`, `api_token` (declared in each environment's `variables.tf`).

## First-time setup

```bash
# Set up credentials for the prod environment (the active one)
cp environments/prod/terraform.tfvars.example environments/prod/terraform.tfvars
# Edit environments/prod/terraform.tfvars with your Okta API token

# Init and validate
cd environments/prod
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

## Common commands

All Terraform commands must be run from `environments/prod/` (the active env).

```bash
cd environments/prod

# Download providers and init backend
terraform init -backend-config=backend.hcl

# Preview changes — always run before apply
terraform plan

# Apply (confirm with user first — never apply without showing plan)
terraform apply

# Tear down all resources in this environment
terraform destroy

# Format all .tf files in place (run from repo root)
terraform fmt -recursive

# Validate config syntax without hitting the API
terraform validate

# Inspect current deployed state
terraform show
terraform state list
```

## Workflow rule

**Always run `terraform plan` and show the output before running `terraform apply`.** The user wants to review what will change before it happens.

## Architecture

```
okta-gitops/
├── modules/
│   ├── identity/   # groups + group rules (okta_group, okta_group_rule)
│   ├── policies/   # scaffolded (no resources yet) — sign-on, password, MFA policies
│   └── apps/       # scaffolded (no resources yet) — SAML/OIDC app integrations
└── environments/
    ├── prod/       # Active Terraform root: providers, backend, module calls, groups.yaml
    └── dev/        # Read-only showcase — same layout as prod, not wired to CI or live state
```

**`environments/prod/` is the only active environment.** `environments/dev/` is kept as a documentation-grade copy showing the same wiring (provider, module call) — do not run Terraform against it.

Each `environments/<env>/` directory is an independent Terraform root:

| File | Purpose |
| --- | --- |
| `main.tf` | Provider config, backend block, module calls |
| `variables.tf` | Input variables (org_name, base_url, api_token) |
| `backend.hcl` | S3 backend config (not committed to TF config — passed via `-backend-config`) |
| `groups.yaml` | Plain-YAML list of groups + Okta Expression Language rules |
| `terraform.tfvars` | Actual credentials (gitignored — copy from `.example`) |

Modules accept structured data (list of groups) from the environment and manage the Okta resources. Modules do **not** configure providers — they inherit from the calling environment. The identity module exposes group and group-rule IDs via `outputs.tf` for use by future modules.

## Source of truth — users live outside Terraform

Users are **not** managed by Terraform. They are created in the Okta Admin Console (or, in a real org, pushed in via SCIM/HRIS or directory integration). Terraform owns only:

- **Groups** (`okta_group`) — stable abstractions of access boundaries
- **Group rules** (`okta_group_rule`) — auto-assign users to groups based on profile attributes via Okta Expression Language

### Adding a user (manual)

1. Admin Console → Directory → People → Add Person
2. Fill in profile, **make sure to set `Division` and `User type`** — these drive group rule matching
3. Save → group rules evaluate within seconds and assign the user to matching groups

### Adding/changing a group or rule

1. Edit `environments/prod/groups.yaml` — add a new group entry with optional `rule` (Okta Expression Language)
2. `terraform plan` → review
3. `terraform apply` (or merge to main and let CI apply)

Rule expression reference: <https://developer.okta.com/docs/reference/okta-expression-language/>. Common attributes: `user.userType`, `user.division`, `user.department`, `user.title`, `user.organization`.

## State & lock file

- State for the active environment is stored in **S3** at `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` (eu-west-2)
- The `dev/` showcase intentionally has no live state object — its `backend.hcl` still points to the legacy `dev/terraform.tfstate` key, which no longer exists
- Init prod with `terraform init -backend-config=backend.hcl` from `environments/prod/`
- `.terraform.lock.hcl` **should be committed** — it pins provider versions per environment
- `backend.hcl` uses `use_lockfile = true` (S3-native locking) — requires Terraform ≥ 1.10; CI workflows pin `~1.10`
- Local Terraform floor is `>= 1.6.0` (`main.tf`), but S3 locking requires `>= 1.10` — use 1.10+ locally too

## CI/CD workflows

- `.github/workflows/plan.yml` — PR trigger: fmt, init, validate, plan; posts plan as PR comment
- `.github/workflows/apply.yml` — push to `main`: gated by GitHub Environment `prod` (manual approval), then `apply -auto-approve`
- AWS auth via **OIDC** — IAM role `github-okta-gitops` (account `756755582140`), no stored AWS keys
- Secrets: `TF_VAR_API_TOKEN` · Variables: `TF_VAR_ORG_NAME`, `AWS_ROLE_ARN`

### IAM role trust — OIDC subject patterns

`github-okta-gitops` trust policy must include all three:
- `repo:yuandrk/okta-gitops:ref:refs/heads/main` — push to main
- `repo:yuandrk/okta-gitops:pull_request` — PR runs (plan.yml)
- `repo:yuandrk/okta-gitops:environment:*` — environment-gated runs (apply.yml uses `environment: prod`)

## Plugins active in this project

- `terraform-skill@antonbabenko` — Terraform best-practice guidance (naming, count vs for_each, testing, CI/CD)
- `claude-md-management` — keep CLAUDE.md current; run `revise-claude-md` at session end

## Key Okta concepts mapped to resources

- `okta_group_rule` is **declarative** — it watches user profile attributes and adds matching users to its target group. Manual group memberships added via the Admin Console for the same user are not removed by the rule, but rule-assigned memberships cannot be removed manually (the rule re-adds them).
- A rule must be **deactivated** before its expression can be edited; the provider handles that transition automatically (it reports `status: ACTIVE → INACTIVE → ACTIVE` in the plan).
- Group rules evaluate on user creation and on profile change. They do **not** evaluate retroactively unless the rule is re-activated.
- Profile attributes used in expressions (`user.userType`, `user.division`, etc.) must exist on the Okta user schema. The built-in Default User Type already includes the most common ones.
