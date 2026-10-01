class UserAccountsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[destroy update_password], with: -> { redirect_to user_account_path, alert: "Try again later." }
  before_action :protect_sandbox_seller, only: %i[destroy update_password]

  def show
    @user = Current.user
    @amazon_connection = @user.amazon_connection
  end

  def update
    @user = Current.user

    if @user.update(profile_params)
      redirect_to user_account_path, notice: "Saved your profile."
    else
      @amazon_connection = @user.amazon_connection
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def update_password
    @user = Current.user
    change = params.require(:password_change).permit(:current_password, :password, :password_confirmation)

    unless @user.authenticate(change[:current_password].to_s)
      redirect_to user_account_path, alert: "Current password didn't match. Your password was not changed."
      return
    end

    if change[:password].blank?
      redirect_to user_account_path, alert: "Enter a new password."
    elsif change[:password_confirmation].blank? || change[:password] != change[:password_confirmation]
      redirect_to user_account_path, alert: "New password and confirmation must match."
    elsif @user.update(password: change[:password], password_confirmation: change[:password_confirmation])
      @user.sessions.where.not(id: Current.session.id).delete_all
      redirect_to user_account_path, notice: "Password updated. Other sessions were signed out."
    else
      redirect_to user_account_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def destroy
    user = Current.user

    unless user.authenticate(params[:password].to_s)
      redirect_to user_account_path, alert: "Password didn't match. Your account was not deleted."
      return
    end

    terminate_session
    user.destroy_with_data!
    redirect_to new_session_path, notice: "Your account, Amazon connection, and transaction data were deleted. Remember to remove the app in Seller Central → Manage Your Apps.", status: :see_other
  end

  private

  # The team shares this login, so its password and existence stay fixed.
  def protect_sandbox_seller
    redirect_to user_account_path, alert: "The sandbox seller's password can't be changed and the account can't be deleted." if SandboxSeller.user?(Current.user)
  end

  def profile_params
    params.require(:user).permit(:display_name, :business_name, :default_tax_year)
  end
end
