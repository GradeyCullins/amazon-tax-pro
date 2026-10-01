class DashboardController < ApplicationController
  def index
    @connection = Current.user.amazon_connection
    @active_sync = @connection&.active_sync_batch
    @year_status = TaxYearStatus.new(Current.user, current_tax_year)
    @years_with_rows = Current.user.amazon_import_rows.years
    @has_rows = @years_with_rows.any? || Current.user.amazon_import_rows.exists?
    @recent_batches = Current.user.amazon_import_batches.order(created_at: :desc).limit(5)
    @export_input = Current.user.turbo_tax_export_inputs.for_year(current_tax_year)

    return unless @year_status.rows?

    @activity = AmazonYearActivity.new(user: Current.user, year: current_tax_year)
    @excluded_count = @year_status.rows.accepted.where(tax_category: AmazonImportRow::EXCLUDED_TAX_CATEGORIES).count
  end
end
