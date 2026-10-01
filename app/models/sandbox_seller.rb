# A shared development account in every environment. Sign in with EMAIL / PASSWORD; the account is created on its
# first sign-in, comes pre-connected to Amazon, and its syncs read SandboxSeller::FinancesClient's generated
# transactions instead of calling SP-API. The data is fake, so the credentials are not secret.
module SandboxSeller
  EMAIL = "sandbox@amazontaxpro.com".freeze
  PASSWORD = "sandbox-seller-2026".freeze
  DISPLAY_NAME = "Sandbox Seller".freeze
  BUSINESS_NAME = "Summit Trail Goods LLC".freeze
  SELLING_PARTNER_ID = "A3SBX7TRAILGDS".freeze
  REFRESH_TOKEN = "sandbox-seller-no-amazon-token".freeze

  module_function

  def email?(email_address)
    email_address.to_s.strip.downcase == EMAIL
  end

  def user?(user)
    user.present? && email?(user.email_address)
  end

  def connection?(connection)
    connection.present? && user?(connection.user)
  end

  def user
    User.find_by(email_address: EMAIL)
  end

  # Creates the account (or restores its known password) so the shared login always works.
  def ensure_user!
    user = User.find_or_initialize_by(email_address: EMAIL)
    if user.new_record?
      user.display_name = DISPLAY_NAME
      user.business_name = BUSINESS_NAME
    end
    user.password = PASSWORD unless user.persisted? && user.authenticate(PASSWORD)
    user.save! if user.changed?
    connect!(user) unless user.amazon_connection
    user
  end

  def connect!(user)
    AmazonConnection.connect!(user: user, selling_partner_id: SELLING_PARTNER_ID, refresh_token: REFRESH_TOKEN)
  end

  # Deletes every synced/uploaded row and export input but keeps the account and its connection.
  def reset!
    user = ensure_user!
    user.transaction do
      AmazonImportRow.where(user_id: user.id).delete_all
      AmazonImportBatch.where(user_id: user.id).delete_all
      TurboTaxExportInput.where(user_id: user.id).delete_all
      user.amazon_connection.update!(status: :active, last_error: nil, last_synced_at: nil)
    end
    user
  end
end
