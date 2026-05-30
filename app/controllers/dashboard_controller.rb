class DashboardController < ApplicationController
  def index
    @year = AmazonImportRow.where.not(posted_on: nil).maximum("strftime('%Y', posted_on)")&.to_i || Date.current.year
    @latest_batch = AmazonImportBatch.order(imported_at: :desc).first
    @recent_batches = AmazonImportBatch.order(imported_at: :desc).limit(5)
    @year_totals = AmazonImportRow.accepted_tax_totals(@year)
    @pending_review_count = AmazonImportRow.pending.count
    @uncategorized_count = AmazonImportRow.pending.where(tax_category: "uncategorized").count
    @accepted_count = AmazonImportRow.accepted.for_year(@year).count
    @excluded_count = AmazonImportRow.for_year(@year).where(tax_category: AmazonImportRow::EXCLUDED_TAX_CATEGORIES).count
    @export_input = TurboTaxExportInput.for_year(@year)
  end
end
