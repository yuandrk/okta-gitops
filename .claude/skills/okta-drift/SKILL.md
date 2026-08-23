---
name: okta-drift
description: Diff the live Okta org against this repo's Terraform (groups.yaml / apps.yaml) and report drift. Use when asked to "check Okta vs Terraform", "drift check", "reconcile", "what's in Okta that isn't in code", or before starting reconcile work. Read-only by default — proposes import-before-apply for real drift, never applies on its own.
---

# okta-drift — live Okta ↔ Terraform reconciliation

Compares what actually exists in the Okta org (`integrator-7752059.okta.com`) against what this
repo's Terraform declares, and reports a clean three-way classification: **managed**, **deliberately
unmanaged**, **drift**. This is a read-only diagnostic — it makes no Okta or state changes itself.

## When to run

- "check okta mcp and terraform" / "compare Okta to the code" / "drift check" / "reconcile"
- Before adding or changing a group/app, to confirm the baseline is clean
- After someone clicked something in the Admin Console, to catch unmanaged changes

## Steps

### 1. Read live Okta (read-only MCP — `okta-mcp-server`)

- `list_groups` — full group inventory (note `type`: `BUILT_IN` vs `OKTA_GROUP`)
- `list_applications` — full app inventory (note `name`/`label`, `signOnMode`, `oauthClient.application_type`, `token_endpoint_auth_method`)
- `get_application` — only if you need one app's detail (oauth config, jwks)
- `list_group_users` / `get_user_profile_attributes` — only if membership or schema is in question

> **Never** call write tools (`create_*`, `update_*`, `delete_*`, `add_user_to_group`, …) from this skill.

### 2. Read the code

Compare against the YAML the Terraform root decodes (read the **current branch**, or `git show origin/main:groups.yaml` for the deployed truth):

- `groups.yaml` → `okta_group` + `okta_group_rule` (managed group names)
- `apps.yaml` → `okta_app_oauth` + signon policy/rule + group assignment (managed app labels)

### 3. Classify every live resource

**Groups**
- `type == "BUILT_IN"` → **deliberately unmanaged** (Okta-owned). Current: `Everyone`, `Okta Administrators`.
- name present in `groups.yaml` → **managed** ✅
- `OKTA_GROUP` **not** in `groups.yaml` → **DRIFT** ⚠️ (created in the Console, not in code)

**Apps**
- Okta first-party / system apps → **deliberately unmanaged**. Identify by `name` (the app's internal name, not the label):
  `saasure` (Admin Console), `okta_enduser` (Dashboard), `okta_browser_plugin`,
  `okta_oin_submission_tester_app`, `okta_iga_reviewer` (Access Certification Reviews),
  `okta_flow_sso` (Workflows), `flow` (Workflows OAuth).
  **Treat this list as a hint, not a roster.** Okta both adds and removes first-party apps on its
  own — `okta_personal_app_migration` appeared 2026-06-26 and was gone by 2026-08-23. So classify
  by the shape, not by the list: an app whose internal `name` is an `okta_*` / Okta-internal
  identifier, which nobody here created, is unmanaged-on-purpose. Note it in the report; don't
  flag it as drift, and don't bother adding it here.
- label `C_mcp` (service app: `application_type == "service"`, `token_endpoint_auth_method == "private_key_jwt"`, `autoKeyRotation: true`) → **deliberately unmanaged**. Reason: Okta-generated auto-rotating keys would perpetually drift, and it's the okta-mcp-server's own bootstrap credential. See CLAUDE.md → "Deliberately unmanaged resources".
- label `Hermes Dashboard` (`0oa16q11mp5oL7Brc698` — `application_type: native`, `token_endpoint_auth_method: none`, PKCE) and label `AI Harmess` (`0oa16pzy2koEUVYf1698`, INACTIVE) → **deliberately unmanaged**. See CLAUDE.md → "Deliberately unmanaged resources" for why Hermes can't be adopted as-is.
  Note there was briefly a **second, abandoned** app also labelled `Hermes Dashboard` (`0oa16pzv08uDQV7Fy698`, `web` + client secret, `ORG_URL`) — superseded 2026-08-22 and deactivated. If two same-labelled apps ever show up again, match by **id**, not label, and check `~/.hermes/config.yaml` on k3s-master for the one actually in use.
- label present in `apps.yaml` → **managed** ✅ (currently `Headlamp`)
- any other `oidc_client` app not in `apps.yaml` → **DRIFT** ⚠️

### 4. Group rules & state-level cleanliness → `terraform plan`

- **No MCP tool reads group rules.** Their presence/absence and expression are confirmed **only** by `terraform plan`.
- A managed resource can still have *field-level* drift (e.g. an app setting changed in the Console) that the inventory diff won't catch — `terraform plan` is the authority.
- Running plan needs **two independent credentials** — AWS for the S3 backend, and the Okta SSWS token for the provider. Either can be dead while the other works:
  - `aws sts get-caller-identity` — if it errors with an expired session, tell the user to run `! aws login` (interactive, they do it), then continue.
  - `terraform init -backend-config=backend.hcl` (if `.terraform` is absent), then `terraform plan`.
  - `No changes.` ⇒ code and live state are in sync. Any diff ⇒ report it verbatim.
- **`401 Unauthorized` from the provider is an expired Okta token, not a broken config:**
  ```
  Error: [ERROR] failed validate configuration: error with v3 SDK client: 401 Unauthorized
  ```
  SSWS tokens die after 30 days without API calls. Do **not** start debugging `main.tf` or the
  variables — send the user to `CLAUDE.md` → Credentials → "The token expires", which covers
  rotating it in both `terraform.tfvars` and the `TF_VAR_API_TOKEN` GitHub secret.
  This is easy to misread from inside this skill: steps 1–3 above will have just succeeded,
  because the MCP authenticates as `C_mcp` via `private_key_jwt` and is unaffected by the SSWS
  token. A working `list_groups` says nothing about whether Terraform can authenticate.
- If either credential is unavailable, still deliver the inventory diff from steps 1–3 and clearly note that the plan-level check was skipped — and which credential blocked it.

### 5. Report

Emit one compact table — Resource · Type · In TF? · Verdict (✅ managed / ⚪ unmanaged-on-purpose / ⚠️ drift) — plus a one-line summary. End with the `terraform plan` result (or that it was skipped and why).

### 6. For real drift — propose, don't apply

Per the repo workflow rule, **never apply automatically**. For each ⚠️ drift item recommend the safe adoption path and let the user decide:

1. Add the resource to `groups.yaml` / `apps.yaml` (or decide to leave it unmanaged and document why).
2. `terraform import '<address>' <okta-id>` to adopt the existing object **before** apply — otherwise apply fails creating a duplicate. Addresses look like `module.identity.okta_group.groups["<name>"]` and `module.apps.okta_app_oauth.oidc["<label>"]`.
3. Iterate the code until `terraform plan` is clean for that resource, show the plan, then apply only after the user confirms.
