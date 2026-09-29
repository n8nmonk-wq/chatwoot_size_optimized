class Api::V1::Accounts::Integrations::ShopifyController < Api::V1::Accounts::Integrations::BaseController
  include Shopify::IntegrationHelper
  before_action :setup_shopify_context, only: [:orders]
  before_action :fetch_hook, except: [:auth]
  before_action :check_authorization, only: [:auth, :show, :update, :destroy]
  before_action :validate_contact, only: [:orders]

  def auth
    shop_domain = params[:shop_domain]
    return render json: { error: 'Shop domain is required' }, status: :unprocessable_entity if shop_domain.blank?

    state = generate_shopify_token(Current.account.id)

    auth_url = "https://#{shop_domain}/admin/oauth/authorize?"
    auth_url += URI.encode_www_form(
      client_id: client_id,
      scope: REQUIRED_SCOPES.join(','),
      redirect_uri: redirect_uri,
      state: state
    )

    render json: { redirect_url: auth_url }
  end

  def show
    return render json: { connected: false } if @hook.blank?

    render json: hook_response_payload
  end

  def update
    validation_error = validate_abandoned_cart_params
    return render json: { error: validation_error }, status: :unprocessable_entity if validation_error.present?

    @hook.settings = @hook.settings.merge('abandoned_cart' => build_updated_abandoned_cart_settings)
    @hook.save!
    render json: hook_response_payload
  end

  def orders
    customers = fetch_customers
    return render json: { orders: [] } if customers.empty?

    orders = fetch_orders(customers.first['id'])
    render json: { orders: orders }
  rescue ShopifyAPI::Errors::HttpResponseError, CustomExceptions::Shopify::TokenRefreshError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @hook.destroy!
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def hook_response_payload
    {
      connected: @hook.present? && @hook.enabled?, reference_id: @hook.reference_id,
      expires_at: @hook.settings['expires_at'], settings: { abandoned_cart: @hook.settings['abandoned_cart'] || {} }
    }
  end

  def abandoned_cart_params
    params[:abandoned_cart] || {}
  end

  def validate_abandoned_cart_params
    return if params[:abandoned_cart].blank?

    validate_inbox_param || validate_delay_param || validate_test_phones_param || validate_store_domain_param
  end

  def validate_inbox_param
    return unless abandoned_cart_params.key?(:inbox_id) && abandoned_cart_params[:inbox_id].present?

    inbox = Current.account.inboxes.find_by(id: abandoned_cart_params[:inbox_id])
    'Invalid WhatsApp inbox' if inbox.blank? || inbox.channel_type != 'Channel::Whatsapp'
  end

  def validate_delay_param
    return unless abandoned_cart_params.key?(:delay_hours) && abandoned_cart_params[:delay_hours].present?

    val = abandoned_cart_params[:delay_hours].to_i
    'Delay hours must be between 1 and 72' unless val.between?(1, 72)
  end

  def validate_test_phones_param
    return unless abandoned_cart_params.key?(:test_phones)

    phones = abandoned_cart_params[:test_phones]
    return 'Test phones must be an array' unless phones.is_a?(Array)

    'Maximum 5 test phones allowed' if phones.length > 5
  end

  def validate_store_domain_param
    return unless abandoned_cart_params.key?(:store_domain) && abandoned_cart_params[:store_domain].present?

    domain = normalize_store_domain(abandoned_cart_params[:store_domain])
    'Invalid store domain' if domain.blank? || !valid_hostname?(domain)
  end

  def valid_hostname?(hostname)
    hostname =~ /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/
  end

  def normalize_store_domain(raw_domain)
    return '' if raw_domain.blank?

    domain = raw_domain.to_s.strip.sub(%r{\Ahttps?://}i, '')
    domain.split(%r{[:/?#]}).first&.strip&.downcase || ''
  end

  def build_updated_abandoned_cart_settings
    current = (@hook.settings['abandoned_cart'] || {}).dup
    abandoned_cart_params.each do |key, value|
      mapped = transform_cart_setting(key.to_sym, value)
      current[key.to_s] = mapped unless mapped == :ignore
    end
    current
  end

  CART_SETTING_MAPPERS = {
    enabled: ->(v) { ActiveRecord::Type::Boolean.new.cast(v) },
    require_marketing_consent: ->(v) { ActiveRecord::Type::Boolean.new.cast(v) },
    template_name: ->(v) { v.to_s.strip }, language: ->(v) { v.to_s.strip },
    inbox_id: ->(v) { v.presence&.to_i }, delay_hours: ->(v) { v.to_i }
  }.freeze

  def transform_cart_setting(key, value)
    return CART_SETTING_MAPPERS[key].call(value) if CART_SETTING_MAPPERS.key?(key)
    return normalize_store_domain(value) if key == :store_domain
    return normalize_test_phones(value) if key == :test_phones

    :ignore
  end

  def normalize_test_phones(raw_phones)
    return [] unless raw_phones.is_a?(Array)

    raw_phones.map do |raw|
      phone = raw.to_s.strip
      country = phone.start_with?('+') ? nil : 'IN'
      TelephoneNumber.parse(phone, country).e164_number&.delete_prefix('+').presence || phone.gsub(/\D/, '')
    end.compact_blank.uniq
  end

  def redirect_uri
    "#{ENV.fetch('FRONTEND_URL', '')}/shopify/callback"
  end

  def contact
    @contact ||= Current.account.contacts.find_by(id: params[:contact_id])
  end

  def fetch_hook
    @hook = Integrations::Hook.find_by(account: Current.account, app_id: 'shopify')
    return if @hook.present? || action_name == 'show'

    render json: { error: 'Integration not found' }, status: :not_found
  end

  def fetch_customers
    query = []
    query << "email:#{contact.email}" if contact.email.present?
    query << "phone:#{contact.phone_number}" if contact.phone_number.present?

    shopify_client.get(
      path: 'customers/search.json',
      query: {
        query: query.join(' OR '),
        fields: 'id,email,phone'
      }
    ).body['customers'] || []
  end

  def fetch_orders(customer_id)
    orders = shopify_client.get(
      path: 'orders.json',
      query: {
        customer_id: customer_id,
        status: 'any',
        fields: 'id,email,created_at,total_price,currency,fulfillment_status,financial_status'
      }
    ).body['orders'] || []

    orders.map do |order|
      order.merge('admin_url' => "https://#{@hook.reference_id}/admin/orders/#{order['id']}")
    end
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

  def shopify_client
    @shopify_client ||= ShopifyAPI::Clients::Rest::Admin.new(session: shopify_session)
  end

  def validate_contact
    return unless contact.blank? || (contact.email.blank? && contact.phone_number.blank?)

    render json: { error: 'Contact information missing' },
           status: :unprocessable_entity
  end
end
