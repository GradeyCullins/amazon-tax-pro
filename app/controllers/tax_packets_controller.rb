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
    @category = params[:category] if AmazonImportRow::TAX_CATEGORIES.except("uncategorized").key?(params[:category])
    audit_rows = @activity.rows
    audit_rows = audit_rows.where(tax_category: @category) if @category
    @pagination = Pagination.new(audit_rows.includes(:amazon_import_batch).order(:posted_on, :source_row_number, :id), page: params[:page])
  end
end
