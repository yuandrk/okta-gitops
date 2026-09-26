variable "groups" {
  description = "List of groups to create in Okta. Each entry may include an Okta Expression Language rule that auto-assigns matching users."
  type = list(object({
    name        = string
    description = string
    rule        = optional(string)
  }))

  validation {
    condition     = length(distinct([for g in var.groups : g.name])) == length(var.groups)
    error_message = "Group names must be unique — the name is the for_each key (state address)."
  }
}
