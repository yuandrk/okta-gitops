terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.6.0"
}

# The okta provider authenticates to your org via API token.
# Under the hood every resource uses the Okta Management API:
# The provider translates HCL → REST calls automatically.
provider "okta" {
  org_name  = var.org_name  # e.g. "integrator-7752059"
  base_url  = var.base_url  # e.g. "okta.com"
  api_token = var.api_token # token from Admin Console → Security → API
}
