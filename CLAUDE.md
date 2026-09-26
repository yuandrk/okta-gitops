# CLAUDE.md

Guidance for AI agents working in this repo. Humans: start at [README.md](README.md).

## Purpose

Okta as the SSO for the homelab (Headlamp, Hermes), managed with the [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) provider (`~> 6.0`). The repo is also a rehearsal ground for an Okta rollout at work, and a learning/portfolio project. Keep the per-resource comments that map each block to its Okta API call and Admin Console screen.

- What's in the org and who manages it: [README → What's in the org](README.md#whats-in-the-org)
- Why things are done this way: [docs/design.md](docs/design.md)
- How-to recipes and incident fixes: [docs/runbook.md](docs/runbook.md)

**Target org:** `integrator-7752059.okta.com` (developer org, safe to experiment). Custom domain: `okta.yuandrk.net`.

## Hard rules

- **Always run `terraform plan` and show the output before `terraform apply`.** Never apply without the user seeing the plan.
- **Never echo secrets.** Read the token into a variable: `TOKEN=$(op read "op://homelab/okta-gitops/credential")`. If 1Password is locked, fall back to `TOKEN=$(awk -F'"' '/api_token/{print $2}' terraform.tfvars)`. Never paste the literal value into a command.
- **Resource addresses must match S3 state.** Changing a `for_each` key (app name, group name, `"App:Group"`), a module name or a resource name forces destroy and recreate. Reconcile work must end with `terraform plan` → **No changes**.
- **Adopt, don't recreate.** Anything that already exists in Okta gets `terraform import '<address>' <id>` **before** apply.
- **Users are never Terraform resources.** They're created in the Admin Console. Terraform owns groups, group rules, apps and bookmarks.

## Credentials: two independent paths

| Path | Credential | Where it lives |
| --- | --- | --- |
| Terraform provider | SSWS API token | 1Password `op://homelab/okta-gitops/credential`. Local copy in `terraform.tfvars` (gitignored). CI secret `TF_VAR_API_TOKEN` |
| S3 backend | AWS session | `aws login` locally; GitHub OIDC → role `github-okta-gitops` in CI |
| okta-mcp-server | device-code login as the admin user, app `okta-mcp-browser` | user-scope MCP config (`OKTA_CLIENT_ID=0oa181pcu93mzNgKr698`) |

**The SSWS token dies after 30 days with no API calls.** A provider `401 Unauthorized` means the token expired, not that the config is broken. Confirm it with the curl check in the [runbook](docs/runbook.md#401-unauthorized-from-the-provider). Rotating it touches **both** `terraform.tfvars` and the GitHub secret.

The MCP keeps working while Terraform gets 401s. **A working `list_groups` proves nothing about the Terraform token.** Diagnose the two paths separately.

The MCP's scopes include `okta.*.manage`. Treat it as **read-only by convention**: use it to inspect, and change the org only through Terraform, unless the user explicitly asks otherwise.

## Commands

```bash
terraform init -backend-config=backend.hcl   # needs a valid AWS session (aws sts get-caller-identity)
terraform fmt -recursive
terraform validate
terraform plan
terraform apply                              # only after the user has reviewed the plan
```

Terraform must be ≥ 1.10, because S3 native locking (`use_lockfile = true`) requires it. The `>= 1.6.0` floor in `main.tf` is outdated. CI pins `~1.10`.

## Layout

Single root. `main.tf` decodes `groups.yaml` and `apps.yaml` and passes them to `modules/identity` (`okta_group`, `okta_group_rule`) and `modules/apps` (`okta_app_oauth` + sign-on policy and rule, `okta_app_bookmark`, group assignments). `module.apps` receives `module.identity.group_ids` so it can resolve groups by name. The modules don't configure a provider.

State is at `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` (eu-west-2). The `prod/` key is legacy; leave it. `.terraform.lock.hcl` is committed.

## Deliberately unmanaged: not drift

- **Built-in groups** (`Everyone`, `Okta Administrators`) and **Okta system apps**. Classify system apps by their internal `name` (`okta_*`, `saasure`, `flow`, …), not by a roster: Okta adds and removes them on its own. Example: `okta_personal_app_migration` appeared and disappeared in summer 2026.
- **`Hermes Dashboard`** `0oa16q11mp5oL7Brc698`: a public native client (`token_endpoint_auth_method: none`, PKCE, CUSTOM_URL). `modules/apps` can't express it, and applying it would fight the live config. Its tile comes from the TF bookmark `Hermes`. Client config: `~/.hermes/config.yaml` (`dashboard.oauth.self_hosted`) and `op://homelab/hermes-dashboard-oidc`.
- **`Hermes Dashboard`** `0oa16pzv08uDQV7Fy698` (INACTIVE, web, ORG_URL): an abandoned first attempt. It has the same label as the live app, so **match by id, not label**.
- **`AI Harmess`** `0oa16pzy2koEUVYf1698`: an inactive experiment.
- **`okta-mcp-browser`** `0oa181pcu93mzNgKr698`: the MCP's own login, a bootstrap credential. An apply that breaks it breaks the MCP. It replaced the `C_mcp` service app on 2026-09-25. `C_mcp` (`0oa146h4n3xbeQS7j698`) was deleted, so if it reappears that **is** drift.

## Drift reconciliation

Use the `/okta-drift` skill (`.claude/skills/okta-drift`). It runs these steps:

1. Read the live inventory with MCP: `list_groups`, `list_applications`, and `get_application` for details.
2. Sort each item into one of three buckets: managed in YAML, deliberately unmanaged (list above), or **drift**.
3. **No MCP tool exposes group rules.** Check them only with `terraform plan`.
4. For real drift, propose import-before-apply. Never apply on your own.
5. If a credential is dead, still report the inventory diff and say which check was skipped and why.

## CI traps

- `plan.yml` runs on PRs and posts the plan as a comment. The `plan` check is required. `apply.yml` runs on push to `main`, behind the `prod` environment approval.
- **`paths:` filters must list every input file** (`*.tf`, `groups.yaml`, `apps.yaml`, `backend.hcl`, `modules/**`). A change to an unlisted file triggers nothing: no plan and no apply. `apps.yaml` was missing until 2026-08-22. When you add a new YAML input, add it to **both** workflows in the same commit.
- The IAM role trust must include `repo:yuandrk/okta-gitops:ref:refs/heads/main`, `:pull_request` and `:environment:*`.

## Docs hygiene

- This file is the **only** agent-guidance file. `AGENTS.md` is a three-line pointer here and must stay that way. It was once a mangled find-and-replace copy. Don't sync the two.
- `.claude/skills/okta-drift` is the only copy of that skill. Tools sometimes recreate `.agents/skills/…` as a duplicate; don't commit it.
- Facts live in one place: inventory in the README, reasoning in `docs/design.md`, procedures in `docs/runbook.md`. Link to them instead of copying. Duplicated facts are what made the docs drift before.

## Plugins and skills

- `terraform-skill@antonbabenko`: Terraform best practices
- `claude-md-management@claude-plugins-official`: keeps this file current
- `.claude/skills/okta-drift`: the drift check described above
