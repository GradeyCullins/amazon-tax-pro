class TaxPacketsController < ApplicationController
  def show
    @year = params.fetch(:year, Date.current.year).to_i
    @totals = AmazonImportRow.accepted_tax_totals(@year)
    @accepted_rows = AmazonImportRow.accepted.for_year(@year).order(:posted_on, :source_row_number)
    @uncategorized_count = AmazonImportRow.pending.where(tax_category: "uncategorized").count
  end
end
