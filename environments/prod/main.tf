terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 6.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
  required_version = ">= 1.6.0"

  backend "s3" {}
}

# The okta provider authenticates to your org via API token.
# Under the hood every resource uses the Okta Management API.
provider "okta" {
  org_name  = var.org_name
  base_url  = var.base_url
  api_token = var.api_token
}

# Reads data.yaml (SOPS-encrypted with age) and decrypts it at plan/apply time.
# The sops provider uses the age key from SOPS_AGE_KEY_FILE or ~/.config/sops/age/keys.txt.
data "sops_file" "org" {
  source_file = "data.yaml"
}

locals {
  org = yamldecode(data.sops_file.org.raw)
}

module "identity" {
  source = "../../modules/identity"
  groups = local.org.groups
  users  = local.org.users
}
