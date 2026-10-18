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
  "https://integrator-7752059.okta.com/api/v1/users/me" | jq -r '.errorSummary // "token OK"'
```

`terraform.tfvars` must contain the same token that 1Password has. See [Rotate the Okta API token](#rotate-the-okta-api-token).

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

For a public client (a native or browser app that holds no secret, like `Hermes Dashboard`), set `type: native` or `type: browser`, `token_endpoint_auth_method: none` and `pkce_required: true`. Validation rejects `none` anywhere else. A public client has no entry in `oidc_client_secrets`, and it can't have a dashboard tile, so add a bookmark if it needs one. See [design.md](design.md#hermes-a-public-native-client-and-a-bookmark-for-its-tile).

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

### Change an authenticator or the enrollment policy

Edit `config/security.yaml`:

- `authenticators[].status` turns one on or off. `INACTIVE` fails while any policy still uses it.
- `enrollment` sets `REQUIRED`, `OPTIONAL` or `NOT_ALLOWED` per authenticator key on the default enrollment policy. An authenticator has to be active before anything but `NOT_ALLOWED` is accepted.
- Removing an authenticator from the list **deactivates** it (Okta can't delete one), so the destroy guard blocks the PR. Everyone enrolled in it loses that factor. Usually you want `status: INACTIVE`, or nothing at all.

Before applying a change that tightens sign-in, keep an admin session open in another browser, and check that the break-glass admin can still get in.

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

It has to be updated in **both** places, or CI stays broken:

```bash
# 1. Admin Console → Security → API → Tokens → Create Token → save into 1Password (okta-gitops)

# 2. Local: write it into terraform.tfvars without printing it
TOK=$(op read "op://homelab/okta-gitops/credential") \
  awk '/^api_token/{print "api_token = \"" ENVIRON["TOK"] "\""; next} {print}' terraform.tfvars > t.new \
  && command mv -f t.new terraform.tfvars

# 3. CI
op read "op://homelab/okta-gitops/credential" | gh secret set TF_VAR_API_TOKEN
```

Then run `terraform plan`. You should see No changes; the token isn't stored in state.

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
