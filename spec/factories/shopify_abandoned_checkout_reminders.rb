# frozen_string_literal: true

FactoryBot.define do
  factory :shopify_abandoned_checkout_reminder, class: 'Shopify::AbandonedCheckoutReminder' do
    account
    sequence(:checkout_id) { |n| "gid://shopify/AbandonedCheckout/#{n}" }
    status { 'sent' }
    sent_at { Time.current }
  end
end
