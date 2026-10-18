# Design decisions

This page explains why the setup looks the way it does. Each section covers one decision and the reasoning behind it. The last section lists the lessons worth carrying over to Okta at work.

---

## Users live outside Terraform; groups and rules live inside it

Terraform owns **structure**: which groups exist, what they mean, and which attributes put someone in them. **People** are created in the Admin Console. In a real company they would arrive via SCIM from HR or a directory.

Why:
- If users were Terraform resources, every hire or leaver would be a PR and an apply. Access would lag behind HR, and the YAML would turn into an HR system pretending not to be one.
- The repo started that way: `users.yaml` encrypted with SOPS, plus `okta_user` and `okta_group_memberships` resources. It was replaced by group rules because a rule is a single declarative decision-maker.

How group rules behave in Okta (Okta Expression Language, [reference](https://developer.okta.com/docs/reference/okta-expression-language/)):
- A rule fires when a user is created and when their profile changes. Changing a rule does **not** re-evaluate existing users; you have to deactivate and reactivate it.
- A rule must be inactive before its expression can be edited. The provider does this for you, and the plan shows `ACTIVE → INACTIVE → ACTIVE`.
- Memberships a rule assigned can't be removed by hand, because the rule adds them back. Manual memberships coexist with rule-based ones.
- Attributes used in rules (`user.division`, `user.userType`, `user.department`, `user.title`, …) must exist on the user schema. The default user type already has the common ones.

## Headlamp (retired 2026-09-26)

Headlamp (the k3s dashboard) was the first OIDC app here. The Okta app, its policy and the `homelab-admins` group were destroyed through Terraform when it was retired. Two lessons from it still apply to any app that feeds a cluster's RBAC:

- **The contract with the cluster is a group name.** The ID token's `groups` claim was read by the k3s API server (`--oidc-groups-claim=groups`), and a `ClusterRoleBinding` in the homelab repo mapped `homelab-admins` → `cluster-admin`. The app assignment decided who could sign in; the binding decided what they could do. Renaming a group here would silently break RBAC there.
- **A custom-domain issuer is a two-repo change.** `issuer_mode: CUSTOM_URL` serves tokens from `okta.yuandrk.net`, the same domain as the dashboard session, so SSO is silent. But the relying party's issuer must match exactly, or the `iss` claim won't validate.

## Hermes (retired 2026-10-18)

The Hermes dashboard (`hermes.yuandrk.net`, on the k3s-master host) signed in through Okta until its app and tile were deleted through Terraform, because the dashboard wasn't being used. `Andriuk corp`, the group that opened it, was kept as the base group for future apps. Its OIDC app was a **public native client**: `token_endpoint_auth_method: none` with PKCE, so there was no client secret to store anywhere. Two lessons from it still apply:

- **Only native and browser apps are public clients, and they need PKCE.** `modules/apps` accepts `none` only for `native` and `browser` apps, and only with `pkce_required`. A public client has no secret, so PKCE is what ties the code exchange to the client that started the login. A `web` app with `none` would just be a confidential app with its secret thrown away.
- **A native app can't have a dashboard tile.** Okta gives tiles only to Web/SPA apps with IdP-initiated login. The workaround is `okta_app_bookmark`: a plain link tile that leaves the real app alone.

## The MCP's own app stays out of Terraform

`okta-mcp-server`, used by Claude to read the org, signs in as `okta-mcp-browser`. That's a public client using the device-code flow, acting **as the signed-in admin**.

- It's the credential the tooling needs to inspect everything else. An apply that breaks it locks out the tool you would use to diagnose the breakage, so it stays in the Console.
- Its scopes include `okta.*.manage`. "The MCP is read-only" is a convention here, not an enforced limit.
- Until 2026-09-25 this was `C_mcp`, a service app with a `private_key_jwt` key in 1Password. It was deleted. User-delegated auth needs no stored key at all.

## Code layout

The layout follows HashiCorp's [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure) and [terraform-best-practices.com](https://www.terraform-best-practices.com/):

- **One concern per file.** `versions.tf` (Terraform/provider constraints, backend), `providers.tf`, `locals.tf` (YAML decoding), `main.tf` (module calls only). Inside `modules/apps`, OIDC apps and bookmarks live in `oidc.tf` and `bookmarks.tf`.
- **Data apart from code.** Everything you edit day to day is in `config/`. The `.tf` files change only when the *shape* of what's managed changes.
- **Version constraints:** the root pins `okta ~> 7.0` and commits `.terraform.lock.hcl` (with linux_amd64 + darwin_arm64 hashes, via `terraform providers lock`); modules only declare a floor (`>= 6.0`), so they don't block a provider upgrade. The 6.10 → 7.0 bump (2026-09-26) was plan → No changes: 7.0's breaking changes hit resources this repo doesn't use.
- **Fail at plan time, with a readable message.** Variable validation rejects unknown group names, bad enum values and duplicate keys before Okta sees anything. Before this, a typo in a group name produced a bare "Invalid index".
- **Tests without an org.** `terraform test` with `mock_provider "okta"` checks the `for_each` key shapes (state addresses) and the validations. On the first run it found a real bug: `signon_policy.description` was optional in the module but required by the provider.
- **Names are state.** Resource and module names (`module.identity`, `okta_group.groups`, `okta_app_oauth.oidc`…) predate these conventions and are kept on purpose. Renaming them would need `moved` blocks for no functional gain.

## Security baseline: adopt first, then tighten

Authenticators and enrollment policies decide whether anyone can sign in at all, so a wrong apply here locks people out instead of breaking one app. The baseline moves into Terraform in two steps:

1. **Adopt it as is.** Import the live authenticators and the default enrollment policy, and adjust the YAML until the plan shows imports and no change in behaviour. From then on, every change to the baseline is a reviewed diff.
2. **Tighten it in separate PRs.** Each one has a plan that shows exactly what changes, and the break-glass admin as a way back in.

Constraints that shaped `modules/security`:

- **Okta never deletes an authenticator.** `okta_authenticator` adopts an existing one on create and deactivates it on destroy. Removing an entry from `config/security.yaml` would deactivate it for everyone enrolled, so the destroy guard treats that like any other delete.
- **Settings stay in the Console for now.** The module manages which authenticators exist and whether they're active, not their `settings` JSON. Taking over settings means mirroring each authenticator's whole settings object, because a partial object would overwrite the rest.
- **Groups are targeted at the policy level.** Sign-on and enrollment policy rules can exclude users only by user ID, while a policy can include groups. So the break-glass admin gets policies of its own, placed ahead of the ones for everyone, instead of an exclusion with a user ID in the YAML.
- **Okta Verify can't be imported.** It is active in the Console, but `GET /api/v1/authenticators` lists it with the ID `okta_verify`, `GET /api/v1/authenticators/okta_verify` answers 404, and it isn't in the default enrollment policy. Terraform has no ID to adopt, so it stays in the Console. Policies don't need it in state: a possession constraint names a kind of factor, such as device-bound, not an authenticator ID.
- **Authenticator names are managed.** The provider ignores `name` by default (`legacy_ignore_name`), which also makes it create a new authenticator with an empty name. The module turns that off.

What the tightening adds:

- **A break-glass admin that doesn't depend on your phone.** Okta Verify on one phone was the only second factor, so losing the phone meant losing the org. The break-glass admin is a second super admin whose factor is a TOTP secret kept in 1Password. Its enrollment and session policies come first and target only its group, so a mistake in the policies for everyone can't take it down too.
- **Session policies set limits; app policies set factors.** The session policy for everyone starts a session with whatever the app's sign-on policy asked for (`PASSWORD_IDP_ANY_FACTOR`) and leaves MFA to the app policies. It only caps the session (2 h idle, 12 h maximum) and drops persistent cookies. Okta's Default Policy stays last as the fallback, and the Admin Console's own sign-on policy is left alone, because breaking it would lock every admin out.
- **Kite: device-bound, not yet phishing-resistant.** Device-bound means Okta Verify or a security key, never SMS, voice or email. Phishing-resistant would need Okta FastPass on the device you sign in from, or a passkey: a push to a phone can be approved for a phishing page. Okta Verify push is the only factor enrolled today, so `PHISHING_RESISTANT` would lock you out of Kite. Enroll a passkey first, then change one line in `config/apps.yaml`.
- **Constraint JSON spells out `required = true`.** The provider always sends `required` for each constraint class, because the SDK field has no `omitempty`, and the API returns `true` for the classes in use. Writing it in the module keeps the plan clean after an apply.

## One Terraform root, no dev/prod

There is one org and one person. A second environment would add a second state, IAM trust scope and org noise, without adding safety. The modules are kept separate so an environment split stays cheap if it's ever needed.

## Plain YAML, no encryption

Group names, rule expressions and app settings are not secrets. Plain YAML makes PR diffs readable. SOPS was used while users were in the repo, and removed when they left.

## State: S3 with native locking

- `s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate` in `eu-west-2`, versioned and encrypted.
- `use_lockfile = true`: the lock is a plain S3 object, so there's no DynamoDB table. This needs Terraform ≥ 1.10.
- The `prod/` prefix is left over from the old dev/prod layout. Renaming it takes `terraform init -reconfigure -migrate-state`, which isn't worth doing.
- `.terraform.lock.hcl` is committed, so CI and local runs use the same provider build.

## CI: plan on PR, gated apply on main

- `plan.yml` runs on each PR: fmt → init → validate → tflint → module tests → plan → destroy guard. It posts the result as one PR comment, which later runs update in place. Branch protection requires the `plan` check and an up-to-date branch.
- **Destroy guard.** The riskiest diff here looks harmless: a renamed app or group in the YAML is a destroy and recreate, so the app gets a new client ID and secret and the group a new ID. One `-/+` line is easy to miss in a long plan, so `plan.yml` fails whenever the plan deletes or replaces anything. A PR that means to delete adds the `allow-destroy` label, which re-runs the check. The label is the explicit "yes, I meant this"; the `prod` approval stays the last gate.
- Runs for one PR are serialized (`concurrency`, without cancel-in-progress): a push and a label change would otherwise race for the S3 lock, and a cancelled plan can leave the lock behind.
- `apply.yml` runs on push to `main`: the `prod` GitHub Environment waits for manual approval, then runs `apply -auto-approve`.
- `drift.yml` runs only when started by hand (`workflow_dispatch`). It runs a read-only `plan -lock=false -detailed-exitcode` and fails on drift or error. There's no schedule on purpose: the check runs when it's needed, not on a timer. Running it also counts as token use for the 30-day inactivity limit.
- AWS access uses GitHub OIDC → IAM role `github-okta-gitops` (account `756755582140`). No static keys are stored. The trust policy must allow `ref:refs/heads/main`, `pull_request` and `environment:*`.
- Secret `TF_VAR_API_TOKEN`. Variables `TF_VAR_ORG_NAME` and `AWS_ROLE_ARN`.
- `plan.yml` runs on **every** PR, with no `paths:` filter. A required check that a path filter skips never reports, so the PR can't merge. Plan is cheap and read-only, so it always runs.
- `apply.yml` filters on `paths:`, so docs-only merges don't ask for an approval. **Every file the root reads must be listed there.** `apps.yaml` was missing until 2026-08-22, so apps-only changes skipped CI without any error. The YAML now lives under `config/**`, so a new config file is covered automatically. `.terraform.lock.hcl` is listed too: it picks the provider build, and Renovate changes it without touching any `.tf` file.
- **Dependencies: Renovate, actions pinned to SHAs.** These workflows hold an Okta super-admin token, and a tag like `@v4` can be moved to different code. A commit SHA can't, so Renovate pins every action to one and keeps the version in a comment. Renovate rather than Dependabot because a Dependabot PR gets no Actions secrets: the required `plan` would fail, unless the Okta token were copied into a third place. Renovate's PRs come from branches in this repo and get a normal plan.

---

## Lessons that carry over to work

- **Import before apply.** Anything clicked together in the Console has to be `terraform import`ed first. Otherwise apply tries to create a duplicate. Iterate on the code until the plan is clean for that resource.
- **`for_each` keys are state addresses.** Renaming an app or group key, a module or a resource means destroy and recreate. For an OIDC app that also means a new client secret.
- **Console edits are drift.** Someone will "just fix it quickly" in the UI. Plan regularly and decide each time whether the fix belongs in code or should be reverted.
- **Decide what not to manage.** System apps, bootstrap credentials, and clients the module can't express yet are all Console-managed. Write down why, or they'll look like drift forever.
- **Tokens expire from inactivity.** An SSWS token that isn't used for 30 days dies. A quiet repo comes back with a 401. Keep the token in a password manager and update CI in the same step.
- **Keep the auth paths separate.** The IaC token and the admin tooling's login are separate credentials, and one working says nothing about the other.
