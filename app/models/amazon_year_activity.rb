# A preliminary view of Amazon activity by the transaction's posted calendar year.
# Prefer API imports over uploads so overlapping files are not double counted.
class AmazonYearActivity
  def self.default_year_for(user)
    user.amazon_import_batches.source_sp_api.where.not(tax_year: nil).order(created_at: :desc).pick(:tax_year) ||
      user.amazon_import_rows.where.not(posted_on: nil).maximum("strftime('%Y', posted_on)")&.to_i || Date.current.year
  end

  EXPENSE_CATEGORIES = %w[
    refunds_returns amazon_fees fba_fees advertising
    marketplace_withheld_tax cost_of_goods_sold other_business_expenses
  ].freeze

  attr_reader :year, :source_label

  def initialize(user:, year:)
    @year = year.to_i
    year_rows = user.amazon_import_rows.for_year(year).joins(:amazon_import_batch)
    api_rows = year_rows.where(amazon_import_batches: { source: AmazonImportBatch.sources.fetch("sp_api") })
    real_rows = api_rows.where(amazon_import_batches: { sandbox_sample: false })
    sample_rows = api_rows.where(amazon_import_batches: { sandbox_sample: true })

    @rows, @source_label = if real_rows.exists?
      [real_rows, "Amazon API imports"]
    elsif sample_rows.exists?
      [sample_rows, "Amazon sandbox samples"]
    else
      [year_rows.where(amazon_import_batches: { source: AmazonImportBatch.sources.fetch("upload") }), "File uploads"]
    end
  end

  def rows
    @rows.where.not(status: :skipped)
  end

  def row_count
    rows.count
  end

  def pending_count
    rows.pending.count
  end

  def uncategorized_count
    rows.where(tax_category: "uncategorized").count
  end

  def totals
    @totals ||= rows.group(:tax_category).sum(:amount_cents)
  end

  def total_cents(category)
    amount = totals.fetch(category, 0)
    EXPENSE_CATEGORIES.include?(category) ? -amount : amount
  end

  def gross_receipts_cents
    totals.fetch("gross_sales", 0) + positive_shipping_cents
  end

  def revenue_cents
    gross_receipts_cents + totals.values_at("refunds_returns", "amazon_fees", "fba_fees", "advertising").compact.sum + negative_shipping_cents
  end

  private

  def positive_shipping_cents
    rows.where(tax_category: "shipping").where("amount_cents > 0").sum(:amount_cents)
  end

  def negative_shipping_cents
    rows.where(tax_category: "shipping").where("amount_cents < 0").sum(:amount_cents)
  end
end
