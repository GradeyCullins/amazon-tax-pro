class AmazonImportBatchesController < ApplicationController
  def index
    @batches = Current.user.amazon_import_batches.order(imported_at: :desc)
  end

  def new
  end

  def create
    result = AmazonSettlementImporter.import!(params[:file], user: Current.user)

    if result.errors.any?
      redirect_to new_amazon_import_batch_path, alert: result.errors.to_sentence
    else
      redirect_to amazon_import_batch_path(result.batch), notice: "Imported #{result.batch.row_count} Amazon settlement rows."
    end
  end

  def show
    @batch = Current.user.amazon_import_batches.find(params[:id])
    @status_counts = @batch.amazon_import_rows.group(:status).count
    @query = params[:q].to_s.strip.first(100)
    @category = params[:category] if AmazonImportRow::TAX_CATEGORIES.key?(params[:category])
    @review_status = params[:status] if AmazonImportRow.statuses.key?(params[:status])
    @min_amount = params[:min_amount].to_s.strip.first(20)
    @max_amount = params[:max_amount].to_s.strip.first(20)
    @sort = params[:sort] == "oldest" ? "oldest" : "newest"
    min_cents = amount_cents(@min_amount)
    max_cents = amount_cents(@max_amount)
    @amount_error = if (@min_amount.present? && min_cents.nil?) || (@max_amount.present? && max_cents.nil?)
      "Enter amounts of $0 or more, using at most two decimal places."
    elsif min_cents && max_cents && min_cents > max_cents
      "Minimum amount must be less than or equal to maximum amount."
    end
    @filters_active = @query.present? || @category.present? || @review_status.present? || @min_amount.present? || @max_amount.present? || @sort == "oldest"
    @view_all = params[:view] == "all" || @filters_active
    @open_group = params[:open_group].to_s.first(120)

    if @view_all
      rows = @batch.amazon_import_rows
      if @query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        rows = rows.where("description LIKE :query OR order_id LIKE :query OR transaction_type LIKE :query OR amount_description LIKE :query", query: pattern)
        rows = rows.or(@batch.amazon_import_rows.where(source_row_number: @query.to_i)) if @query.match?(/\A\d+\z/)
      end
      rows = rows.where(tax_category: @category) if @category
      rows = rows.where(status: @review_status) if @review_status
      rows = rows.where("ABS(amount_cents) >= ?", min_cents) if min_cents
      rows = rows.where("ABS(amount_cents) <= ?", max_cents) if max_cents
      rows = rows.none if @amount_error
      @result_count = rows.count
      @group_count = rows.distinct.count(Arel.sql(AmazonImportRow::REVIEW_GROUP_SQL))
      @page = [[params[:page].to_i, 1].max, [(@group_count / 20.0).ceil, 1].max].min
      group_order = if @sort == "oldest"
        "MIN(posted_on) IS NULL, MIN(posted_on) ASC, MIN(id) ASC"
      else
        "MAX(posted_on) IS NULL, MAX(posted_on) DESC, MAX(id) DESC"
      end
      row_order = @sort == "oldest" ? "posted_on IS NULL, posted_on ASC, id ASC" : "posted_on IS NULL, posted_on DESC, id DESC"
      keys = rows.group(Arel.sql(AmazonImportRow::REVIEW_GROUP_SQL))
        .order(Arel.sql(group_order))
        .limit(20).offset((@page - 1) * 20)
        .pluck(Arel.sql(AmazonImportRow::REVIEW_GROUP_SQL))
      grouped = rows.where("#{AmazonImportRow::REVIEW_GROUP_SQL} IN (?)", keys)
        .order(Arel.sql(row_order)).to_a.group_by(&:review_group_key)
      @groups = keys.map { |key| [key, grouped.fetch(key, [])] }
    else
      pending = @batch.amazon_import_rows.pending
      priority_sets = [
        ["Needs a category", pending.where(tax_category: "uncategorized").order(Arel.sql("ABS(amount_cents) DESC, id ASC")).limit(2)],
        ["Large refund", pending.where(tax_category: "refunds_returns").where("amount_cents < 0").order(Arel.sql("ABS(amount_cents) DESC, id ASC")).limit(2)],
        ["Large fee", %w[advertising fba_fees].filter_map do |category|
          pending.where(tax_category: category).where("amount_cents < 0").order(Arel.sql("ABS(amount_cents) DESC, id ASC")).first
        end],
        ["Adjustment", pending.where(tax_category: "reserves_adjustments").order(Arel.sql("ABS(amount_cents) DESC, id ASC")).limit(1)],
        ["Reimbursement", pending.where(tax_category: "reimbursements").order(Arel.sql("ABS(amount_cents) DESC, id ASC")).limit(1)]
      ]
      @featured_reasons = {}
      featured = priority_sets.flat_map do |reason, candidates|
        candidates.map { |row| [row, reason] }
      end.filter_map do |row, reason|
        next if @featured_reasons.key?(row.review_group_key)

        @featured_reasons[row.review_group_key] = reason
        row
      end.first(8)
      keys = featured.map(&:review_group_key)
      order_ids = featured.filter_map { |row| row.order_id&.strip.presence }.uniq
      rows = featured + @batch.amazon_import_rows.where("TRIM(order_id) IN (?)", order_ids).to_a
      grouped = rows.uniq(&:id).sort_by { |row| [row.source_row_number, row.id] }.group_by(&:review_group_key)
      @groups = keys.map { |key| [key, grouped.fetch(key, [])] }
    end
  end

  private

  def amount_cents(value)
    return if value.blank?
    return unless value.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/)

    dollars, cents = value.split(".")
    dollars.to_i * 100 + cents.to_s.ljust(2, "0").to_i
  end
end
