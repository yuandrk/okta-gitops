# prod

Placeholder — not yet provisioned.

When ready, this directory will mirror `../dev/` with its own:
- `main.tf` — provider config and module calls
- `variables.tf`
- `backend.hcl` — `key = "prod/terraform.tfstate"`
- `terraform.tfvars` (gitignored) — prod API token
- `data.yaml` — SOPS-encrypted prod users and groups
