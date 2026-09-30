# frozen_string_literal: true

module Shopify::TemplateVariableHelper
  RESOLVERS = {
    'first_name' => :resolve_first_name, 'full_name' => :resolve_full_name,
    'order_name' => :resolve_order_name, 'item_summary' => :resolve_item_summary,
    'total' => :resolve_total, 'tracking_number' => :resolve_tracking_number,
    'courier' => :resolve_courier, 'store_name' => :resolve_store_name,
    'order_status_url_suffix' => :resolve_order_status_url_suffix,
    'checkout_url_suffix' => :resolve_checkout_url_suffix
  }.freeze

  def resolve_template_source(source, context)
    return source['static'].to_s if source.is_a?(Hash) && source.key?('static')

    method_name = RESOLVERS[source]
    send(method_name, context) if method_name.present?
  end

  def resolve_first_name(context)
    candidates = [
      context.dig(:order, 'customer', 'first_name'), context.dig(:order, 'shipping_address', 'first_name'),
      context.dig(:order, 'billing_address', 'first_name'), context.dig(:checkout, 'customer', 'firstName'),
      context.dig(:checkout, 'shippingAddress', 'firstName'), context.dig(:checkout, 'billingAddress', 'firstName')
    ]
    format_first_name(candidates.compact_blank.first)
  end

  def resolve_full_name(context)
    cust = context.dig(:order, 'customer') || {}
    names = [cust['first_name'], cust['last_name']].compact_blank
    candidates = [
      (names.join(' ') if names.present?), cust['name'],
      context.dig(:order, 'shipping_address', 'name'), context.dig(:order, 'billing_address', 'name'),
      context.dig(:checkout, 'customer', 'name')
    ]
    candidates.compact_blank.first || 'there'
  end

  def resolve_order_name(context)
    order = context[:order] || {}
    order['name'].presence || (order['order_number'].present? ? "##{order['order_number']}" : nil)
  end

  def resolve_item_summary(context)
    line_items = context.dig(:order, 'line_items')
    titles = if line_items.present?
               line_items.filter_map { |li| li['title'] || li['name'] }
             else
               Array(context.dig(:checkout, 'lineItems', 'nodes')).filter_map { |item| item['title'] }
             end
    format_product_titles(titles)
  end

  def resolve_total(context)
    amount = context.dig(:order, 'total_price') ||
             context.dig(:checkout, 'totalPriceSet', 'shopMoney', 'amount') ||
             context.dig(:checkout, 'totalPrice', 'amount')
    currency = context.dig(:order, 'currency') ||
               context.dig(:checkout, 'totalPriceSet', 'shopMoney', 'currencyCode') ||
               context.dig(:checkout, 'totalPrice', 'currencyCode')
    format_total_price(amount, currency)
  end

  def resolve_tracking_number(context)
    context.dig(:payload, 'tracking_number').presence ||
      Array(context.dig(:payload, 'tracking_numbers')).first.presence ||
      context.dig(:order, 'fulfillments', 0, 'tracking_number').presence || 'will be shared soon'
  end

  def resolve_courier(context)
    context.dig(:payload, 'tracking_company').presence ||
      context.dig(:order, 'fulfillments', 0, 'tracking_company').presence || 'our delivery partner'
  end

  def resolve_store_name(context)
    context[:hook]&.settings&.dig('store_name').presence || context[:store_domain].presence || context[:hook]&.reference_id
  end

  def resolve_order_status_url_suffix(context)
    resolve_url_suffix(context.dig(:order, 'order_status_url'), context[:store_domain])
  end

  def resolve_checkout_url_suffix(context)
    url = context.dig(:checkout, 'abandonedCheckoutUrl') || context.dig(:checkout, 'webUrl')
    resolve_url_suffix(url, context[:store_domain])
  end

  def resolve_url_suffix(url, store_domain)
    return nil if url.blank?
    return :url_host_mismatch unless valid_checkout_host?(parse_url(url), store_domain)

    extract_button_suffix(url, store_domain)
  end

  def build_template_processed_params(mapping, context)
    processed = { 'header' => {}, 'body' => {}, 'buttons' => [] }

    image_url = mapping['header_image_url'].presence || mapping[:header_image_url].presence
    processed['header'] = { 'media_url' => image_url, 'media_type' => 'image' } if image_url.present?

    (mapping['variables'] || {}).each do |slot_key, source_def|
      value = resolve_template_source(source_def, context)
      return [:error, 'url_host_mismatch'] if value == :url_host_mismatch
      return [:error, "empty_param:#{slot_key}"] if value.blank?

      populate_processed_slot(processed, slot_key, value)
    end

    [:ok, processed]
  end

  def populate_processed_slot(processed, slot_key, value)
    component, identifier = slot_key.split('.', 2)
    case component
    when 'header' then processed['header'][identifier] = value
    when 'body' then processed['body'][identifier] = value
    when 'button' then processed['buttons'][identifier.to_i] = { 'type' => 'url', 'parameter' => value }
    end
  end
end
