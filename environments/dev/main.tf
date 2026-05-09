terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 6.0"
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

locals {
  org = yamldecode(file("${path.module}/groups.yaml"))
}

module "identity" {
  source = "../../modules/identity"
  groups = local.org.groups
}
