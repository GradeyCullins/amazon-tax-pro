class DashboardController < ApplicationController
  def index
    @cash_balance = Account.asset.sum(:balance_cents) / 100.0
    @monthly_revenue = Transaction.current_month.revenue.sum(:amount_cents) / 100.0
    @monthly_expenses = Transaction.current_month.expense.sum(:amount_cents) / 100.0
    @outstanding_invoices = Invoice.outstanding.sum(:total_cents) / 100.0
    @recent_transactions = Transaction.includes(:debit_account, :credit_account).order(transacted_on: :desc).limit(8)
    @expense_breakdown = Expense.current_month.group(:category).sum(:amount_cents)
  end
end
