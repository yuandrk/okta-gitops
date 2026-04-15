variable "groups" {
  description = "List of groups to create in Okta"
  type = list(object({
    name        = string
    description = string
  }))
}

variable "users" {
  description = "List of users to create in Okta"
  type = list(object({
    first_name = string
    last_name  = string
    login      = string
    email      = string
    status     = string
    groups     = optional(list(string), [])
  }))
}
