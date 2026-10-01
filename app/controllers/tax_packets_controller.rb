class TaxPacketsController < ApplicationController
  def show
    @year = params[:year].presence&.to_i || Current.user.effective_tax_year
    @totals = Current.user.amazon_import_rows.accepted_tax_totals(@year)
    @accepted_rows = Current.user.amazon_import_rows.accepted.for_year(@year).order(:posted_on, :source_row_number)
    @uncategorized_count = Current.user.amazon_import_rows.pending.where(tax_category: "uncategorized").count
  end
end
