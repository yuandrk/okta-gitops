# Admin Console equivalent: Directory → Groups → Add Group
resource "okta_group" "engineering" {
  name        = "Engineering"
  description = "All engineering staff"
}

# Admin Console equivalent: Directory → Groups → Add Group
resource "okta_group" "it_admins" {
  name        = "IT-Admins"
  description = "IT administrators with elevated access"
}
