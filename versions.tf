terraform {
  # >= 1.10: the S3 backend's native locking (use_lockfile) needs it.
  required_version = ">= 1.10"

  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 7.0"
    }
  }

  # Partial config — values live in backend.hcl (terraform init -backend-config=backend.hcl).
  backend "s3" {}
}
