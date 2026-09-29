# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::AccessToken do
  let(:account) { create(:account) }
  let(:shop_domain) { 'test-store.myshopify.com' }
  let(:client_id) { 'shopify_test_client_id' }
  let(:client_secret) { 'shopify_test_client_secret' }

  before do
    allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_ID', nil).and_return(client_id)
    allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return(client_secret)
  end

  describe '.token_for' do
    context 'when hook has no refresh_token (legacy non-expiring token)' do
      let(:hook) do
        create(:integrations_hook, :shopify,
               account: account,
               access_token: 'shpat_legacy_token',
               reference_id: shop_domain,
               settings: { 'scope' => 'read_customers,read_orders' })
      end

      it 'returns stored access_token unchanged without making any HTTP request' do
        expect(described_class.token_for(hook)).to eq('shpat_legacy_token')
      end
    end

    context 'when hook has a refresh_token and expires_at is far in the future' do
      let(:hook) do
        create(:integrations_hook, :shopify,
               account: account,
               access_token: 'shpat_current_token',
               reference_id: shop_domain,
               settings: {
                 'scope' => 'read_customers,read_orders',
                 'refresh_token' => 'shprt_valid_refresh_token',
                 'expires_at' => 30.minutes.from_now.iso8601
               })
      end

      it 'returns stored access_token without refreshing' do
        expect(described_class.token_for(hook)).to eq('shpat_current_token')
      end
    end

    context 'when hook has a refresh_token and expires_at is within 5 minutes' do
      let(:hook) do
        create(:integrations_hook, :shopify,
               account: account,
               access_token: 'shpat_old_token',
               reference_id: shop_domain,
               settings: {
                 'scope' => 'read_customers,read_orders',
                 'refresh_token' => 'shprt_old_refresh_token',
                 'expires_at' => 4.minutes.from_now.iso8601
               })
      end
      let(:new_token_data) do
        {
          'access_token' => 'shpat_new_refreshed_token',
          'scope' => 'read_customers,read_orders',
          'expires_in' => 3600,
          'refresh_token' => 'shprt_new_refresh_token'
        }
      end

      before do
        stub_request(:post, "https://#{shop_domain}/admin/oauth/access_token")
          .with(
            body: {
              client_id: client_id,
              client_secret: client_secret,
              grant_type: 'refresh_token',
              refresh_token: 'shprt_old_refresh_token'
            }.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'Accept' => 'application/json'
            }
          ).to_return(
            status: 200,
            body: new_token_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'refreshes the token and saves new access_token, refresh_token, and expires_at' do
        freeze_time do
          token = described_class.token_for(hook)
          expect(token).to eq('shpat_new_refreshed_token')

          hook.reload
          expect(hook.access_token).to eq('shpat_new_refreshed_token')
          expect(hook.settings['refresh_token']).to eq('shprt_new_refresh_token')
          expect(hook.settings['expires_at']).to eq(3600.seconds.from_now.iso8601)
        end
      end
    end

    context 'when hook has an expired token' do
      let(:hook) do
        create(:integrations_hook, :shopify,
               account: account,
               access_token: 'shpat_expired_token',
               reference_id: shop_domain,
               settings: {
                 'refresh_token' => 'shprt_valid_refresh',
                 'expires_at' => 10.minutes.ago.iso8601
               })
      end

      before do
        stub_request(:post, "https://#{shop_domain}/admin/oauth/access_token")
          .to_return(
            status: 200,
            body: {
              'access_token' => 'shpat_renewed_token',
              'expires_in' => 3600,
              'refresh_token' => 'shprt_renewed_refresh'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'refreshes the token' do
        expect(described_class.token_for(hook)).to eq('shpat_renewed_token')
      end
    end

    context 'when refresh request fails' do
      let(:hook) do
        create(:integrations_hook, :shopify,
               account: account,
               access_token: 'shpat_expired_token',
               reference_id: shop_domain,
               settings: {
                 'refresh_token' => 'shprt_invalid_refresh',
                 'expires_at' => 5.minutes.ago.iso8601
               })
      end

      before do
        stub_request(:post, "https://#{shop_domain}/admin/oauth/access_token")
          .to_return(
            status: 400,
            body: { 'error' => 'invalid_grant', 'error_description' => 'The refresh token is invalid' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises CustomExceptions::Shopify::TokenRefreshError and does not update the hook' do
        expect do
          described_class.token_for(hook)
        end.to raise_error(CustomExceptions::Shopify::TokenRefreshError)

        expect(hook.reload.access_token).to eq('shpat_expired_token')
      end
    end
  end
end
