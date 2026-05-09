# State backend

State for the active environment lives in S3 with native S3 locking (no DynamoDB).

## Layout

```text
s3://terraform-state-homelab-yuandrk/
└── prod/
    ├── terraform.tfstate         # state object (versioned, SSE-S3 encrypted)
    └── terraform.tfstate.tflock  # transient lock object (only while apply runs)
```

Bucket is in `eu-west-2`. The legacy `dev/terraform.tfstate` key was deleted when prod became the active environment — `environments/dev/backend.hcl` still references it as a reminder that dev is showcase-only.

## `backend.hcl` for prod

```hcl
bucket       = "terraform-state-homelab-yuandrk"
key          = "prod/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true   # S3 native locking, requires Terraform ≥ 1.10
```

Pass with `terraform init -backend-config=backend.hcl`. The `backend "s3" {}` block in `main.tf` is intentionally empty — config is supplied at init time so the same `main.tf` could be reused across multiple state keys if needed.

## Why native S3 locking, not DynamoDB

- One less resource to provision, monitor, and pay for
- DynamoDB lock table was the historical workaround when S3 didn't support conditional writes; that's no longer the case as of Terraform 1.10
- Lock is just an object — easy to inspect and clear manually if a run is killed (see [runbook](runbook.md#recover-from-a-broken-state-lock))

## Provider lockfile

`.terraform.lock.hcl` is committed per environment. It pins the exact provider versions and checksum hashes Terraform fetched, so CI and local runs use byte-identical providers. Run `terraform init -upgrade` to bump.

## Recovery scenarios

### State got out of sync with reality

Someone changed something in the Admin Console that Terraform also manages. On next plan, Terraform will propose to undo the change.

- If the manual change was correct: import the new value or update the code to match, then apply
- If the manual change was wrong: just `terraform apply` to restore the declared state

### Accidental `terraform destroy`

S3 versioning is enabled on the state bucket. Restore the previous state object version:

```bash
aws s3api list-object-versions \
  --bucket terraform-state-homelab-yuandrk \
  --prefix prod/terraform.tfstate

aws s3api copy-object \
  --bucket terraform-state-homelab-yuandrk \
  --copy-source "terraform-state-homelab-yuandrk/prod/terraform.tfstate?versionId=<previous-version>" \
  --key prod/terraform.tfstate
```

Then `terraform plan` to see what's now drifted from the live Okta org.

### Need to move state

`terraform state mv` for in-state moves. For renaming the S3 key, change `backend.hcl`, then `terraform init -reconfigure -migrate-state`.
