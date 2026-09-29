class SiteGatesController < ApplicationController
  skip_site_gate
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_site_gate_path, alert: "Too many attempts. Try again in a few minutes." }

  layout "gate"

  def new
    redirect_to root_path if !self.class.site_gate_enabled? || site_gate_unlocked?
  end

  def create
    password = self.class.site_password

    if password.present? && ActiveSupport::SecurityUtils.secure_compare(params[:password].to_s, password)
      unlock_site_gate!
      redirect_to session.delete(:site_gate_return_to).presence || root_path
    else
      redirect_to new_site_gate_path, alert: password.blank? ? "The site password has not been configured yet." : "That password didn't work."
    end
  end
end
