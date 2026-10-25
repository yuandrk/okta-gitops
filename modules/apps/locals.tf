locals {
  # OIDC apps keyed by name — for_each keys are state addresses, e.g. "Grafana".
  apps_by_name = { for a in var.apps : a.name => a }

  # One assignment per app×group pair, keyed "App:Group" — e.g. "Grafana:Andriuk corp".
  app_group_pairs = merge([
    for a in var.apps : {
      for g in a.groups : "${a.name}:${g}" => { app = a.name, group = g }
    }
  ]...)

  # Bookmarks keyed by label, and their "Label:Group" assignment pairs.
  bookmarks_by_label = { for b in var.bookmarks : b.label => b }

  bookmark_group_pairs = merge([
    for b in var.bookmarks : {
      for g in b.groups : "${b.label}:${g}" => { app = b.label, group = g }
    }
  ]...)

  # SAML apps keyed by name, and their "App:Group" assignment pairs — e.g. "Fleet:IT".
  saml_apps_by_name = { for a in var.saml_apps : a.name => a }

  saml_app_group_pairs = merge([
    for a in var.saml_apps : {
      for g in a.groups : "${a.name}:${g}" => { app = a.name, group = g }
    }
  ]...)

  # signon_policy.possession → the possession half of an Okta verification-method
  # constraint. `required = true` is what the API returns, so writing it keeps the
  # plan clean after an apply.
  possession_constraints = {
    DEVICE_BOUND       = { required = true, deviceBound = "REQUIRED" }
    PHISHING_RESISTANT = { required = true, phishingResistant = "REQUIRED" }
  }
}
