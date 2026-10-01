class TaxPacketsController < ApplicationController
  def show
    @year = current_tax_year
    @year_status = TaxYearStatus.new(Current.user, @year)
    @activity = AmazonYearActivity.new(user: Current.user, year: @year)
    @cogs_input = Current.user.turbo_tax_export_inputs.for_year(@year)
    @pagination = Pagination.new(@activity.rows.order(:posted_on, :source_row_number, :id), page: params[:page])
  end
end
