ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "minitest/autorun"

class AmazonYearActivityTest < Minitest::Test
  def test_default_year_follows_the_latest_sync_on_both_tax_views
    ActiveRecord::Base.transaction do
      user = User.create!(email_address: "latest-sync@example.com", password: "test-password")
      older = batch(user, source: :sp_api, year: 2026)
      row(user, older, 2026, "gross_sales", 20_000)
      newer = batch(user, source: :sp_api, year: 2025)
      newer.update_columns(created_at: older.created_at + 1.minute)
      row(user, newer, 2025, "gross_sales", 10_000)

      assert_equal 2025, AmazonYearActivity.default_year_for(user)
      raise ActiveRecord::Rollback
    end
  end

  def test_year_totals_exclude_skipped_rows_and_overlapping_uploads
    ActiveRecord::Base.transaction do
      user = User.create!(email_address: "year-activity@example.com", password: "test-password")
      api_batch = batch(user, source: :sp_api, year: 2025)
      upload_batch = batch(user, source: :upload, year: 2025)

      row(user, api_batch, 2025, "gross_sales", 10_000)
      row(user, api_batch, 2025, "shipping", 500)
      row(user, api_batch, 2025, "shipping", -200)
      row(user, api_batch, 2025, "refunds_returns", -1_000)
      row(user, api_batch, 2025, "refunds_returns", 100)
      row(user, api_batch, 2025, "reimbursements", 300)
      row(user, api_batch, 2025, "amazon_fees", -700)
      row(user, api_batch, 2025, "amazon_fees", 50)
      row(user, api_batch, 2025, "fba_fees", -400)
      row(user, api_batch, 2025, "advertising", -200)
      row(user, api_batch, 2025, "marketplace_withheld_tax", -80)
      row(user, api_batch, 2025, "other_business_expenses", -100)
      row(user, api_batch, 2025, "gross_sales", 99_999, status: :skipped)
      row(user, api_batch, 2026, "gross_sales", 20_000)
      row(user, upload_batch, 2025, "gross_sales", 5_000)

      activity = AmazonYearActivity.new(user: user, year: 2025)
      assert_equal "Amazon API imports", activity.source_label
      assert_equal 12, activity.row_count
      assert_equal 12, activity.pending_count
      assert_equal 10_000, activity.total_cents("gross_sales")
      assert_equal 900, activity.total_cents("refunds_returns")
      assert_equal 650, activity.total_cents("amazon_fees")
      assert_equal 80, activity.total_cents("marketplace_withheld_tax")
      assert_equal 10_500, activity.gross_receipts_cents
      assert_equal 8_150, activity.revenue_cents
      assert_equal 20_000, AmazonYearActivity.new(user: user, year: 2026).total_cents("gross_sales")

      input = user.turbo_tax_export_inputs.create!(tax_year: 2025, business_name: "Test business")
      lines = TurboTaxExport.new(year: 2025, input: input).lines.index_by(&:key)
      assert_equal 10_500, lines.fetch(:gross_receipts).amount_cents
      assert_equal(-900, lines.fetch(:returns_and_allowances).amount_cents)
      assert_equal(-650, lines.fetch(:commissions_and_fees).amount_cents)
      assert_equal(-700, lines.fetch(:other_business_expenses).amount_cents)

      raise ActiveRecord::Rollback
    end
  end

  def test_sandbox_rows_do_not_mix_with_real_api_rows
    ActiveRecord::Base.transaction do
      user = User.create!(email_address: "sandbox-activity@example.com", password: "test-password")
      real_batch = batch(user, source: :sp_api, year: 2025)
      sample_batch = batch(user, source: :sp_api, year: 2025, sandbox_sample: true)
      row(user, real_batch, 2025, "gross_sales", 10_000)
      row(user, sample_batch, 2025, "gross_sales", 500)
      row(user, sample_batch, 2023, "gross_sales", 700)

      assert_equal 10_000, AmazonYearActivity.new(user: user, year: 2025).total_cents("gross_sales")
      sample_activity = AmazonYearActivity.new(user: user, year: 2023)
      assert_equal "Amazon sandbox samples", sample_activity.source_label
      assert_equal 700, sample_activity.total_cents("gross_sales")

      raise ActiveRecord::Rollback
    end
  end

  private

  def batch(user, source:, year:, sandbox_sample: false)
    user.amazon_import_batches.create!(
      source: source,
      sync_status: source == :sp_api ? :succeeded : nil,
      sandbox_sample: sandbox_sample,
      tax_year: year,
      filename: "test #{source}",
      imported_at: Time.current
    )
  end

  def row(user, batch, year, category, cents, status: :pending)
    batch.amazon_import_rows.create!(
      user: user,
      source_row_number: batch.amazon_import_rows.count + 1,
      posted_on: Date.new(year, 6, 15),
      tax_category: category,
      amount_cents: cents,
      status: status
    )
  end
end
