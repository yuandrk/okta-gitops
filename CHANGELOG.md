# Changelog

What changed in the org and the code, and when. One line per merged PR, newest first. Add yours in the same PR.
Why a thing is the way it is lives in [docs/design.md](docs/design.md), not here.

## 2026-10

- Break-glass path: Google Authenticator (TOTP) plus the `Break-glass` enrollment and session policies. `Everyone` session policy: 2 h idle, 12 h max, no persistent cookie. Kite requires a device-bound second factor. Authenticator names are now managed. [#26](https://github.com/yuandrk/okta-gitops/pull/26)
- **Breaking:** retire Hermes: delete the `Hermes Dashboard` OIDC app (with its sign-on policy, rule and assignment) and the `Hermes` bookmark tile. `Andriuk corp` stays. Drop the applied import blocks from #24. [#25](https://github.com/yuandrk/okta-gitops/pull/25)
- Adopt the security baseline as is with import blocks: the Password and Email authenticators and the default enrollment policy (new `modules/security`). Add the `break-glass` group (no rule). [#24](https://github.com/yuandrk/okta-gitops/pull/24)
- Adopt `Hermes Dashboard` (public native client, PKCE) with an import block; it gets its own 2FA / 12h sign-on policy. `modules/apps` supports public clients. [#23](https://github.com/yuandrk/okta-gitops/pull/23)
- Renovate config: GitHub Actions pinned to commit SHAs, okta provider updates inside `~> 7.0`, monthly lock-file maintenance; `apply.yml` now also runs when `.terraform.lock.hcl` changes. [#22](https://github.com/yuandrk/okta-gitops/pull/22)
- Destroy guard: a plan that deletes or replaces anything fails the `plan` check unless the PR has the `allow-destroy` label. The plan comment is now one comment, updated on each run. [#21](https://github.com/yuandrk/okta-gitops/pull/21)
- README rework: highlights, access and delivery diagrams, inventory split into managed vs left out on purpose; add the MIT `LICENSE` file. [#20](https://github.com/yuandrk/okta-gitops/pull/20)
- Add `inventory` output (group → rule → apps/bookmarks), Kite `groups` claim regex `IT` → `^IT$` (same match, now explicit), more validation tests, readability pass. [#19](https://github.com/yuandrk/okta-gitops/pull/19)

## 2026-09

- Add Kite OIDC app and the `IT` group that gates it. [#18](https://github.com/yuandrk/okta-gitops/pull/18)
- **Breaking:** retire Headlamp (Okta app + `homelab-admins` group). [#17](https://github.com/yuandrk/okta-gitops/pull/17)
- Require MFA on Headlamp; sign-on factor becomes configurable (`factor_mode`, default 2FA). [#16](https://github.com/yuandrk/okta-gitops/pull/16)
- Manual drift workflow (`drift.yml`); drop deleted inactive apps from docs. [#15](https://github.com/yuandrk/okta-gitops/pull/15)
- okta provider `~> 6.0` → `~> 7.0` (6.10.0 → 7.0.0), plan → No changes. [#14](https://github.com/yuandrk/okta-gitops/pull/14)
- Standard Terraform layout, variable validation, module tests, tflint; YAML moves to `config/`. [#13](https://github.com/yuandrk/okta-gitops/pull/13)
- Consolidate docs into README, design and runbook. [#12](https://github.com/yuandrk/okta-gitops/pull/12)

## 2026-08

- Bookmark apps; dashboard tile for the Hermes dashboard. [#11](https://github.com/yuandrk/okta-gitops/pull/11)
- Finish Headlamp `CUSTOM_URL` migration; consolidate agent docs. [#10](https://github.com/yuandrk/okta-gitops/pull/10)

## 2026-06

- Delete the `Test` group. [#9](https://github.com/yuandrk/okta-gitops/pull/9)
- Add a `Test` group to exercise the apply on `main`. [#8](https://github.com/yuandrk/okta-gitops/pull/8)
- Reconcile Terraform with live Okta: `Andriuk corp` group, Headlamp drift. [#7](https://github.com/yuandrk/okta-gitops/pull/7)
