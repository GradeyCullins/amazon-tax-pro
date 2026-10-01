# Signed totals for one tax year, from the rows that count (accepted). Shared by the dashboard, tax packet, and
# TurboTax export so every page shows the same numbers. Credits net against their category: a refunded fee
# lowers fees, and a reversed refund lowers refunds.
class AmazonYearActivity
  # Shown as positive amounts; Amazon reports them as negative.
  EXPENSE_CATEGORIES = %w[
    refunds_returns amazon_fees fba_fees advertising
    marketplace_withheld_tax cost_of_goods_sold other_business_expenses
  ].freeze
  # Netted out of gross receipts to give the after-fee revenue planning figure.
  SELLING_COST_CATEGORIES = %w[refunds_returns amazon_fees fba_fees advertising].freeze

  attr_reader :year

  def initialize(user:, year:)
    @year = year.to_i
    @rows = user.amazon_import_rows.accepted.for_year(@year)
  end

  attr_reader :rows

  def totals
    @totals ||= rows.group(:tax_category).sum(:amount_cents)
  end

  def total_cents(category)
    amount = totals.fetch(category, 0)
    EXPENSE_CATEGORIES.include?(category) ? -amount : amount
  end

  # Schedule C line 1: sales plus shipping credits paid by buyers.
  def gross_receipts_cents
    totals.fetch("gross_sales", 0) + shipping_cents.fetch(:credits)
  end

  # Planning subtotal, not a Schedule C line: gross receipts minus refunds, selling fees, ads, and shipping charges.
  def revenue_cents
    gross_receipts_cents + totals.values_at(*SELLING_COST_CATEGORIES).compact.sum + shipping_cents.fetch(:charges)
  end

  private

  def shipping_cents
    @shipping_cents ||= begin
      shipping = rows.where(tax_category: "shipping")
      { credits: shipping.where("amount_cents > 0").sum(:amount_cents), charges: shipping.where("amount_cents < 0").sum(:amount_cents) }
    end
  end
end
