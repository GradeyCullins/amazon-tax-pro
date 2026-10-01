# One tax year shared by every page. Any request with ?year= switches it; the choice is kept in the session.
module TaxYearContext
  extend ActiveSupport::Concern

  included do
    helper_method :current_tax_year, :tax_year_options
  end

  private

  def current_tax_year
    @current_tax_year ||= begin
      requested = valid_tax_year(params[:year])
      remember_tax_year(requested) if requested
      requested || valid_tax_year(session[:tax_year]) || default_tax_year
    end
  end

  def tax_year_options
    @tax_year_options ||= (AmazonTransactionsSync.selectable_tax_years + years_with_rows + [current_tax_year]).uniq.sort.reverse
  end

  def remember_tax_year(year)
    session[:tax_year] = year
  end

  def valid_tax_year(value)
    year = Integer(value.to_s, 10, exception: false)
    year if AmazonImportRow.tax_years.cover?(year)
  end

  # Tax season default: last year when it has data, else the latest year with data, else last year.
  def default_tax_year
    last_completed_year = Date.current.year - 1
    years_with_rows.include?(last_completed_year) ? last_completed_year : years_with_rows.first || last_completed_year
  end

  def years_with_rows
    @years_with_rows ||= Current.user ? Current.user.amazon_import_rows.years : []
  end
end
