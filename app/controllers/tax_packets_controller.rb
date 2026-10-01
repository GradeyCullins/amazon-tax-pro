class TaxPacketsController < ApplicationController
  def show
    posted_years = Current.user.amazon_import_rows.where.not(posted_on: nil).distinct.pluck(Arel.sql("strftime('%Y', posted_on)"))
    @year_options = (posted_years.map(&:to_i) + Current.user.amazon_import_batches.source_sp_api.where.not(tax_year: nil).distinct.pluck(:tax_year) + AmazonTransactionsSync.selectable_tax_years).uniq.sort.reverse
    requested_year = params[:year].presence&.to_i
    @year = requested_year && requested_year.between?(2000, Date.current.year + 1) ? requested_year : AmazonYearActivity.default_year_for(Current.user)
    @activity = AmazonYearActivity.new(user: Current.user, year: @year)
    @cogs_input = Current.user.turbo_tax_export_inputs.for_year(@year)
    @latest_year_sync = Current.user.amazon_import_batches.source_sp_api.where(tax_year: @year).order(created_at: :desc).first
    @accepted_rows = @activity.rows.accepted.order(:posted_on, :source_row_number)
  end
end
