class TaxPacketsController < ApplicationController
  def show
    @year = params.fetch(:year, Date.current.year).to_i
    @totals = Current.user.amazon_import_rows.accepted_tax_totals(@year)
    @accepted_rows = Current.user.amazon_import_rows.accepted.for_year(@year).order(:posted_on, :source_row_number)
    @uncategorized_count = Current.user.amazon_import_rows.pending.where(tax_category: "uncategorized").count
  end
end
