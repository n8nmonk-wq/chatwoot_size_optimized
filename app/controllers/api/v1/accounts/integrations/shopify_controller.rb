class Api::V1::Accounts::Integrations::ShopifyController < Api::V1::Accounts::Integrations::BaseController
  include Shopify::IntegrationHelper
  include Shopify::SharedHelper
  before_action :setup_shopify_context, only: [:orders]
  before_action :fetch_hook, except: [:auth]
  before_action :check_authorization, only: [:auth, :show, :update, :destroy, :register_webhooks]
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
    updater = Shopify::SettingsUpdater.new(@hook, params, Current.account)
    return render json: { error: updater.error }, status: :unprocessable_entity unless updater.valid?

    updater.perform!
    render json: hook_response_payload
  end

  def register_webhooks
    result = Shopify::WebhookRegistrationService.new(@hook).perform
    return render json: result if result[:success]

    render json: { error: result[:error] || 'Failed to register webhooks' }, status: :unprocessable_entity
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
      expires_at: @hook.settings['expires_at'],
      settings: {
        abandoned_cart: @hook.settings['abandoned_cart'] || {},
        order_updates: @hook.settings['order_updates'] || {}
      }
    }
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
