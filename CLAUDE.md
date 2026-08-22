# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Hands-on learning project for the [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) Terraform provider (~> 6.0) against a real Okta developer org. Goal is practical IAM understanding — each resource block includes a comment mapping it to the underlying Okta Management API call and Admin Console equivalent.

## Target org

`integrator-7752059.okta.com` (developer org, safe to experiment)

## Credentials

Never hardcode secrets. Supply via:

- `terraform.tfvars` (gitignored, in the repo root) for local work
- `TF_VAR_api_token` env var for CI or shell sessions

Variable names: `org_name`, `base_url`, `api_token` (declared in `variables.tf`).

**Canonical source of the API token: 1Password — `op://homelab/okta-gitops/credential`** (vault
`homelab`, alongside `okta-mcp`). Read it from there rather than copying it between machines.

### The token expires — this will bite you

**Okta SSWS tokens die after 30 days with no API calls.** Not 30 days since issue — 30 days of
silence. A repo that goes quiet for a month comes back to a dead token.

Symptom:

```
Error: [ERROR] failed validate configuration: error with v3 SDK client: 401 Unauthorized
  with provider["registry.terraform.io/okta/okta"]
```

Confirm it's the token and not the config:

```bash
TOK=$(op read "op://homelab/okta-gitops/credential")
curl -s -H "Authorization: SSWS $TOK" -H "Accept: application/json" \
  "https://integrator-7752059.okta.com/api/v1/users/me" | jq -r '.errorSummary // "token OK"'
# "Invalid token provided" (E0000011) ⇒ expired, not a config problem
```

Rotation touches **two** places. Doing only the first leaves CI broken until the next PR fails:

```bash
# 1. Admin Console → Security → API → Tokens → Create Token → save into 1Password
# 2. local — rewrite api_token in terraform.tfvars from 1Password, never from clipboard history
op read "op://homelab/okta-gitops/credential"
# 3. CI
op read "op://homelab/okta-gitops/credential" | gh secret set TF_VAR_API_TOKEN
```

> **MCP access does not depend on this token.** `okta-mcp-server` authenticates as the `C_mcp`
> service app via `private_key_jwt`. So the MCP tools keep reading the org happily while Terraform
> 401s — don't let a working `list_groups` convince you the credentials are fine. Two independent
> auth paths; diagnose them separately.

## First-time setup

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Okta API token

# Init and validate
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

## Common commands

All Terraform commands run from the repo root (the single Terraform root).

```bash
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

Single Terraform root at the repo root — no dev/prod split.

```
okta-gitops/
├── main.tf            # provider, backend, locals, module.identity + module.apps
├── variables.tf       # input variables (org_name, base_url, api_token)
├── outputs.tf         # oidc_client_ids, oidc_client_secrets (re-exported from module.apps)
├── backend.hcl        # S3 backend config (passed via -backend-config)
├── groups.yaml        # plain-YAML groups + Okta Expression Language rules
├── apps.yaml          # plain-YAML OIDC app integrations (Headlamp)
├── terraform.tfvars   # actual credentials (gitignored — copy from .example)
└── modules/
    ├── identity/      # okta_group + okta_group_rule
    └── apps/          # okta_app_oauth + sign-on policy/rule + group assignment
```

The root decodes `groups.yaml` / `apps.yaml` and passes the data to the modules; `module.apps` also receives `module.identity.group_ids` to resolve group assignments by name. Modules do **not** configure a provider — they inherit from the root.

The showcase use case: **Headlamp** (homelab Kubernetes dashboard) is an `okta_app_oauth` OIDC app. Terraform manages the app, its sign-on policy/rule, and the group assignment (`homelab-admins` may sign in). Users authenticate through Okta; the OIDC `groups` claim carries their membership, and the k3s cluster maps groups to RBAC roles (in the separate homelab repo, not here).

> **State ↔ code:** resource addresses (`module.apps.okta_app_oauth.oidc["Headlamp"]`, `module.identity.okta_group.groups["homelab-admins"]`, etc.) must match the live S3 state exactly. Changing a module name, resource name, or `for_each` key forces destroy/recreate — verify `terraform plan` stays **No changes** for reconcile work.

## Source of truth — users live outside Terraform

Users are **not** managed by Terraform. They are created in the Okta Admin Console (or, in a real org, pushed in via SCIM/HRIS or directory integration). Terraform owns:

- **Groups** (`okta_group`) — stable abstractions of access boundaries
- **Group rules** (`okta_group_rule`) — auto-assign users to groups based on profile attributes via Okta Expression Language
- **OIDC apps** (`okta_app_oauth` + sign-on policy/rule + group assignment) — app integrations like Headlamp

### Adding a user (manual)

1. Admin Console → Directory → People → Add Person
2. Fill in profile, **make sure to set `Division` and `User type`** — these drive group rule matching
3. Save → group rules evaluate within seconds and assign the user to matching groups

### Adding/changing a group or rule

1. Edit `groups.yaml` — add a new group entry with optional `rule` (Okta Expression Language)
2. `terraform plan` → review
3. `terraform apply` (or merge to main and let CI apply)

Rule expression reference: <https://developer.okta.com/docs/reference/okta-expression-language/>. Common attributes: `user.userType`, `user.division`, `user.department`, `user.title`, `user.organization`.

### Deliberately unmanaged resources

Not everything in the org belongs in Terraform. Left out **on purpose**:

- **Built-in groups** (`Everyone`, `Okta Administrators`) and **system Okta apps** (Admin Console, Dashboard, Browser Plugin, Workflows, Access Certification Reviews, OIN Submission Tester, **Okta Personal App Migration**, etc.) — managed by Okta itself. Okta adds these over time without asking: `Okta Personal App Migration` (`okta_personal_app_migration`) appeared in the org on 2026-06-26. A new first-party app showing up is normal, not drift.
- **`C_mcp`** — the service (machine-to-machine) OIDC app whose `private_key_jwt` credential the okta-mcp-server authenticates with. It uses **Okta-generated, auto-rotating signing keys** (`autoKeyRotation: true`, multiple ACTIVE/INACTIVE keys). Declaring its `jwks` in Terraform would fight Okta's rotation (perpetual drift) and an apply could overwrite the active key and break the MCP's own auth. It's also a bootstrap credential that rarely changes. So it stays in the Admin Console; its private key lives in 1Password (`op://`), never in code.

## Inspecting live Okta & reconciling drift

The `okta-mcp-server` MCP tools read the live org **read-only** — use them to diff what's actually in Okta against `groups.yaml` / `apps.yaml`. The `/okta-drift` skill (`.claude/skills/okta-drift`) automates this end to end; the manual steps it follows:

1. **Read live state** (read-only MCP): `list_groups` and `list_applications` for the full inventory, `get_application` for one app's detail (e.g. oauth/jwks), `list_group_users` and `get_user_profile_attributes` for membership/schema.
2. **Classify each resource:** managed in TF · **deliberately unmanaged** (the allowlist above — built-in groups, system Okta apps, `C_mcp`) · real drift.
3. **Group *rules* are not exposed by any MCP tool** — their presence/absence and correctness are confirmed only via `terraform plan`, never MCP.
4. **Adopt, don't recreate:** a resource that already exists in Okta must be brought into state with `terraform import '<address>' <okta-id>` **before** apply — otherwise apply fails trying to create a duplicate. After import, iterate the code until `terraform plan` is clean for that resource. Changing a `for_each` key / module / resource name re-keys state and forces destroy/recreate (see the State ↔ code note above).
5. **AWS auth:** the S3 backend needs valid creds. If `aws sts get-caller-identity` errors with an expired session, run `aws login` before `terraform init` / `plan`.
6. **Okta auth:** a `401 Unauthorized` from the provider means the SSWS token expired, not that the config is wrong — see "The token expires" under [Credentials](#credentials). Note that MCP steps 1–2 succeed regardless, since the MCP uses a different credential.
7. **Never echo the token:** read it into a variable without printing it — `TOKEN=$(op read "op://homelab/okta-gitops/credential")` (fallback if 1Password is locked: `TOKEN=$(awk -F'"' '/api_token/{print $2}' terraform.tfvars)`) — then use `$TOKEN`. Don't paste the literal value into any command.

## State & lock file

- State is stored in **S3** at `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` (eu-west-2). The `prod/` key is legacy from the old layout — kept to avoid a state migration; rename via `terraform init -migrate-state` only if desired.
- Init with `terraform init -backend-config=backend.hcl` from the repo root
- `.terraform.lock.hcl` **should be committed** — it pins provider versions
- `backend.hcl` uses `use_lockfile = true` (S3-native locking) — requires Terraform ≥ 1.10; CI workflows pin `~1.10`
- Local Terraform floor is `>= 1.6.0` (`main.tf`), but S3 locking requires `>= 1.10` — use 1.10+ locally too

## CI/CD workflows

- `.github/workflows/plan.yml` — PR trigger: fmt, init, validate, plan; posts plan as PR comment
- `.github/workflows/apply.yml` — push to `main`: gated by GitHub Environment `prod` (manual approval), then `apply -auto-approve`

> **`paths:` filters must list every input file.** Both workflows gate on a `paths:` allowlist
> (`*.tf`, `groups.yaml`, `apps.yaml`, `backend.hcl`, `modules/**`). A change to a file *not* in
> that list triggers **nothing** — no plan on the PR, and no apply on merge. `apps.yaml` was
> missing until 2026-08-22, so an `apps.yaml`-only change silently skipped CI entirely; it went
> unnoticed because every earlier `apps.yaml` commit happened to also touch `groups.yaml` or
> `modules/**`. When you add a new YAML input that the root decodes, add it to **both** workflows
> in the same commit.
- AWS auth via **OIDC** — IAM role `github-okta-gitops` (account `756755582140`), no stored AWS keys
- Secrets: `TF_VAR_API_TOKEN` · Variables: `TF_VAR_ORG_NAME`, `AWS_ROLE_ARN`

### IAM role trust — OIDC subject patterns

`github-okta-gitops` trust policy must include all three:
- `repo:yuandrk/okta-gitops:ref:refs/heads/main` — push to main
- `repo:yuandrk/okta-gitops:pull_request` — PR runs (plan.yml)
- `repo:yuandrk/okta-gitops:environment:*` — environment-gated runs (apply.yml uses `environment: prod`)

## Plugins & skills active in this project

- `terraform-skill@antonbabenko` — Terraform best-practice guidance (naming, count vs for_each, testing, CI/CD)
- `claude-md-management@claude-plugins-official` — keep CLAUDE.md current; run `revise-claude-md` at session end
- `.claude/skills/okta-drift` — project skill: diff live Okta against the YAML and report drift (see "Inspecting live Okta & reconciling drift" above). This is the **only** copy — an earlier duplicate under `.agents/skills/` was removed.

**This file is the single source of truth for agent guidance.** `AGENTS.md` is a three-line pointer
here and must stay that way — it was once a full copy of this file, produced by a `Claude`→`Codex`
find-and-replace that mangled paths and plugin names. Don't re-sync the two; edit only `CLAUDE.md`.

## Key Okta concepts mapped to resources

- `okta_group_rule` is **declarative** — it watches user profile attributes and adds matching users to its target group. Manual group memberships added via the Admin Console for the same user are not removed by the rule, but rule-assigned memberships cannot be removed manually (the rule re-adds them).
- A rule must be **deactivated** before its expression can be edited; the provider handles that transition automatically (it reports `status: ACTIVE → INACTIVE → ACTIVE` in the plan).
- Group rules evaluate on user creation and on profile change. They do **not** evaluate retroactively unless the rule is re-activated.
- Profile attributes used in expressions (`user.userType`, `user.division`, etc.) must exist on the Okta user schema. The built-in Default User Type already includes the most common ones.
