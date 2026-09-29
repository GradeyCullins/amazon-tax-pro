class DashboardController < ApplicationController
  def index
    @year = rows.where.not(posted_on: nil).maximum("strftime('%Y', posted_on)")&.to_i || Date.current.year
    @latest_batch = Current.user.amazon_import_batches.order(imported_at: :desc).first
    @recent_batches = Current.user.amazon_import_batches.order(imported_at: :desc).limit(5)
    @year_totals = rows.accepted_tax_totals(@year)
    @pending_review_count = rows.pending.count
    @uncategorized_count = rows.pending.where(tax_category: "uncategorized").count
    @accepted_count = rows.accepted.for_year(@year).count
    @excluded_count = rows.for_year(@year).where(tax_category: AmazonImportRow::EXCLUDED_TAX_CATEGORIES).count
    @export_input = Current.user.turbo_tax_export_inputs.for_year(@year)
    @amazon_connection = Current.user.amazon_connection
    @latest_sync = Current.user.amazon_import_batches.source_sp_api.order(created_at: :desc).first
    @sync_year_options = AmazonTransactionsSync.selectable_tax_years
  end

  private

  def rows
    Current.user.amazon_import_rows
  end
end
