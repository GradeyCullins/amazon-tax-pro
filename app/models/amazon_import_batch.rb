class AmazonImportBatch < ApplicationRecord
  has_many :amazon_import_rows, dependent: :destroy

  enum :status, { imported: 0, reviewed: 1 }

  validates :filename, :imported_at, presence: true

  def refresh_status!
    update!(
      row_count: amazon_import_rows.count,
      status: amazon_import_rows.pending.exists? ? :imported : :reviewed
    )
  end
end
