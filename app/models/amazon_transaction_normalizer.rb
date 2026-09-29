require "bigdecimal"
require "digest"

# Converts one Finances API v2024-06-19 transaction (camelCase JSON hash) into AmazonImportRow attributes:
# one row per leaf breakdown, mirroring how the 2025 transaction report importer splits component columns.
class AmazonTransactionNormalizer
  REPORTING_TIME_ZONE = "America/Los_Angeles".freeze

  def self.rows_for(transaction)
    new(transaction).rows
  end

  def initialize(transaction)
    @transaction = transaction.deep_stringify_keys
  end

  def rows
    leaves = leaf_breakdowns(@transaction["breakdowns"])
    rows = leaves.filter_map.with_index do |(path, amount_cents), index|
      next if amount_cents.zero?

      build_row(path, amount_cents, "#{transaction_key}:#{index}")
    end

    residual_cents = total_cents - leaves.sum { |_path, amount_cents| amount_cents }
    rows << build_row(leaves.empty? ? ["Total"] : ["Unallocated"], residual_cents, "#{transaction_key}:total") unless residual_cents.zero?
    rows
  end

  private

  def build_row(path, amount_cents, external_id)
    transaction_type = @transaction["transactionType"]
    description = @transaction["description"]

    {
      external_id: external_id,
      posted_on: posted_on,
      settlement_id: related_identifier("SETTLEMENT_ID") || related_identifier("FINANCIAL_EVENT_GROUP_ID"),
      order_id: related_identifier("ORDER_ID"),
      transaction_type: transaction_type,
      amount_type: path.join(" > "),
      amount_description: description,
      description: [transaction_type, path.join(" > "), description].compact_blank.join(" - "),
      marketplace: @transaction.dig("marketplaceDetails", "marketplaceName") || @transaction.dig("marketplaceDetails", "marketplaceId"),
      amount_cents: amount_cents,
      tax_category: AmazonTaxCategorizer.for_transaction_breakdown(transaction_type, path, amount_cents),
      raw_data: @transaction
    }
  end

  def leaf_breakdowns(breakdowns, parent_path = [])
    Array(breakdowns).flat_map do |breakdown|
      path = parent_path + [breakdown["breakdownType"].presence || "Unknown"]
      children = Array(breakdown["breakdowns"])

      children.any? ? leaf_breakdowns(children, path) : [[path, cents(breakdown.dig("breakdownAmount", "currencyAmount"))]]
    end
  end

  def transaction_key
    @transaction["transactionId"].presence || Digest::SHA256.hexdigest(@transaction.to_json)[0, 32]
  end

  def total_cents
    cents(@transaction.dig("totalAmount", "currencyAmount"))
  end

  def posted_on
    value = @transaction["postedDate"]
    value.present? ? Time.iso8601(value).in_time_zone(REPORTING_TIME_ZONE).to_date : nil
  rescue ArgumentError
    nil
  end

  def related_identifier(name)
    Array(@transaction["relatedIdentifiers"]).find { |identifier| identifier["relatedIdentifierName"] == name }&.dig("relatedIdentifierValue")
  end

  def cents(value)
    (BigDecimal(value.to_s.presence || "0") * 100).round.to_i
  end
end
