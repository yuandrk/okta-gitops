# Runbook

How to do common changes and handle incidents. For the reasoning behind any of this, see [design.md](design.md).

All Terraform commands run from the repo root. Always read the output of `terraform plan` before you apply.

---

## Before anything: credentials

Two things have to be valid, and each expires on its own:

```bash
# AWS, for the S3 state backend
aws sts get-caller-identity || aws login

# Okta SSWS token, for the Terraform provider. Never echo the token itself.
TOK=$(op read "op://homelab/okta-gitops/credential")
curl -s -H "Authorization: SSWS $TOK" -H "Accept: application/json" \
  "https://integrator-7752059.okta.com/api/v1/users/me" | jq -r '.errorSummary // "token OK: \(.profile.login)"'
```

The login it prints is the token's owner, which should be [`svc-terraform`](#create-terraforms-admin-svc-terraform). `terraform.tfvars` must contain the same token that 1Password has. See [Rotate the Okta API token](#rotate-the-okta-api-token).

---

## Day to day

### Add a user

Users are not managed in Terraform.

1. Go to Admin Console → **Directory → People → Add Person**.
2. Set **Division**. `IT` is currently the only value any rule matches: it lands the user in `Andriuk corp`.
3. Save. The group rules evaluate within seconds.
4. Check in **Directory → Groups → \<group\> → People**.

If the user didn't land in a group:
- Check that the rule is **ACTIVE**.
- Attribute values are case-sensitive.
- Rules only fire on user creation and on profile changes.

### Add a group or change a rule

Edit `config/groups.yaml`:

```yaml
- name: homelab-viewers
  description: Read-only access to the homelab
  rule: 'user.division == "IT" and user.userType == "Contractor"'   # optional
```

Then add a line to [CHANGELOG.md](../CHANGELOG.md), open a PR, review the plan comment, merge, and approve the apply in the `prod` environment. Afterwards `terraform output inventory` shows the group with its rule.

To change an existing rule expression, the provider deactivates the rule, updates it, and reactivates it. In the plan this shows as `ACTIVE → INACTIVE → ACTIVE`, which is expected.

### Add an OIDC app

Add an entry to `config/apps.yaml`. Only `name`, `redirect_uris`, `signon_policy.name` and `signon_policy.description` are required. Everything else has defaults in `modules/apps/variables.tf`, and validation there catches bad enum values and group names that aren't in `groups.yaml`.

```yaml
- name: Grafana
  type: web
  grant_types: ["authorization_code", "refresh_token"]
  redirect_uris: ["https://grafana.yuandrk.net/login/generic_oauth"]
  post_logout_redirect_uris: ["https://grafana.yuandrk.net"]
  issuer_mode: CUSTOM_URL      # tokens issued by okta.yuandrk.net, so it shares the dashboard SSO session
  hide_web: false              # tile on the end-user dashboard (needs login_mode + login_uri)
  login_mode: SPEC
  login_scopes: ["openid"]
  login_uri: "https://grafana.yuandrk.net"
  groups: ["Andriuk corp"]
  signon_policy:
    name: "Grafana Sign-On Policy"
    description: "Managed by Terraform — password + second factor"
    # factor_mode defaults to 2FA with a 12h re-auth (re_authentication_frequency: PT12H).
    # Everyone assigned must have a second factor enrolled, or they can't sign in.
```

After the apply, read the client credentials and use them to configure the app:

```bash
terraform output oidc_client_ids
terraform output -json oidc_client_secrets | jq -r '.Grafana'
```

The app `name` and each `App:Group` pair are `for_each` keys. **Renaming either one destroys and recreates the resource**, and a recreated app gets a new client ID and secret.

For a public client (a native or browser app that holds no secret, such as a desktop app or a single-page app), set `type: native` or `type: browser`, `token_endpoint_auth_method: none` and `pkce_required: true`. Validation rejects `none` anywhere else. A public client has no entry in `oidc_client_secrets`, and a native one can't have a dashboard tile, so add a bookmark if it needs one. See [design.md](design.md#hermes-retired-2026-10-18).

### Add a SAML app

For a service provider that speaks SAML 2.0 but not OIDC. Add an entry under `saml_apps` in `config/apps.yaml`:

```yaml
saml_apps:
  - name: Fleet
    sso_url: https://fleet.yuandrk.net/api/v1/fleet/sso/callback   # the SP's ACS URL
    audience: https://fleet.yuandrk.net                            # the SP's entity ID
    groups: ["IT"]
    signon_policy:
      name: "Fleet Sign-On Policy"
      description: "Managed by Terraform — password + second factor"
      possession: DEVICE_BOUND
```

The ACS URL comes from the SP's docs. The entity ID is whatever the SP is configured with, and the two sides must match character for character. The module sets the rest: NameID = the user's email, response and assertion signed with SHA-256, no dashboard tile. The sign-on policy works as it does for OIDC apps.

After the apply, give the SP the metadata URL. There's no secret to hand over:

```bash
terraform output saml_metadata_urls
```

It's on the custom domain, so the SP sends people to the domain that holds their Okta session ([why](design.md#fleet-signs-in-with-saml)). As with OIDC apps, the `name` and each `App:Group` pair are `for_each` keys: renaming the app recreates it with a new signing certificate and metadata URL, and the SP has to be pointed at the new one.

### Sign in to Fleet with Okta

Fleet's side, set by hand in Fleet after the apply that created the `Fleet` app. Keep the order: step 1 leaves a way into Fleet if single sign-on breaks.

1. **A break-glass admin first.** Settings → Users → Create user: role Admin, password authentication, an email of its own (plus addressing works). Keep the password in 1Password. If Fleet can send mail (SMTP is set up), turn on email two-factor authentication for it.
2. Settings → Organization settings: check that **Fleet web address** is `https://fleet.yuandrk.net`. Fleet builds the callback URL in its SAML requests from it.
3. Settings → Integrations → Authentication (SSO) → **Fleet users**:

   | Field | Value |
   | --- | --- |
   | Enable single sign-on | on |
   | Identity provider name | `Okta`, shown on the login button |
   | Entity ID | `https://fleet.yuandrk.net`, the same as `audience` in `config/apps.yaml` |
   | IdP image URL, Metadata | empty |
   | Metadata URL | from `terraform output saml_metadata_urls`, also printed at the end of the apply log |
   | Allow SSO login initiated by identity provider | off: the login starts at Fleet |

4. Signed in as the break-glass admin: Settings → Users → your user. Its email must be your primary email in Okta, which is what the NameID carries. Then Actions → Edit → **Enable single sign-on**. From then on, that user can't sign in with a password.
5. Test in a private window: Fleet → **Sign in with Okta**. The address bar should show `okta.yuandrk.net`. After the password and Okta Verify you're back in Fleet, signed in. Then check that the break-glass admin still gets in with its password.

If Fleet answers that the user doesn't exist, the email in Fleet doesn't match the one Okta sends. Optionally, set `FLEET_SESSION_DURATION=12h` in Fleet's deployment, so Fleet sends you back to Okta as often as the sign-on policy asks for ([why](design.md#fleet-signs-in-with-saml)).

### Add a dashboard tile (bookmark)

Use this for anything that needs a link on the Okta dashboard but has no OIDC app of its own, or whose OIDC app can't have a tile:

```yaml
bookmarks:
  - label: Grafana
    url: https://grafana.yuandrk.net
    groups: ["Andriuk corp"]
```

### Retire an app, group or tile

1. Remove the entry from `config/apps.yaml` or `config/groups.yaml`, along with any reference to a removed group in apps and bookmarks. Validation rejects group names that no longer exist.
2. Open a PR. The destroy guard fails the `plan` check and lists everything the plan would delete.
3. Check the list, then add the `allow-destroy` label. The check re-runs and passes.
4. Merge, then approve the apply.

If the guard fires on a PR that wasn't meant to delete anything, a `for_each` key changed: an app, group or bookmark was renamed. Put the old name back. To rename on purpose, add a `moved` block for every address that changes (for an app: the app, its policy, its rule and its `App:Group` assignments), so the plan shows moves instead of replaces.

### Check the code locally (what CI runs)

```bash
terraform fmt -check -recursive
terraform validate
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
for m in modules/*/; do terraform -chdir="$m" init -backend=false >/dev/null && terraform -chdir="$m" test; done
terraform-docs modules/identity && terraform-docs modules/apps   # refresh module READMEs after changing variables/outputs
```

The module tests use a mocked provider, so they need no token and make no Okta calls.

### Check for drift

Drift is anything changed in the Admin Console that the code doesn't know about.

- **Quick way:** in Claude Code, run `/okta-drift`. It compares the live inventory (via MCP) against the YAML and runs `terraform plan`.
- **From CI:** Actions → *Terraform Drift* → *Run workflow*, or `gh workflow run drift.yml`. It runs the plan only, and the result is in the run summary. Green means no drift.
- **By hand:**
  1. List groups and apps with the MCP tools, or in the Admin Console.
  2. Sort each one into one of three buckets: in YAML, deliberately in the Console (see the [README](../README.md#whats-in-the-org)), or drift.
  3. Run `terraform plan`. Group rules can **only** be checked this way.

### Adopt something that was created in the Console

Import it **before** you apply. Otherwise the apply tries to create a duplicate.

The usual way is an import block, so the import is reviewed in the PR and CI applies it:

1. Add the entry to `config/*.yaml`, and an `import` block for each resource to `imports.tf`. The ID formats are on each resource's registry page.

   ```hcl
   import {
     to = module.apps.okta_app_oauth.oidc["<name>"]
     id = "<0oa…id>"
   }
   ```

2. Open a PR. The plan comment shows `will be imported`, followed by every attribute where the YAML and the live object differ.
3. Adjust the YAML until only the changes you mean remain, then merge and approve the apply.
4. In the next PR, delete the block. Once applied it's a no-op.

From a laptop, the CLI does the same: `terraform import '<address>' <id>`, then `terraform plan` until that resource shows no changes.

### Change an authenticator, an enrollment or a session policy

Edit `config/security.yaml`:

- `authenticators[].status` turns one on or off. `INACTIVE` fails while any policy still uses it.
- `enrollment` sets `REQUIRED`, `OPTIONAL` or `NOT_ALLOWED` per authenticator key on the default enrollment policy. An authenticator has to be active before anything but `NOT_ALLOWED` is accepted.
- `session` sets the global session policy for everyone: idle and maximum minutes, and whether the cookie survives closing the browser. `break_glass` sets the break-glass admin's own factor and session.
- Removing an authenticator from the list **deactivates** it (Okta can't delete one), so the destroy guard blocks the PR. Everyone enrolled in it loses that factor. Usually you want `status: INACTIVE`, or nothing at all.

A factor that one app needs goes on that app instead: `signon_policy.possession` in `config/apps.yaml`.

Anything that tightens sign-in follows the same protocol:

1. Keep an admin session open in another browser while the apply runs.
2. After the apply, sign in to an app in a private window.
3. Check that the [break-glass admin](#set-up-and-test-the-break-glass-admin) still gets in.

### Set up and test the break-glass admin

The break-glass admin is a second super admin that doesn't depend on your phone. Its policies come first in `config/security.yaml`, and its credentials live in 1Password.

1. Admin Console → Directory → People → Add Person, with a mailbox you control. Set a long random password and save both in a 1Password item.
2. Security → Administrators → Add administrator: the new user, Super Administrator.
3. Directory → Groups → `break-glass` → Assign people: the new user. Nobody else belongs in this group.
4. In a private window, sign in as the new user and enroll the factor named in `break_glass.factor`. Keep its secret in the same 1Password item. No factor is set yet ([why](design.md#security-baseline-adopt-first-then-tighten)), so for now the account has only a password, and the Admin Console's own sign-on policy may not let it in.
5. Open the Admin Console as that user, then sign out.

Test it every quarter, the same way as step 5. A break-glass account that has quietly stopped working is worse than none, because you find out during an incident.

### Create Terraform's admin (`svc-terraform`)

Terraform's API token belongs to an admin of its own, not to your account ([why](design.md#terraform-runs-as-its-own-admin-svc-terraform)). One-time setup:

1. Admin Console → Directory → People → Add Person: first name `svc`, last name `terraform`, username and email on a mailbox you control (plus addressing works). Leave **Division** empty, so no group rule picks the account up. Set a long random password and save the login in the 1Password item `okta-gitops`, next to the token.
2. Security → Administrators → Add administrator: `svc-terraform`, Super Administrator.
3. In a private window, sign in as `svc-terraform`. The Admin Console asks for a second factor: enroll Okta Verify, as a second account in the app.
4. Mint its token, roll it out and revoke your own account's token with [Rotate the Okta API token](#rotate-the-okta-api-token). The credentials check above should then print the `svc-terraform` login.

### Review a Renovate PR

Renovate opens dependency PRs on Monday mornings (London time), and refreshes the lock file on the first of the month.

- **GitHub Actions** arrive as one grouped PR, pinned to commit SHAs. The plan should say No changes.
- **The okta provider inside `~> 7.0`** changes only `.terraform.lock.hcl`. Still read the plan: a minor release can change how a resource is read. After the merge the apply runs and waits for approval, usually with No changes.
- **A new provider major** (`~> 7.0` → `~> 8.0`) gets its own PR. Read the provider's upgrade guide, check the plan for the resources this repo uses, and add a CHANGELOG line, as in [#14](https://github.com/yuandrk/okta-gitops/pull/14).

The Dependency Dashboard issue lists everything Renovate has pending or held back.

---

## Incidents

### `401 Unauthorized` from the provider

```
Error: [ERROR] failed validate configuration: error with v3 SDK client: 401 Unauthorized
```

This means the token expired: SSWS tokens die after **30 days without API calls**. The config is fine, so don't debug the `.tf` files. Rotate the token, as below.

The MCP tools keep working through a 401, because they use a different credential. That doesn't mean Terraform's token is fine.

### Rotate the Okta API token

A token acts as the admin who minted it, so mint it as `svc-terraform`, never from your own account. It has to be updated in **both** places, or CI stays broken:

```bash
# 1. Private window, signed in as svc-terraform (login in 1Password okta-gitops):
#    Admin Console → Security → API → Tokens → Create Token → save into 1Password (okta-gitops)

# 2. Local: write it into terraform.tfvars without printing it
TOK=$(op read "op://homelab/okta-gitops/credential") \
  awk '/^api_token/{print "api_token = \"" ENVIRON["TOK"] "\""; next} {print}' terraform.tfvars > t.new \
  && command mv -f t.new terraform.tfvars

# 3. CI
op read "op://homelab/okta-gitops/credential" | gh secret set TF_VAR_API_TOKEN
```

Then run `terraform plan`. You should see No changes; the token isn't stored in state. If the old token is still live, revoke it in Security → API → Tokens (the list shows who created each one), so only one exists.

### Stale state lock

If a run was killed mid-apply, the lock can be left behind as an object in S3. Only delete it if nothing else is running:

```bash
aws s3 ls s3://terraform-state-homelab-yuandrk/prod/
aws s3 rm s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate.tflock
```

### Restore state (accidental destroy or corrupted state)

The bucket is versioned. Copy the previous version back over the current one:

```bash
aws s3api list-object-versions --bucket terraform-state-homelab-yuandrk --prefix prod/terraform.tfstate
aws s3api copy-object --bucket terraform-state-homelab-yuandrk \
  --copy-source "terraform-state-homelab-yuandrk/prod/terraform.tfstate?versionId=<id>" \
  --key prod/terraform.tfstate
terraform plan   # see how far live Okta has moved from the restored state
```

### Stop a rule from assigning users right now

1. **Stopgap:** Admin Console → Directory → Groups → Rules → deactivate the rule. The next apply turns it back on.
2. **Proper fix:** remove the `rule:` line from `config/groups.yaml` (keeps the group), or remove the whole entry. Then open a PR and apply.

### Locked out of your own account

Your phone with Okta Verify is gone, or a policy change shut you out:

1. Sign in as the break-glass admin, with the password and one-time code from its 1Password item.
2. Fix the cause. For a lost phone: Directory → People → you → Reset Authenticators, then enroll again. For a bad policy: revert the PR. CI's token doesn't need a Console session, so the revert applies like any other change.
3. Sign out of the break-glass account, and check that your own account works.
