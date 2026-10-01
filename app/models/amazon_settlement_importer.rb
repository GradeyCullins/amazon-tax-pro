require "csv"
require "bigdecimal/util"

class AmazonSettlementImporter
  Result = Struct.new(:batch, :errors, :skipped_count, :skipped_years, keyword_init: true)

  def self.import!(uploaded_file, user:)
    new(uploaded_file, user: user).import!
  end

  def initialize(uploaded_file, user:)
    @uploaded_file = uploaded_file
    @user = user
  end

  def import!
    return Result.new(errors: ["Choose a Seller Central CSV or TSV report to upload."]) if @uploaded_file.blank?

    content = @uploaded_file.read
    separator = detect_separator(content)
    header_line_number = detect_header_line_number(content, separator)
    content = trim_to_header(content, separator)
    parsed_rows = CSV.parse(content, headers: true, col_sep: separator)
    return Result.new(errors: ["The file does not contain a header row."]) if parsed_rows.headers.blank?

    # Sync wins: rows dated in a year Amazon sync already covers would double count, so they're left out.
    synced_years = @user.synced_tax_years.to_set
    skipped_years = Set.new
    skipped_count = 0
    row_attributes = []

    parsed_rows.each.with_index(header_line_number + 1) do |row, row_number|
      normalize_row(row.to_h).each do |attrs|
        if attrs[:posted_on] && synced_years.include?(attrs[:posted_on].year)
          skipped_years << attrs[:posted_on].year
          skipped_count += 1
          next
        end

        row_attributes << attrs.merge(
          source_row_number: row_number,
          raw_data: row.to_h,
          status: AmazonImportRow.initial_status_for(attrs[:tax_category])
        )
      end
    end

    if row_attributes.empty?
      return Result.new(errors: [skipped_years.any? ? all_rows_synced_message(skipped_years) : "No transactions with amounts were found in this file."])
    end

    batch = AmazonImportBatch.transaction do
      @user.amazon_import_batches.create!(
        source: :upload,
        filename: @uploaded_file.original_filename.presence || "amazon-report",
        imported_at: Time.current
      ).tap do |new_batch|
        row_attributes.each { |attrs| new_batch.amazon_import_rows.create!(attrs.merge(user: @user)) }
        new_batch.refresh_status!
      end
    end

    Result.new(batch: batch, errors: [], skipped_count: skipped_count, skipped_years: skipped_years.sort)
  rescue CSV::MalformedCSVError => error
    Result.new(errors: ["Could not parse the file: #{error.message}"])
  end

  private

  def all_rows_synced_message(years)
    "Every row in this report is from #{years.sort.to_sentence}, which you've already synced from Amazon. Synced data replaces uploads, so nothing was imported."
  end

  def detect_separator(content)
    first_line = content.lines.find { |line| line.include?("date/time") || line.include?("posted-date") } || content.lines.first.to_s
    first_line.count("\t") > first_line.count(",") ? "\t" : ","
  end

  def trim_to_header(content, separator)
    lines = content.lines
    header_index = detect_header_line_number(content, separator) - 1

    header_index ? lines[header_index..].join : content
  end

  def detect_header_line_number(content, separator)
    content.lines.index do |line|
      columns = CSV.parse_line(line, col_sep: separator) || []
      normalized = columns.map { |column| column.to_s.strip.downcase }
      normalized.include?("date/time") || normalized.include?("posted-date") || normalized.include?("posted-date-time")
    rescue CSV::MalformedCSVError
      false
    end.to_i + 1
  end

  def normalize_row(raw)
    normalized = raw.transform_keys { |key| key.to_s.strip.downcase }
    return normalize_2025_transaction_report_row(normalized) if normalized.key?("date/time") && normalized.key?("product sales")

    amount_cents = parse_amount(fetch_value(normalized, "amount", "total-amount", "net-amount"))
    transaction_type = fetch_value(normalized, "transaction-type", "type")
    amount_type = fetch_value(normalized, "amount-type")
    amount_description = fetch_value(normalized, "amount-description", "description")

    [{
      posted_on: parse_date(fetch_value(normalized, "posted-date", "posted-date-time", "deposit-date", "settlement-start-date")),
      settlement_id: fetch_value(normalized, "settlement-id"),
      order_id: fetch_value(normalized, "order-id", "merchant-order-id"),
      transaction_type: transaction_type,
      amount_type: amount_type,
      amount_description: amount_description,
      description: [transaction_type, amount_type, amount_description].compact_blank.join(" - "),
      marketplace: fetch_value(normalized, "marketplace-name", "marketplace"),
      amount_cents: amount_cents,
      tax_category: AmazonTaxCategorizer.suggest(transaction_type, amount_type, amount_description, amount_cents)
    }]
  end

  def normalize_2025_transaction_report_row(row)
    component_rows(row).filter_map do |column, amount_cents, category|
      next if amount_cents.zero?

      transaction_type = fetch_value(row, "type")
      description = fetch_value(row, "description")

      {
        posted_on: parse_date(fetch_value(row, "date/time")),
        settlement_id: nil,
        order_id: nil,
        transaction_type: transaction_type,
        amount_type: column,
        amount_description: description,
        description: [transaction_type, column, description, fetch_value(row, "sku")].compact_blank.join(" - "),
        marketplace: fetch_value(row, "marketplace"),
        amount_cents: amount_cents,
        tax_category: category
      }
    end
  end

  def component_rows(row)
    transaction_type = fetch_value(row, "type").to_s
    description = fetch_value(row, "description").to_s

    if transaction_type == "Transfer"
      return [["other", parse_amount(fetch_value(row, "total")), "bank_transfers"]]
    end

    if transaction_type == "Adjustment"
      return [["other", parse_amount(fetch_value(row, "other", "total")), "reimbursements"]]
    end

    if transaction_type == "FBA Inventory Fee"
      return [["other", parse_amount(fetch_value(row, "other", "total")), "fba_fees"]]
    end

    if transaction_type == "Service Fee"
      category = description.match?(/advertis/i) ? "advertising" : AmazonTaxCategorizer.service_fee_category(description)
      return [["other transaction fees", parse_amount(fetch_value(row, "other transaction fees", "total")), category]]
    end

    [
      ["product sales", parse_amount(fetch_value(row, "product sales")), transaction_type == "Refund" ? "refunds_returns" : "gross_sales"],
      ["shipping credits", parse_amount(fetch_value(row, "shipping credits")), "shipping"],
      ["gift wrap credits", parse_amount(fetch_value(row, "gift wrap credits")), "gross_sales"],
      ["Regulatory Fee", parse_amount(fetch_value(row, "regulatory fee")), "gross_sales"],
      ["promotional rebates", parse_amount(fetch_value(row, "promotional rebates")), "refunds_returns"],
      ["marketplace withheld tax", parse_amount(fetch_value(row, "marketplace withheld tax")), "marketplace_withheld_tax"],
      ["selling fees", parse_amount(fetch_value(row, "selling fees")), "amazon_fees"],
      ["fba fees", parse_amount(fetch_value(row, "fba fees")), "fba_fees"],
      ["other transaction fees", parse_amount(fetch_value(row, "other transaction fees")), "amazon_fees"]
    ]
  end

  def fetch_value(row, *keys)
    keys.lazy.map { |key| row[key].to_s.strip.presence }.find(&:present?)
  end

  def parse_amount(value)
    (value.to_s.gsub(/[$,]/, "").to_d * 100).round
  end

  def parse_date(value)
    date = Date.parse(value.to_s)
    date if AmazonImportRow.tax_years.cover?(date.year)
  rescue ArgumentError, TypeError
    nil
  end
end
