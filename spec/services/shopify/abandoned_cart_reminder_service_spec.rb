# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::AbandonedCartReminderService do
  let(:account) { create(:account) }
  let(:shop_domain) { 'biotane-store.myshopify.com' }
  let(:whatsapp_channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           sync_templates: false,
           validate_provider_config: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:hook) do
    create(:integrations_hook, :shopify,
           account: account,
           reference_id: shop_domain,
           access_token: 'shpat_test_access_token',
           status: :enabled,
           settings: {
             'abandoned_cart' => {
               'enabled' => true,
               'inbox_id' => inbox.id,
               'template_name' => 'abandoned_cart_reminder',
               'language' => 'en',
               'require_marketing_consent' => false
             }
           })
  end

  let(:graphql_client) { instance_double(ShopifyAPI::Clients::Graphql::Admin) }
  let(:checkout_id) { 'gid://shopify/AbandonedCheckout/987654321' }
  let(:checkout_created_at) { 30.hours.ago.iso8601 }
  let(:checkout_url) { "https://#{shop_domain}/checkouts/cn/c1-12345/recovery?key=secret_token" }
  let(:checkout_node) do
    {
      'id' => checkout_id,
      'createdAt' => checkout_created_at,
      'completedAt' => nil,
      'abandonedCheckoutUrl' => checkout_url,
      'totalPriceSet' => {
        'shopMoney' => {
          'amount' => '1299.00',
          'currencyCode' => 'INR'
        }
      },
      'customer' => {
        'firstName' => 'Aarav',
        'phone' => '+919876543210',
        'emailMarketingConsent' => { 'marketingState' => 'NOT_SUBSCRIBED' },
        'smsMarketingConsent' => { 'marketingState' => 'NOT_SUBSCRIBED' }
      },
      'shippingAddress' => { 'firstName' => nil, 'phone' => nil, 'countryCodeV2' => 'IN' },
      'billingAddress' => { 'firstName' => nil, 'phone' => nil, 'countryCodeV2' => 'IN' },
      'lineItems' => {
        'nodes' => [
          { 'title' => 'Biotane Herbal Shampoo' },
          { 'title' => 'Biotane Conditioner' }
        ]
      }
    }
  end

  let(:graphql_response_body) do
    {
      'data' => {
        'abandonedCheckouts' => {
          'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
          'nodes' => [checkout_node]
        }
      }
    }
  end
  let(:graphql_response) { instance_double(ShopifyAPI::Clients::HttpResponse, body: graphql_response_body) }
  let(:meta_messages_url_pattern) { %r{https://graph\.facebook\.com/.*/messages} }

  before do
    allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_ID', nil).and_return('client_id')
    allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return('client_secret')
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new).and_return(graphql_client)
    allow(graphql_client).to receive(:query).and_return(graphql_response)
    stub_request(:post, meta_messages_url_pattern)
      .to_return(
        status: 200,
        body: { messages: [{ id: 'wamid.HBgLMTIzNDU2Nzg5' }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#perform' do
    it 'sends WhatsApp reminder template and records sent reminder row' do
      expect { described_class.new(hook).perform }.to change {
        Shopify::AbandonedCheckoutReminder.where(account_id: account.id, checkout_id: checkout_id, status: 'sent').count
      }.by(1)

      expected_request = a_request(:post, meta_messages_url_pattern).with do |req|
        body = JSON.parse(req.body)
        body['to'] == '919876543210' &&
          body['template']['name'] == 'abandoned_cart_reminder' &&
          body['template']['components'].any? { |c| c['type'] == 'body' } &&
          body['template']['components'].any? { |c| c['type'] == 'button' }
      end
      expect(expected_request).to have_been_made.once

      reminder = Shopify::AbandonedCheckoutReminder.find_by(account_id: account.id, checkout_id: checkout_id)
      expect(reminder.status).to eq('sent')
      expect(reminder.sent_at).to be_present
      expect(reminder.reason).to be_nil
    end

    describe 'F1 pagination' do
      it 'processes checkouts across multiple pages until hasNextPage is false' do
        second_node = checkout_node.deep_dup
        second_node['id'] = 'gid://shopify/AbandonedCheckout/987654322'
        second_node['customer']['phone'] = '+919876543299'

        page1_response = instance_double(
          ShopifyAPI::Clients::HttpResponse,
          body: {
            'data' => {
              'abandonedCheckouts' => {
                'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor_page_1' },
                'nodes' => [checkout_node]
              }
            }
          }
        )
        page2_response = instance_double(
          ShopifyAPI::Clients::HttpResponse,
          body: {
            'data' => {
              'abandonedCheckouts' => {
                'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
                'nodes' => [second_node]
              }
            }
          }
        )

        expect(graphql_client).to receive(:query).with(
          query: Shopify::AbandonedCartReminderService::GRAPHQL_QUERY,
          variables: hash_not_including(:after)
        ).and_return(page1_response)

        expect(graphql_client).to receive(:query).with(
          query: Shopify::AbandonedCartReminderService::GRAPHQL_QUERY,
          variables: hash_including(after: 'cursor_page_1')
        ).and_return(page2_response)

        expect { described_class.new(hook).perform }.to change {
          Shopify::AbandonedCheckoutReminder.where(account_id: account.id, status: 'sent').count
        }.by(2)
      end
    end

    describe 'F2 address phone without country code' do
      it 'formats address phone using countryCodeV2 when missing plus' do
        checkout_node['customer']['phone'] = nil
        checkout_node['shippingAddress']['phone'] = '9812143700'
        checkout_node['shippingAddress']['countryCodeV2'] = 'IN'

        described_class.new(hook).perform
        expect(a_request(:post, meta_messages_url_pattern).with { |req| JSON.parse(req.body)['to'] == '919812143700' }).to have_been_made.once
      end
    end

    describe 'F3 fail loudly on Shopify errors' do
      it 'raises error when GraphQL returns error response' do
        error_response = instance_double(ShopifyAPI::Clients::HttpResponse, body: { 'errors' => [{ 'message' => 'Access denied' }] })
        allow(graphql_client).to receive(:query).and_return(error_response)

        expect { described_class.new(hook).perform }.to raise_error(/Shopify GraphQL error/)
      end
    end

    describe 'selection criteria' do
      it 'excludes completed checkouts' do
        checkout_node['completedAt'] = 25.hours.ago.iso8601

        expect { described_class.new(hook).perform }.not_to(change(Shopify::AbandonedCheckoutReminder, :count))
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end

      it 'excludes checkouts created less than 24 hours ago' do
        checkout_node['createdAt'] = 12.hours.ago.iso8601

        expect { described_class.new(hook).perform }.not_to(change(Shopify::AbandonedCheckoutReminder, :count))
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end

      it 'excludes checkouts created more than 72 hours ago' do
        checkout_node['createdAt'] = 80.hours.ago.iso8601

        expect { described_class.new(hook).perform }.not_to(change(Shopify::AbandonedCheckoutReminder, :count))
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end
    end

    describe 'send-once deduplication' do
      it 'does not send if a reminder record already exists for the checkout' do
        create(:shopify_abandoned_checkout_reminder,
               account: account,
               checkout_id: checkout_id,
               status: 'sent',
               sent_at: 1.day.ago)

        expect { described_class.new(hook).perform }.not_to(change(Shopify::AbandonedCheckoutReminder, :count))
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end

      it 'sends only once when perform is invoked twice' do
        described_class.new(hook).perform
        expect(Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'sent').count).to eq(1)

        # Second run should skip and not call Meta messages API again
        described_class.new(hook).perform
        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        expect(Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'sent').count).to eq(1)
      end
    end

    describe 'marketing consent' do
      context 'when require_marketing_consent is false (default)' do
        it 'sends even when customer has not subscribed to marketing' do
          checkout_node['customer']['emailMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'
          checkout_node['customer']['smsMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'

          described_class.new(hook).perform
          expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        end
      end

      context 'when require_marketing_consent is true' do
        before do
          hook.settings['abandoned_cart']['require_marketing_consent'] = true
          hook.save!
        end

        it 'skips and records skipped when customer has neither email nor SMS marketing consent' do
          checkout_node['customer']['emailMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'
          checkout_node['customer']['smsMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'

          expect { described_class.new(hook).perform }.to change {
            Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'skipped', reason: 'consent_required').count
          }.by(1)
          expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        end

        it 'sends when customer has email marketing consent' do
          checkout_node['customer']['emailMarketingConsent']['marketingState'] = 'SUBSCRIBED'
          checkout_node['customer']['smsMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'

          described_class.new(hook).perform
          expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        end

        it 'sends when customer has SMS marketing consent' do
          checkout_node['customer']['emailMarketingConsent']['marketingState'] = 'NOT_SUBSCRIBED'
          checkout_node['customer']['smsMarketingConsent']['marketingState'] = 'SUBSCRIBED'

          described_class.new(hook).perform
          expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        end
      end
    end

    describe 'phone resolution and opt-out / blocked contacts' do
      it 'resolves phone from shippingAddress when customer phone is absent' do
        checkout_node['customer']['phone'] = nil
        checkout_node['shippingAddress']['phone'] = '+919876543211'

        described_class.new(hook).perform
        expect(a_request(:post, meta_messages_url_pattern).with { |req| JSON.parse(req.body)['to'] == '919876543211' }).to have_been_made.once
      end

      it 'resolves phone from billingAddress when customer and shippingAddress phones are absent' do
        checkout_node['customer']['phone'] = nil
        checkout_node['shippingAddress']['phone'] = nil
        checkout_node['billingAddress']['phone'] = '+919876543212'

        described_class.new(hook).perform
        expect(a_request(:post, meta_messages_url_pattern).with { |req| JSON.parse(req.body)['to'] == '919876543212' }).to have_been_made.once
      end

      it 'records skipped with reason missing_phone when no phone number is present' do
        checkout_node['customer']['phone'] = nil
        checkout_node['shippingAddress']['phone'] = nil
        checkout_node['billingAddress']['phone'] = nil

        expect { described_class.new(hook).perform }.to change {
          Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'skipped', reason: 'missing_phone').count
        }.by(1)
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end

      it 'skips and records skipped when contact with that phone is blocked' do
        create(:contact, account: account, phone_number: '+919876543210', blocked: true)

        expect { described_class.new(hook).perform }.to change {
          Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'skipped', reason: 'contact_opted_out').count
        }.by(1)
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end

      %w[unsubscribed opted_out dnd].each do |tag|
        it "skips and records skipped when contact is tagged #{tag}" do
          contact = create(:contact, account: account, phone_number: '+919876543210')
          contact.label_list.add(tag)
          contact.save!

          expect { described_class.new(hook).perform }.to change {
            Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'skipped', reason: 'contact_opted_out').count
          }.by(1)
          expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        end
      end
    end

    describe 'checkout URL host mismatch' do
      it 'records failed with checkout_url_host_mismatch when host does not match configured store domain' do
        checkout_node['abandonedCheckoutUrl'] = 'https://attacker-domain.com/checkouts/cn/c1-12345/recovery'

        expect { described_class.new(hook).perform }.to change {
          Shopify::AbandonedCheckoutReminder.where(checkout_id: checkout_id, status: 'failed', reason: 'checkout_url_host_mismatch').count
        }.by(1)
        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
      end
    end

    describe 'F4 product text and F5 name fallback formatting' do
      it 'uses "there" when customer and address first names are missing' do
        checkout_node['customer']['firstName'] = nil
        checkout_node['shippingAddress']['firstName'] = nil
        checkout_node['billingAddress']['firstName'] = nil

        described_class.new(hook).perform
        expect(
          a_request(:post, meta_messages_url_pattern).with do |req|
            body = JSON.parse(req.body)
            body['template']['components'].any? do |c|
              c['type'] == 'body' && c['parameters'].any? { |p| p['text'] == 'there' }
            end
          end
        ).to have_been_made.once
      end

      it 'falls back to shippingAddress firstName when customer firstName is missing' do
        checkout_node['customer']['firstName'] = nil
        checkout_node['shippingAddress']['firstName'] = 'Priya'

        described_class.new(hook).perform
        expect(
          a_request(:post, meta_messages_url_pattern).with do |req|
            body = JSON.parse(req.body)
            body['template']['components'].any? do |c|
              c['type'] == 'body' && c['parameters'].any? { |p| p['text'] == 'Priya' }
            end
          end
        ).to have_been_made.once
      end

      it 'formats single product as just the title' do
        checkout_node['lineItems']['nodes'] = [{ 'title' => 'Single Product' }]

        described_class.new(hook).perform
        expect(
          a_request(:post, meta_messages_url_pattern).with do |req|
            body = JSON.parse(req.body)
            body['template']['components'].any? do |c|
              c['type'] == 'body' && c['parameters'].any? { |p| p['text'] == 'Single Product' }
            end
          end
        ).to have_been_made.once
      end

      it 'formats multiple products as first product and N more items' do
        checkout_node['lineItems']['nodes'] = [
          { 'title' => 'Item 1' },
          { 'title' => 'Item 2' },
          { 'title' => 'Item 3' },
          { 'title' => 'Item 4' }
        ]

        described_class.new(hook).perform
        expect(
          a_request(:post, meta_messages_url_pattern).with do |req|
            body = JSON.parse(req.body)
            body['template']['components'].any? do |c|
              c['type'] == 'body' && c['parameters'].any? { |p| p['text'] == 'Item 1 and 3 more items' }
            end
          end
        ).to have_been_made.once
      end
    end

    describe 'guards' do
      it 'returns early if hook is disabled' do
        hook.update!(status: :disabled)
        expect(ShopifyAPI::Clients::Graphql::Admin).not_to receive(:new)
        described_class.new(hook).perform
      end

      it 'returns early if abandoned_cart is not enabled in settings' do
        hook.update!(settings: { 'abandoned_cart' => { 'enabled' => false } })
        expect(ShopifyAPI::Clients::Graphql::Admin).not_to receive(:new)
        described_class.new(hook).perform
      end

      it 'returns early if inbox does not exist' do
        hook.update!(settings: { 'abandoned_cart' => { 'enabled' => true, 'inbox_id' => 999_999 } })
        expect(ShopifyAPI::Clients::Graphql::Admin).not_to receive(:new)
        described_class.new(hook).perform
      end
    end

    describe 'delay_hours and test_phones (test mode)' do
      it 'uses default 24h-72h window when delay_hours is not configured' do
        expect(graphql_client).to receive(:query).with(hash_including(
                                                         variables: hash_including(query: /created_at:>=.* AND created_at:<=.*/)
                                                       )) do |args|
          query_str = args[:variables][:query]
          expect(query_str).to match(/created_at:>=#{72.hours.ago.strftime('%Y-%m-%d')}/)
          expect(query_str).to match(/created_at:<=#{24.hours.ago.strftime('%Y-%m-%d')}/)
          graphql_response
        end

        described_class.new(hook).perform
      end

      it 'picks a 2h-old checkout when delay_hours is set to 1' do
        hook.settings['abandoned_cart']['delay_hours'] = 1
        hook.save!

        checkout_node['createdAt'] = 2.hours.ago.iso8601
        expect(described_class.new(hook).send(:eligible_checkout?, checkout_node, checkout_id)).to be true
      end

      it 'sends to a matching test phone, writes no row for other phones, and sends the other normally after clearing test mode' do
        hook.settings['abandoned_cart']['test_phones'] = ['919876543210']
        hook.save!

        other_node = checkout_node.deep_dup
        other_node['id'] = 'gid://shopify/AbandonedCheckout/111222333'
        other_node['customer']['phone'] = '+919812143700'

        allow(graphql_client).to receive(:query).and_return(
          instance_double(ShopifyAPI::Clients::HttpResponse,
                          body: {
                            'data' => {
                              'abandonedCheckouts' => {
                                'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
                                'nodes' => [checkout_node, other_node]
                              }
                            }
                          })
        )

        described_class.new(hook).perform

        expect(account.shopify_abandoned_checkout_reminders.exists?(checkout_id: checkout_id)).to be true
        expect(account.shopify_abandoned_checkout_reminders.exists?(checkout_id: other_node['id'])).to be false

        hook.settings['abandoned_cart']['test_phones'] = []
        hook.save!

        described_class.new(hook).perform

        expect(account.shopify_abandoned_checkout_reminders.exists?(checkout_id: other_node['id'])).to be true
      end

      it 'does not re-send to a test phone already sent after test mode is cleared' do
        hook.settings['abandoned_cart']['test_phones'] = ['919876543210']
        hook.save!

        described_class.new(hook).perform
        expect(account.shopify_abandoned_checkout_reminders.where(checkout_id: checkout_id).count).to eq(1)

        hook.settings['abandoned_cart']['test_phones'] = []
        hook.save!

        expect(whatsapp_channel).not_to receive(:send_template)
        described_class.new(hook).perform
      end

      it 'uses custom template mapping when configured' do
        hook.settings['abandoned_cart']['template'] = {
          'template_name' => 'custom_cart_reminder',
          'language' => 'en',
          'variables' => {
            'body.1' => 'first_name',
            'body.2' => 'item_summary',
            'button.0' => 'checkout_url_suffix'
          }
        }
        hook.save!

        expect { described_class.new(hook).perform }.to change {
          Shopify::AbandonedCheckoutReminder.where(account_id: account.id, checkout_id: checkout_id, status: 'sent').count
        }.by(1)

        expected_request = a_request(:post, meta_messages_url_pattern).with do |req|
          body = JSON.parse(req.body)
          body['template']['name'] == 'custom_cart_reminder'
        end
        expect(expected_request).to have_been_made.once
      end
    end
  end
end
