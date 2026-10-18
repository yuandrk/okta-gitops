# Adopt what already exists in Okta instead of creating a duplicate (import before
# apply), or let go of what Terraform shouldn't track any more (removed). Each block is
# a one-time instruction: once applied it's a no-op, and the next PR removes it.

# #26's apply created a Google Authenticator (aut18ur2y4sw3mjUr698) that the API now
# answers with 404, so every plan failed while refreshing it. A removed block forgets
# a resource without refreshing it, but can't name one for_each instance, so the whole
# old `okta_authenticator.this` is forgotten (nothing changes in Okta), and Password and
# Email are imported again under the new name, `by_key`.
removed {
  from = module.security.okta_authenticator.this

  lifecycle {
    destroy = false
  }
}

import {
  to = module.security.okta_authenticator.by_key["okta_password"]
  id = "aut1184gquzOCZiXH698"
}

import {
  to = module.security.okta_authenticator.by_key["okta_email"]
  id = "aut1184gqv0CEChLZ698"
}
