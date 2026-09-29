# frozen_string_literal: true

class Shopify::CallbacksController < ApplicationController
  include Shopify::IntegrationHelper

  def show
    verify_account!

    @response = oauth_client.auth_code.get_token(
      params[:code],
      redirect_uri: '/shopify/callback',
      expiring: 1
    )

    handle_response
  rescue StandardError => e
    Rails.logger.error("Shopify callback error: #{e.message}")
    redirect_to "#{redirect_uri}?error=true"
  end

  private

  def verify_account!
    @account_id = verify_shopify_token(params[:state])
    raise StandardError, 'Invalid state parameter' if account.blank?
  end

  def handle_response
    hook = account.hooks.find_or_initialize_by(app_id: 'shopify')
    hook.assign_attributes(
      access_token: parsed_body['access_token'],
      status: 'enabled',
      reference_id: params[:shop],
      settings: build_settings(hook)
    )
    hook.save!
    register_webhooks(hook)

    redirect_to shopify_integration_url
  end

  def register_webhooks(hook)
    Shopify::WebhookRegistrationService.perform(hook)
  rescue StandardError => e
    Rails.logger.error("Failed to register Shopify webhooks on connect: #{e.message}")
  end

  def build_settings(hook)
    settings = (hook.settings || {}).merge('scope' => parsed_body['scope'])
    settings['refresh_token'] = parsed_body['refresh_token'] if parsed_body['refresh_token'].present?
    settings['expires_at'] = token_expires_at if token_expires_at.present?
    settings
  end

  def token_expires_at
    if parsed_body['expires_in'].present?
      parsed_body['expires_in'].to_i.seconds.from_now.iso8601
    else
      parsed_body['expires_at']
    end
  end

  def parsed_body
    @parsed_body ||= @response.response.parsed
  end

  def oauth_client
    OAuth2::Client.new(
      client_id,
      client_secret,
      {
        site: "https://#{params[:shop]}",
        authorize_url: '/admin/oauth/authorize',
        token_url: '/admin/oauth/access_token'
      }
    )
  end

  def account
    @account ||= Account.find(@account_id)
  end

  def account_id
    @account_id ||= params[:state].split('_').first
  end

  def shopify_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account.id}/settings/integrations/shopify"
  end

  def redirect_uri
    return shopify_integration_url if account

    ENV.fetch('FRONTEND_URL', nil)
  end
end
