# One Review page per tax year, across every sync and upload. Defaults to the rows we couldn't categorize.
class ReviewsController < ApplicationController
  STATUS_FILTERS = AmazonImportRow::REVIEW_STATUSES.merge("all" => "All rows").freeze
  DEFAULT_STATUS = "needs_review".freeze

  helper_method :review_filter_path

  def show
    @year_status = TaxYearStatus.new(Current.user, current_tax_year)
    @status = STATUS_FILTERS.key?(params[:status]) ? params[:status] : DEFAULT_STATUS
    @category = params[:category] if AmazonImportRow::TAX_CATEGORIES.key?(params[:category])
    @import = Current.user.amazon_import_batches.find_by(id: params[:import_id]) if params[:import_id].present?

    rows = @year_status.rows
    rows = rows.where(tax_category: @category) if @category
    rows = rows.where(amazon_import_batch: @import) if @import
    @counts = rows.review_counts.merge("all" => rows.count)

    rows = rows.public_send(@status) unless @status == "all"
    @pagination = Pagination.new(rows.includes(:amazon_import_batch).order(:posted_on, :id), page: params[:page])
    @connection = Current.user.amazon_connection
  end

  private

  # Filter links carry the year so a second browser tab on another year can't switch this one.
  def review_filter_path(**overrides)
    query = { year: current_tax_year, status: @status, category: @category, import_id: @import&.id }.merge(overrides)
    query[:status] = nil if query[:status] == DEFAULT_STATUS
    review_path(query.compact)
  end
end
