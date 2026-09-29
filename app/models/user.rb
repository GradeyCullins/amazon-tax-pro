class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :amazon_connection, dependent: :destroy
  has_many :amazon_import_batches, dependent: :destroy
  has_many :amazon_import_rows, dependent: :delete_all
  has_many :turbo_tax_export_inputs, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true

  def destroy_with_data!
    transaction do
      AmazonImportRow.where(user_id: id).delete_all
      AmazonImportBatch.where(user_id: id).delete_all
      TurboTaxExportInput.where(user_id: id).delete_all
      AmazonConnection.where(user_id: id).delete_all
      Session.where(user_id: id).delete_all
      destroy!
    end
  end
end
