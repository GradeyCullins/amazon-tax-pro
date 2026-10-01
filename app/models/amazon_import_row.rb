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
  FIRST_TAX_YEAR = 2000
  # SQLite returns NULL here for years it can't format (five digits or negative).
  POSTED_YEAR_SQL = "CAST(strftime('%Y', amazon_import_rows.posted_on) AS INTEGER)"

  # Review buckets, in the order the Review page shows them. Every row is in exactly one.
  REVIEW_STATUSES = {
    "needs_review" => "Needs review",
    "auto_accepted" => "Auto-categorized",
    "user_accepted" => "Accepted",
    "skipped" => "Skipped"
  }.freeze

  belongs_to :user
  belongs_to :amazon_import_batch
  belongs_to :accounting_transaction, class_name: "Transaction", foreign_key: :transaction_id, optional: true
  belongs_to :expense, optional: true

  enum :status, { pending: 0, accepted: 1, skipped: 2 }

  serialize :raw_data, coder: JSON
  encrypts :raw_data

  validates :source_row_number, :amount_cents, :tax_category, presence: true
  validates :tax_category, inclusion: { in: TAX_CATEGORIES.keys }
  validate :category_chosen, if: -> { accepted? && (will_save_change_to_status? || will_save_change_to_tax_category?) }

  scope :for_year, ->(year) { where(posted_on: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31)) }
  scope :needs_review, -> { pending }
  scope :auto_accepted, -> { accepted.where(reviewed_at: nil) }
  scope :user_accepted, -> { accepted.where.not(reviewed_at: nil) }
  scope :synced, -> { joins(:amazon_import_batch).merge(AmazonImportBatch.source_sp_api) }
  scope :uploaded, -> { joins(:amazon_import_batch).merge(AmazonImportBatch.source_upload) }

  def self.category_options
    TAX_CATEGORIES.map { |key, label| [label, key] }
  end

  # Auto-accept: a row with a suggested category counts right away; only uncategorized rows wait for a person.
  def self.initial_status_for(tax_category)
    tax_category.to_s == "uncategorized" ? :pending : :accepted
  end

  def self.review_counts
    REVIEW_STATUSES.keys.index_with { |review_status| public_send(review_status).count }
  end

  # Years a row can count toward. Uploaded dates outside this range (a typo like 20255) import as undated.
  def self.tax_years
    FIRST_TAX_YEAR..Date.current.year
  end

  def self.years
    where.not(posted_on: nil).distinct.pluck(Arel.sql(POSTED_YEAR_SQL)).select { |year| tax_years.cover?(year) }.sort.reverse
  end

  def self.accepted_tax_totals(year)
    accepted.for_year(year).group_by(&:tax_category).transform_values do |rows|
      rows.sum(&:tax_amount_cents)
    end
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

  def review_status
    return "needs_review" if pending?
    return "skipped" if skipped?

    reviewed_at? ? "user_accepted" : "auto_accepted"
  end

  def review_label
    REVIEW_STATUSES.fetch(review_status)
  end

  def accept!(category)
    update!(tax_category: category, status: :accepted, reviewed_at: Time.current)
    amazon_import_batch.refresh_status!
  end

  def skip!
    update!(status: :skipped, reviewed_at: Time.current)
    amazon_import_batch.refresh_status!
  end

  private

  def category_chosen
    errors.add(:base, "Choose a tax category before accepting, or skip the row.") if tax_category == "uncategorized"
  end
end
