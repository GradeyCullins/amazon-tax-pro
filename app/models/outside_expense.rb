require "bigdecimal/util"

class OutsideExpense < ApplicationRecord
  CATEGORIES = {
    "advertising" => "Advertising",
    "commissions_and_fees" => "Commissions and fees",
    "insurance" => "Business insurance (not health)",
    "legal_professional" => "Legal and professional",
    "office_expense" => "Office expense",
    "rent" => "Business rent (not home office)",
    "repairs" => "Repairs and maintenance",
    "supplies" => "Supplies outside inventory",
    "taxes_licenses" => "Business taxes and licenses",
    "utilities" => "Business utilities (not home office)",
    "other_business_expenses" => "Other business expenses"
  }.freeze

  belongs_to :user

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_year, ->(year) { where(spent_on: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31)) }

  validates :spent_on, presence: true
  validates :payee, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :business_use_percent, numericality: { only_integer: true, in: 1..100 }
  validate :supported_year
  validate :not_in_future

  def amount_dollars
    format("%.2f", amount_cents.to_i / 100.0)
  end

  def amount_dollars=(value)
    cleaned = value.to_s.strip.delete("$,")
    self.amount_cents = cleaned.match?(/\A\d{1,9}(?:\.\d{1,2})?\z/) ? (cleaned.to_d * 100).to_i : nil
  end

  def deductible_cents
    (amount_cents.to_i * business_use_percent.to_i + 50) / 100
  end

  def category_name
    CATEGORIES.fetch(category)
  end

  def self.years
    active.where.not(spent_on: nil).distinct.pluck(Arel.sql("CAST(strftime('%Y', outside_expenses.spent_on) AS INTEGER)"))
      .select { |year| AmazonImportRow.tax_years.cover?(year) }.sort.reverse
  end

  private

  def supported_year
    return if spent_on.nil? || AmazonImportRow.tax_years.cover?(spent_on.year)

    errors.add(:spent_on, "must be within a supported tax year")
  end

  def not_in_future
    errors.add(:spent_on, "cannot be in the future") if spent_on && spent_on > Date.current
  end
end
