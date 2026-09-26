# The okta provider authenticates to your org via API token.
# Under the hood every resource uses the Okta Management API.
provider "okta" {
  org_name  = var.org_name
  base_url  = var.base_url
  api_token = var.api_token
}
