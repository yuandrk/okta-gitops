# Changelog

History of major changes to this repo, in roughly the order they happened. Earlier items use TODO-style checkboxes from when they were being planned; newer items are written as completed-fact summaries.

## User management via YAML + SOPS ✓

Replace hardcoded/tfvars user definitions with an encrypted YAML file committed to the repo.

**Why:** GitOps-friendly — user additions/removals are tracked as git diffs, reviewable via PRs, safe to store in a public repo.

**Plan:**
- [x] Add `users.yaml` with user + group membership data
- [x] Encrypt `users.yaml` with SOPS (age key)
- [x] Add `terraform-provider-sops` to `provider.tf`
- [x] Refactor `users.tf` to use `for_each` driven by YAML
- [x] Refactor `groups.tf` and `memberships.tf` to be data-driven from the same YAML
- [x] Update CI/CD to inject the SOPS decryption key (`SOPS_AGE_KEY` secret)
- [x] Document SOPS setup in CLAUDE.md

**References:**
- [terraform-provider-sops](https://registry.terraform.io/providers/carlpett/sops/latest/docs)
- [SOPS by Mozilla](https://github.com/getsops/sops)

---

## Remote state in S3 ✓

Move Terraform state from local file to S3 with DynamoDB locking.

**Why:** Local state breaks in CI/CD and on teams — S3 backend gives shared, versioned state with locking so concurrent applies don't corrupt it.

**Plan:**
- [x] Create S3 bucket (versioning enabled, SSE-S3 or KMS encryption)
- [x] Add `backend "s3"` block to `backend.tf` (native S3 lock file — no DynamoDB needed)
- [x] Config split into `backend.hcl` (keeps config out of version-controlled `backend.tf`)
- [x] Run `terraform init -migrate-state` to move existing local state to S3
- [x] OIDC role `github-okta-gitops` configured for GitHub Actions (no static AWS keys)

**Backend config** (`environments/dev/backend.hcl`):
```hcl
bucket       = "terraform-state-homelab-yuandrk"
key          = "dev/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true  # S3-native locking (Terraform ≥ 1.10), no DynamoDB
```

---

## Repo restructure: modules + environments ✓

Reorganised from flat root into reusable modules and environment-scoped Terraform roots.

- [x] `modules/identity/` — users, groups, memberships (driven by YAML input variables)
- [x] `modules/policies/`, `modules/apps/` — stubs for future resources
- [x] `environments/dev/` — full environment root with backend, SOPS data.yaml, module calls
- [x] `environments/prod/` — placeholder stub
- [x] State migrated from `okta/terraform.tfstate` → `dev/terraform.tfstate` with `module.identity.` prefix (no destroy/recreate)
- [x] CLAUDE.md updated

---

## GitOps CI/CD with GitHub Actions ✓

Add proper branch protection and automated plan/apply pipeline.

**Why:** Demonstrates real GitOps skills — no manual `terraform apply`, all changes go through PR review with visible plan output.

**Plan:**
- [x] Create `.github/workflows/plan.yml` — fmt-check, validate, plan → PR comment
- [x] Create `.github/workflows/apply.yml` — apply on merge to main, gated by GitHub Environment approval
- [x] Configure GitHub repo secrets (`TF_VAR_API_TOKEN`, `SOPS_AGE_KEY`), variables (`TF_VAR_ORG_NAME`, `AWS_ROLE_ARN`), and `dev` environment with required reviewer
- [x] Set up AWS IAM OIDC provider + `github-okta-gitops` role with trust for `ref:refs/heads/main`, `pull_request`, and `environment:*`
- [x] Enable branch protection on `main` (require PR + `plan / dev` status check)

---

## Promote prod, demote dev to showcase ✓

`environments/prod/` became the only active env. State object moved in S3 from `dev/terraform.tfstate` → `prod/terraform.tfstate`. Workflows retargeted to `prod`. `environments/dev/` kept as a read-only documentation copy with a README warning against running Terraform there. Branch protection required check renamed `plan / dev` → `plan / prod`. GitHub Environment renamed accordingly.

---

## Replace SOPS users/memberships with group rules ✓

Pivoted users out of Terraform entirely.

- Removed `okta_user` and `okta_group_memberships` resources from `modules/identity/`
- Added `okta_group_rule` driven by Okta Expression Language (`user.userType`, `user.division`)
- Dropped the SOPS provider, `.sops.yaml`, `data.yaml`, and the `SOPS_AGE_KEY` secret
- Replaced encrypted `data.yaml` with plain `groups.yaml` (group names + rule expressions are not secrets)
- Users now created in the Admin Console, sorted into groups by rules — see [source-of-truth.md](source-of-truth.md)

---

## Documentation site ✓

Moved long-form docs out of `README.md` and `CLAUDE.md` into `docs/`:

- `README.md` rewritten as a short entry point with links to `docs/`
- `docs/architecture.md`, `docs/source-of-truth.md`, `docs/runbook.md`, `docs/ci-cd.md`, `docs/state-backend.md`
- `TODO.md` → `docs/changelog.md` (this file)
- `CLAUDE.md` retained as the AI-facing terse reference

---

## Flatten to a single root + homelab groups ✓

Simplified the repo from a dev/prod environment split into one Terraform root, and refocused the example groups on the real use case: gating homelab k3s access via Okta OIDC.

- Moved `environments/prod/{main.tf,variables.tf,backend.hcl,groups.yaml,terraform.tfvars*,.terraform.lock.hcl}` to the repo root; `module.identity` source changed `../../modules/identity` → `./modules/identity`
- Deleted `environments/` (dev showcase + prod) and the empty `modules/policies/`, `modules/apps/` scaffolds
- Replaced `Engineering` / `IT-Admins` groups with `homelab-admins` (rule `user.division == "IT"` → `cluster-admin`) and `homelab-viewers` (manual membership → `view`)
- `homelab-admins` already existed in the org (created manually) — brought into state with `terraform import` instead of recreating; `Engineering` / `IT-Admins` are destroyed by the next apply
- Workflows: dropped the `matrix.environment` / `working-directory` indirection, retargeted trigger paths to root files, required check renamed `plan / prod` → `plan`
- S3 state key left as `prod/terraform.tfstate` to avoid a migration; documented how to rename
- Documented the Okta-group → OIDC `groups` claim → k8s `ClusterRoleBinding` mapping (binding lives in the separate homelab repo)
