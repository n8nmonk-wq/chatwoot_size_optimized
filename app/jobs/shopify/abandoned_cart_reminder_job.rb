# frozen_string_literal: true

class Shopify::AbandonedCartReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    errors = []
    active_hooks.each do |hook|
      Shopify::AbandonedCartReminderService.perform(hook)
    rescue StandardError => e
      Rails.logger.error("[Shopify::AbandonedCartReminderJob] Error processing hook #{hook.id}: #{e.message}")
      errors << "Hook #{hook.id}: #{e.message}"
    end

    raise errors.join('; ') if errors.any?
  end

  private

  def active_hooks
    Integrations::Hook.where(app_id: 'shopify', status: :enabled).select do |hook|
      hook.settings&.dig('abandoned_cart', 'enabled') == true
    end
  end
end
