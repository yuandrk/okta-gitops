# CLAUDE.md

Guidance for AI agents working in this repo. Humans: start at [README.md](README.md).

## Purpose

Okta as the SSO for the homelab (Kite; Headlamp was retired 2026-09-26, Hermes 2026-10-18), managed with the [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) provider (`~> 7.0`). The repo is also a rehearsal ground for an Okta rollout at work, and a learning/portfolio project. Keep the per-resource comments that map each block to its Okta API call and Admin Console screen.

- What's in the org and who manages it: [README → What's in the org](README.md#whats-in-the-org)
- Why things are done this way: [docs/design.md](docs/design.md)
- How-to recipes and incident fixes: [docs/runbook.md](docs/runbook.md)

**Target org:** `integrator-7752059.okta.com` (developer org, safe to experiment). Custom domain: `okta.yuandrk.net`.

## Hard rules

- **Always run `terraform plan` and show the output before `terraform apply`.** Never apply without the user seeing the plan.
- **Never echo secrets.** Read the token into a variable: `TOKEN=$(op read "op://homelab/okta-gitops/credential")`. If 1Password is locked, fall back to `TOKEN=$(awk -F'"' '/api_token/{print $2}' terraform.tfvars)`. Never paste the literal value into a command.
- **Resource addresses must match S3 state.** Changing a `for_each` key (app name, group name, `"App:Group"`), a module name or a resource name forces destroy and recreate. Reconcile work must end with `terraform plan` → **No changes**.
- **Adopt, don't recreate.** Anything that already exists in Okta gets imported **before** apply: an `import` block in `imports.tf`, which the PR's plan shows and CI applies, or `terraform import '<address>' <id>`. Delete applied import blocks in the next PR.
- **Users are never Terraform resources.** They're created in the Admin Console. Terraform owns groups, group rules, apps, bookmarks, authenticators, enrollment policies and global session policies.
- **Never remove an authenticator from `config/security.yaml` casually.** Okta can't delete one, so destroy deactivates it, and everyone enrolled in it loses that factor.
- **Sign-in changes follow the lockout protocol.** For any PR that tightens session, enrollment or app sign-on policies, remind the user to keep an admin session open during the apply, and afterwards to sign in to an app and test the break-glass admin ([runbook](docs/runbook.md#set-up-and-test-the-break-glass-admin)).

## Credentials: two independent paths

| Path | Credential | Where it lives |
| --- | --- | --- |
| Terraform provider | SSWS API token of the admin `svc-terraform` (Super Admin) | 1Password `op://homelab/okta-gitops/credential`, next to that admin's login. Local copy in `terraform.tfvars` (gitignored). CI secret `TF_VAR_API_TOKEN` |
| S3 backend | AWS session | `aws login` locally; GitHub OIDC → role `github-okta-gitops` in CI |
| okta-mcp-server | device-code login as the admin user, app `okta-mcp-browser` | user-scope MCP config (`OKTA_CLIENT_ID=0oa181pcu93mzNgKr698`) |

**The SSWS token dies after 30 days with no API calls.** A provider `401 Unauthorized` means the token expired, not that the config is broken. Confirm it with the curl check in the [runbook](docs/runbook.md#401-unauthorized-from-the-provider). Rotating it touches **both** `terraform.tfvars` and the GitHub secret. A token acts as the admin who minted it, so it's minted signed in as `svc-terraform`, never from the user's own account ([why](docs/design.md#terraform-runs-as-its-own-admin-svc-terraform)).

The MCP keeps working while Terraform gets 401s. **A working `list_groups` proves nothing about the Terraform token.** Diagnose the two paths separately.

The MCP's scopes include `okta.*.manage`. Treat it as **read-only by convention**: use it to inspect, and change the org only through Terraform, unless the user explicitly asks otherwise.

## Commands

```bash
terraform init -backend-config=backend.hcl   # needs a valid AWS session (aws sts get-caller-identity)
terraform fmt -recursive
terraform validate
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
for m in modules/*/; do terraform -chdir="$m" init -backend=false && terraform -chdir="$m" test; done   # mocked, no Okta calls
for m in modules/*/; do terraform-docs "$m"; done   # after changing module variables/outputs
terraform plan
terraform output inventory                   # per group: rule, apps, bookmarks (what TF manages)
terraform apply                              # only after the user has reviewed the plan
```

Terraform must be ≥ 1.10, because S3 native locking (`use_lockfile = true`) requires it. `versions.tf` enforces this. CI pins `~1.10`.

## Layout

Single root, one concern per file: `versions.tf`, `providers.tf`, `locals.tf` (decodes `config/groups.yaml`, `config/apps.yaml` and `config/security.yaml`), `main.tf` (module calls only), `imports.tf` (one-time import blocks; empty between adoptions). `modules/identity` (`okta_group`, `okta_group_rule`) and `modules/apps` (`oidc.tf`: `okta_app_oauth` + sign-on policy and rule; `bookmarks.tf`: `okta_app_bookmark`; group assignments) and `modules/security` (`main.tf`: `okta_authenticator`, the default and break-glass enrollment policies; `sessions.tf`: global session policies). `module.apps` receives `module.identity.group_ids` so it can resolve groups by name, and its validation rejects unknown group names. The modules don't configure a provider and only set a provider floor (`>= 6.0`). Each module has `tests/` (mock provider) and a README whose inputs/outputs tables are generated by terraform-docs. Rationale: [design.md → Code layout](docs/design.md#code-layout).

**Don't rename** modules or resources to match conventions: names are state addresses. If it's ever needed, use `moved` blocks and prove it with plan → No changes.

State is at `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` (eu-west-2). The `prod/` key is legacy; leave it. `.terraform.lock.hcl` is committed.

## Deliberately unmanaged: not drift

- **Built-in groups** (`Everyone`, `Okta Administrators`) and **Okta system apps**. Classify system apps by their internal `name` (`okta_*`, `saasure`, `flow`, …), not by a roster: Okta adds and removes them on its own. Example: `okta_personal_app_migration` appeared and disappeared in summer 2026.
- **`okta-mcp-browser`** `0oa181pcu93mzNgKr698`: the MCP's own login, a bootstrap credential. An apply that breaks it breaks the MCP. It replaced the `C_mcp` service app on 2026-09-25.
- **Admin role assignments** (`svc-terraform`, the break-glass admin, the user's own): set in the Console, like users. A Terraform that managed its own Super Admin role could take it away.
- **Okta's Default global session policy** (the built-in fallback after the managed ones) and **the Admin Console's own sign-on policy**: an apply that broke it could lock every admin out.
- **The Okta Verify authenticator:** active in the Console, but `ListAuthenticators` returns it with ID `okta_verify`, which the API can't fetch, so it can't be imported. It isn't in the default enrollment policy either. See [design.md → Security baseline](docs/design.md#security-baseline-adopt-first-then-tighten).
- **Google Authenticator** `aut18ur2y4sw3mjUr698`: #26's apply created it, the API answers its ID with 404, and Terraform forgot it in #27. Not drift; don't re-add it without a probe.
- **Deleted, so drift if they reappear:** `C_mcp` `0oa146h4n3xbeQS7j698` (2026-09-25); the inactive leftovers `Hermes Dashboard` `0oa16pzv08uDQV7Fy698` (web, abandoned first attempt) and `AI Harmess` `0oa16pzy2koEUVYf1698` (2026-09-26); the native `Hermes Dashboard` `0oa16q11mp5oL7Brc698` and the bookmark `Hermes` `0oa16r0m9psZy4qCf698` (retired 2026-10-18).

## Drift reconciliation

Use the `/okta-drift` skill (`.claude/skills/okta-drift`). It runs these steps:

1. Read the live inventory with MCP: `list_groups`, `list_applications`, and `get_application` for details.
2. Sort each item into one of three buckets: managed in YAML, deliberately unmanaged (list above), or **drift**.
3. **No MCP tool exposes group rules.** Check them only with `terraform plan`.
4. For real drift, propose import-before-apply. Never apply on your own.
5. If a credential is dead, still report the inventory diff and say which check was skipped and why.

## CI traps

- `plan.yml` runs on PRs and posts the plan as one comment, updated in place on every run. The `plan` check is required. `apply.yml` runs on push to `main`, behind the `prod` environment approval. `drift.yml` is manual only (`workflow_dispatch`, no schedule by the user's choice): read-only plan, fails on drift or error.
- **`plan.yml` has no `paths:` filter on purpose.** `plan` is a required check; with a filter, a docs-only PR never gets it and stays BLOCKED forever (happened to PR #12). Don't add one back.
- **`apply.yml`'s `paths:` filter must list every input** (`*.tf`, `config/**`, `backend.hcl`, `modules/**`, `.terraform.lock.hcl`). A merge touching only unlisted files runs no apply. `apps.yaml` was missing until 2026-08-22. Keep new YAML inputs under `config/` so they're covered.
- **Renovate** (`renovate.json`) opens the dependency PRs: GitHub Actions pinned to commit SHAs, the okta provider inside `~> 7.0` through the lock file only, and monthly lock-file maintenance. Don't unpin an action back to a tag. A Renovate PR that only bumps dependencies needs no CHANGELOG line; a provider major bump does (like PR #14).
- `plan.yml` fails the job if fmt, tflint, module tests, plan or the destroy guard fail. Each step uses `continue-on-error` so the PR comment still gets posted, and a final step checks every outcome.
- **Destroy guard.** `.github/scripts/destroy-guard.sh` fails `plan` when the plan deletes or replaces any resource, unless the PR has the `allow-destroy` label. Adding or removing a label re-runs the check. A replace usually means a renamed `for_each` key; fix the name rather than reach for the label.
- **Never put `${{ steps.*.outputs.* }}` inside a script body** (github-script or `run:`). Pass it through `env:` or a file. Plan text contains `${source.login}`, which the JS template literal evaluated, failing `plan` on PR #17.
- `plan.yml` runs Terraform without the setup-terraform wrapper and passes the plan through files (`plan.txt`, `tfplan`), so it has no `steps.plan.outputs.*`. `drift.yml` still uses the wrapper's outputs.
- The IAM role trust must include `repo:yuandrk/okta-gitops:ref:refs/heads/main`, `:pull_request` and `:environment:*`.

## Docs hygiene

- This file is the **only** agent-guidance file. `AGENTS.md` is a three-line pointer here and must stay that way. It was once a mangled find-and-replace copy. Don't sync the two.
- `.claude/skills/okta-drift` is the only copy of that skill. Tools sometimes recreate `.agents/skills/…` as a duplicate; don't commit it.
- Every PR that changes the org or the code adds one dated line to `CHANGELOG.md` (newest first, PR link). It records *what/when* only; reasons go to `docs/design.md`. Dependency-only Renovate PRs are the exception.
- Facts live in one place: inventory in the README, reasoning in `docs/design.md`, procedures in `docs/runbook.md`. Link to them instead of copying. Duplicated facts are what made the docs drift before.

## Plugins and skills

- `terraform-skill@antonbabenko`: Terraform best practices
- `claude-md-management@claude-plugins-official`: keeps this file current
- `.claude/skills/okta-drift`: the drift check described above
