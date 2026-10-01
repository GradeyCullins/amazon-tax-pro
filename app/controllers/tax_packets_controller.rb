class TaxPacketsController < ApplicationController
  def show
    @year = current_tax_year
    @year_status = TaxYearStatus.new(Current.user, @year)
    @totals = @year_status.rows.accepted_tax_totals(@year)
    @pagination = Pagination.new(@year_status.rows.accepted.order(:posted_on, :source_row_number, :id), page: params[:page])
  end
end
