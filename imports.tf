# Adopt what already exists in Okta instead of creating a duplicate (import before
# apply). An import block is a one-time instruction: once the apply has imported the
# resource the block is a no-op, and the next PR removes it.

# Security baseline (modules/security). Every org already has these authenticators
# and a default enrollment policy, so they are imported rather than created.
data "okta_authenticator" "import" {
  for_each = toset([for a in local.authenticators : a.key])
  key      = each.key
}

import {
  for_each = toset([for a in local.authenticators : a.key])
  to       = module.security.okta_authenticator.this[each.key]
  id       = data.okta_authenticator.import[each.key].id
}

# The default enrollment policy is a singleton; its import ID is ".".
import {
  to = module.security.okta_policy_mfa_default.this
  id = "."
}
