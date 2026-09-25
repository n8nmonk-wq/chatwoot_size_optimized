json.id resource.id
json.account_id Current.account&.id
json.name resource.name
json.username resource.username
json.email resource.email
json.role resource.role
json.thumbnail resource.avatar_url
json.inbox_ids resource.inboxes.where(account_id: Current.account&.id).pluck(:id)
