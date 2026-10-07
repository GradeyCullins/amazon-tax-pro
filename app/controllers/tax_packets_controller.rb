class TaxPacketsController < ApplicationController
  FIGURE_GROUPS = {
    "Sales and adjustments" => %w[gross_sales shipping_credits refunds_returns reimbursements],
    "Costs and expenses" => %w[amazon_fees fba_fees advertising shipping_charges cost_of_goods_sold other_business_expenses],
    "Other activity" => %w[marketplace_withheld_tax bank_transfers reserves_adjustments]
  }.freeze

  def show
    @year = current_tax_year
    @year_status = TaxYearStatus.new(Current.user, @year)
    @activity = AmazonYearActivity.new(user: Current.user, year: @year)
    @cogs_input = Current.user.turbo_tax_export_inputs.for_year(@year)
    @outside_expenses = Current.user.outside_expenses.active.for_year(@year).order(spent_on: :desc, id: :desc).to_a
    @outside_total_cents = @outside_expenses.sum(&:deductible_cents)
    @outside_by_category = @outside_expenses.group_by(&:category).transform_values { |entries| entries.sum(&:deductible_cents) }
    @category = params[:category] if AmazonImportRow::TAX_CATEGORIES.except("uncategorized").key?(params[:category])
    audit_rows = @activity.rows
    audit_rows = audit_rows.where(tax_category: @category) if @category
    @pagination = Pagination.new(audit_rows.includes(:amazon_import_batch).order(:posted_on, :source_row_number, :id), page: params[:page])
  end
end
