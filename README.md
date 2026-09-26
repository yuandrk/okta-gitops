# 🔐 Okta GitOps

> Okta as the single sign-on for my homelab, managed with Terraform — groups, auto-assignment rules, and app integrations, changed only through reviewed PRs.

[![Terraform Plan](https://github.com/yuandrk/okta-gitops/actions/workflows/plan.yml/badge.svg)](https://github.com/yuandrk/okta-gitops/actions/workflows/plan.yml)
![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A5_1.10-7B42BC?logo=terraform&logoColor=white)
![Okta provider](https://img.shields.io/badge/okta%2Fokta-~%3E_7.0-blue)
![State](https://img.shields.io/badge/state-S3_native_locking-FF9900?logo=amazons3&logoColor=white)

## Why this exists

1. **Real SSO for the homelab.** Signing in to [Headlamp](https://headlamp.dev/) (k3s dashboard) and the Hermes dashboard goes through Okta, and the Okta side lives here.
2. **A rehearsal for Okta at work.** Patterns like import-before-apply, drift checks and the MCP-assisted admin get worked out here first, on a developer org where mistakes are cheap.
3. **Learning and a portfolio.** Each resource is annotated with the Okta API call and Admin Console screen it maps to.

## What's in the org

Org: `integrator-7752059.okta.com` (developer org), with custom domain `okta.yuandrk.net`.

| Thing | Managed by | Notes |
| --- | --- | --- |
| Group `homelab-admins` | Terraform | Rule `user.division == "IT"`. Gates Headlamp → k3s `cluster-admin` |
| Group `Andriuk corp` | Terraform | Same rule. Gates the Hermes tile |
| OIDC app `Headlamp` | Terraform | Web app, `issuer_mode: CUSTOM_URL`, sign-on policy "password only" |
| Bookmark `Hermes` | Terraform | Dashboard tile → `https://hermes.yuandrk.net` |
| OIDC app `Hermes Dashboard` | Admin Console | Native/PKCE public client. The module can't express it yet |
| OIDC app `okta-mcp-browser` | Admin Console | Login for the okta-mcp-server (device code). Bootstrap credential |
| `AI Harmess`, an old inactive `Hermes Dashboard` | Admin Console | Inactive leftovers and experiments |
| Built-in groups, `okta_*` system apps | Okta | Okta adds and removes these on its own |
| **Users** | Admin Console | Never in Terraform. Group rules sort them into groups |

Why things are split this way: [docs/design.md](docs/design.md).

## How it works

```mermaid
flowchart LR
    U[User in Okta<br/>division=IT] --> R[okta_group_rule]
    R -->|auto-assign| G1[homelab-admins]
    R -->|auto-assign| G2[Andriuk corp]
    G1 -->|assigned| A[Headlamp<br/>OIDC app]
    G2 -->|assigned| B[Hermes<br/>bookmark tile]
    A -->|OIDC via okta.yuandrk.net<br/>+ groups claim| H[Headlamp → k3s RBAC]
    B -->|link| HD[hermes.yuandrk.net]

    subgraph TF["🟣 Terraform (this repo)"]
        R
        G1
        G2
        A
        B
    end
```

The group name in the OIDC `groups` claim is the contract with the cluster. The `ClusterRoleBinding` that turns `homelab-admins` into `cluster-admin` lives in the separate homelab repo.

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# api_token comes from 1Password: op://homelab/okta-gitops/credential
aws login                                   # S3 state backend
terraform init -backend-config=backend.hcl
terraform plan                              # expect: No changes
```

## Making a change

Edit `config/groups.yaml` or `config/apps.yaml`, then open a PR. CI runs fmt, validate, tflint and the module tests, and posts the `terraform plan` as a comment. After the merge, the apply waits for manual approval in the `prod` environment. Recipes are in the [runbook](docs/runbook.md).

```text
okta-gitops/
├── versions.tf · providers.tf            # Terraform/provider versions, S3 backend, okta provider
├── locals.tf · main.tf                   # decode config/*.yaml → module calls
├── variables.tf · outputs.tf
├── backend.hcl                           # S3 backend config
├── config/
│   ├── groups.yaml                       # groups + group rules
│   └── apps.yaml                         # OIDC apps + bookmark tiles
└── modules/                              # each: versions · variables · outputs · README · tests/
    ├── identity/   # main.tf: okta_group, okta_group_rule
    └── apps/       # oidc.tf: okta_app_oauth (+ sign-on policy/rule); bookmarks.tf: okta_app_bookmark; group assignments
```

> **Two independent credentials.** Terraform uses an SSWS API token, which dies after 30 days without use. The okta-mcp-server uses its own device-code login. One can work while the other is dead, so check them separately.

## Docs

- [Runbook](docs/runbook.md): add a user, group, app or tile; rotate the token; drift check; state recovery
- [Design](docs/design.md): the decisions behind this setup, and lessons that carry over to work
- [CLAUDE.md](CLAUDE.md): rules for AI agents working in this repo

## License

MIT.
