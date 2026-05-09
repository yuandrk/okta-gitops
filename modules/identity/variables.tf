variable "groups" {
  description = "List of groups to create in Okta. Each entry may include an Okta Expression Language rule that auto-assigns matching users."
  type = list(object({
    name        = string
    description = string
    rule        = optional(string)
  }))
}
