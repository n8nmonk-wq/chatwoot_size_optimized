# frozen_string_literal: true

class Shopify::AbandonedCartPayloadBuilder
  CURRENCY_SYMBOLS = { 'INR' => '₹', 'USD' => '$', 'EUR' => '€', 'GBP' => '£', 'CAD' => 'CA$', 'AUD' => 'A$' }.freeze

  def initialize(hook:, checkout:, channel:, button_suffix:)
    @hook = hook
    @checkout = checkout
    @channel = channel
    @button_suffix = button_suffix
  end

  def build
    template_params = {
      'name' => template_name,
      'language' => template_language,
      'processed_params' => {
        'body' => { '1' => first_name, '2' => product_titles, '3' => total_formatted },
        'buttons' => [{ 'type' => 'url', 'parameter' => @button_suffix }]
      }
    }

    processor = Whatsapp::TemplateProcessorService.new(channel: @channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call

    {
      name: name.presence || template_name,
      namespace: namespace,
      lang_code: lang_code.presence || template_language,
      parameters: processed_parameters.presence || default_components
    }
  end

  private

  def settings
    @hook.settings&.dig('abandoned_cart') || {}
  end

  def template_name
    settings['template_name'].presence || 'abandoned_cart_reminder'
  end

  def template_language
    settings['language'].presence || 'en'
  end

  def first_name
    @checkout.dig('customer', 'firstName').presence ||
      @checkout.dig('shippingAddress', 'firstName').presence ||
      @checkout.dig('billingAddress', 'firstName').presence ||
      'there'
  end

  def product_titles
    nodes = @checkout.dig('lineItems', 'nodes') || []
    titles = nodes.filter_map { |item| item['title'].presence }
    return 'your items' if titles.empty?
    return titles.first if titles.length == 1

    remaining = titles.length - 1
    suffix = remaining == 1 ? '1 more item' : "#{remaining} more items"
    "#{titles.first} and #{suffix}"
  end

  def total_formatted
    total_price_set = @checkout['totalPriceSet']
    amount = total_price_set&.dig('shopMoney', 'amount')
    currency_code = total_price_set&.dig('shopMoney', 'currencyCode')
    return '' if amount.blank?

    symbol = CURRENCY_SYMBOLS[currency_code] || "#{currency_code} "
    ActiveSupport::NumberHelper.number_to_currency(amount, unit: symbol, format: '%u%n')
  end

  def default_components
    components = [
      {
        type: 'body',
        parameters: [
          { type: 'text', text: first_name },
          { type: 'text', text: product_titles },
          { type: 'text', text: total_formatted }
        ]
      }
    ]
    if @button_suffix.present?
      components << {
        type: 'button',
        sub_type: 'url',
        index: 0,
        parameters: [{ type: 'text', text: @button_suffix }]
      }
    end
    components
  end
end
