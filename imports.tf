# Adopt what already exists in Okta instead of creating a duplicate (import before
# apply). An import block is a one-time instruction: once the apply has imported the
# resource the block is a no-op, and the next PR removes it.
#
# Empty: nothing is waiting to be adopted. The recipe is in docs/runbook.md, under
# "Adopt something that was created in the Console".
