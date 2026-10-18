#!/usr/bin/env bash
# Destroy guard for plan.yml: lists every resource the plan deletes or replaces and
# fails unless the PR carries the `allow-destroy` label.
#
# Usage: destroy-guard.sh <planfile> <out.md>
# Env:   ALLOW_DESTROY=true when the PR has the label
#
# A replace is a delete too. Here it usually comes from a renamed for_each key: a
# replaced okta_app_oauth gets a new client ID and secret, a replaced okta_group a
# new ID. Deleting an okta_authenticator deactivates it, which can lock users out.
#
# shellcheck disable=SC2016 # backticks in single quotes are Markdown, not command substitution
set -euo pipefail

plan=$1
out=$2

# The plan JSON holds every input variable in plain text, api_token included.
# It stays in a temp file and is never printed or uploaded.
json=$(mktemp)
trap 'rm -f "$json"' EXIT
terraform show -json "$plan" >"$json"

hits=$(jq -r '
  .resource_changes[]?
  | select(.change.actions | index("delete"))
  | "- \(if (.change.actions | length) > 1 then "replace" else "delete" end) `\(.address)`"
' "$json")

if [ -z "$hits" ]; then
  echo '#### Destroy guard 🛡️ `success`: nothing is deleted or replaced' >"$out"
  exit 0
fi

count=$(grep -c '^- ' <<<"$hits")
if [ "${ALLOW_DESTROY:-false}" = "true" ]; then
  status='`allowed` by the `allow-destroy` label'
  advice='Check that the list matches what the PR means to remove before merging.'
else
  status='`blocked`'
  advice='If this is intended, add the `allow-destroy` label to the PR; the check re-runs on its own.'
fi

cat >"$out" <<EOF
#### Destroy guard 🛡️ ${status}

This plan deletes or replaces ${count} resource(s):

${hits}

A replaced OIDC app gets a new client ID and secret, and a replaced group gets a new ID. Deleting an \`okta_authenticator\` deactivates it. ${advice}
EOF

[ "${ALLOW_DESTROY:-false}" = "true" ]
