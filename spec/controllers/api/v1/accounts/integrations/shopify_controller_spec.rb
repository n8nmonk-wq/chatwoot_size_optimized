require 'rails_helper'

# Stub class for ShopifyAPI response
class ShopifyAPIResponse
  attr_reader :body

  def initialize(body)
    @body = body
  end
end

RSpec.describe 'Shopify Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:client) { create(:user, account: account, role: :client) }
  let(:unauthorized_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, email: 'test@example.com', phone_number: '+1234567890') }

  describe 'POST /api/v1/accounts/:account_id/integrations/shopify/auth' do
    let(:shop_domain) { 'test-store.myshopify.com' }

    context 'when it is an administrator' do
      it 'returns a redirect URL for Shopify OAuth' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key('redirect_url')
        expect(response.parsed_body['redirect_url']).to include(shop_domain)
      end

      it 'returns error when shop domain is missing' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Shop domain is required')
      end
    end

    context 'when it is a client' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             headers: client.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/shopify/orders' do
    before do
      create(:integrations_hook, :shopify, account: account)
    end

    context 'when it is an authenticated user' do
      # rubocop:disable RSpec/AnyInstance
      let(:shopify_client) { instance_double(ShopifyAPI::Clients::Rest::Admin) }

      let(:customers_response) do
        instance_double(
          ShopifyAPIResponse,
          body: { 'customers' => [{ 'id' => '123' }] }
        )
      end

      let(:orders_response) do
        instance_double(
          ShopifyAPIResponse,
          body: {
            'orders' => [{
              'id' => '456',
              'email' => 'test@example.com',
              'created_at' => Time.now.iso8601,
              'total_price' => '100.00',
              'currency' => 'USD',
              'fulfillment_status' => 'fulfilled',
              'financial_status' => 'paid'
            }]
          }
        )
      end

      before do
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:shopify_client).and_return(shopify_client)

        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_id).and_return('test_client_id')
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_secret).and_return('test_client_secret')

        allow(shopify_client).to receive(:get).with(
          path: 'customers/search.json',
          query: { query: "email:#{contact.email} OR phone:#{contact.phone_number}", fields: 'id,email,phone' }
        ).and_return(customers_response)

        allow(shopify_client).to receive(:get).with(
          path: 'orders.json',
          query: { customer_id: '123', status: 'any', fields: 'id,email,created_at,total_price,currency,fulfillment_status,financial_status' }
        ).and_return(orders_response)
      end

      it 'returns orders for the contact' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key('orders')
        expect(response.parsed_body['orders'].length).to eq(1)
        expect(response.parsed_body['orders'][0]['id']).to eq('456')
      end

      it 'initializes Shopify context with supported API_VERSION' do
        expect(ShopifyAPI::Context).to receive(:setup).with(
          api_key: 'test_client_id',
          api_secret_key: 'test_client_secret',
          api_version: Shopify::IntegrationHelper::API_VERSION,
          scope: Shopify::IntegrationHelper::REQUIRED_SCOPES.join(','),
          is_embedded: true,
          is_private: false
        ).and_call_original

        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
      end

      it 'returns error when contact has no email or phone' do
        contact_without_info = create(:contact, account: account)

        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact_without_info.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Contact information missing')
      end

      it 'returns empty array when no customers found' do
        empty_customers_response = instance_double(
          ShopifyAPIResponse,
          body: { 'customers' => [] }
        )

        allow(shopify_client).to receive(:get).with(
          path: 'customers/search.json',
          query: { query: "email:#{contact.email} OR phone:#{contact.phone_number}", fields: 'id,email,phone' }
        ).and_return(empty_customers_response)

        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['orders']).to eq([])
      end
      # rubocop:enable RSpec/AnyInstance
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/integrations/shopify' do
    before do
      create(:integrations_hook, :shopify, account: account)
    end

    context 'when it is an administrator' do
      it 'deletes the shopify integration' do
        expect do
          delete "/api/v1/accounts/#{account.id}/integrations/shopify",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change { account.hooks.count }.by(-1)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized and keeps the integration' do
        expect do
          delete "/api/v1/accounts/#{account.id}/integrations/shopify",
                 headers: agent.create_new_auth_token,
                 as: :json
        end.not_to(change { account.hooks.count })

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/integrations/shopify",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/shopify' do
    context 'when it is an administrator' do
      it 'returns connected false if hook does not exist' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({ 'connected' => false })
      end

      it 'returns status and settings without exposing secrets if hook exists' do
        create(:integrations_hook, :shopify,
               account: account,
               reference_id: 'test-store.myshopify.com',
               access_token: 'secret_token_123',
               settings: {
                 'refresh_token' => 'secret_refresh_123',
                 'scope' => 'read_customers,read_orders',
                 'expires_at' => '2026-10-01T00:00:00Z',
                 'abandoned_cart' => {
                   'enabled' => true,
                   'template_name' => 'abandoned_cart_reminder'
                 }
               })

        get "/api/v1/accounts/#{account.id}/integrations/shopify",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        aggregate_failures do
          expect(body['connected']).to be true
          expect(body['reference_id']).to eq('test-store.myshopify.com')
          expect(body['expires_at']).to eq('2026-10-01T00:00:00Z')
          expect(body.dig('settings', 'abandoned_cart', 'enabled')).to be true
          expect(body.dig('settings', 'abandoned_cart', 'template_name')).to eq('abandoned_cart_reminder')
          expect(body.dig('settings', 'order_updates')).to eq({})
          expect(body).not_to have_key('access_token')
          expect(body).not_to have_key('refresh_token')
          expect(body).not_to have_key('scope')
        end
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is a client' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify",
            headers: client.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/integrations/shopify' do
    let(:sample_templates) do
      [
        {
          'name' => 'order_confirmed_template',
          'status' => 'APPROVED',
          'language' => 'en',
          'components' => [
            { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Hi {{1}}' },
            { 'type' => 'BODY', 'text' => 'Your order {{1}} of {{2}} is confirmed.' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }
          ]
        },
        {
          'name' => 'cart_reminder_template',
          'status' => 'APPROVED',
          'language' => 'en',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hi {{1}}, items: {{2}}, total: {{3}}' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }
          ]
        },
        {
          'name' => 'pending_template',
          'status' => 'PENDING',
          'language' => 'en',
          'components' => [{ 'type' => 'BODY', 'text' => 'Pending' }]
        },
        {
          'name' => 'media_template',
          'status' => 'APPROVED',
          'language' => 'en',
          'components' => [
            { 'type' => 'HEADER', 'format' => 'IMAGE' },
            { 'type' => 'BODY', 'text' => 'Image' }
          ]
        }
      ]
    end
    let(:whatsapp_channel) do
      create(:channel_whatsapp,
             account: account,
             provider: 'whatsapp_cloud',
             sync_templates: false,
             validate_provider_config: false,
             message_templates: sample_templates)
    end
    let(:whatsapp_inbox) { whatsapp_channel.inbox }
    let(:email_channel) { create(:channel_email, account: account) }
    let(:email_inbox) { email_channel.inbox }
    let!(:hook) do
      create(:integrations_hook, :shopify,
             account: account,
             reference_id: 'test-store.myshopify.com',
             access_token: 'secret_token_123',
             settings: {
               'refresh_token' => 'secret_refresh_123',
               'scope' => 'read_customers,read_orders',
               'expires_at' => '2026-10-01T00:00:00Z',
               'abandoned_cart' => {
                 'enabled' => false,
                 'template_name' => 'old_template'
               }
             })
    end

    context 'when it is an administrator' do
      it 'merges abandoned cart settings without wiping tokens or secrets' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                abandoned_cart: {
                  enabled: true,
                  inbox_id: whatsapp_inbox.id,
                  template_name: 'new_reminder_template',
                  language: 'en',
                  store_domain: 'biotane.in',
                  require_marketing_consent: true,
                  test_phones: ['+91 98121 43700'],
                  delay_hours: 2
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        hook.reload
        aggregate_failures do
          expect(hook.settings['refresh_token']).to eq('secret_refresh_123')
          expect(hook.settings['scope']).to eq('read_customers,read_orders')
          expect(hook.settings['expires_at']).to eq('2026-10-01T00:00:00Z')

          cart_settings = hook.settings['abandoned_cart']
          expect(cart_settings['enabled']).to be true
          expect(cart_settings['inbox_id']).to eq(whatsapp_inbox.id)
          expect(cart_settings['template_name']).to eq('new_reminder_template')
          expect(cart_settings['language']).to eq('en')
          expect(cart_settings['store_domain']).to eq('biotane.in')
          expect(cart_settings['require_marketing_consent']).to be true
          expect(cart_settings['test_phones']).to eq(['919812143700'])
          expect(cart_settings['delay_hours']).to eq(2)
        end
      end

      it 'returns 422 if inbox is not a WhatsApp inbox' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { inbox_id: email_inbox.id } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid WhatsApp inbox')
      end

      it 'returns 422 if delay_hours is outside 1..72' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { delay_hours: 0 } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Delay hours must be between 1 and 72')
      end

      it 'returns 422 if test_phones exceeds 5 numbers' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { test_phones: %w[1 2 3 4 5 6] } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Maximum 5 test phones allowed')
      end

      it 'normalizes store_domain by stripping scheme, path, trailing slash and lowercasing' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { store_domain: 'https://Biotane.in/' } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        expect(hook.reload.settings['abandoned_cart']['store_domain']).to eq('biotane.in')
      end

      it 'returns 422 if store_domain is not a valid hostname' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { store_domain: 'not a domain' } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid store domain')
      end

      it 'merges order_updates settings without wiping abandoned_cart or tokens' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  enabled: true,
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: {
                        template_name: 'order_confirmed_template',
                        language: 'en',
                        variables: {
                          'header.1' => 'first_name',
                          'body.1' => 'order_name',
                          'body.2' => 'total',
                          'button.0' => 'order_status_url_suffix'
                        }
                      }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        hook.reload
        aggregate_failures do
          expect(hook.settings['refresh_token']).to eq('secret_refresh_123')
          expect(hook.settings['abandoned_cart']['template_name']).to eq('old_template')

          order_settings = hook.settings['order_updates']
          expect(order_settings['enabled']).to be true
          expect(order_settings['inbox_id']).to eq(whatsapp_inbox.id)
          expect(order_settings.dig('milestones', 'confirmed', 'enabled')).to be true
          expect(order_settings.dig('milestones', 'confirmed', 'template', 'template_name')).to eq('order_confirmed_template')
          expect(order_settings.dig('milestones', 'confirmed', 'template', 'variables', 'body.1')).to eq('order_name')
        end
      end

      it 'returns 422 if order_updates is enabled but inbox_id is missing' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { order_updates: { enabled: true } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('WhatsApp inbox is required when order updates are enabled')
      end

      it 'returns 422 if order_updates inbox is not a WhatsApp inbox' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { order_updates: { inbox_id: email_inbox.id } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid WhatsApp inbox')
      end

      it 'returns 422 if milestone kind is invalid' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: { cancelled: { enabled: true } }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Invalid milestone kind')
      end

      it 'returns 422 if enabled milestone has no template' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: { confirmed: { enabled: true } }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq("Template is required for enabled milestone 'confirmed'")
      end

      it 'returns 422 if milestone template is not found in inbox' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: { template_name: 'non_existent_template', language: 'en', variables: {} }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq("Template 'non_existent_template' not found in chosen inbox")
      end

      it 'returns 422 if milestone template is not approved' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: { template_name: 'pending_template', language: 'en', variables: {} }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Template is not approved')
      end

      it 'returns 422 if milestone template has media header' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: { template_name: 'media_template', language: 'en', variables: {} }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Media header templates are not supported')
      end

      it 'returns 422 if template has unmapped variables' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: {
                        template_name: 'order_confirmed_template',
                        language: 'en',
                        variables: { 'header.1' => 'first_name', 'body.1' => 'order_name' }
                      }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Missing template variable mappings')
      end

      it 'returns 422 if source is disallowed for milestone' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: {
                        template_name: 'order_confirmed_template',
                        language: 'en',
                        variables: {
                          'header.1' => 'first_name',
                          'body.1' => 'tracking_number',
                          'body.2' => 'total',
                          'button.0' => 'order_status_url_suffix'
                        }
                      }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq("Source 'tracking_number' is not allowed for confirmed")
      end

      it 'returns 422 if URL suffix source is used in body' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: {
                        template_name: 'order_confirmed_template',
                        language: 'en',
                        variables: {
                          'header.1' => 'first_name',
                          'body.1' => 'order_status_url_suffix',
                          'body.2' => 'total',
                          'button.0' => 'order_status_url_suffix'
                        }
                      }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('URL suffix sources can only be used in URL button variables')
      end

      it 'returns 422 if static text is used in button slot' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                order_updates: {
                  inbox_id: whatsapp_inbox.id,
                  milestones: {
                    confirmed: {
                      enabled: true,
                      template: {
                        template_name: 'order_confirmed_template',
                        language: 'en',
                        variables: {
                          'header.1' => 'first_name',
                          'body.1' => 'order_name',
                          'body.2' => 'total',
                          'button.0' => { 'static' => 'https://example.com' }
                        }
                      }
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Static text can only be used in header or body variables')
      end

      it 'allows saving custom template mapping for abandoned_cart' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: {
                abandoned_cart: {
                  inbox_id: whatsapp_inbox.id,
                  template: {
                    template_name: 'cart_reminder_template',
                    language: 'en',
                    variables: {
                      'body.1' => 'first_name',
                      'body.2' => 'item_summary',
                      'body.3' => 'total',
                      'button.0' => 'checkout_url_suffix'
                    }
                  }
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        expect(hook.reload.settings.dig('abandoned_cart', 'template', 'template_name')).to eq('cart_reminder_template')
      end

      it 'returns 404 if hook does not exist' do
        hook.destroy!

        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { enabled: true } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { enabled: true } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is a client' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/integrations/shopify",
              params: { abandoned_cart: { enabled: true } },
              headers: client.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/shopify/register_webhooks' do
    let!(:hook) { create(:integrations_hook, :shopify, account: account) }
    let(:registration_service) { instance_double(Shopify::WebhookRegistrationService) }

    context 'when it is an administrator' do
      before do
        allow(Shopify::WebhookRegistrationService).to receive(:new).with(hook).and_return(registration_service)
      end

      it 'calls WebhookRegistrationService and returns 200 with results' do
        allow(registration_service).to receive(:perform).and_return(
          success: true,
          results: { 'ORDERS_CREATE' => 'created', 'FULFILLMENTS_CREATE' => 'already_registered' }
        )

        post "/api/v1/accounts/#{account.id}/integrations/shopify/register_webhooks",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['success']).to be true
        expect(response.parsed_body['results']['ORDERS_CREATE']).to eq('created')
      end

      it 'returns 422 with error message when registration fails' do
        allow(registration_service).to receive(:perform).and_return(
          success: false,
          error: 'Protected customer data access required'
        )

        post "/api/v1/accounts/#{account.id}/integrations/shopify/register_webhooks",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Protected customer data access required')
      end

      it 'returns 404 if hook does not exist' do
        hook.destroy!

        post "/api/v1/accounts/#{account.id}/integrations/shopify/register_webhooks",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/register_webhooks",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is a client' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/register_webhooks",
             headers: client.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
