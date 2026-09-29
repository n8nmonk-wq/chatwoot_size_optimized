# frozen_string_literal: true

class Shopify::WebhookRegistrationService
  include Shopify::IntegrationHelper

  TOPICS = %w[ORDERS_CREATE FULFILLMENTS_CREATE FULFILLMENT_EVENTS_CREATE].freeze

  LIST_QUERY = <<~GRAPHQL
    query GetWebhookSubscriptions {
      webhookSubscriptions(first: 50) {
        nodes {
          id
          topic
          endpoint {
            __typename
            ... on WebhookHttpEndpoint {
              callbackUrl
            }
          }
        }
      }
    }
  GRAPHQL

  CREATE_MUTATION = <<~GRAPHQL
    mutation CreateWebhookSubscription($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {
      webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
        userErrors {
          field
          message
        }
        webhookSubscription {
          id
          topic
        }
      }
    }
  GRAPHQL

  def self.perform(hook)
    new(hook).perform
  end

  def initialize(hook)
    @hook = hook
  end

  def perform
    return { success: false, error: 'Integration hook missing' } if @hook.blank?
    return { success: false, error: 'Frontend URL not configured' } if callback_url.blank?

    setup_shopify_context
    existing = fetch_existing_subscriptions
    results = {}

    TOPICS.each do |topic|
      if existing.include?(topic)
        results[topic] = 'already_registered'
      else
        created, err = create_subscription(topic)
        return { success: false, error: err, results: results } unless created

        results[topic] = 'created'
      end
    end

    { success: true, results: results }
  rescue StandardError => e
    Rails.logger.error("[Shopify::WebhookRegistrationService] Error registering webhooks for hook #{@hook.id}: #{e.message}")
    { success: false, error: e.message }
  end

  private

  def callback_url
    frontend_url = ENV.fetch('FRONTEND_URL', '').presence || GlobalConfigService.load('FRONTEND_URL', '')
    "#{frontend_url.chomp('/')}/webhooks/shopify" if frontend_url.present?
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

  def fetch_existing_subscriptions
    response = graphql_client.query(query: LIST_QUERY)
    validate_graphql_response!(response)

    nodes = response.body.dig('data', 'webhookSubscriptions', 'nodes') || []
    nodes.filter_map { |node| node['topic'] if matching_callback?(node) }
  end

  def matching_callback?(node)
    url = node.dig('endpoint', 'callbackUrl')
    url.present? && url.chomp('/') == callback_url.chomp('/')
  end

  def validate_graphql_response!(response)
    return if response.body.present? && response.body['errors'].blank?

    raise StandardError, "Shopify GraphQL error: #{response.body&.dig('errors') || 'empty response'}"
  end

  def create_subscription(topic)
    variables = { topic: topic, webhookSubscription: { callbackUrl: callback_url, format: 'JSON' } }
    response = graphql_client.query(query: CREATE_MUTATION, variables: variables)
    parse_create_response(response)
  end

  def parse_create_response(response)
    body = response.body
    return [false, 'Failed to create subscription'] if body.blank?
    return [false, body['errors'].pluck('message').join(', ')] if body['errors'].present?

    user_errors = body.dig('data', 'webhookSubscriptionCreate', 'userErrors') || []
    user_errors.blank? ? [true, nil] : [false, user_errors.pluck('message').join(', ')]
  end
end
