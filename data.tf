# Reads users.yaml (SOPS-encrypted with age) and decrypts it at plan/apply time.
# The sops provider uses the age key from $SOPS_AGE_KEY_FILE or ~/.config/sops/age/keys.txt.
data "sops_file" "org" {
  source_file = "users.yaml"
}

locals {
  org         = yamldecode(data.sops_file.org.raw)
  groups_list = local.org.groups # list of {name, description}
  users_list  = local.org.users  # list of {first_name, last_name, login, email, status, groups}

  # group_name => list of user logins that belong to it
  group_member_logins = {
    for g in local.groups_list : g.name => [
      for u in local.users_list : u.login
      if contains(lookup(u, "groups", []), g.name)
    ]
  }
}
