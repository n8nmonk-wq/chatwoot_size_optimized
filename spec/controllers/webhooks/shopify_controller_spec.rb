# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ShopifyController, type: :request do
  let(:secret) { 'shopify_shared_secret_key' }
  let(:shop_domain) { 'test-store.myshopify.com' }
  let(:account) { create(:account) }
  let!(:hook) do
    create(
      :integrations_hook,
      :shopify,
      account: account,
      reference_id: shop_domain,
      settings: {
        'order_updates' => { 'enabled' => true }
      }
    )
  end

  before do
    allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return(secret)
  end

  def generate_hmac(data, secret_key)
    Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret_key, data))
  end

  describe 'POST /webhooks/shopify' do
    let(:payload) { { id: 123_456, email: 'customer@example.com' } }
    let(:body) { payload.to_json }
    let(:valid_hmac) { generate_hmac(body, secret) }

    context 'with HMAC verification' do
      it 'returns 401 when HMAC header is missing' do
        post '/webhooks/shopify',
             params: body,
             headers: {
               'CONTENT_TYPE' => 'application/json',
               'X-Shopify-Topic' => 'orders/create',
               'X-Shopify-Shop-Domain' => shop_domain
             }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 when HMAC signature is invalid' do
        post '/webhooks/shopify',
             params: body,
             headers: {
               'CONTENT_TYPE' => 'application/json',
               'X-Shopify-Hmac-SHA256' => 'invalid_signature',
               'X-Shopify-Topic' => 'orders/create',
               'X-Shopify-Shop-Domain' => shop_domain
             }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 when SHOPIFY_CLIENT_SECRET is missing' do
        allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return(nil)

        post '/webhooks/shopify',
             params: body,
             headers: {
               'CONTENT_TYPE' => 'application/json',
               'X-Shopify-Hmac-SHA256' => valid_hmac,
               'X-Shopify-Topic' => 'orders/create',
               'X-Shopify-Shop-Domain' => shop_domain
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with shop/redact event' do
      let(:redact_payload) { { shop_id: 999, shop_domain: shop_domain } }
      let(:redact_body) { redact_payload.to_json }
      let(:redact_hmac) { generate_hmac(redact_body, secret) }

      it 'deletes matching hooks and returns 200' do
        expect do
          post '/webhooks/shopify',
               params: redact_body,
               headers: {
                 'CONTENT_TYPE' => 'application/json',
                 'X-Shopify-Hmac-SHA256' => redact_hmac,
                 'X-Shopify-Topic' => 'shop/redact'
               }
        end.to change(Integrations::Hook, :count).by(-1)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with order update topics' do
      %w[orders/create fulfillments/create fulfillment_events/create].each do |topic|
        it "enqueues Shopify::OrderUpdateJob for #{topic} when enabled" do
          expect do
            post '/webhooks/shopify',
                 params: body,
                 headers: {
                   'CONTENT_TYPE' => 'application/json',
                   'X-Shopify-Hmac-SHA256' => valid_hmac,
                   'X-Shopify-Topic' => topic,
                   'X-Shopify-Shop-Domain' => shop_domain
                 }
          end.to have_enqueued_job(Shopify::OrderUpdateJob).with(
            account.id,
            topic,
            satisfy { |arg| arg['id'] == 123_456 && arg['email'] == 'customer@example.com' && !arg.key?('shopify') }
          )

          expect(response).to have_http_status(:ok)
        end
      end

      it 'returns 200 and does not enqueue job if order updates are disabled' do
        hook.update!(settings: { 'order_updates' => { 'enabled' => false } })

        expect do
          post '/webhooks/shopify',
               params: body,
               headers: {
                 'CONTENT_TYPE' => 'application/json',
                 'X-Shopify-Hmac-SHA256' => valid_hmac,
                 'X-Shopify-Topic' => 'orders/create',
                 'X-Shopify-Shop-Domain' => shop_domain
               }
        end.not_to have_enqueued_job(Shopify::OrderUpdateJob)

        expect(response).to have_http_status(:ok)
      end

      it 'returns 200 and does not enqueue job if hook does not exist' do
        hook.destroy!

        expect do
          post '/webhooks/shopify',
               params: body,
               headers: {
                 'CONTENT_TYPE' => 'application/json',
                 'X-Shopify-Hmac-SHA256' => valid_hmac,
                 'X-Shopify-Topic' => 'orders/create',
                 'X-Shopify-Shop-Domain' => shop_domain
               }
        end.not_to have_enqueued_job(Shopify::OrderUpdateJob)

        expect(response).to have_http_status(:ok)
      end

      it 'returns 200 and does not enqueue job if topic is not an order update topic' do
        unhandled_body = { id: 1 }.to_json
        unhandled_hmac = generate_hmac(unhandled_body, secret)

        expect do
          post '/webhooks/shopify',
               params: unhandled_body,
               headers: {
                 'CONTENT_TYPE' => 'application/json',
                 'X-Shopify-Hmac-SHA256' => unhandled_hmac,
                 'X-Shopify-Topic' => 'products/create',
                 'X-Shopify-Shop-Domain' => shop_domain
               }
        end.not_to have_enqueued_job(Shopify::OrderUpdateJob)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
