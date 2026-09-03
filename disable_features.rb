disabled_flags = %w[
  captain_integration
  captain_integration_v2
  help_center
  agent_bots
  sla
  audit_logs
  linear_integration
  notion_integration
  shopify_integration
  channel_voice
]

Account.find_each do |acc|
  disabled_flags.each do |flag|
    method_name = "feature_#{flag}="
    acc.send(method_name, false) if acc.respond_to?(method_name)
  end
  acc.save(validate: false)
end

puts "Disabled features successfully updated in DB."
