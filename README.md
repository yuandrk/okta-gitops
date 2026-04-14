# Okta Identity Management with Terraform

Infrastructure-as-Code management of Okta users, groups, and memberships using the official Okta Terraform provider. Built as a practical reference for IAM automation and GitOps-driven identity management.

---

## Highlights

- **Declarative IAM** — users, groups, and memberships defined in version-controlled HCL
- **Remote state on S3** with native locking (`use_lockfile = true`, Terraform 1.10+) — no DynamoDB required
- **Secret hygiene** — API tokens and state files gitignored; example files provided for onboarding
- **Documented intent** — every resource comments its underlying Okta Management API call and Admin Console equivalent
- **Provider version pinned** via committed `.terraform.lock.hcl` for reproducible builds

---

## Tech stack

| Layer | Tool |
|---|---|
| Identity provider | [Okta](https://www.okta.com/) (developer org) |
| IaC | Terraform `>= 1.10` with `okta/okta ~> 6.0` |
| Remote state | AWS S3 + native S3 locking |
| Secrets | Local `terraform.tfvars` (gitignored) → env vars in CI |

---

## Architecture

```
┌─────────────────┐        ┌──────────────────┐        ┌──────────────────┐
│   Terraform     │ ─────▶ │  Okta Mgmt API   │ ─────▶ │  Okta Org        │
│   (HCL files)   │        │  (via provider)  │        │  (users, groups) │
└────────┬────────┘        └──────────────────┘        └──────────────────┘
         │
         │ state
         ▼
┌─────────────────────┐
│  AWS S3 bucket      │
│  + native locking   │
│  + versioning + SSE │
└─────────────────────┘
```

---

## Repository layout

```
.
├── backend.tf              # S3 backend declaration (no values)
├── backend.hcl             # backend config — bucket, key, region, lock flag
├── provider.tf             # provider version + auth config
├── variables.tf            # typed input variables
├── groups.tf               # okta_group resources
├── users.tf                # okta_user resources
├── memberships.tf          # okta_group_memberships (authoritative)
├── outputs.tf              # exported values
├── terraform.tfvars.example # template for local credentials
├── .terraform.lock.hcl     # committed — pins provider versions
└── TODO.md                 # roadmap
```

---

## Quick start

```bash
# 1. Configure credentials (copy template, fill in Okta values)
cp terraform.tfvars.example terraform.tfvars

# 2. Initialize with S3 backend
terraform init -backend-config=backend.hcl

# 3. Preview and apply
terraform plan
terraform apply
```

AWS credentials for the state bucket are resolved via the standard AWS SDK chain (env vars, `AWS_PROFILE`, or IAM role in CI).

---

## Design decisions

### Why S3 native locking over DynamoDB
Terraform 1.10 added `use_lockfile = true` for the S3 backend, storing lock metadata as an S3 object. Removes the need for a DynamoDB table — one less resource to provision and pay for.

### Why `okta_group_memberships` (plural) over `okta_group_membership` (singular)
The plural resource is **authoritative** — it owns the complete member list for a group. Membership drift from manual Admin Console edits is automatically corrected on the next apply, which is the behavior we want for IaC-managed identity.

### Why users are staged, not active
Test users are created with `status = "STAGED"` so no activation email is sent and no real account is provisioned. Changing to `"ACTIVE"` triggers the full Okta activation flow.

### Why state lives in S3, not locally
Local state breaks in CI/CD and on teams. Remote state with locking is the baseline for any shared or automated Terraform workflow.

---

## Roadmap

See [TODO.md](TODO.md) for the full plan:

1. **YAML + SOPS** for user/group data — encrypted at rest, reviewable via PR diffs, safe to commit publicly
2. **GitHub Actions CI/CD** — `terraform plan` as PR comment, `terraform apply` on merge to `main`, branch protection on `main`

---

## References

- [Okta Terraform provider docs](https://registry.terraform.io/providers/okta/okta/latest/docs)
- [Okta Management API](https://developer.okta.com/docs/reference/core-okta-api/)
- [S3 backend with native locking](https://developer.hashicorp.com/terraform/language/backend/s3)
