# Suggests AmazonImportRow tax categories for settlement/report rows and SP-API transaction breakdowns.
module AmazonTaxCategorizer
  module_function

  def suggest(transaction_type, amount_type, amount_description, amount_cents)
    text = [transaction_type, amount_type, amount_description].compact.join(" ").downcase

    return "advertising" if text.match?(/advertis|sponsored/)
    return "fba_fees" if text.match?(/\bfba\b|fulfillment|storage|pick.*pack/)
    return "refunds_returns" if text.match?(/refund|return/) || amount_cents.negative? && text.match?(/principal|product charges|itemprice/)
    return "shipping" if text.match?(/shipping|postage|freight/)
    return "reimbursements" if text.match?(/reimbursement/)
    return "reserves_adjustments" if text.match?(/reserve|adjustment|transfer/)
    return "amazon_fees" if text.match?(/fee|commission|subscription|closing/)
    return "gross_sales" if text.match?(/principal|product charges|itemprice|sale/)

    "uncategorized"
  end

  def service_fee_category(description)
    return "fba_fees" if description.match?(/\bfba\b|storage|removal|disposal|inbound/i)
    return "amazon_fees" if description.match?(/subscription|fee/i)

    "other_business_expenses"
  end

  # breakdown_path is the list of breakdownType values from the top-level breakdown down to the leaf,
  # e.g. ["Expenses", "AmazonFees", "Commission"]. breakdownType is open-ended, so fall back to keyword rules.
  def for_transaction_breakdown(transaction_type, breakdown_path, amount_cents)
    type = transaction_type.to_s
    path = breakdown_path.map(&:to_s)
    text = path.join(" ")

    return "bank_transfers" if type.match?(/transfer|disbursement|payout/i)
    return "reserves_adjustments" if type.match?(/reserve/i) || text.match?(/reserve/i)
    # Sales tax and regulatory fees Amazon remits as marketplace facilitator net to zero and are excluded from income.
    return "marketplace_withheld_tax" if text.match?(/MarketplaceFacilitator|MPFRegulatoryFee|Withheld|Tax(?!able)/i)
    return "advertising" if type.match?(/advertis|sponsored|ProductAds/i) || text.match?(/advertis|sponsored/i)
    return "reimbursements" if type.match?(/reimburse|SAFE-?T|Guarantee/i) || text.match?(/reimburse/i)
    return "fba_fees" if text.match?(/\bFBA|Fulfillment|Storage|Removal|Disposal|Inbound|Placement|PickPack/i)
    return "shipping" if text.match?(/Shipping(Charge|Credit)?\b|GiftWrap/i) && amount_cents.positive?
    return "refunds_returns" if type.match?(/refund|return|chargeback|a-to-z|guarantee/i) && text.match?(/Principal|ProductCharges|ItemPrice|Sales|Promotion|Shipping/i)
    return "refunds_returns" if text.match?(/Promotion|Discount|Rebate/i)
    return "amazon_fees" if text.match?(/Fee|Commission|Closing|Subscription|CSBA/i)
    return "gross_sales" if text.match?(/Principal|ProductCharges|ItemPrice|Sales|OurPriceRegulatoryFee/i)

    suggest(type, path.first, path.last, amount_cents)
  end
end
