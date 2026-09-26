terraform {
  required_version = ">= 1.10"

  # Modules set a floor only; the root module pins the exact range.
  required_providers {
    okta = {
      source  = "okta/okta"
      version = ">= 6.0"
    }
  }
}
