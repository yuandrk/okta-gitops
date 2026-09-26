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

## The contract with the cluster is a group name

Headlamp signs users in via OIDC. The ID token carries a `groups` claim. The k3s API server reads it (`--oidc-groups-claim=groups`), and a `ClusterRoleBinding` in the **homelab repo** maps `homelab-admins` → `cluster-admin`.

That means there are two independent gates:
- The **app assignment** in `apps.yaml` decides who can sign in at all.
- The **RBAC binding** in the homelab repo decides what they can do once signed in.

The only thing shared between the two repos is the group name string. Renaming a group here silently breaks RBAC there.

## Headlamp uses a custom-domain issuer

`issuer_mode: CUSTOM_URL` means tokens and discovery are served from `okta.yuandrk.net`, the same domain as the end-user dashboard session. That makes SSO silent: no second login per app.

The catch is that the Headlamp/k3s OIDC issuer must also be `https://okta.yuandrk.net`. Otherwise the `iss` claim won't validate. Changing `issuer_mode` is a change that touches two repos.

## Hermes OIDC app stays in the Console; a bookmark gives it a tile

The Hermes dashboard (`hermes.yuandrk.net`) runs on the k3s-master host itself, and its OIDC app is a **public native client**: `token_endpoint_auth_method: none` with PKCE. `modules/apps` only models confidential web apps, so importing Hermes would fight the live config. Until the module grows `pkce_required` and `token_endpoint_auth_method` inputs, the app is managed in the Console.

Okta gives dashboard tiles only to Web/SPA apps with IdP-initiated login. A native client can never have one. The workaround is `okta_app_bookmark`: a plain link tile, managed in Terraform, that leaves the real app alone.

## The MCP's own app stays out of Terraform

`okta-mcp-server`, used by Claude to read the org, signs in as `okta-mcp-browser`. That's a public client using the device-code flow, acting **as the signed-in admin**.

- It's the credential the tooling needs to inspect everything else. An apply that breaks it locks out the tool you would use to diagnose the breakage, so it stays in the Console.
- Its scopes include `okta.*.manage`. "The MCP is read-only" is a convention here, not an enforced limit.
- Until 2026-09-25 this was `C_mcp`, a service app with a `private_key_jwt` key in 1Password. It was deleted. User-delegated auth needs no stored key at all.

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

- `plan.yml` runs on each PR: fmt → init → validate → plan, and posts the plan as a PR comment. Branch protection requires the `plan` check and an up-to-date branch.
- `apply.yml` runs on push to `main`: the `prod` GitHub Environment waits for manual approval, then runs `apply -auto-approve`.
- AWS access uses GitHub OIDC → IAM role `github-okta-gitops` (account `756755582140`). No static keys are stored. The trust policy must allow `ref:refs/heads/main`, `pull_request` and `environment:*`.
- Secret `TF_VAR_API_TOKEN`. Variables `TF_VAR_ORG_NAME` and `AWS_ROLE_ARN`.
- `plan.yml` runs on **every** PR, with no `paths:` filter. A required check that a path filter skips never reports, so the PR can't merge. Plan is cheap and read-only, so it always runs.
- `apply.yml` filters on `paths:`, so docs-only merges don't ask for an approval. **Every file the root reads must be listed there.** `apps.yaml` was missing until 2026-08-22, so apps-only changes skipped CI without any error.

---

## Lessons that carry over to work

- **Import before apply.** Anything clicked together in the Console has to be `terraform import`ed first. Otherwise apply tries to create a duplicate. Iterate on the code until the plan is clean for that resource.
- **`for_each` keys are state addresses.** Renaming an app or group key, a module or a resource means destroy and recreate. For an OIDC app that also means a new client secret.
- **Console edits are drift.** Someone will "just fix it quickly" in the UI. Plan regularly and decide each time whether the fix belongs in code or should be reverted.
- **Decide what not to manage.** System apps, bootstrap credentials, and clients the module can't express yet are all Console-managed. Write down why, or they'll look like drift forever.
- **Tokens expire from inactivity.** An SSWS token that isn't used for 30 days dies. A quiet repo comes back with a 401. Keep the token in a password manager and update CI in the same step.
- **Keep the auth paths separate.** The IaC token and the admin tooling's login are separate credentials, and one working says nothing about the other.
