require "csv"

class TurboTaxExport
  SCHEDULE_C_REFS = {
    gross_receipts: 293,
    returns_and_allowances: 296,
    cost_of_goods_sold: 295,
    other_business_income: 303,
    advertising: 304,
    commissions_and_fees: 307,
    insurance: 310,
    legal_professional: 298,
    office_expense: 313,
    rent: 300,
    repairs: 315,
    supplies: 301,
    taxes_licenses: 316,
    utilities: 318,
    other_business_expenses: 302
  }.freeze

  CATEGORY_LINES = {
    "gross_sales" => :gross_receipts,
    "shipping" => :gross_receipts,
    "refunds_returns" => :returns_and_allowances,
    "reimbursements" => :other_business_income,
    "advertising" => :advertising,
    "amazon_fees" => :commissions_and_fees,
    "fba_fees" => :other_business_expenses,
    "other_business_expenses" => :other_business_expenses
  }.freeze

  EXCLUDED_CATEGORIES = %w[
    bank_transfers
    marketplace_withheld_tax
    reserves_adjustments
    uncategorized
  ].freeze

  Line = Struct.new(:key, :label, :txf_ref, :amount_cents, keyword_init: true)

  attr_reader :year, :input

  def initialize(year:, input:)
    @year = year.to_i
    @input = input
  end

  def activity
    @activity ||= AmazonYearActivity.new(user: input.user, year: year)
  end

  # Same rows as the tax packet: accepted only. Rows still waiting for review are reported in #warnings.
  def rows
    activity.rows
  end

  def needs_review_count
    @needs_review_count ||= input.user.amazon_import_rows.needs_review.for_year(year).count
  end

  def year_status
    @year_status ||= TaxYearStatus.new(input.user, year)
  end

  def lines
    grouped = taxable_rows.group_by { |row| line_key_for(row) }
    generated = grouped.map do |key, line_rows|
      amount_cents = line_rows.sum(&:amount_cents)
      Line.new(key: key, label: label_for(key), txf_ref: SCHEDULE_C_REFS.fetch(key), amount_cents: amount_cents)
    end

    outside_expenses.group_by(&:category).each do |category, expenses|
      key = category.to_sym
      generated << Line.new(
        key: key, label: label_for(key), txf_ref: SCHEDULE_C_REFS.fetch(key),
        amount_cents: -expenses.sum(&:deductible_cents)
      )
    end

    if input.cost_of_goods_sold_cents.positive?
      generated << Line.new(
        key: :cost_of_goods_sold,
        label: "Cost of goods sold",
        txf_ref: SCHEDULE_C_REFS.fetch(:cost_of_goods_sold),
        amount_cents: -input.cost_of_goods_sold_cents
      )
    end

    generated.group_by(&:key).map do |key, line_items|
      Line.new(key: key, label: label_for(key), txf_ref: SCHEDULE_C_REFS.fetch(key), amount_cents: line_items.sum(&:amount_cents))
    end.reject { |line| line.amount_cents.zero? }.sort_by(&:txf_ref)
  end

  def outside_expenses
    @outside_expenses ||= input.user.outside_expenses.active.for_year(year).order(:spent_on, :id).to_a
  end

  def outside_expense_total_cents
    outside_expenses.sum(&:deductible_cents)
  end

  def excluded_rows
    rows.select { |row| EXCLUDED_CATEGORIES.include?(row.tax_category) }
  end

  def uncategorized_rows
    rows.select { |row| row.tax_category == "uncategorized" }
  end

  def warnings
    messages = []
    messages << "Not included yet: #{count_rows(needs_review_count)} that need review." if needs_review_count.positive?
    messages << "Possible double counting: #{year} has both synced and uploaded rows." if year_status.mixed_sources?
    messages << "Left out of the TXF: #{count_rows(uncategorized_rows.count)} accepted as Uncategorized." if uncategorized_rows.any?
    messages << "Left out of Schedule C lines: #{count_rows(excluded_rows.count)} of transfers, withheld tax, or reserves." if excluded_rows.any?
    messages << "Cost of goods sold is $0. Add inventory and purchase totals if you had product costs." if input.cost_of_goods_sold_cents.zero?
    messages
  end

  def txf
    output = [
      "V042",
      "AAccounting Demo Amazon Seller TurboTax Export",
      "D #{Date.current.strftime('%m/%d/%Y')}",
      "^"
    ]

    lines.each do |line|
      output.concat([
        "TS",
        "N#{line.txf_ref}",
        "C1",
        "L1",
        money_line(line.amount_cents),
        "P#{input.business_name}",
        "^"
      ])
    end

    output.join("\n") + "\n"
  end

  def audit_csv
    CSV.generate(headers: true) do |csv|
      csv << ["posted_on", "category", "amount", "schedule_c_line", "description", "source_row_number", "review_status", "source"]

      rows.includes(:amazon_import_batch).order(:posted_on, :source_row_number).each do |row|
        line_key = line_key_for(row)
        csv << [
          row.posted_on,
          row.tax_category_name,
          format_amount(row.amount_cents),
          line_key ? label_for(line_key) : "Excluded from TXF",
          row.description,
          row.source_row_number,
          row.review_label,
          row.amazon_import_batch.source_label
        ]
      end

      outside_expenses.each do |expense|
        details = [expense.payee, expense.description].reject(&:blank?).join(" — ")
        details += " (#{expense.business_use_percent}% of $#{format_amount(expense.amount_cents)} paid)"
        csv << [expense.spent_on, expense.category_name, format_amount(-expense.deductible_cents),
          label_for(expense.category.to_sym), details, nil, "Entered", "Outside Amazon"]
      end
    end
  end

  def instructions_html
    <<~HTML
      <h1>TurboTax Desktop Import Guide</h1>
      <p>This package is for TurboTax Desktop TXF import. TurboTax Online does not provide the same general TXF import workflow.</p>
      <ol>
        <li>Open the #{year} return in TurboTax Desktop.</li>
        <li>Choose File, then Import.</li>
        <li>On Windows choose From Accounting Software. On Mac choose From TXF Files.</li>
        <li>Select the generated .txf file and complete the TurboTax import prompts.</li>
        <li>Review Schedule C inside TurboTax before filing. Confirm business name, inventory/COGS, outside Amazon expenses, and any special deductions not handled here.</li>
      </ol>
      <h2>Important review items</h2>
      <ul>
        #{warnings.map { |warning| "<li>#{ERB::Util.html_escape(warning)}</li>" }.join}
      </ul>
    HTML
  end

  private

  def count_rows(count)
    "#{count} #{count == 1 ? "row" : "rows"}"
  end

  def taxable_rows
    rows.reject { |row| EXCLUDED_CATEGORIES.include?(row.tax_category) || !CATEGORY_LINES.key?(row.tax_category) }
  end

  # Amounts keep Amazon's signs, so credits net against their line. Shipping Amazon charged the seller is an
  # expense, not negative receipts.
  def line_key_for(row)
    return :other_business_expenses if row.tax_category == "shipping" && row.amount_cents.negative?

    CATEGORY_LINES[row.tax_category]
  end

  def label_for(key)
    {
      gross_receipts: "Gross receipts",
      returns_and_allowances: "Returns and allowances",
      cost_of_goods_sold: "Cost of goods sold",
      other_business_income: "Other business income",
      advertising: "Advertising",
      commissions_and_fees: "Commissions and fees",
      insurance: "Business insurance (not health)",
      legal_professional: "Legal and professional",
      office_expense: "Office expense",
      rent: "Business rent (not home office)",
      repairs: "Repairs and maintenance",
      supplies: "Supplies",
      taxes_licenses: "Taxes and licenses",
      utilities: "Business utilities (not home office)",
      other_business_expenses: "Other business expenses"
    }.fetch(key)
  end

  def money_line(cents)
    "$#{format_amount(cents)}"
  end

  def format_amount(cents)
    format("%.2f", cents.to_i / 100.0)
  end
end
