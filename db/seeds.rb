cash = Account.create!(name: 'Cash', kind: :asset, balance_cents: 1525000)
revenue = Account.create!(name: 'Service Revenue', kind: :revenue, balance_cents: 0)
expenses = Account.create!(name: 'Operating Expenses', kind: :expense, balance_cents: 0)

10.times do |i|
  Transaction.create!(
    transacted_on: Date.current - i.days,
    description: "Client payment ##{1000 + i}",
    debit_account: cash,
    credit_account: revenue,
    amount_cents: rand(40_000..120_000)
  )
end

5.times do |i|
  Expense.create!(vendor: "Vendor #{i + 1}", category: %w[Software Payroll Rent Utilities Marketing][i], spent_on: Date.current - i.days, amount_cents: rand(8_000..35_000))
end

3.times do |i|
  Invoice.create!(number: "INV-#{200 + i}", customer_name: "Client #{i + 1}", due_on: Date.current + (i + 3).days, status: :sent, total_cents: rand(50_000..180_000))
end
