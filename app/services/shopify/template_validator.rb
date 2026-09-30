# frozen_string_literal: true

class Shopify::TemplateValidator
  ALLOWED_SOURCES_BY_KIND = {
    'abandoned_cart' => %w[first_name full_name item_summary total store_name checkout_url_suffix static],
    'confirmed' => %w[first_name full_name order_name item_summary total store_name order_status_url_suffix static],
    'shipped' => %w[first_name full_name order_name item_summary total tracking_number courier store_name order_status_url_suffix static],
    'out_for_delivery' => %w[first_name full_name order_name item_summary total tracking_number courier store_name order_status_url_suffix static],
    'delivered' => %w[first_name full_name order_name item_summary total tracking_number courier store_name order_status_url_suffix static]
  }.freeze

  def self.validate(template_def, mapping, kind)
    new(template_def, mapping, kind).validate
  end

  def initialize(template_def, mapping, kind)
    @template_def = template_def
    @mapping = mapping || {}
    @kind = kind.to_s
  end

  def validate
    return 'Template not found' if @template_def.blank?
    return 'Template is not approved' unless @template_def['status']&.upcase == 'APPROVED'

    media_err = check_media_header
    return media_err if media_err.present?

    slots_err = check_required_slots
    return slots_err if slots_err.present?

    validate_variable_sources
  end

  private

  def check_media_header
    format = header_format
    if %w[IMAGE VIDEO DOCUMENT].include?(format)
      return validate_header_image_url if format == 'IMAGE' && @kind == 'abandoned_cart'

      return 'Media header templates are not supported'
    end

    return 'Header image is not supported for order updates' if @kind != 'abandoned_cart' && header_image_url.present?

    nil
  end

  def header_format
    header = Array(@template_def['components']).find { |c| c['type']&.casecmp?('HEADER') }
    header['format']&.upcase if header
  end

  def header_image_url
    (@mapping['header_image_url'] || @mapping[:header_image_url]).to_s.strip
  end

  def validate_header_image_url
    url = header_image_url
    return 'Header image URL is required for this template' if url.blank?

    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end
    return 'Header image URL must start with https://' unless uri.is_a?(URI::HTTPS) && uri.host.present?

    nil
  end

  def check_required_slots
    required = extract_required_slots
    mapped = (@mapping['variables'] || @mapping[:variables] || {}).keys.map(&:to_s)
    missing = required - mapped
    "Missing template variable mappings: #{missing.join(', ')}" if missing.any?
  end

  def extract_required_slots
    slots = []
    Array(@template_def['components']).each do |c|
      extract_component_slots(c, slots)
    end
    slots.uniq
  end

  def extract_component_slots(component, slots)
    type = component['type']&.upcase
    slots.concat(extract_text_slots(component['text'], 'header')) if type == 'HEADER' && component['format']&.upcase == 'TEXT'
    slots.concat(extract_text_slots(component['text'], 'body')) if type == 'BODY'
    extract_button_slots(component['buttons'], slots) if type == 'BUTTONS'
  end

  def extract_button_slots(buttons, slots)
    Array(buttons).each_with_index do |btn, idx|
      slots << "button.#{idx}" if btn['type']&.upcase == 'URL' && btn['url']&.include?('{{')
    end
  end

  def extract_text_slots(text, prefix)
    return [] if text.blank?

    text.scan(/{{([^}]+)}}/).flatten.map { |v| "#{prefix}.#{v}" }
  end

  def validate_variable_sources
    allowed = ALLOWED_SOURCES_BY_KIND[@kind] || []
    variables = (@mapping['variables'] || @mapping[:variables] || {})

    variables.each do |slot, source|
      err = validate_slot_source(slot.to_s, source, allowed)
      return err if err.present?
    end
    nil
  end

  def validate_slot_source(slot, source, allowed)
    source_name = source.is_a?(Hash) ? 'static' : source.to_s
    return "Source '#{source_name}' is not allowed for #{@kind}" unless allowed.include?(source_name)
    return 'URL suffix sources can only be used in URL button variables' if source_name.end_with?('_url_suffix') && !slot.start_with?('button.')
    return 'Static text can only be used in header or body variables' if source_name == 'static' && slot.start_with?('button.')

    nil
  end
end
