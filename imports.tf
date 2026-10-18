# Adopt what already exists in Okta instead of creating a duplicate (import before
# apply). An import block is a one-time instruction: once the apply has imported the
# resource the block is a no-op, and the next PR removes it.

# Hermes Dashboard: the public native (PKCE) client, created in the Admin Console.
import {
  to = module.apps.okta_app_oauth.oidc["Hermes Dashboard"]
  id = "0oa16q11mp5oL7Brc698"
}

# Its assignment to Andriuk corp, also made in the Console. ID format: <app_id>/<group_id>.
import {
  to = module.apps.okta_app_group_assignment.oidc["Hermes Dashboard:Andriuk corp"]
  id = "0oa16q11mp5oL7Brc698/${module.identity.group_ids["Andriuk corp"]}"
}
