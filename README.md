# Okta GitOps

Hands-on learning project: managing an [Okta](https://www.okta.com/) developer org with Terraform via the official [okta/okta](https://registry.terraform.io/providers/okta/okta/latest/docs) provider.

The repo demonstrates a small but real GitOps workflow — modular Terraform, remote state on S3 with native locking, GitHub Actions plan/apply pipeline gated by an environment, and OIDC auth to AWS (no static keys). Users are intentionally **not** managed by Terraform — they live in Okta as the source of truth, and Terraform owns only groups and the rules that auto-assign users by profile attributes.

```text
HR/Admin Console ──▶ Okta (users)            ◀── source of truth for people
                            │
                            │ profile attributes (userType, division)
                            ▼
                    okta_group_rule  ◀── managed by Terraform
                            │
                            ▼
                       okta_group    ◀── managed by Terraform
```

## Quick start

```bash
git clone https://github.com/yuandrk/okta-gitops
cd okta-gitops/environments/prod

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — add your Okta API token

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Need a deeper dive? See [`docs/`](docs/):

- [Architecture](docs/architecture.md) — repo layout, modules, environments
- [Source of truth](docs/source-of-truth.md) — why users live in Okta, how group rules work
- [Runbook](docs/runbook.md) — add a group, add a user, rotate the API token
- [CI/CD](docs/ci-cd.md) — plan/apply workflows, OIDC trust, branch protection
- [State backend](docs/state-backend.md) — S3 native locking, recovery
- [Changelog](docs/changelog.md) — what was built, in order

## Stack

| Layer | Choice |
| --- | --- |
| Identity provider | Okta developer org (`integrator-7752059.okta.com`) |
| IaC | Terraform `>= 1.10` with `okta/okta ~> 6.0` |
| Remote state | AWS S3 + native S3 locking (`use_lockfile = true`) |
| CI/CD | GitHub Actions, OIDC to AWS, GitHub Environment gate |
| Secrets | `TF_VAR_api_token` env var (CI) / `terraform.tfvars` (local, gitignored) |

## License

MIT — see [LICENSE](LICENSE) if present, otherwise treat as MIT-style.
