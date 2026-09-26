# Admin Console: Applications → Browse App Catalog → Bookmark App
# Okta API: POST /api/v1/apps  (signOnMode BOOKMARK, name "bookmark")
resource "okta_app_bookmark" "link" {
  for_each = local.bookmarks_by_label

  label = each.value.label
  url   = each.value.url

  # Visible on the end-user dashboard — that's the whole point of a bookmark.
  hide_ios = true
  hide_web = false
}

# Same Okta API as the OIDC assignment: PUT /api/v1/apps/{appId}/groups/{groupId}
resource "okta_app_group_assignment" "bookmark" {
  for_each = local.bookmark_group_pairs

  app_id   = okta_app_bookmark.link[each.value.app].id
  group_id = var.group_ids[each.value.group]
}
