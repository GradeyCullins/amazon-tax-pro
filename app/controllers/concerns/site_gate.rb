# Shared-password gate in front of the whole site. The unlock cookie stores an HMAC of the current
# site password, so changing `site_password` in credentials locks everyone out again.
module SiteGate
  extend ActiveSupport::Concern

  COOKIE_NAME = :site_gate
  UNLOCK_DURATION = 30.days

  included do
    prepend_before_action :require_site_gate
  end

  class_methods do
    def skip_site_gate(**options)
      skip_before_action :require_site_gate, **options
    end

    def site_gate_enabled?
      Rails.env.production? || ActiveModel::Type::Boolean.new.cast(ENV["SITE_GATE"])
    end

    def site_password
      Rails.application.credentials.site_password.to_s
    end

    def site_gate_token
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "site-gate:#{site_password}")
    end
  end

  private

  def require_site_gate
    return unless self.class.site_gate_enabled?
    return if site_gate_unlocked?

    session[:site_gate_return_to] = request.fullpath if request.get?
    redirect_to new_site_gate_path
  end

  def site_gate_unlocked?
    return false if self.class.site_password.blank?

    token = cookies.signed[COOKIE_NAME].to_s
    token.present? && ActiveSupport::SecurityUtils.secure_compare(token, self.class.site_gate_token)
  end

  def unlock_site_gate!
    cookies.signed[COOKIE_NAME] = {
      value: self.class.site_gate_token,
      expires: UNLOCK_DURATION.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end
end
