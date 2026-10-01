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
  validates :default_tax_year, inclusion: { in: ->(_user) { AmazonImportRow.tax_years }, message: "must be a year from 2000 through this year" }, allow_nil: true
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true

  # Years Amazon sync owns: sync runs that didn't fail empty, plus the years synced rows landed in
  # (sandbox sample rows keep Amazon's dates whatever year was requested).
  def synced_tax_years
    run_years = amazon_import_batches.source_sp_api.reject { |batch| batch.sync_failed? && batch.row_count.zero? }.map(&:tax_year)
    (run_years + amazon_import_rows.synced.years).compact.uniq.sort.reverse
  end

  # Sync wins: removes one year's uploaded rows (other years in the same upload stay) and deletes emptied uploads.
  def remove_uploaded_rows!(year)
    rows = amazon_import_rows.uploaded.for_year(year)
    batch_ids = rows.distinct.pluck(:amazon_import_batch_id)

    transaction do
      removed_count = AmazonImportRow.where(id: rows.select(:id)).delete_all
      amazon_import_batches.where(id: batch_ids).each do |batch|
        batch.amazon_import_rows.exists? ? batch.refresh_status! : batch.destroy!
      end
      removed_count
    end
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
