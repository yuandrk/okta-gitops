# CI/CD

GitHub Actions runs Terraform. Authentication to AWS (for S3 state) is via OIDC — no static AWS keys live in GitHub.

## Workflows

### `plan.yml` — pull request gate

Triggers on PRs that touch `environments/prod/**` or `modules/**`.

Steps: `fmt -check` → `init -backend-config=backend.hcl` → `validate` → `plan -no-color` → post the plan as a PR comment.

The PR cannot merge until this check passes (branch protection enforces required check `plan / prod`).

### `apply.yml` — main-branch apply

Triggers on push to `main` (typically a merged PR).

Gated by the `prod` GitHub Environment — at least one designated reviewer must approve in the Actions UI before `terraform apply -auto-approve` runs. State writes go to S3.

## Secrets and variables

Configured in GitHub: **Settings → Secrets and variables → Actions**.

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `TF_VAR_API_TOKEN` | Okta API token |
| Variable | `TF_VAR_ORG_NAME` | Okta org subdomain (e.g. `integrator-7752059`) |
| Variable | `AWS_ROLE_ARN` | IAM role ARN for OIDC (`arn:aws:iam::756755582140:role/github-okta-gitops`) |

## OIDC trust to AWS

The IAM role `github-okta-gitops` (account `756755582140`) trusts GitHub's OIDC provider. Trust policy must accept three subject patterns:

| Subject | Where it's used |
| --- | --- |
| `repo:yuandrk/okta-gitops:ref:refs/heads/main` | Push to `main` (apply.yml without env gate, if any) |
| `repo:yuandrk/okta-gitops:pull_request` | PR runs (plan.yml) |
| `repo:yuandrk/okta-gitops:environment:*` | Environment-gated runs (apply.yml uses `environment: prod`) |

If you fork or rename the repo, update the trust policy to match — otherwise OIDC-issued tokens won't be accepted.

## Branch protection on `main`

Configured in **Settings → Branches → Branch protection rules**:

- Require a pull request before merging
- Require status check `plan / prod` to pass
- Strict: branch must be up to date with `main` before merging

Admin can bypass branch protection — the recent restructuring commits used this. Day-to-day, go through PRs.

## GitHub Environment: `prod`

**Settings → Environments → `prod`**:

- Required reviewers: yourself (so apply waits for manual approval)
- Optional: deployment branch rule restricting which branches can deploy

## CI gotchas

- The `plan` job uses `continue-on-error: true` so it can still post the PR comment when plan fails. The job then re-fails at the end via `Fail if plan failed`.
- `terraform fmt -check` runs over `../../` (the repo root) — formatting issues anywhere fail the check.
- `terraform_version: "~1.10"` is pinned in workflows because S3 native locking requires Terraform ≥ 1.10.
