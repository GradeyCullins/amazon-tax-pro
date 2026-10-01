ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "minitest/autorun"

ActiveRecord::Migration.maintain_test_schema!

class AmazonYearActivityTest < Minitest::Test
  def test_year_totals_count_accepted_rows_with_signed_credits
    with_user do |user|
      sync = batch(user, source: :sp_api, year: 2025)

      row(user, sync, 2025, "gross_sales", 10_000)
      row(user, sync, 2025, "shipping", 500)
      row(user, sync, 2025, "shipping", -200)
      row(user, sync, 2025, "refunds_returns", -1_000)
      row(user, sync, 2025, "refunds_returns", 100)
      row(user, sync, 2025, "reimbursements", 300)
      row(user, sync, 2025, "amazon_fees", -700)
      row(user, sync, 2025, "amazon_fees", 50)
      row(user, sync, 2025, "fba_fees", -400)
      row(user, sync, 2025, "advertising", -200)
      row(user, sync, 2025, "marketplace_withheld_tax", -80)
      row(user, sync, 2025, "other_business_expenses", -100)
      row(user, sync, 2025, "gross_sales", 99_999, status: :skipped)
      row(user, sync, 2025, "uncategorized", 55_555, status: :pending)
      row(user, sync, 2026, "gross_sales", 20_000)

      activity = AmazonYearActivity.new(user: user, year: 2025)
      assert_equal 12, activity.rows.count
      assert_equal 10_000, activity.total_cents("gross_sales")
      assert_equal 900, activity.total_cents("refunds_returns")
      assert_equal 650, activity.total_cents("amazon_fees")
      assert_equal 80, activity.total_cents("marketplace_withheld_tax")
      assert_equal 300, activity.total_cents("shipping")
      assert_equal 10_500, activity.gross_receipts_cents
      assert_equal 8_150, activity.revenue_cents
      assert_equal 20_000, AmazonYearActivity.new(user: user, year: 2026).total_cents("gross_sales")

      input = user.turbo_tax_export_inputs.create!(tax_year: 2025, business_name: "Test business")
      lines = TurboTaxExport.new(year: 2025, input: input).lines.index_by(&:key)
      assert_equal 10_500, lines.fetch(:gross_receipts).amount_cents
      assert_equal(-900, lines.fetch(:returns_and_allowances).amount_cents)
      assert_equal(-650, lines.fetch(:commissions_and_fees).amount_cents)
      assert_equal(-200, lines.fetch(:advertising).amount_cents)
      assert_equal 300, lines.fetch(:other_business_income).amount_cents
      assert_equal(-700, lines.fetch(:other_business_expenses).amount_cents) # FBA 400 + shipping charge 200 + other 100
    end
  end

  def test_audit_csv_puts_shipping_charges_on_other_expenses
    with_user do |user|
      sync = batch(user, source: :sp_api, year: 2025)
      row(user, sync, 2025, "shipping", 500)
      row(user, sync, 2025, "shipping", -200)

      input = user.turbo_tax_export_inputs.create!(tax_year: 2025, business_name: "Test business")
      lines = CSV.parse(TurboTaxExport.new(year: 2025, input: input).audit_csv, headers: true).map { |r| [r["amount"], r["schedule_c_line"]] }
      assert_includes lines, ["5.00", "Gross receipts"]
      assert_includes lines, ["-2.00", "Other business expenses"]
    end
  end

  def test_plain_labels_describe_credits_and_charges
    with_user do |user|
      sync = batch(user, source: :sp_api, year: 2025)
      assert_equal "Referral fee", row(user, sync, 2025, "amazon_fees", -300, amount_description: "Commission").plain_label
      assert_equal "Referral fee credit", row(user, sync, 2025, "amazon_fees", 300, amount_description: "Commission").plain_label
      assert_equal "Customer refund", row(user, sync, 2025, "refunds_returns", -1_000).plain_label
      assert_equal "Shipping charge", row(user, sync, 2025, "shipping", -200).plain_label
      assert_equal "Needs a category", row(user, sync, 2025, "uncategorized", 5, status: :pending).plain_label
    end
  end

  private

  def with_user
    ActiveRecord::Base.transaction do
      yield User.create!(email_address: "year-activity-#{SecureRandom.hex(4)}@example.com", password: "test-password")
      raise ActiveRecord::Rollback
    end
  end

  def batch(user, source:, year:)
    user.amazon_import_batches.create!(
      source: source,
      sync_status: source == :sp_api ? :succeeded : nil,
      tax_year: year,
      filename: "test #{source}",
      imported_at: Time.current
    )
  end

  def row(user, batch, year, category, cents, status: :accepted, amount_description: nil)
    batch.amazon_import_rows.create!(
      user: user,
      source_row_number: batch.amazon_import_rows.count + 1,
      posted_on: Date.new(year, 6, 15),
      tax_category: category,
      amount_cents: cents,
      amount_description: amount_description,
      status: status
    )
  end
end
