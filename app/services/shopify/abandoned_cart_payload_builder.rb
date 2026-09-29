# frozen_string_literal: true

class Shopify::AbandonedCartPayloadBuilder
  include Shopify::SharedHelper

  def initialize(hook:, checkout:, channel:, button_suffix:)
    @hook = hook
    @checkout = checkout
    @channel = channel
    @button_suffix = button_suffix
  end

  def build
    if custom_mapping.present?
      build_from_custom_mapping
    else
      build_legacy
    end
  end

  private

  def custom_mapping
    settings['template']
  end

  def build_from_custom_mapping
    context = { checkout: @checkout, hook: @hook, store_domain: store_domain, milestone: 'abandoned_cart' }
    status, processed_params = build_template_processed_params(custom_mapping, context)
    return build_legacy if status == :error

    template_params = {
      'name' => custom_mapping['template_name'],
      'language' => custom_mapping['language'],
      'processed_params' => processed_params
    }
    processor = Whatsapp::TemplateProcessorService.new(channel: @channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call

    {
      name: name.presence || custom_mapping['template_name'],
      namespace: namespace,
      lang_code: lang_code.presence || custom_mapping['language'],
      parameters: processed_parameters.presence || []
    }
  end

  def store_domain
    settings['store_domain'].presence || @hook.reference_id
  end

  def build_legacy
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
    raw = @checkout.dig('customer', 'firstName').presence ||
          @checkout.dig('shippingAddress', 'firstName').presence ||
          @checkout.dig('billingAddress', 'firstName').presence
    format_first_name(raw)
  end

  def product_titles
    nodes = @checkout.dig('lineItems', 'nodes') || []
    titles = nodes.filter_map { |item| item['title'].presence }
    format_product_titles(titles)
  end

  def total_formatted
    total_price_set = @checkout['totalPriceSet']
    amount = total_price_set&.dig('shopMoney', 'amount')
    currency_code = total_price_set&.dig('shopMoney', 'currencyCode')
    format_total_price(amount, currency_code)
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
