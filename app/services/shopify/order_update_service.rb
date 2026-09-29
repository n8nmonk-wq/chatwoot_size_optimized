# frozen_string_literal: true

class Shopify::OrderUpdateService
  include Shopify::SharedHelper

  attr_reader :account_id, :topic, :payload

  def self.perform(account_id:, topic:, payload:)
    new(account_id: account_id, topic: topic, payload: payload).perform
  end

  def initialize(account_id:, topic:, payload:)
    @account_id = account_id
    @topic = topic
    @payload = payload || {}
  end

  def perform
    return unless setup_and_validate!

    @kind = resolve_kind
    return if @kind.blank?

    milestone_config = order_updates_settings.dig('milestones', @kind)
    return unless milestone_config&.dig('enabled') == true

    @mapping = milestone_config['template']
    return if @mapping.blank?

    process_order_update
  end

  private

  def setup_and_validate!
    @account = Account.find_by(id: account_id)
    return false if @account.blank?

    @hook = Integrations::Hook.find_by(account_id: account_id, app_id: 'shopify')
    return false if @hook.blank? || @hook.disabled?
    return false unless order_updates_settings['enabled'] == true

    inbox_id = order_updates_settings['inbox_id']
    @inbox = @account.inboxes.find_by(id: inbox_id)
    return false if @inbox.blank? || @inbox.channel.blank?

    @channel = @inbox.channel
    true
  end

  def order_updates_settings
    @hook.settings['order_updates'] || {}
  end

  def resolve_kind
    case topic
    when 'orders/create' then 'confirmed'
    when 'fulfillments/create' then 'shipped'
    when 'fulfillment_events/create'
      status = payload['status'] || payload['event_status']
      return 'out_for_delivery' if status == 'out_for_delivery'
      return 'delivered' if status == 'delivered'

      nil
    end
  end

  def store_domain
    @hook.settings.dig('abandoned_cart', 'store_domain').presence || @hook.reference_id
  end

  def process_order_update
    order_id = resolve_order_id
    return if order_id.blank?

    order = resolve_order_data(order_id)
    phone = extract_order_phone(order, @inbox)

    test_phones = @hook.settings.dig('abandoned_cart', 'test_phones') || []
    return if test_phones.present? && !test_phone_allowed?(phone, test_phones)

    reason = ineligible_reason(order_id, phone)
    if reason.present?
      record_skipped(order_id, reason)
      return
    end

    send_milestone_notification(order_id, order, phone)
  end

  def ineligible_reason(order_id, phone)
    return 'missing_phone' if phone.blank?
    return 'contact_opted_out' if contact_opted_out_or_blocked?(@account, @inbox, phone)
    return 'already_delivered' if out_for_delivery_or_shipped_after_delivered?(order_id)

    nil
  end

  def resolve_order_id
    (payload['id'] if topic == 'orders/create') ||
      payload['order_id'] ||
      payload.dig('order', 'id')
  end

  def resolve_order_data(order_id)
    return payload if topic == 'orders/create' || payload_has_order_details?

    fetch_shopify_order(order_id)
  end

  def payload_has_order_details?
    payload['name'].present? && payload['customer'].present? && payload['order_status_url'].present?
  end

  def out_for_delivery_or_shipped_after_delivered?(order_id)
    return false unless %w[shipped out_for_delivery].include?(@kind)

    Shopify::OrderNotification.exists?(account_id: @account.id, order_id: order_id.to_s, kind: 'delivered')
  end

  def record_skipped(order_id, reason)
    @account.shopify_order_notifications.create!(
      order_id: order_id.to_s,
      kind: @kind,
      status: 'skipped',
      reason: reason
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def send_milestone_notification(order_id, order, phone)
    notification = create_initial_notification(order_id)
    return if notification.blank?

    context = { order: order, payload: payload, hook: @hook, store_domain: store_domain, milestone: @kind }
    status, processed_params = build_template_processed_params(@mapping, context)

    if status == :error
      notification.update!(status: 'failed', reason: processed_params)
      return
    end

    deliver_template(notification, phone, processed_params)
  end

  def create_initial_notification(order_id)
    @account.shopify_order_notifications.create!(
      order_id: order_id.to_s,
      kind: @kind,
      status: 'failed',
      reason: 'sending'
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def deliver_template(notification, phone, processed_params)
    payload_data = build_send_payload(processed_params)
    send_response = @channel.send_template(phone, payload_data, nil)

    if send_response.present?
      notification.update!(status: 'sent', sent_at: Time.current, reason: nil)
    else
      notification.update!(status: 'failed', reason: 'send_template_failed')
    end
  rescue StandardError => e
    Rails.logger.error("[Shopify::OrderUpdateService] Delivery error: #{e.message}")
    notification.update!(status: 'failed', reason: e.message.truncate(255))
  end

  def build_send_payload(processed_params)
    template_params = {
      'name' => @mapping['template_name'],
      'language' => @mapping['language'],
      'processed_params' => processed_params
    }
    processor = Whatsapp::TemplateProcessorService.new(channel: @channel, template_params: template_params)
    name, namespace, lang_code, parameters = processor.call

    {
      name: name.presence || @mapping['template_name'],
      namespace: namespace,
      lang_code: lang_code.presence || @mapping['language'],
      parameters: parameters
    }
  end

  def fetch_shopify_order(order_id)
    return {} if order_id.blank?

    setup_shopify_context
    session = ShopifyAPI::Auth::Session.new(shop: @hook.reference_id, access_token: @hook.shopify_access_token)
    client = ShopifyAPI::Clients::Rest::Admin.new(session: session)
    response = client.get(path: "orders/#{order_id}.json")
    response.body['order'] || {}
  rescue StandardError => e
    Rails.logger.error("[Shopify::OrderUpdateService] Error fetching order #{order_id}: #{e.message}")
    {}
  end

  def setup_shopify_context
    client_id = GlobalConfigService.load('SHOPIFY_CLIENT_ID', nil)
    client_secret = GlobalConfigService.load('SHOPIFY_CLIENT_SECRET', nil)
    return if client_id.blank? || client_secret.blank?

    ShopifyAPI::Context.setup(
      api_key: client_id,
      api_secret_key: client_secret,
      api_version: Shopify::IntegrationHelper::API_VERSION,
      scope: Shopify::IntegrationHelper::REQUIRED_SCOPES.join(','),
      is_embedded: true,
      is_private: false
    )
  end
end
