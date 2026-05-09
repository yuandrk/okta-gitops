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
# Install SOPS and age (if not already present)
brew install age sops

# Generate an age key (one-time, stored at SOPS default location)
age-keygen -o ~/.config/sops/age/keys.txt
# Copy the printed public key into .sops.yaml → creation_rules → age

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
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt terraform plan

# Apply (confirm with user first — never apply without showing plan)
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt terraform apply

# Tear down all resources in this environment
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt terraform destroy

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
│   ├── identity/   # users, groups, memberships (okta_group, okta_user, okta_group_memberships)
│   ├── policies/   # scaffolded (no resources yet) — sign-on, password, MFA policies
│   └── apps/       # scaffolded (no resources yet) — SAML/OIDC app integrations
├── environments/
│   ├── prod/       # Active Terraform root: providers, backend, module calls, data.yaml
│   └── dev/        # Read-only showcase — same layout as prod, not wired to CI or live state
└── .sops.yaml      # SOPS age public key (repo root — SOPS searches up the tree)
```

**`environments/prod/` is the only active environment.** `environments/dev/` is kept as a documentation-grade copy showing the same wiring (provider, SOPS data source, module call) — do not run Terraform against it.

Each `environments/<env>/` directory is an independent Terraform root:

| File | Purpose |
|---|---|
| `main.tf` | Provider config, backend block, SOPS data source, module calls |
| `variables.tf` | Input variables (org_name, base_url, api_token) |
| `backend.hcl` | S3 backend config (not committed to TF config — passed via `-backend-config`) |
| `data.yaml` | SOPS-encrypted source of truth for groups, users, and memberships |
| `terraform.tfvars` | Actual credentials (gitignored — copy from `.example`) |

Modules accept structured data (lists of groups/users) from the environment and manage the Okta resources. Modules do **not** configure providers — they inherit from the calling environment. The identity module exposes group and user IDs via `outputs.tf` for use by future modules.

## SOPS — encrypted user data

Users and groups are defined in `environments/<env>/data.yaml`, encrypted with [SOPS](https://github.com/getsops/sops) using an **age** key.

### Editing data.yaml

```bash
# Opens in $EDITOR, re-encrypts on save
sops environments/prod/data.yaml

# Or decrypt to stdout (read-only inspection)
sops --decrypt environments/prod/data.yaml
```

### Adding a user

1. `sops environments/prod/data.yaml` — opens in editor
2. Add a new entry under `users:` with `first_name`, `last_name`, `login`, `email`, `status`, and `groups`
3. Save and close — SOPS re-encrypts automatically
4. Commit, open a PR — Terraform will plan the new user on next run

### CI/CD

Set the `SOPS_AGE_KEY` environment secret to the **private key contents** (everything in `~/.config/sops/age/keys.txt`). The provider picks it up without needing the key file on disk.

## State & lock file

- State for the active environment is stored in **S3** at `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` (eu-west-2)
- The `dev/` showcase intentionally has no live state object — its `backend.hcl` still points to the legacy `dev/terraform.tfstate` key, which no longer exists
- Init prod with `terraform init -backend-config=backend.hcl` from `environments/prod/`
- `.terraform.lock.hcl` **should be committed** — it pins provider versions per environment
- `backend.hcl` uses `use_lockfile = true` (S3-native locking) — requires Terraform ≥ 1.10; CI workflows pin `~1.10`
- Local Terraform floor is `>= 1.6.0` (`main.tf`), but S3 locking requires `>= 1.10` — use 1.10+ locally too

## CI/CD

- `.github/workflows/plan.yml` — PR trigger: fmt, init, validate, plan; posts plan as PR comment
- `.github/workflows/apply.yml` — push to `main`: gated by GitHub Environment `prod` (manual approval), then `apply -auto-approve`
- AWS auth via **OIDC** — IAM role `github-okta-gitops` (account `756755582140`), no stored AWS keys
- Secrets: `TF_VAR_API_TOKEN`, `SOPS_AGE_KEY` · Variables: `TF_VAR_ORG_NAME`, `AWS_ROLE_ARN`

### IAM role trust — OIDC subject patterns

`github-okta-gitops` trust policy must include all three:
- `repo:yuandrk/okta-gitops:ref:refs/heads/main` — push to main
- `repo:yuandrk/okta-gitops:pull_request` — PR runs (plan.yml)
- `repo:yuandrk/okta-gitops:environment:*` — environment-gated runs (apply.yml uses `environment: prod`)

## Plugins active in this project

- `terraform-skill@antonbabenko` — Terraform best-practice guidance (naming, count vs for_each, testing, CI/CD)
- `claude-md-management` — keep CLAUDE.md current; run `revise-claude-md` at session end

## Key Okta concepts mapped to resources

- `okta_group_memberships` is **authoritative** — it owns the full member list. Members added manually in the Admin Console will be removed on next apply.
- User `status = "STAGED"` means the account exists but is inactive (no email sent, no login possible). Change to `"ACTIVE"` to trigger activation.
- `login` on `okta_user` is the immutable unique key — changing it forces destroy + recreate.
- SOPS-decrypted `var.users`/`var.groups` are sensitive — wrap `for_each` iterables with `nonsensitive()` (see `modules/identity/main.tf`). Keys like `login`/`name` are not real secrets.
