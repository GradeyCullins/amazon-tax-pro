class DashboardController < ApplicationController
  def index
    @connection = Current.user.amazon_connection
    @active_sync = @connection&.active_sync_batch
    @year_status = TaxYearStatus.new(Current.user, current_tax_year)
    @years_with_rows = Current.user.amazon_import_rows.years
    @has_rows = @years_with_rows.any? || Current.user.amazon_import_rows.exists?
    @recent_batches = Current.user.amazon_import_batches.order(created_at: :desc).limit(5)
    @export_input = Current.user.turbo_tax_export_inputs.for_year(current_tax_year)
    outside_entries = Current.user.outside_expenses.active.for_year(current_tax_year).to_a
    @outside_expense_count = outside_entries.size
    @outside_expense_total_cents = outside_entries.sum(&:deductible_cents)

    return unless @year_status.rows?

    @activity = AmazonYearActivity.new(user: Current.user, year: current_tax_year)
    @excluded_count = @year_status.rows.accepted.where(tax_category: AmazonImportRow::EXCLUDED_TAX_CATEGORIES).count
  end
end
