class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :amazon_connection, dependent: :destroy
  has_many :amazon_import_batches, dependent: :destroy
  has_many :amazon_import_rows, dependent: :delete_all
  has_many :turbo_tax_export_inputs, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :display_name, :business_name, with: ->(value) { value.strip.presence }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :display_name, :business_name, length: { maximum: 100 }, allow_blank: true
  validates :default_tax_year, numericality: { only_integer: true, greater_than_or_equal_to: 2000, less_than_or_equal_to: ->(_user) { Date.current.year + 1 } }, allow_nil: true
  validates :review_threshold_dollars, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000_000 }, allow_nil: true
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true

  def effective_tax_year
    default_tax_year ||
      amazon_import_batches.source_sp_api.where.not(tax_year: nil).order(created_at: :desc).pick(:tax_year) ||
      amazon_import_rows.where.not(posted_on: nil).maximum("strftime('%Y', posted_on)")&.to_i ||
      Date.current.year
  end

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
