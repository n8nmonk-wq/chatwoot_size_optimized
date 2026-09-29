# frozen_string_literal: true

module Shopify::SharedHelper
  include Shopify::TemplateVariableHelper

  UNSUBSCRIBED_TAGS = %w[unsubscribed opted_out dnd].freeze
  CURRENCY_SYMBOLS = { 'INR' => '₹', 'USD' => '$', 'EUR' => '€', 'GBP' => '£', 'CAD' => 'CA$', 'AUD' => 'A$' }.freeze

  def parsed_e164(raw_phone, country_code = nil)
    return nil if raw_phone.blank?

    if raw_phone.start_with?('+')
      TelephoneNumber.parse(raw_phone).e164_number&.delete_prefix('+')
    elsif country_code.present?
      TelephoneNumber.parse(raw_phone, country_code).e164_number&.delete_prefix('+')
    end
  end

  def normalize_phone(raw_phone, country_code = nil, inbox = nil)
    clean = parsed_e164(raw_phone, country_code) || raw_phone.to_s.gsub(/\D/, '')
    return nil if clean.blank?
    return clean if inbox.blank?

    normalizer = Whatsapp::PhoneNumberNormalizationService.new(inbox)
    normalizer.normalize_and_find_contact_by_provider(clean, :cloud).presence || clean
  end

  def test_phone_allowed?(phone, test_phones)
    return true if test_phones.blank?
    return false if phone.blank?

    test_phones.map(&:to_s).include?(phone.to_s)
  end

  def contact_opted_out_or_blocked?(account, inbox, phone_digits)
    return false if account.blank? || phone_digits.blank?

    candidates = ([phone_digits, "+#{phone_digits}"] + candidate_phones(inbox, phone_digits)).uniq
    account.contacts.where(phone_number: candidates).any? { |c| c.blocked? || c.label_list.intersect?(UNSUBSCRIBED_TAGS) }
  end

  def candidate_phones(inbox, phone_digits)
    return [] if inbox.blank?

    Whatsapp::PhoneNumberNormalizationService.new(inbox).phone_number_candidates(phone_digits).flat_map { |c| [c, "+#{c}"] }
  end

  def parse_url(url_string)
    URI.parse(url_string)
  rescue URI::InvalidURIError
    nil
  end

  def valid_checkout_host?(parsed_url, store_domain)
    return false if store_domain.blank? || parsed_url.blank?

    expected_host = parse_url("https://#{store_domain}")&.host
    expected_host.present? && parsed_url.host&.casecmp?(expected_host)
  end

  def extract_button_suffix(raw_url, store_domain)
    return nil if raw_url.blank? || store_domain.blank?

    parsed = parse_url(raw_url)
    return nil unless valid_checkout_host?(parsed, store_domain)

    [parsed.path.delete_prefix('/'), parsed.query].compact_blank.join('?')
  end

  def format_first_name(raw_name)
    raw_name.to_s.strip.presence || 'there'
  end

  def format_product_titles(titles)
    clean_titles = Array(titles).filter_map { |t| t.to_s.strip.presence }
    return 'your items' if clean_titles.empty?
    return clean_titles.first if clean_titles.length == 1

    remaining = clean_titles.length - 1
    suffix = remaining == 1 ? '1 more item' : "#{remaining} more items"
    "#{clean_titles.first} and #{suffix}"
  end

  def format_total_price(amount, currency_code)
    return '' if amount.blank?

    symbol = CURRENCY_SYMBOLS[currency_code] || "#{currency_code} "
    ActiveSupport::NumberHelper.number_to_currency(amount, unit: symbol, format: '%u%n')
  end

  def valid_hostname?(hostname)
    hostname =~ /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/
  end

  def normalize_store_domain(raw_domain)
    return '' if raw_domain.blank?

    domain = raw_domain.to_s.strip.sub(%r{\Ahttps?://}i, '')
    domain.split(%r{[:/?#]}).first&.strip&.downcase || ''
  end

  def normalize_test_phones(raw_phones)
    return [] unless raw_phones.is_a?(Array)

    raw_phones.map do |raw|
      phone = raw.to_s.strip
      country = phone.start_with?('+') ? nil : 'IN'
      TelephoneNumber.parse(phone, country).e164_number&.delete_prefix('+').presence || phone.gsub(/\D/, '')
    end.compact_blank.uniq
  end

  def extract_order_phone(order, inbox = nil)
    return nil if order.blank?

    candidates = [
      [order['phone'], nil],
      [order.dig('customer', 'phone'), nil],
      [order.dig('shipping_address', 'phone'), order.dig('shipping_address', 'country_code')],
      [order.dig('billing_address', 'phone'), order.dig('billing_address', 'country_code')]
    ]

    candidates.each do |raw_phone, country_code|
      next if raw_phone.blank?

      normalized = normalize_phone(raw_phone, country_code, inbox)
      return normalized if normalized.present?
    end

    nil
  end
end
