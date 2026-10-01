# One Review page per tax year, across every sync and upload. Defaults to the rows we couldn't categorize.
class ReviewsController < ApplicationController
  STATUS_FILTERS = AmazonImportRow::REVIEW_STATUSES.merge("all" => "All rows").freeze
  DEFAULT_STATUS = "needs_review".freeze
  SORTS = { "oldest" => "Oldest first", "newest" => "Newest first", "largest" => "Largest amount first" }.freeze
  DEFAULT_SORT = "oldest".freeze
  SEARCH_COLUMNS = %w[description order_id transaction_type amount_type amount_description].freeze

  helper_method :review_filter_path, :filters_active?

  def show
    @year_status = TaxYearStatus.new(Current.user, current_tax_year)
    @status = STATUS_FILTERS.key?(params[:status]) ? params[:status] : DEFAULT_STATUS
    @category = params[:category] if AmazonImportRow::TAX_CATEGORIES.key?(params[:category])
    @import = Current.user.amazon_import_batches.find_by(id: params[:import_id]) if params[:import_id].present?
    @query = params[:q].to_s.strip.first(100).presence
    @min_amount = params[:min_amount].to_s.strip.first(20).presence
    @max_amount = params[:max_amount].to_s.strip.first(20).presence
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
    min_cents = amount_cents(@min_amount)
    max_cents = amount_cents(@max_amount)
    @amount_error = if (@min_amount && min_cents.nil?) || (@max_amount && max_cents.nil?)
      "Enter amounts of $0 or more, with at most two decimal places."
    elsif min_cents && max_cents && min_cents > max_cents
      "The minimum amount can't be more than the maximum."
    end

    rows = @year_status.rows
    rows = rows.where(tax_category: @category) if @category
    rows = rows.where(amazon_import_batch: @import) if @import
    rows = search(rows, @query) if @query
    rows = rows.where("ABS(amazon_import_rows.amount_cents) >= ?", min_cents) if min_cents
    rows = rows.where("ABS(amazon_import_rows.amount_cents) <= ?", max_cents) if max_cents
    rows = rows.none if @amount_error
    @counts = rows.review_counts.merge("all" => rows.count)

    rows = rows.public_send(@status) unless @status == "all"
    @pagination = Pagination.new(rows.includes(:amazon_import_batch).order(order_clause), page: params[:page])
    @connection = Current.user.amazon_connection
  end

  private

  # Filter links carry the year so a second browser tab on another year can't switch this one.
  def review_filter_path(**overrides)
    query = {
      year: current_tax_year, status: @status, category: @category, import_id: @import&.id,
      q: @query, min_amount: @min_amount, max_amount: @max_amount, sort: @sort
    }.merge(overrides)
    query[:status] = nil if query[:status] == DEFAULT_STATUS
    query[:sort] = nil if query[:sort] == DEFAULT_SORT
    review_path(query.compact)
  end

  def filters_active?
    [@category, @import, @query, @min_amount, @max_amount].any?
  end

  def search(rows, query)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    conditions = SEARCH_COLUMNS.map { |column| "amazon_import_rows.#{column} LIKE :pattern" }
    conditions << "amazon_import_rows.source_row_number = :number" if query.match?(/\A\d{1,9}\z/)
    rows.where(conditions.join(" OR "), pattern: pattern, number: query.to_i)
  end

  def order_clause
    case @sort
    when "newest" then Arel.sql("amazon_import_rows.posted_on DESC, amazon_import_rows.id DESC")
    when "largest" then Arel.sql("ABS(amazon_import_rows.amount_cents) DESC, amazon_import_rows.posted_on, amazon_import_rows.id")
    else Arel.sql("amazon_import_rows.posted_on, amazon_import_rows.id")
    end
  end

  # Matches on size, so $500 finds both a $500 sale and a -$500 fee.
  def amount_cents(value)
    return unless value&.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)

    dollars, cents = value.split(".")
    dollars.to_i * 100 + cents.to_s.ljust(2, "0").to_i
  end
end
