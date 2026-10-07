ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "minitest/autorun"

class OutsideExpensesTest < Minitest::Test
  def test_business_share_flows_to_exports_and_archiving_removes_it
    assert_empty OutsideExpense::CATEGORIES.keys.map(&:to_sym) - TurboTaxExport::SCHEDULE_C_REFS.keys
    with_users do |seller, other_seller|
      expense = seller.outside_expenses.create!(
        spent_on: Date.new(2025, 6, 12), payee: "Software vendor", category: "other_business_expenses",
        amount_dollars: "25.00", business_use_percent: 60, description: "Inventory software"
      )
      seller.outside_expenses.create!(
        spent_on: Date.new(2026, 6, 12), payee: "Different year", category: "office_expense",
        amount_dollars: "99.00", business_use_percent: 100
      )
      other_seller.outside_expenses.create!(
        spent_on: Date.new(2025, 6, 12), payee: "Different seller", category: "office_expense",
        amount_dollars: "99.00", business_use_percent: 100
      )

      input = seller.turbo_tax_export_inputs.create!(tax_year: 2025, business_name: "Test business")
      export = TurboTaxExport.new(year: 2025, input: input)
      assert_equal 1_500, expense.deductible_cents
      assert_equal 1_500, export.outside_expense_total_cents
      assert_equal(-1_500, export.lines.index_by(&:key).fetch(:other_business_expenses).amount_cents)
      assert_includes export.txf, "N302"
      assert_includes export.audit_csv, "Software vendor"

      expense.update!(archived_at: Time.current)
      export = TurboTaxExport.new(year: 2025, input: input)
      assert_equal 0, export.outside_expense_total_cents
      refute export.lines.any? { |line| line.key == :other_business_expenses }
      refute_includes export.audit_csv, "Software vendor"
    end
  end

  def test_future_expense_date_is_rejected
    expense = OutsideExpense.new(spent_on: Date.current + 1, payee: "Merchant", category: "office_expense",
      amount_dollars: "10.00", business_use_percent: 100)

    refute expense.valid?
    assert_includes expense.errors[:spent_on], "cannot be in the future"
  end

  private

  def with_users
    ActiveRecord::Base.transaction do
      seller = User.create!(email_address: "outside-#{SecureRandom.hex(4)}@example.com", password: "test-password")
      other_seller = User.create!(email_address: "outside-#{SecureRandom.hex(4)}@example.com", password: "test-password")
      yield seller, other_seller
      raise ActiveRecord::Rollback
    end
  end
end
