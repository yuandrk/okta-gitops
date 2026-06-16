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

# groups.yaml / apps.yaml are plain text — group names, rule expressions, and app
# config are not secrets. Users are the source of truth and are created in the Admin
# Console (or via SCIM/HRIS); group rules sort them into groups by profile attributes.
locals {
  org  = yamldecode(file("${path.module}/groups.yaml"))
  apps = yamldecode(file("${path.module}/apps.yaml"))
}

module "identity" {
  source = "./modules/identity"
  groups = local.org.groups
}

module "apps" {
  source    = "./modules/apps"
  apps      = local.apps.apps
  group_ids = module.identity.group_ids
}
