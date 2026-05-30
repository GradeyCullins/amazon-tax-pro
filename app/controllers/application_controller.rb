class ApplicationController < ActionController::Base
  before_action :require_basic_authentication, if: :production?

  private

  def require_basic_authentication
    authenticate_or_request_with_http_basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(username),
        ::Digest::SHA256.hexdigest(Rails.application.credentials.admin_user.to_s)
      ) & ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(password),
        ::Digest::SHA256.hexdigest(Rails.application.credentials.admin_pass.to_s)
      )
    end
  end

  def production?
    Rails.env.production?
  end
end
