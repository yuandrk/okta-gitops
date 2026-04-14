# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Hands-on learning project for the [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) Terraform provider (~> 6.0) against a real Okta developer org. Goal is practical IAM understanding — each resource block includes a comment mapping it to the underlying Okta Management API call and Admin Console equivalent.

## Target org

`integrator-7752059.okta.com` (developer org, safe to experiment)

## Credentials

Never hardcode secrets. Supply via:

- `terraform.tfvars` (gitignored) for local work
- `TF_VAR_api_token` env var for CI or shell sessions

Variable names: `org_name`, `base_url`, `api_token` (declared in `variables.tf`).

## First-time setup

1. Create `terraform.tfvars` (gitignored) with your credentials:
   ```hcl
   org_name  = "integrator-7752059"
   base_url  = "okta.com"
   api_token = "00abc..."   # Admin Console → Security → API → Tokens
   ```
2. Run `terraform init` to download the provider
3. Run `terraform validate` to confirm syntax
4. Run `terraform plan` before any apply

## Common commands

```bash
# Download provider
terraform init

# Preview changes — always run before apply
terraform plan

# Apply (confirm with user first — never apply without showing plan)
terraform apply

# Tear down all resources
terraform destroy

# Format all .tf files in place
terraform fmt -recursive

# Validate config syntax without hitting the API
terraform validate
```

## Workflow rule

**Always run `terraform plan` and show the output before running `terraform apply`.** The user wants to review what will change before it happens.

## Architecture

Single flat directory (no modules yet). Resources are split by concern:

| File | What it manages |
|---|---|
| `provider.tf` | Provider version lock and authentication config |
| `variables.tf` | All input variables |
| `outputs.tf` | Output values (currently empty) |
| `groups.tf` | `okta_group` resources |
| `users.tf` | `okta_user` resources |
| `memberships.tf` | `okta_group_memberships` — links users to groups |

Resource references (e.g. `okta_group.engineering.id`) create implicit dependencies; Terraform resolves the creation order automatically.

## State & lock file

- State is stored **locally** (`terraform.tfstate`) — no remote backend configured. This file is gitignored and contains sensitive data.
- `.terraform.lock.hcl` **should be committed** — it pins provider versions so all collaborators use the same binary.

## Plugins active in this project

- `terraform-skill@antonbabenko` — Terraform best-practice guidance (naming, count vs for_each, testing, CI/CD)
- `claude-md-management` — keep CLAUDE.md current; run `revise-claude-md` at session end

## Key Okta concepts mapped to resources

- `okta_group_memberships` is **authoritative** — it owns the full member list. Members added manually in the Admin Console will be removed on next apply.
- User `status = "STAGED"` means the account exists but is inactive (no email sent, no login possible). Change to `"ACTIVE"` to trigger activation.
- `login` on `okta_user` is the immutable unique key — changing it forces destroy + recreate.
