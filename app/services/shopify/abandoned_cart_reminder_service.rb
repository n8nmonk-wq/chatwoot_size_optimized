# frozen_string_literal: true

class Shopify::AbandonedCartReminderService
  include Shopify::IntegrationHelper

  UNSUBSCRIBED_TAGS = %w[unsubscribed opted_out dnd].freeze

  GRAPHQL_QUERY = <<~GRAPHQL
    query GetAbandonedCheckouts($query: String) {
      abandonedCheckouts(first: 50, query: $query) {
        nodes {
          id createdAt completedAt abandonedCheckoutUrl totalPriceSet { shopMoney { amount currencyCode } }
          customer { firstName phone emailMarketingConsent { marketingState } smsMarketingConsent { marketingState } }
          shippingAddress { phone } billingAddress { phone } lineItems(first: 5) { nodes { title } }
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
    return false if @hook.blank? || !@hook.enabled?
    return false unless abandoned_cart_settings['enabled'] == true
    return false if inbox.blank? || channel.blank?

    true
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
      api_key: client_id,
      api_secret_key: client_secret,
      api_version: API_VERSION,
      scope: REQUIRED_SCOPES.join(','),
      is_embedded: true,
      is_private: false
    )
  end

  def shopify_session
    ShopifyAPI::Auth::Session.new(shop: @hook.reference_id, access_token: @hook.shopify_access_token)
  end

  def graphql_client
    @graphql_client ||= ShopifyAPI::Clients::Graphql::Admin.new(session: shopify_session)
  end

  def fetch_abandoned_checkouts
    since_iso = 72.hours.ago.iso8601
    response = graphql_client.query(query: GRAPHQL_QUERY, variables: { query: "created_at:>=#{since_iso}" })
    return [] if response.body.blank? || response.body['errors'].present?

    response.body.dig('data', 'abandonedCheckouts', 'nodes') || []
  rescue StandardError => e
    Rails.logger.error("[Shopify::AbandonedCartReminderService] GraphQL query error: #{e.message}")
    []
  end

  def parse_time(time_string)
    Time.zone.parse(time_string)
  rescue ArgumentError, TypeError
    nil
  end

  def eligible_checkout?(checkout, checkout_id)
    return false if checkout_id.blank? || checkout['completedAt'].present?

    created_at = parse_time(checkout['createdAt'])
    return false if created_at.blank? || created_at > 24.hours.ago || created_at < 72.hours.ago
    return false if @hook.account.shopify_abandoned_checkout_reminders.exists?(checkout_id: checkout_id)

    true
  end

  def process_checkout(checkout)
    checkout_id = checkout['id']
    return unless eligible_checkout?(checkout, checkout_id)

    phone = resolve_and_validate_phone(checkout, checkout_id)
    return if phone.blank?

    button_suffix = extract_button_suffix(checkout['abandonedCheckoutUrl'])
    if button_suffix.nil?
      record_reminder(checkout_id, 'failed', 'checkout_url_host_mismatch')
      return
    end

    send_reminder(checkout, phone, button_suffix)
  end

  def resolve_and_validate_phone(checkout, checkout_id)
    raw_phone = extract_raw_phone(checkout)
    return record_reminder(checkout_id, 'skipped', 'missing_phone') if raw_phone.blank?

    phone = normalize_phone(raw_phone)
    return record_reminder(checkout_id, 'skipped', 'missing_phone') if phone.blank?
    return record_reminder(checkout_id, 'skipped', 'consent_required') if require_marketing_consent? && !customer_consented?(checkout)
    return record_reminder(checkout_id, 'skipped', 'contact_opted_out') if contact_opted_out_or_blocked?(phone)

    phone
  end

  def extract_raw_phone(checkout)
    checkout.dig('customer', 'phone').presence ||
      checkout.dig('shippingAddress', 'phone').presence ||
      checkout.dig('billingAddress', 'phone').presence
  end

  def normalize_phone(raw_phone)
    clean_digits = raw_phone.gsub(/\D/, '')
    return nil if clean_digits.blank?

    normalizer = Whatsapp::PhoneNumberNormalizationService.new(inbox)
    normalized = normalizer.normalize_and_find_contact_by_provider(clean_digits, :cloud)
    normalized.presence || clean_digits
  end

  def customer_consented?(checkout)
    email_consent = checkout.dig('customer', 'emailMarketingConsent', 'marketingState')&.upcase
    sms_consent = checkout.dig('customer', 'smsMarketingConsent', 'marketingState')&.upcase

    email_consent == 'SUBSCRIBED' || sms_consent == 'SUBSCRIBED'
  end

  def contact_opted_out_or_blocked?(phone_digits)
    candidates = ([phone_digits, "+#{phone_digits}"] +
      Whatsapp::PhoneNumberNormalizationService.new(inbox).phone_number_candidates(phone_digits).flat_map { |c| [c, "+#{c}"] }).uniq

    contacts = @hook.account.contacts.where(phone_number: candidates)
    contacts.any? { |c| c.blocked? || c.label_list.intersect?(UNSUBSCRIBED_TAGS) }
  end

  def parse_url(url_string)
    URI.parse(url_string)
  rescue URI::InvalidURIError
    nil
  end

  def valid_checkout_host?(parsed_url)
    return false if parsed_url&.host.blank?

    expected_host = parse_url("https://#{store_domain}")&.host&.downcase
    expected_host.present? && parsed_url.host.casecmp?(expected_host)
  end

  def extract_button_suffix(raw_url)
    return nil if raw_url.blank?

    parsed = parse_url(raw_url)
    return nil unless valid_checkout_host?(parsed)

    [parsed.path.delete_prefix('/'), parsed.query].compact_blank.join('?')
  end

  def send_reminder(checkout, phone, button_suffix)
    checkout_id = checkout['id']
    reminder = record_reminder(checkout_id, 'failed', 'sending')
    return if reminder.blank?

    builder = Shopify::AbandonedCartPayloadBuilder.new(hook: @hook, checkout: checkout, channel: channel, button_suffix: button_suffix)
    template_payload = builder.build
    send_response = channel.send_template(phone, template_payload, nil)

    status = send_response.present? ? 'sent' : 'failed'
    reason = send_response.present? ? nil : 'send_template_failed'
    reminder.update!(status: status, sent_at: (Time.current if status == 'sent'), reason: reason)
  rescue StandardError => e
    Rails.logger.error("[Shopify::AbandonedCartReminderService] Error sending reminder for #{checkout_id}: #{e.message}")
    reminder&.update(status: 'failed', reason: e.message.truncate(255))
  end

  def record_reminder(checkout_id, status, reason = nil)
    @hook.account.shopify_abandoned_checkout_reminders.create!(
      checkout_id: checkout_id,
      status: status,
      reason: reason
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end
