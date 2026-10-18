# Temporary probe, removed before this PR is ready: does google_otp exist in this
# org, and does the API give it a real ID? Okta Verify comes back with the ID
# "okta_verify", which can't be fetched.
data "okta_authenticator" "probe_google_otp" {
  key = "google_otp"
}

output "probe_google_otp" {
  description = "Temporary: what the API returns for google_otp"
  value = {
    id     = data.okta_authenticator.probe_google_otp.id
    name   = data.okta_authenticator.probe_google_otp.name
    status = data.okta_authenticator.probe_google_otp.status
  }
}
