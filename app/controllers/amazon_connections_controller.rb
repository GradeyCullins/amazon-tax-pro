# SP-API website authorization workflow:
#   new      -> redirect seller to Seller Central consent page
#   login    -> (Login URI) Amazon sends the signed-in seller here; bounce back to amazon_callback_uri
#   callback -> (Redirect URI) exchange spapi_oauth_code for a refresh token and store the connection
class AmazonConnectionsController < ApplicationController
  STATE_TTL = 15.minutes

  before_action :require_sp_api_configuration, only: %i[new login callback]
  before_action -> { response.headers["Referrer-Policy"] = "no-referrer" }, only: %i[login callback]

  def new
    if AmazonSpApi.sandbox?
      AmazonConnection.connect!(user: Current.user, selling_partner_id: "sandbox-user-#{Current.user.id}", refresh_token: "sandbox-credentials")
      return redirect_to root_path, notice: "Amazon sandbox connected. Sync a tax year to import mock transactions."
    end

    redirect_to AmazonSpApi.consent_url(state: issue_oauth_state, redirect_uri: callback_amazon_connection_url), allow_other_host: true
  end

  def login
    callback_uri = params[:amazon_callback_uri].to_s
    unless AmazonSpApi.trusted_amazon_callback?(callback_uri)
      return redirect_to root_path, alert: "Amazon sent an invalid authorization callback. Please try connecting again."
    end

    query = { redirect_uri: callback_amazon_connection_url, amazon_state: params[:amazon_state], state: current_oauth_state || issue_oauth_state }
    query[:version] = "beta" if AmazonSpApi.draft?
    separator = callback_uri.include?("?") ? "&" : "?"
    redirect_to "#{callback_uri}#{separator}#{query.to_query}", allow_other_host: true
  end

  def callback
    unless valid_oauth_state?(params[:state])
      return redirect_to root_path, alert: "Amazon authorization expired or didn't match this session. Please try connecting again."
    end
    if params[:spapi_oauth_code].blank? || params[:selling_partner_id].blank?
      return redirect_to root_path, alert: "Amazon did not complete the authorization. Please try again."
    end

    refresh_token = AmazonSpApi.exchange_authorization_code!(params[:spapi_oauth_code])
    AmazonConnection.connect!(user: Current.user, selling_partner_id: params[:selling_partner_id], refresh_token: refresh_token)
    redirect_to root_path, notice: "Amazon seller account connected. Choose a tax year and sync your transactions."
  rescue AmazonSpApi::Error => error
    redirect_to root_path, alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    message = error.record.errors.of_kind?(:selling_partner_id, :taken) ? "That Amazon seller account is already connected to another Amazon Tax Pro account." : error.record.errors.full_messages.to_sentence
    redirect_to root_path, alert: message
  end

  def destroy
    Current.user.amazon_connection&.destroy!
    redirect_to root_path, notice: "Amazon disconnected and its stored authorization deleted. To fully revoke access, also remove Amazon Tax Pro under Seller Central → Apps and Services → Manage Your Apps."
  end

  private

  def require_sp_api_configuration
    redirect_to root_path, alert: "Amazon connection isn't available yet: SP-API credentials are not configured." unless AmazonSpApi.configured?
  end

  def issue_oauth_state
    SecureRandom.urlsafe_base64(32).tap do |state|
      session[:amazon_oauth_state] = { "value" => state, "expires_at" => STATE_TTL.from_now.to_i }
    end
  end

  def current_oauth_state
    stored = session[:amazon_oauth_state]
    stored["value"] if stored.is_a?(Hash) && stored["expires_at"].to_i > Time.current.to_i
  end

  def valid_oauth_state?(state)
    expected = current_oauth_state
    session.delete(:amazon_oauth_state)
    expected.present? && state.present? && ActiveSupport::SecurityUtils.secure_compare(expected, state.to_s)
  end
end
