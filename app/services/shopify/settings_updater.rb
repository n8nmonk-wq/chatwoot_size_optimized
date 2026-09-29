# frozen_string_literal: true

class Shopify::SettingsUpdater
  include Shopify::SharedHelper

  attr_reader :error

  def initialize(hook, params, account)
    @hook = hook
    @params = params
    @account = account
    @cart_params = params[:abandoned_cart] || {}
    @order_params = params[:order_updates] || {}
  end

  def valid?
    @error = validate_abandoned_cart || validate_order_updates
    @error.blank?
  end

  def perform!
    updated = @hook.settings.dup
    updated['abandoned_cart'] = build_cart_settings if @params.key?(:abandoned_cart)
    updated['order_updates'] = build_order_settings if @params.key?(:order_updates)
    @hook.settings = updated
    @hook.save!
  end

  private

  def validate_abandoned_cart
    return if @params[:abandoned_cart].blank?

    validate_cart_inbox || validate_delay || validate_test_phones || validate_store_domain || validate_cart_template
  end

  def validate_cart_inbox
    return unless @cart_params.key?(:inbox_id) && @cart_params[:inbox_id].present?

    inbox = @account.inboxes.find_by(id: @cart_params[:inbox_id])
    'Invalid WhatsApp inbox' if inbox.blank? || inbox.channel_type != 'Channel::Whatsapp'
  end

  def validate_delay
    return unless @cart_params.key?(:delay_hours) && @cart_params[:delay_hours].present?

    val = @cart_params[:delay_hours].to_i
    'Delay hours must be between 1 and 72' unless val.between?(1, 72)
  end

  def validate_test_phones
    return unless @cart_params.key?(:test_phones)

    phones = @cart_params[:test_phones]
    return 'Test phones must be an array' unless phones.is_a?(Array)

    'Maximum 5 test phones allowed' if phones.length > 5
  end

  def validate_store_domain
    return unless @cart_params.key?(:store_domain) && @cart_params[:store_domain].present?

    domain = normalize_store_domain(@cart_params[:store_domain])
    'Invalid store domain' if domain.blank? || !valid_hostname?(domain)
  end

  def validate_cart_template
    tmpl = @cart_params[:template]
    return if tmpl.blank?

    inbox = find_inbox(@cart_params[:inbox_id] || @hook.settings.dig('abandoned_cart', 'inbox_id'))
    return 'WhatsApp inbox is required to validate templates' if inbox.blank?

    validate_template_config(inbox, 'abandoned_cart', tmpl)
  end

  def validate_order_updates
    return if @params[:order_updates].blank?

    validate_order_inbox || validate_milestones
  end

  def validate_order_inbox
    inbox_id = @order_params[:inbox_id] || @hook.settings.dig('order_updates', 'inbox_id')
    return 'WhatsApp inbox is required when order updates are enabled' if boolean_cast(@order_params[:enabled]) && inbox_id.blank?
    return if inbox_id.blank?

    inbox = @account.inboxes.find_by(id: inbox_id)
    'Invalid WhatsApp inbox' if inbox.blank? || inbox.channel_type != 'Channel::Whatsapp'
  end

  def validate_milestones
    milestones = @order_params[:milestones]
    return if milestones.blank?

    inbox = find_inbox(@order_params[:inbox_id] || @hook.settings.dig('order_updates', 'inbox_id'))
    milestones.each do |kind, config|
      err = validate_single_milestone(kind.to_s, config, inbox)
      return err if err.present?
    end
    nil
  end

  def validate_single_milestone(kind, config, inbox)
    return "Invalid milestone kind '#{kind}'" unless Shopify::OrderNotification::KINDS.include?(kind)

    cfg = safe_hash(config)
    return "Template is required for enabled milestone '#{kind}'" if boolean_cast(cfg['enabled']) && cfg['template'].blank?
    return if cfg['template'].blank?
    return 'WhatsApp inbox is required to validate templates' if inbox.blank?

    validate_template_config(inbox, kind, cfg['template'])
  end

  def validate_template_config(inbox, kind, template_config)
    cfg = safe_hash(template_config)
    name = cfg['template_name'] || cfg['name']
    return 'Template name is required' if name.blank?

    template_def = find_template_def(inbox, name, cfg['language'])
    return "Template '#{name}' not found in chosen inbox" if template_def.blank?

    Shopify::TemplateValidator.validate(template_def, cfg, kind)
  end

  def find_template_def(inbox, name, language)
    templates = inbox.channel.message_templates || []
    templates.find { |t| t['name'] == name && (language.blank? || t['language'] == language) }
  end

  def find_inbox(id)
    @account.inboxes.find_by(id: id)
  end

  def build_cart_settings
    current = (@hook.settings['abandoned_cart'] || {}).dup
    @cart_params.each do |key, value|
      mapped = transform_cart_setting(key.to_sym, value)
      current[key.to_s] = mapped unless mapped == :ignore
    end
    current['template'] = normalize_template(@cart_params[:template]) if @cart_params.key?(:template)
    current
  end

  def build_order_settings
    current = (@hook.settings['order_updates'] || {}).dup
    current['enabled'] = boolean_cast(@order_params[:enabled]) if @order_params.key?(:enabled)
    current['inbox_id'] = @order_params[:inbox_id].presence&.to_i if @order_params.key?(:inbox_id)
    current['milestones'] = build_milestones_settings(current['milestones']) if @order_params.key?(:milestones)
    current
  end

  def build_milestones_settings(existing_milestones)
    current_milestones = (existing_milestones || {}).dup
    @order_params[:milestones].each do |kind, config|
      next unless Shopify::OrderNotification::KINDS.include?(kind.to_s)

      cfg = safe_hash(config)
      current_milestones[kind.to_s] = {
        'enabled' => boolean_cast(cfg['enabled']),
        'template' => normalize_template(cfg['template'])
      }.compact
    end
    current_milestones
  end

  CART_MAPPERS = {
    enabled: ->(v) { ActiveRecord::Type::Boolean.new.cast(v) },
    require_marketing_consent: ->(v) { ActiveRecord::Type::Boolean.new.cast(v) },
    template_name: ->(v) { v.to_s.strip }, language: ->(v) { v.to_s.strip },
    inbox_id: ->(v) { v.presence&.to_i }, delay_hours: ->(v) { v.to_i }
  }.freeze

  def transform_cart_setting(key, value)
    return CART_MAPPERS[key].call(value) if CART_MAPPERS.key?(key)
    return normalize_store_domain(value) if key == :store_domain
    return normalize_test_phones(value) if key == :test_phones

    :ignore
  end

  def normalize_template(tmpl)
    return nil if tmpl.blank?

    safe_hash(tmpl).deep_stringify_keys
  end

  def safe_hash(val)
    return val.to_unsafe_h if val.respond_to?(:to_unsafe_h)
    return val.to_h if val.respond_to?(:to_h)

    val || {}
  end

  def boolean_cast(val)
    ActiveRecord::Type::Boolean.new.cast(val)
  end
end
