# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::WebhookRegistrationService do
  let(:account) { create(:account) }
  let(:hook) do
    create(
      :integrations_hook,
      :shopify,
      account: account,
      reference_id: 'test-shop.myshopify.com',
      access_token: 'shpat_test123'
    )
  end
  let(:graphql_client) { instance_double(ShopifyAPI::Clients::Graphql::Admin) }

  before do
    allow(ShopifyAPI::Context).to receive(:setup)
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new).and_return(graphql_client)
  end

  describe '#perform' do
    around do |example|
      with_modified_env FRONTEND_URL: 'https://app.chatwoot.test' do
        example.run
      end
    end

    context 'when no subscriptions exist' do
      before do
        # List query returns no existing subscriptions
        allow(graphql_client).to receive(:query).with(
          query: described_class::LIST_QUERY
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: { 'data' => { 'webhookSubscriptions' => { 'nodes' => [] } } }
          )
        )

        # Create mutation succeeds for each topic
        allow(graphql_client).to receive(:query).with(
          hash_including(query: described_class::CREATE_MUTATION)
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: {
              'data' => {
                'webhookSubscriptionCreate' => {
                  'userErrors' => [],
                  'webhookSubscription' => { 'id' => 'gid://shopify/WebhookSubscription/1' }
                }
              }
            }
          )
        )
      end

      it 'registers all three order topics' do
        result = described_class.new(hook).perform

        expect(result[:success]).to be true
        expect(result[:results]).to eq(
          'ORDERS_CREATE' => 'created',
          'FULFILLMENTS_CREATE' => 'created',
          'FULFILLMENT_EVENTS_CREATE' => 'created'
        )
      end
    end

    context 'when some subscriptions already exist pointing at callback_url' do
      before do
        allow(graphql_client).to receive(:query).with(
          query: described_class::LIST_QUERY
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: {
              'data' => {
                'webhookSubscriptions' => {
                  'nodes' => [
                    {
                      'id' => 'gid://shopify/WebhookSubscription/10',
                      'topic' => 'ORDERS_CREATE',
                      'endpoint' => { 'callbackUrl' => 'https://app.chatwoot.test/webhooks/shopify' }
                    }
                  ]
                }
              }
            }
          )
        )

        allow(graphql_client).to receive(:query).with(
          hash_including(
            query: described_class::CREATE_MUTATION,
            variables: hash_including(topic: 'FULFILLMENTS_CREATE')
          )
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: {
              'data' => {
                'webhookSubscriptionCreate' => {
                  'userErrors' => [],
                  'webhookSubscription' => { 'id' => 'gid://shopify/WebhookSubscription/11' }
                }
              }
            }
          )
        )

        allow(graphql_client).to receive(:query).with(
          hash_including(
            query: described_class::CREATE_MUTATION,
            variables: hash_including(topic: 'FULFILLMENT_EVENTS_CREATE')
          )
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: {
              'data' => {
                'webhookSubscriptionCreate' => {
                  'userErrors' => [],
                  'webhookSubscription' => { 'id' => 'gid://shopify/WebhookSubscription/12' }
                }
              }
            }
          )
        )
      end

      it 'skips already registered topic and creates remaining ones' do
        result = described_class.new(hook).perform

        expect(result[:success]).to be true
        expect(result[:results]).to eq(
          'ORDERS_CREATE' => 'already_registered',
          'FULFILLMENTS_CREATE' => 'created',
          'FULFILLMENT_EVENTS_CREATE' => 'created'
        )
      end
    end

    context 'when Shopify returns a protected customer data error' do
      before do
        allow(graphql_client).to receive(:query).with(
          query: described_class::LIST_QUERY
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: { 'data' => { 'webhookSubscriptions' => { 'nodes' => [] } } }
          )
        )

        allow(graphql_client).to receive(:query).with(
          hash_including(
            query: described_class::CREATE_MUTATION,
            variables: hash_including(topic: 'ORDERS_CREATE')
          )
        ).and_return(
          instance_double(
            ShopifyAPI::Clients::HttpResponse,
            body: {
              'data' => {
                'webhookSubscriptionCreate' => {
                  'userErrors' => [
                    { 'field' => ['topic'], 'message' => 'App must be approved for protected customer data' }
                  ],
                  'webhookSubscription' => nil
                }
              }
            }
          )
        )
      end

      it 'returns success: false with the Shopify error message' do
        result = described_class.new(hook).perform

        expect(result[:success]).to be false
        expect(result[:error]).to include('App must be approved for protected customer data')
      end
    end
  end
end
