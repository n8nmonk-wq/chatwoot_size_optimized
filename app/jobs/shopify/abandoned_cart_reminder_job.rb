# frozen_string_literal: true

class Shopify::AbandonedCartReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    active_hooks.each do |hook|
      process_hook(hook)
    end
  end

  private

  def active_hooks
    Integrations::Hook.where(app_id: 'shopify', status: :enabled).select do |hook|
      hook.settings&.dig('abandoned_cart', 'enabled') == true
    end
  end

  def process_hook(hook)
    Shopify::AbandonedCartReminderService.perform(hook)
  rescue StandardError => e
    Rails.logger.error("[Shopify::AbandonedCartReminderJob] Error processing hook #{hook.id}: #{e.message}")
  end
end
