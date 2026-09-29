# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::OrderUpdateService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           sync_templates: false,
           validate_provider_config: false,
           message_templates: default_message_templates)
  end
  let(:inbox) { channel.inbox }
  let(:shop_domain) { 'test-store.myshopify.com' }
  let(:test_phone) { '919876543210' }
  let(:language) { 'en' }
  let(:meta_messages_url_pattern) { %r{https://graph\.facebook\.com/.*/messages} }
  let(:shopify_order_url_pattern) { %r{https://#{shop_domain}/admin/api/.*/orders/.*\.json} }
  let!(:hook) do
    create(
      :integrations_hook,
      :shopify,
      account: account,
      reference_id: shop_domain,
      settings: build_hook_settings(inbox.id)
    )
  end

  def approved_template(name, components)
    { 'name' => name, 'language' => 'en', 'status' => 'approved', 'components' => components }
  end

  def default_message_templates
    [
      approved_template('order_update_template', [
                          { 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}} total {{3}}' },
                          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }
                        ]),
      approved_template('shipped_template', [{ 'type' => 'BODY', 'text' => 'Hi {{1}}, tracked at {{2}} by {{3}}' }]),
      approved_template('ofd_template', [{ 'type' => 'BODY', 'text' => 'Hi {{1}}, out for delivery by {{2}}' }]),
      approved_template('delivered_template', [{ 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}} is delivered!' }])
    ]
  end

  def confirmed_mapping
    {
      'template_name' => 'order_update_template',
      'language' => language,
      'variables' => {
        'body.1' => 'first_name',
        'body.2' => 'order_name',
        'body.3' => 'total',
        'button.0' => 'order_status_url_suffix'
      }
    }
  end

  def shipped_mapping
    {
      'template_name' => 'shipped_template',
      'language' => language,
      'variables' => { 'body.1' => 'first_name', 'body.2' => 'tracking_number', 'body.3' => 'courier' }
    }
  end

  def out_for_delivery_mapping
    {
      'template_name' => 'ofd_template',
      'language' => language,
      'variables' => { 'body.1' => 'first_name', 'body.2' => 'courier' }
    }
  end

  def delivered_mapping
    {
      'template_name' => 'delivered_template',
      'language' => language,
      'variables' => { 'body.1' => 'first_name', 'body.2' => 'order_name' }
    }
  end

  def build_hook_settings(inbox_id)
    {
      'abandoned_cart' => { 'store_domain' => shop_domain, 'test_phones' => [] },
      'order_updates' => {
        'enabled' => true,
        'inbox_id' => inbox_id,
        'milestones' => {
          'confirmed' => { 'enabled' => true, 'template' => confirmed_mapping },
          'shipped' => { 'enabled' => true, 'template' => shipped_mapping },
          'out_for_delivery' => { 'enabled' => true, 'template' => out_for_delivery_mapping },
          'delivered' => { 'enabled' => true, 'template' => delivered_mapping }
        }
      }
    }
  end

  before do
    stub_request(:post, meta_messages_url_pattern).to_return(
      status: 200,
      body: { 'messages' => [{ 'id' => 'wamid.123' }] }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:get, shopify_order_url_pattern).to_return(
      status: 200,
      body: { 'order' => order_payload }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#perform' do
    let(:order_payload) do
      {
        'id' => 987_654,
        'name' => '#1001',
        'phone' => '+919876543210',
        'total_price' => '1299.00',
        'currency' => 'INR',
        'order_status_url' => "https://#{shop_domain}/orders/987654/status?key=abc",
        'customer' => {
          'first_name' => 'John',
          'last_name' => 'Doe',
          'phone' => '+919876543210'
        },
        'line_items' => [
          { 'title' => 'Handmade Soap' }
        ]
      }
    end

    context 'when orders/create arrives' do
      it 'creates an order notification with sent status and sends template' do
        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        notification = Shopify::OrderNotification.find_by(account_id: account.id, order_id: '987654', kind: 'confirmed')
        expect(notification).to be_present
        expect(notification.status).to eq('sent')
        expect(notification.sent_at).to be_present
      end

      it 'sends message for COD orders as well as prepaid' do
        order_payload['financial_status'] = 'pending'

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        expect(Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed').status).to eq('sent')
      end
    end

    context 'with dedup and duplicate webhooks' do
      it 'sends only once on duplicate orders/create webhook' do
        service = described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload)
        service.perform
        service.perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        expect(Shopify::OrderNotification.where(order_id: '987654', kind: 'confirmed').count).to eq(1)
      end
    end

    context 'with fulfillments/create' do
      let(:fulfillment_payload) do
        {
          'id' => 111,
          'order_id' => 987_654,
          'tracking_number' => 'TRACK123',
          'tracking_company' => 'BlueDart',
          'customer' => { 'first_name' => 'John', 'phone' => '+919876543210' },
          'phone' => '+919876543210'
        }
      end

      it 'sends shipped template and records sent' do
        described_class.new(account_id: account.id, topic: 'fulfillments/create', payload: fulfillment_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'shipped')
        expect(notification.status).to eq('sent')
      end
    end

    context 'with fulfillment_events/create' do
      let(:event_payload) do
        {
          'order_id' => 987_654,
          'fulfillment_id' => 111,
          'status' => 'delivered',
          'tracking_company' => 'BlueDart'
        }
      end

      it 'sends delivered template when status is delivered' do
        described_class.new(account_id: account.id, topic: 'fulfillment_events/create', payload: event_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'delivered')
        expect(notification.status).to eq('sent')
      end

      it 'sends out_for_delivery template when status is out_for_delivery' do
        event_payload['status'] = 'out_for_delivery'

        described_class.new(account_id: account.id, topic: 'fulfillment_events/create', payload: event_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'out_for_delivery')
        expect(notification.status).to eq('sent')
      end

      it 'ignores non-delivered and non-OFD statuses without creating any row' do
        event_payload['status'] = 'in_transit'

        described_class.new(account_id: account.id, topic: 'fulfillment_events/create', payload: event_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        expect(Shopify::OrderNotification.where(order_id: '987654')).to be_empty
      end
    end

    context 'with out-of-order delivery' do
      it 'never sends shipped or out_for_delivery after delivered is recorded' do
        Shopify::OrderNotification.create!(
          account_id: account.id,
          order_id: '987654',
          kind: 'delivered',
          status: 'sent'
        )

        fulfillment_payload = {
          'id' => 111,
          'order_id' => 987_654,
          'tracking_number' => 'TRACK123',
          'tracking_company' => 'BlueDart',
          'phone' => '+919876543210'
        }

        described_class.new(account_id: account.id, topic: 'fulfillments/create', payload: fulfillment_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        shipped_record = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'shipped')
        expect(shipped_record&.status).to be_in(['skipped', nil])
      end
    end

    context 'with test mode gate' do
      before do
        hook.settings['abandoned_cart']['test_phones'] = ['919999999999']
        hook.save!
      end

      it 'does not send and writes NO row when phone is not in test_phones' do
        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        expect(Shopify::OrderNotification.where(order_id: '987654')).to be_empty
      end

      it 'sends and writes row when phone matches test_phones' do
        hook.settings['abandoned_cart']['test_phones'] = [test_phone]
        hook.save!

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).to have_been_made.once
        expect(Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed').status).to eq('sent')
      end
    end

    context 'with missing phone when test mode is off' do
      it 'records skipped with reason missing_phone' do
        order_payload['phone'] = nil
        order_payload['customer']['phone'] = nil

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed')
        expect(notification.status).to eq('skipped')
        expect(notification.reason).to eq('missing_phone')
      end
    end

    context 'with opted-out or blocked contact' do
      it 'records skipped with reason contact_opted_out' do
        contact = create(:contact, account: account, phone_number: "+#{test_phone}")
        contact.update!(label_list: ['opted_out'])

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed')
        expect(notification.status).to eq('skipped')
        expect(notification.reason).to eq('contact_opted_out')
      end
    end

    context 'with URL host mismatch' do
      it 'records failed with reason url_host_mismatch' do
        order_payload['order_status_url'] = 'https://attacker.com/orders/987654'

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed')
        expect(notification.status).to eq('failed')
        expect(notification.reason).to eq('url_host_mismatch')
      end
    end

    context 'with milestone switched off' do
      it 'skips and writes NO row when milestone is disabled' do
        hook.settings['order_updates']['milestones']['confirmed']['enabled'] = false
        hook.save!

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        expect(Shopify::OrderNotification.where(order_id: '987654')).to be_empty
      end
    end

    context 'with empty parameter without fallback' do
      it 'records failed with reason empty_param:<slot>' do
        hook.settings['order_updates']['milestones']['confirmed']['template']['variables']['body.3'] = { 'static' => '' }
        hook.save!

        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expect(a_request(:post, meta_messages_url_pattern)).not_to have_been_made
        notification = Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed')
        expect(notification.status).to eq('failed')
        expect(notification.reason).to eq('empty_param:body.3')
      end
    end

    context 'with NAMED parameter templates' do
      before do
        named_template = {
          'name' => 'named_order_update',
          'language' => language,
          'status' => 'approved',
          'parameter_format' => 'NAMED',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hello {{customer_name}}, your order {{order_id}} is confirmed!' }
          ]
        }
        channel.update!(message_templates: default_message_templates + [named_template])
        hook.settings['order_updates']['milestones']['confirmed']['template'] = {
          'template_name' => 'named_order_update',
          'language' => language,
          'variables' => {
            'body.customer_name' => 'first_name',
            'body.order_id' => 'order_name'
          }
        }
        hook.save!
      end

      it 'correctly builds named parameters and sends template' do
        described_class.new(account_id: account.id, topic: 'orders/create', payload: order_payload).perform

        expected_req = a_request(:post, meta_messages_url_pattern).with do |req|
          parsed = JSON.parse(req.body)
          components = parsed.dig('template', 'components') || []
          body_comp = components.find { |c| c['type'] == 'body' }
          params = body_comp['parameters']
          cust_param = params.find { |p| p['parameter_name'] == 'customer_name' }
          order_param = params.find { |p| p['parameter_name'] == 'order_id' }
          cust_param['text'] == 'John' && order_param['text'] == '#1001'
        end
        expect(expected_req).to have_been_made.once

        expect(Shopify::OrderNotification.find_by(order_id: '987654', kind: 'confirmed').status).to eq('sent')
      end
    end
  end
end
