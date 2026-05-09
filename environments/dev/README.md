# dev — showcase only

This directory is kept as a **read-only example** of how an environment is wired up
(provider config, SOPS data source, module call, S3 backend). It is not the active
environment.

The working environment is [`../prod/`](../prod/). State for this project lives at
`s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate`. CI workflows
(`.github/workflows/plan.yml`, `apply.yml`) target prod only.

Do **not** run `terraform apply` here — it would create a separate, empty state at
`dev/terraform.tfstate` and start managing the same Okta org in parallel with prod.
