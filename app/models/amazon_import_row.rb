class AmazonImportRow < ApplicationRecord
  TAX_CATEGORIES = {
    "gross_sales" => "Gross sales",
    "refunds_returns" => "Refunds and returns",
    "amazon_fees" => "Amazon fees",
    "fba_fees" => "FBA fees",
    "shipping" => "Shipping",
    "advertising" => "Advertising",
    "reimbursements" => "Reimbursements",
    "marketplace_withheld_tax" => "Marketplace withheld tax",
    "bank_transfers" => "Bank transfers",
    "cost_of_goods_sold" => "Cost of goods sold",
    "other_business_expenses" => "Other business expenses",
    "reserves_adjustments" => "Reserves and adjustments",
    "uncategorized" => "Uncategorized"
  }.freeze

  REVENUE_CATEGORIES = %w[gross_sales reimbursements].freeze
  EXCLUDED_TAX_CATEGORIES = %w[bank_transfers marketplace_withheld_tax reserves_adjustments].freeze
  REVIEW_GROUP_SQL = "CASE WHEN TRIM(COALESCE(order_id, '')) <> '' THEN 'order:' || TRIM(order_id) ELSE 'row:' || id END".freeze

  belongs_to :user
  belongs_to :amazon_import_batch
  belongs_to :accounting_transaction, class_name: "Transaction", foreign_key: :transaction_id, optional: true
  belongs_to :expense, optional: true

  enum :status, { pending: 0, accepted: 1, skipped: 2 }

  serialize :raw_data, coder: JSON
  encrypts :raw_data

  validates :source_row_number, :amount_cents, :tax_category, presence: true
  validates :tax_category, inclusion: { in: TAX_CATEGORIES.keys }

  scope :for_year, ->(year) { where(posted_on: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31)) }

  def self.category_options
    TAX_CATEGORIES.map { |key, label| [label, key] }
  end

  def self.accepted_tax_totals(year)
    accepted.for_year(year).group_by(&:tax_category).transform_values do |rows|
      rows.sum(&:tax_amount_cents)
    end
  end

  def self.turbotax_ready_for_year(year)
    for_year(year).where.not(status: :skipped)
  end

  def tax_category_name
    TAX_CATEGORIES.fetch(tax_category)
  end

  def review_group_key
    order_id.present? && order_id.strip.present? ? "order:#{order_id.strip}" : "row:#{id}"
  end

  def review_group_title
    order_id.to_s.strip.match?(/\A\d{3}-\d{7}-\d{7}\z/) ? "Order" : "Amazon reference"
  end

  def review_label
    detail = [amount_type, amount_description].compact.join(" ")

    case tax_category
    when "gross_sales" then amount_cents.negative? ? "Sales adjustment" : "Product sale"
    when "refunds_returns" then amount_cents.positive? ? "Refund adjustment" : "Customer refund"
    when "amazon_fees"
      fee = if detail.match?(/commission/i)
        "Referral fee"
      elsif detail.match?(/subscription/i)
        "Seller subscription fee"
      elsif detail.match?(/shipping.?chargeback/i)
        "Shipping chargeback"
      else
        "Amazon selling fee"
      end
      amount_cents.positive? ? "#{fee} credit" : fee
    when "fba_fees"
      fee = detail.match?(/storage/i) ? "FBA storage fee" : "FBA fulfillment fee"
      amount_cents.positive? ? "#{fee} credit" : fee
    when "shipping" then amount_cents.negative? ? "Shipping charge" : "Shipping credit"
    when "advertising" then amount_cents.positive? ? "Advertising credit" : "Advertising charge"
    when "reimbursements" then amount_cents.negative? ? "Reimbursement reversal" : "Amazon reimbursement"
    when "marketplace_withheld_tax" then "Marketplace tax withheld"
    when "bank_transfers" then "Bank payout or transfer"
    when "cost_of_goods_sold" then "Cost of goods sold"
    when "other_business_expenses" then "Other business expense"
    when "reserves_adjustments" then "Account adjustment"
    else "Needs a category"
    end
  end

  def tax_amount_cents
    taxable_expense? ? amount_cents.abs : amount_cents
  end

  def excluded_from_income_tax?
    EXCLUDED_TAX_CATEGORIES.include?(tax_category)
  end

  def taxable_expense?
    !REVENUE_CATEGORIES.include?(tax_category) && !excluded_from_income_tax?
  end

  def accept!(category)
    update!(tax_category: category, status: :accepted)
    amazon_import_batch.refresh_status!
  end

  def skip!
    update!(status: :skipped)
    amazon_import_batch.refresh_status!
  end
end
