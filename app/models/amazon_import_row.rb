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

  belongs_to :amazon_import_batch
  belongs_to :accounting_transaction, class_name: "Transaction", foreign_key: :transaction_id, optional: true
  belongs_to :expense, optional: true

  enum :status, { pending: 0, accepted: 1, skipped: 2 }

  serialize :raw_data, coder: JSON

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

  private

end
