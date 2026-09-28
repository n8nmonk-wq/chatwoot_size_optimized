# frozen_string_literal: true

class Shopify::AbandonedCheckoutReminder < ApplicationRecord
  self.table_name = 'shopify_abandoned_checkout_reminders'

  belongs_to :account

  validates :account_id, presence: true
  validates :checkout_id, presence: true, uniqueness: { scope: :account_id }
  validates :status, presence: true, inclusion: { in: %w[sent skipped failed] }
end
