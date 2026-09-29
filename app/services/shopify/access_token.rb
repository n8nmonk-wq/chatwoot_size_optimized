# frozen_string_literal: true

class Shopify::AccessToken
  include Shopify::IntegrationHelper

  REFRESH_BUFFER = 5.minutes

  def self.token_for(hook)
    new(hook).token
  end

  def initialize(hook)
    @hook = hook
  end

  def token
    return @hook.access_token unless refreshable? && token_expiring?

    if @hook.persisted?
      @hook.with_lock do
        @hook.reload
        @expires_at = nil
        return @hook.access_token unless refreshable? && token_expiring?

        perform_refresh!
      end
    else
      perform_refresh!
    end
  end

  private

  def refreshable?
    @hook.settings&.dig('refresh_token').present?
  end

  def token_expiring?
    return false if expires_at.blank?

    expires_at <= REFRESH_BUFFER.from_now
  end

  def expires_at
    @expires_at ||= begin
      raw = @hook.settings&.dig('expires_at')
      Time.zone.parse(raw.to_s) if raw.present?
    rescue ArgumentError
      nil
    end
  end

  def perform_refresh!
    ensure_client_credentials!

    response = fetch_refreshed_tokens
    unless response.success?
      Rails.logger.error("Shopify token refresh failed for hook #{@hook.id}: #{response.code}")
      raise CustomExceptions::Shopify::TokenRefreshError, "Shopify token refresh failed: #{response.code} #{response.body}"
    end

    update_hook_tokens(response.parsed_response)
  end

  def fetch_refreshed_tokens
    HTTParty.post(
      "https://#{@hook.reference_id}/admin/oauth/access_token",
      headers: {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      },
      body: {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: 'refresh_token',
        refresh_token: @hook.settings['refresh_token']
      }.to_json
    )
  end

  def ensure_client_credentials!
    return if client_id.present? && client_secret.present?

    raise CustomExceptions::Shopify::TokenRefreshError, 'Shopify client credentials missing'
  end

  def update_hook_tokens(data)
    new_settings = (@hook.settings || {}).dup
    new_settings['refresh_token'] = data['refresh_token'] if data['refresh_token'].present?
    new_settings['expires_at'] = data['expires_in'].to_i.seconds.from_now.iso8601 if data['expires_in'].present?
    new_settings['scope'] = data['scope'] if data['scope'].present?

    @hook.update!(
      access_token: data['access_token'],
      settings: new_settings
    )

    @hook.access_token
  end
end
