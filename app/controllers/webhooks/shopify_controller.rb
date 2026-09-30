# frozen_string_literal: true

class Webhooks::ShopifyController < ActionController::API
  before_action :verify_hmac!

  ORDER_TOPICS = %w[orders/create fulfillments/create fulfillment_events/create].freeze

  def events
    topic = request.headers['X-Shopify-Topic']
    case topic
    when 'shop/redact'
      handle_shop_redact
    when *ORDER_TOPICS
      handle_order_update(topic)
    end

    head :ok
  end

  private

  def verify_hmac!
    secret = GlobalConfigService.load('SHOPIFY_CLIENT_SECRET', nil)
    return head :unauthorized if secret.blank?

    data = request.body.read
    request.body.rewind

    hmac_header = request.headers['X-Shopify-Hmac-SHA256']
    return head :unauthorized if hmac_header.blank?

    computed = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, data))
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, hmac_header)
  end

  def handle_shop_redact
    shop_domain = params[:shop_domain]
    return if shop_domain.blank?

    Integrations::Hook.where(app_id: 'shopify', reference_id: shop_domain).destroy_all
  end

  def handle_order_update(topic)
    shop_domain = request.headers['X-Shopify-Shop-Domain']
    return if shop_domain.blank?

    hook = Integrations::Hook.find_by(app_id: 'shopify', reference_id: shop_domain)
    return unless hook&.settings&.dig('order_updates', 'enabled') == true

    payload = params.to_unsafe_hash.except('controller', 'action', 'shopify')
    Shopify::OrderUpdateJob.perform_later(hook.account_id, topic, payload)
  end
end
