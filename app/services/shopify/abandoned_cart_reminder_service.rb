# frozen_string_literal: true

class Shopify::AbandonedCartReminderService
  include Shopify::IntegrationHelper
  include Shopify::SharedHelper

  GRAPHQL_QUERY = <<~GRAPHQL
    query GetAbandonedCheckouts($query: String, $after: String) {
      abandonedCheckouts(first: 50, query: $query, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id createdAt completedAt abandonedCheckoutUrl totalPriceSet { shopMoney { amount currencyCode } }
          customer { firstName phone emailMarketingConsent { marketingState } smsMarketingConsent { marketingState } }
          shippingAddress { firstName phone countryCodeV2 } billingAddress { firstName phone countryCodeV2 }
          lineItems(first: 50) { nodes { title } }
        }
      }
    }
  GRAPHQL

  def self.perform(hook)
    new(hook).perform
  end

  def initialize(hook = nil)
    @hook = hook
  end

  def perform(target_hook = nil)
    @hook = target_hook if target_hook.present?
    return unless valid_hook?

    setup_shopify_context
    fetch_abandoned_checkouts.each { |checkout| process_checkout(checkout) }
  end

  private

  def valid_hook?
    @hook.present? && @hook.enabled? && abandoned_cart_settings['enabled'] == true && inbox.present? && channel.present?
  end

  def abandoned_cart_settings
    @abandoned_cart_settings ||= (@hook.settings&.dig('abandoned_cart') || {})
  end

  def inbox
    @inbox ||= @hook.account.inboxes.find_by(id: abandoned_cart_settings['inbox_id'])
  end

  def channel
    @channel ||= inbox&.channel
  end

  def require_marketing_consent?
    ActiveRecord::Type::Boolean.new.cast(abandoned_cart_settings['require_marketing_consent']) || false
  end

  def store_domain
    abandoned_cart_settings['store_domain'].presence || @hook.reference_id
  end

  def setup_shopify_context
    return if client_id.blank? || client_secret.blank?

    ShopifyAPI::Context.setup(
      api_key: client_id, api_secret_key: client_secret, api_version: API_VERSION,
      scope: REQUIRED_SCOPES.join(','), is_embedded: true, is_private: false
    )
  end

  def shopify_session
    ShopifyAPI::Auth::Session.new(shop: @hook.reference_id, access_token: @hook.shopify_access_token)
  end

  def graphql_client
    @graphql_client ||= ShopifyAPI::Clients::Graphql::Admin.new(session: shopify_session)
  end

  def delay_hours
    abandoned_cart_settings['delay_hours'].to_i.then { |h| h.positive? ? h : 24 }
  end

  def test_phones
    @test_phones ||= (abandoned_cart_settings['test_phones'] || []).map(&:to_s)
  end

  def fetch_abandoned_checkouts
    query_filter = "created_at:>=#{(delay_hours + 48).hours.ago.iso8601} AND created_at:<=#{delay_hours.hours.ago.iso8601}"
    cursor = nil
    checkouts = []

    loop do
      data = query_checkout_page(query_filter, cursor)
      checkouts.concat(data['nodes'] || [])
      break unless data.dig('pageInfo', 'hasNextPage')

      cursor = data.dig('pageInfo', 'endCursor')
      break if cursor.blank?
    end

    checkouts
  end

  def query_checkout_page(query_filter, cursor)
    response = graphql_client.query(query: GRAPHQL_QUERY, variables: { query: query_filter, after: cursor }.compact)
    raise "Shopify GraphQL error: #{response.body&.dig('errors') || 'empty response'}" if response.body.blank? || response.body['errors'].present?

    response.body.dig('data', 'abandonedCheckouts') || {}
  end

  def eligible_checkout?(checkout, checkout_id)
    return false if checkout_id.blank? || checkout['completedAt'].present?

    created_at = Time.zone.parse(checkout['createdAt'])
    return false if created_at.blank? || created_at > delay_hours.hours.ago || created_at < (delay_hours + 48).hours.ago

    !@hook.account.shopify_abandoned_checkout_reminders.exists?(checkout_id: checkout_id)
  end

  def process_checkout(checkout)
    checkout_id = checkout['id']
    return unless eligible_checkout?(checkout, checkout_id)

    phone = resolve_and_validate_phone(checkout, checkout_id)
    return if phone.blank?

    button_suffix = extract_button_suffix(checkout['abandonedCheckoutUrl'], store_domain)
    return record_reminder(checkout_id, 'failed', 'checkout_url_host_mismatch') if button_suffix.nil?

    send_reminder(checkout, phone, button_suffix)
  end

  def resolve_and_validate_phone(checkout, checkout_id)
    raw_phone, country_code = extract_raw_phone_and_country(checkout)
    return test_phones.present? ? nil : record_reminder(checkout_id, 'skipped', 'missing_phone') if raw_phone.blank?

    phone = normalize_phone(raw_phone, country_code, inbox)
    return nil if test_phones.present? && test_phones.exclude?(phone)
    return record_reminder(checkout_id, 'skipped', 'missing_phone') if phone.blank?

    validate_contact_consent_and_opt_out(checkout, checkout_id, phone)
  end

  def validate_contact_consent_and_opt_out(checkout, checkout_id, phone)
    return record_reminder(checkout_id, 'skipped', 'consent_required') if require_marketing_consent? && !customer_consented?(checkout)
    return record_reminder(checkout_id, 'skipped', 'contact_opted_out') if contact_opted_out_or_blocked?(@hook.account, inbox, phone)

    phone
  end

  def extract_raw_phone_and_country(checkout)
    return [checkout.dig('customer', 'phone'), nil] if checkout.dig('customer', 'phone').present?

    shipping = checkout['shippingAddress']
    return [shipping['phone'], shipping['countryCodeV2']] if shipping&.dig('phone').present?

    billing = checkout['billingAddress']
    return [billing['phone'], billing['countryCodeV2']] if billing&.dig('phone').present?

    [nil, nil]
  end

  def customer_consented?(checkout)
    %w[emailMarketingConsent smsMarketingConsent].any? do |type|
      checkout.dig('customer', type, 'marketingState')&.casecmp?('subscribed')
    end
  end

  def send_reminder(checkout, phone, button_suffix)
    checkout_id = checkout['id']
    reminder = record_reminder(checkout_id, 'failed', 'sending')
    return if reminder.blank?

    builder = Shopify::AbandonedCartPayloadBuilder.new(hook: @hook, checkout: checkout, channel: channel, button_suffix: button_suffix)
    status, payload_or_reason = builder.build

    if status == :error
      reminder.update!(status: 'failed', reason: payload_or_reason)
      return
    end

    send_response = channel.send_template(phone, payload_or_reason, nil)

    sent = send_response.present?
    reminder.update!(status: sent ? 'sent' : 'failed', sent_at: (Time.current if sent), reason: (sent ? nil : 'send_template_failed'))
  rescue StandardError => e
    Rails.logger.error("[Shopify::AbandonedCartReminderService] Error sending reminder for #{checkout_id}: #{e.message}")
    reminder&.update(status: 'failed', reason: e.message.truncate(255))
  end

  def record_reminder(checkout_id, status, reason = nil)
    @hook.account.shopify_abandoned_checkout_reminders.create!(checkout_id: checkout_id, status: status, reason: reason)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
