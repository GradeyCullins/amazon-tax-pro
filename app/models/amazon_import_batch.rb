class AmazonImportBatch < ApplicationRecord
  SYNC_STATUS_LABELS = { "queued" => "Queued", "running" => "Syncing", "succeeded" => "Finished", "failed" => "Failed" }.freeze

  belongs_to :user
  belongs_to :amazon_connection, optional: true
  has_many :amazon_import_rows, dependent: :destroy

  enum :status, { imported: 0, reviewed: 1 }
  enum :source, { upload: 0, sp_api: 1 }, prefix: true
  enum :sync_status, { queued: 0, running: 1, succeeded: 2, failed: 3 }, prefix: :sync

  validates :filename, :imported_at, presence: true
  validates :tax_year, presence: true, if: :source_sp_api?

  def self.start_sp_api_sync!(connection:, tax_year:)
    batch = connection.user.amazon_import_batches.create!(
      amazon_connection: connection,
      source: :sp_api,
      sync_status: :queued,
      sandbox_sample: AmazonSpApi.sandbox? || SandboxSeller.connection?(connection),
      tax_year: tax_year,
      filename: "Amazon sync · #{tax_year}",
      imported_at: Time.current
    )
    AmazonTransactionsSyncJob.perform_later(batch)
    batch
  end

  def sync_active?
    sync_queued? || sync_running?
  end

  # Older sync runs were stored as "Amazon SP-API sync — YEAR"; derive the name instead of trusting filename.
  def display_name
    source_sp_api? ? "Amazon sync · #{tax_year}" : filename
  end

  def source_label
    source_sp_api? ? "Amazon sync" : "Upload"
  end

  def sync_status_label
    SYNC_STATUS_LABELS.fetch(sync_status.to_s, "Uploaded")
  end

  # Batches don't need a separate sign-off: they're ready once no row is waiting for a category.
  def status_label
    imported? ? "Needs review" : "Ready"
  end

  def refresh_status!
    update!(
      row_count: amazon_import_rows.count,
      status: amazon_import_rows.pending.exists? ? :imported : :reviewed
    )
  end
end
