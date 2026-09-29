class UserAccountsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :destroy, with: -> { redirect_to user_account_path, alert: "Try again later." }

  def show
    @user = Current.user
    @amazon_connection = @user.amazon_connection
  end

  def destroy
    user = Current.user

    unless user.authenticate(params[:password].to_s)
      redirect_to user_account_path, alert: "Password didn't match. Your account was not deleted."
      return
    end

    terminate_session
    user.destroy_with_data!
    redirect_to new_session_path, notice: "Your account, Amazon connection, and imported data were deleted. Remember to remove the app in Seller Central → Manage Your Apps.", status: :see_other
  end
end
