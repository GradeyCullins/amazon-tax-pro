require "peddler"

# Thin wrapper around the peddler gem for the SP-API calls this app makes.
#
# Credentials (bin/rails credentials:edit):
#   amazon_sp_api:
#     application_id: amzn1.sp.solution.xxxx
#     lwa_client_id: amzn1.application-oa2-client.xxxx
#     lwa_client_secret: xxxx
#     draft: true   # appends version=beta to the consent URL while the app is unpublished
module AmazonSpApi
  class Error < StandardError; end
  class NotConfigured < Error; end
  class AuthorizationRevoked < Error; end

  SELLER_CENTRAL_URL = "https://sellercentral.amazon.com".freeze
  AWS_REGIONS = { "na" => "us-east-1" }.freeze

  module_function

  def config
    Rails.application.credentials.amazon_sp_api || {}
  end

  def configured?
    config[:application_id].present? && config[:lwa_client_id].present? && config[:lwa_client_secret].present?
  end

  def draft?
    ActiveModel::Type::Boolean.new.cast(config[:draft])
  end

  def consent_url(state:, redirect_uri:)
    ensure_configured!

    params = { application_id: config[:application_id], state: state, redirect_uri: redirect_uri }
    params[:version] = "beta" if draft?
    "#{SELLER_CENTRAL_URL}/apps/authorize/consent?#{params.to_query}"
  end

  # Only Amazon-hosted callback URLs may be used as the amazon_callback_uri redirect target.
  def trusted_amazon_callback?(url)
    uri = URI.parse(url.to_s)
    uri.scheme == "https" && uri.host.to_s.match?(/\A([a-z0-9-]+\.)*amazon\.com\z/)
  rescue URI::InvalidURIError
    false
  end

  def exchange_authorization_code!(code)
    ensure_configured!

    token = Peddler::LWA.request(client_id: config[:lwa_client_id], client_secret: config[:lwa_client_secret], code: code).parse
    raise Error, "Amazon did not return a refresh token." if token.refresh_token.blank?

    token.refresh_token
  rescue Peddler::Error => error
    raise Error, "Amazon authorization failed: #{error.message}"
  end

  def access_token_for(connection)
    ensure_configured!

    Peddler::LWA.request(
      client_id: config[:lwa_client_id],
      client_secret: config[:lwa_client_secret],
      refresh_token: connection.refresh_token
    ).parse.access_token
  rescue Peddler::Errors::InvalidGrant, Peddler::Errors::Unauthorized => error
    raise AuthorizationRevoked, "Amazon authorization is no longer valid (#{error.message}). Reconnect your Amazon account."
  end

  def finances_client(connection, access_token:)
    Peddler::APIs::Finances20240619.new(AWS_REGIONS.fetch(connection.region), access_token, retries: 5)
  end

  def ensure_configured!
    raise NotConfigured, "Amazon SP-API credentials are not configured." unless configured?
  end
end
