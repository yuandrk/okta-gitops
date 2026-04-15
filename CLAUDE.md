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
| `data.tf` | SOPS data source + shared locals (groups, users, memberships map) |
| `users.yaml` | SOPS-encrypted source of truth for all groups, users, and memberships |
| `groups.tf` | `okta_group` resources (data-driven via `for_each`) |
| `users.tf` | `okta_user` resources (data-driven via `for_each`) |
| `memberships.tf` | `okta_group_memberships` — links users to groups (data-driven) |

All Okta resources are keyed by their natural identifier: group `name` and user `login`. Terraform resolves creation order automatically via implicit dependencies.

## SOPS — encrypted user data

Users and groups are defined in `users.yaml`, which is encrypted with [SOPS](https://github.com/getsops/sops) using an **age** key. The encrypted file is safe to commit.

### Local setup

```bash
# Install tools (if not already present)
brew install age sops

# Generate an age key (stored at the SOPS default location)
age-keygen -o ~/.config/sops/age/keys.txt
# Copy the printed public key into .sops.yaml → creation_rules → age
```

The `carlpett/sops` Terraform provider reads the key automatically from `~/.config/sops/age/keys.txt`.

### Editing users.yaml

```bash
# Opens in $EDITOR, re-encrypts on save
sops users.yaml

# Or decrypt to stdout (read-only inspection)
sops --decrypt users.yaml
```

### Adding a user

1. `sops users.yaml` — edit the file
2. Add a new entry under `users:` with `first_name`, `last_name`, `login`, `email`, `status`, and `groups`
3. Save and close — SOPS re-encrypts automatically
4. Commit, open a PR — Terraform will plan the new user on next run

### CI/CD

Set the `SOPS_AGE_KEY` environment secret to the **private key contents** (everything in `keys.txt`).
The provider picks it up without needing the key file on disk.

## State & lock file

- State is stored in **S3** (`terraform-state-homelab-yuandrk`, eu-west-2). Init with `terraform init -backend-config=backend.hcl`.
- `.terraform.lock.hcl` **should be committed** — it pins provider versions so all collaborators use the same binary.

## Plugins active in this project

- `terraform-skill@antonbabenko` — Terraform best-practice guidance (naming, count vs for_each, testing, CI/CD)
- `claude-md-management` — keep CLAUDE.md current; run `revise-claude-md` at session end

## Key Okta concepts mapped to resources

- `okta_group_memberships` is **authoritative** — it owns the full member list. Members added manually in the Admin Console will be removed on next apply.
- User `status = "STAGED"` means the account exists but is inactive (no email sent, no login possible). Change to `"ACTIVE"` to trigger activation.
- `login` on `okta_user` is the immutable unique key — changing it forces destroy + recreate.
