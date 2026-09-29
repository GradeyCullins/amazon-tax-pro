require "csv"

class TurboTaxExport
  SCHEDULE_C_REFS = {
    gross_receipts: 293,
    returns_and_allowances: 296,
    cost_of_goods_sold: 295,
    other_business_income: 303,
    advertising: 304,
    commissions_and_fees: 307,
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

  def rows
    @rows ||= input.user.amazon_import_rows.turbotax_ready_for_year(year)
  end

  def lines
    grouped = taxable_rows.group_by { |row| CATEGORY_LINES.fetch(row.tax_category) }
    generated = grouped.map do |key, line_rows|
      amount_cents = line_rows.sum { |row| amount_for_line(row, key) }
      Line.new(key: key, label: label_for(key), txf_ref: SCHEDULE_C_REFS.fetch(key), amount_cents: amount_cents)
    end

    if input.cost_of_goods_sold_cents.positive?
      generated << Line.new(
        key: :cost_of_goods_sold,
        label: "Cost of goods sold",
        txf_ref: SCHEDULE_C_REFS.fetch(:cost_of_goods_sold),
        amount_cents: -input.cost_of_goods_sold_cents
      )
    end

    generated.reject { |line| line.amount_cents.zero? }.sort_by(&:txf_ref)
  end

  def excluded_rows
    rows.select { |row| EXCLUDED_CATEGORIES.include?(row.tax_category) }
  end

  def uncategorized_rows
    rows.select { |row| row.tax_category == "uncategorized" }
  end

  def warnings
    messages = []
    messages << "#{uncategorized_rows.count} uncategorized Amazon rows are excluded from the TXF." if uncategorized_rows.any?
    messages << "#{excluded_rows.count} non-tax rows are excluded from Schedule C lines." if excluded_rows.any?
    messages << "Manual COGS inputs are all zero. Add inventory/purchase totals if this seller had product costs." if input.cost_of_goods_sold_cents.zero?
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
      csv << ["posted_on", "category", "amount", "schedule_c_line", "description", "source_row_number"]

      rows.order(:posted_on, :source_row_number).each do |row|
        line_key = CATEGORY_LINES[row.tax_category]
        csv << [
          row.posted_on,
          row.tax_category_name,
          format_amount(row.amount_cents),
          line_key ? label_for(line_key) : "Excluded from TXF",
          row.description,
          row.source_row_number
        ]
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
        <li>Review Schedule C inside TurboTax before filing. Confirm business name, inventory/COGS, and any non-Amazon expenses.</li>
      </ol>
      <h2>Important review items</h2>
      <ul>
        #{warnings.map { |warning| "<li>#{ERB::Util.html_escape(warning)}</li>" }.join}
      </ul>
    HTML
  end

  private

  def taxable_rows
    rows.reject { |row| EXCLUDED_CATEGORIES.include?(row.tax_category) || !CATEGORY_LINES.key?(row.tax_category) }
  end

  def amount_for_line(row, line_key)
    case line_key
    when :returns_and_allowances, :advertising, :commissions_and_fees, :other_business_expenses
      -row.amount_cents.abs
    else
      row.amount_cents
    end
  end

  def label_for(key)
    {
      gross_receipts: "Gross receipts",
      returns_and_allowances: "Returns and allowances",
      cost_of_goods_sold: "Cost of goods sold",
      other_business_income: "Other business income",
      advertising: "Advertising",
      commissions_and_fees: "Commissions and fees",
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
