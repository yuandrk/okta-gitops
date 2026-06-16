# Runbook

Common operations, in order of frequency.

## Add a user

Users are not in Terraform. To create one:

1. Admin Console → **Directory → People → Add Person**
2. Fill in profile. **Make sure to set:**
   - **User type** (e.g. `Employee`, `Contractor`)
   - **Division** (e.g. `Engineering`, `IT`)
   - Any other attributes referenced by your group rules
3. Save → group rules evaluate within seconds and add the user to matching groups
4. Verify in Admin Console → **Directory → Groups → <group> → People** that the rule picked them up

If the user did not land in the expected group, check:

- Group rule status is **ACTIVE**
- The exact attribute value matches the expression (case-sensitive — `Engineering` ≠ `engineering`)
- The rule expression is well-formed (Admin Console → Directory → Groups → Rules shows validation errors)

## Add a group (with auto-assignment rule)

1. Edit `groups.yaml`:

   ```yaml
   - name: homelab-ci
     description: CI/CD service access to homelab k3s via Okta OIDC.
     rule: 'user.division == "Platform"'
   ```

2. Open a PR. CI runs `terraform plan` and posts the diff as a PR comment.
3. Merge to `main`. The `apply` workflow waits for manual approval in the `prod` GitHub Environment, then runs `terraform apply -auto-approve`.

## Change a group rule expression

Same flow as adding a group. The Okta provider deactivates the rule, updates the expression, and reactivates — visible in plan output as `status: ACTIVE → INACTIVE → ACTIVE`.

## Rotate the Okta API token

1. Admin Console → **Security → API → Tokens** → create new token
2. Copy the new token, invalidate the old one
3. Update GitHub repo secret `TF_VAR_API_TOKEN` (Settings → Secrets and variables → Actions)
4. Update local `terraform.tfvars` if you run Terraform locally
5. Optional: `terraform plan` — should show no changes (token doesn't appear in state)

## Recover from a broken state lock

S3-native locking stores a `<key>.tflock` object. If a previous run was killed mid-apply:

```bash
aws s3 ls s3://terraform-state-homelab-yuandrk/prod/
# look for terraform.tfstate.tflock
aws s3 rm s3://terraform-state-homelab-yuandrk/prod/terraform.tfstate.tflock
```

Only do this if you are certain no other process is running.

## Emergency: stop a rule from assigning users

Two options, in order of preference:

1. **Deactivate the rule** in Admin Console → Directory → Groups → Rules → toggle to Inactive. This is *not* picked up by Terraform on next apply (provider will revert it back to ACTIVE if `status = "ACTIVE"` in code) — so this is a stopgap until you can ship a code change.
2. **Remove the group entry from `groups.yaml`** and apply. The rule and group are destroyed.

## Adding a non-trivial resource

When adding something the identity module doesn't cover (an app, a policy):

1. Start it as a concrete resource in the root `main.tf`; extract a `modules/<name>/` only once you have 2–3 instances sharing a real shape — don't pre-abstract
2. Reference existing groups through `module.identity.group_ids["<name>"]` if the resource needs to assign to them (e.g. an `okta_app_group_assignment` for `homelab-admins`)
