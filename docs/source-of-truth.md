# Source of truth — users live outside Terraform

## The pattern

Users are **not** Terraform resources. They are created in the Okta Admin Console (or, in a real org, pushed in via SCIM from an HRIS like Workday/BambooHR, or via directory integration with Google Workspace / Entra ID). Terraform owns only:

- **`okta_group`** — stable named buckets representing access boundaries
- **`okta_group_rule`** — declarative "if user attribute matches, add to this group" logic

When a user's profile is created or changed in the SoT, Okta evaluates all active group rules and assigns the user to matching groups automatically.

## From Okta group to homelab access

The groups exist to gate access to a homelab k3s cluster. The chain:

```text
user.division == "IT"  →  homelab-admins  →  OIDC `groups` claim  →  ClusterRoleBinding  →  cluster-admin
```

When you sign in to [Headlamp](https://headlamp.dev/) via Okta OIDC, the ID token carries your group memberships in the `groups` claim. The k3s API server (configured with `--oidc-groups-claim=groups`) reads them, and a `ClusterRoleBinding` maps each group to a Kubernetes role. That binding lives in the **separate homelab repo** — this repo owns only the Okta side. For reference, the binding looks like:

```yaml
# Applied in the homelab cluster, NOT by this repo.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: okta-homelab-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: homelab-admins        # matches the Okta group name in the `groups` claim
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: okta-homelab-viewers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: homelab-viewers
```

The contract between Okta and the cluster is just the group name string. Add someone to `homelab-admins` in Okta (or let the rule do it) and they get `cluster-admin` on next login — no cluster change needed.

## Why this split

| Concern | Where it lives |
| --- | --- |
| Who works at the company | HR / IdP (the source of employment truth) |
| What groups exist and what they mean | Terraform (named, reviewed, versioned) |
| How attributes map to access | Terraform (group rules, expression language) |
| Lifecycle (hire/fire/transfer) | HR → Okta (SCIM, automatic) |

If Terraform managed `okta_user`, two things break:

1. **Lifecycle race conditions** — HR onboards someone Monday, but the next `terraform apply` is Wednesday. The user doesn't exist for 48h, despite already being employed.
2. **The `data.yaml` becomes a HR system pretending not to be one** — every hire/termination becomes a PR. Fine for 5 users, broken at 50.

Treating users as data flowing in from an upstream SoT keeps Terraform focused on what it's actually good at: declarative *structure*.

## Group rules (Okta Expression Language)

Reference: <https://developer.okta.com/docs/reference/okta-expression-language/>

Common attributes available on every user:

| Expression | Meaning |
| --- | --- |
| `user.userType` | "Employee", "Contractor", or any custom type |
| `user.division` | Division (e.g. "Engineering", "Sales") |
| `user.department` | Department within a division |
| `user.title` | Job title |
| `user.organization` | Organization name |
| `user.manager` | Login of manager |
| `user.employeeNumber` | HR ID |

Operators: `==`, `!=`, `and`, `or`, `not`, `String.startsWith()`, `String.contains()`, regex via `String.matches()`.

Examples:

```text
user.division == "Engineering"
user.userType == "Employee" and user.division == "IT"
user.title != null and String.startsWith(user.title, "Senior")
user.department == "Platform" or user.department == "Infra"
```

## Rule lifecycle quirks

- A rule must be **deactivated** before its expression can be edited. The Okta provider handles this automatically — you'll see `status: ACTIVE → INACTIVE → ACTIVE` in plan output.
- Rules evaluate on **user creation** and on **profile change**. They don't sweep retroactively unless the rule is deactivated and reactivated.
- A rule-assigned membership cannot be removed manually in the Admin Console — the rule re-adds it on next evaluation. To remove a user from a rule-managed group, change the user's attribute so the expression no longer matches, or delete the rule.
- Manual memberships added directly (outside the rule) coexist with rule-based ones. Authoritative `okta_group_memberships` is intentionally not used here so the rule remains the single decision-maker.

## Profile schema

Expressions reference attributes that must exist on the Okta user schema. The built-in **Default User Type** already includes the common ones (`userType`, `division`, `department`, `title`, `organization`, `manager`, `employeeNumber`). For custom attributes, manage the schema with `okta_user_schema_property` — not currently in this repo.
