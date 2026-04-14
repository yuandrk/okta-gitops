# TODO

## User management via YAML + SOPS

Replace hardcoded/tfvars user definitions with an encrypted YAML file committed to the repo.

**Why:** GitOps-friendly — user additions/removals are tracked as git diffs, reviewable via PRs, safe to store in a public repo.

**Plan:**
- [ ] Add `users.yaml` with user + group membership data
- [ ] Encrypt `users.yaml` with SOPS (age or AWS KMS key)
- [ ] Add `terraform-provider-sops` to `provider.tf`
- [ ] Refactor `users.tf` to use `yamldecode(sops_decrypt_file("users.yaml"))` with `for_each`
- [ ] Refactor `groups.tf` and `memberships.tf` to be data-driven from the same YAML
- [ ] Update CI/CD to inject the SOPS decryption key (age private key or KMS access)
- [ ] Document SOPS setup in CLAUDE.md

**References:**
- [terraform-provider-sops](https://registry.terraform.io/providers/carlpett/sops/latest/docs)
- [SOPS by Mozilla](https://github.com/getsops/sops)

---

## Remote state in S3

Move Terraform state from local file to S3 with DynamoDB locking.

**Why:** Local state breaks in CI/CD and on teams — S3 backend gives shared, versioned state with locking so concurrent applies don't corrupt it.

**Plan:**
- [ ] Create S3 bucket (versioning enabled, SSE-S3 or KMS encryption)
- [ ] Create DynamoDB table for state locking (`LockID` as partition key)
- [ ] Add `backend "s3"` block to `provider.tf`
- [ ] Run `terraform init -migrate-state` to move existing local state to S3
- [ ] Add `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (or OIDC role) to GitHub Actions secrets
- [ ] Gitignore `terraform.tfstate` is already in place — verify nothing leaks after migration

**Backend config:**
```hcl
terraform {
  backend "s3" {
    bucket         = "okta-tf-state"
    key            = "okta/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "okta-tf-state-lock"
    encrypt        = true
  }
}
```

---

## GitOps CI/CD with GitHub Actions

Add proper branch protection and automated plan/apply pipeline.

**Why:** Demonstrates real GitOps skills — no manual `terraform apply`, all changes go through PR review with visible plan output.

**Plan:**
- [ ] Create `.github/workflows/plan.yml` — runs on PR: `fmt -check`, `validate`, `plan` (post output as PR comment)
- [ ] Create `.github/workflows/apply.yml` — runs on merge to `main`: `apply -auto-approve`
- [ ] Add required GitHub Actions secrets: `TF_VAR_api_token`, `TF_VAR_org_name`
- [ ] Enable branch protection on `main` (no direct push, require PR + CI pass)
- [ ] First PR should be `feature/ci-github-actions` → merge via the new pipeline itself
