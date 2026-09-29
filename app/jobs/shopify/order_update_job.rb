# frozen_string_literal: true

class Shopify::OrderUpdateJob < ApplicationJob
  queue_as :default

  def perform(account_id, topic, payload)
    Shopify::OrderUpdateService.new(account_id: account_id, topic: topic, payload: payload).perform
  end
end
