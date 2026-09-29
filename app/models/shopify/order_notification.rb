# frozen_string_literal: true

class Shopify::OrderNotification < ApplicationRecord
  self.table_name = 'shopify_order_notifications'

  KINDS = %w[confirmed shipped out_for_delivery delivered].freeze
  STATUSES = %w[sent skipped failed].freeze

  belongs_to :account

  validates :account_id, presence: true
  validates :order_id, presence: true, uniqueness: { scope: [:account_id, :kind] }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
