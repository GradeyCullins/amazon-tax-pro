require "minitest/autorun"
require_relative "../app/models/amazon_tax_categorizer"

class AmazonTaxCategorizerTest < Minitest::Test
  def category(type, path, cents = 100)
    AmazonTaxCategorizer.for_transaction_breakdown(type, path.split(" > "), cents)
  end

  def test_customer_orders_remain_gross_sales
    assert_equal "gross_sales", category("Shipment", "Sales > ProductCharges")
    assert_equal "shipping", category("Shipment", "Sales > Shipping")
    assert_equal "shipping", category("Shipment", "Expenses > AmazonFees > ShippingChargeback", -599)
    assert_equal "shipping", category("Shipment", "Expenses > AmazonFees > ShippingChargeback", 599)
    assert_equal "refunds_returns", category("Refund", "Sales > Shipping", -599)
  end

  def test_account_movements_are_not_gross_sales
    assert_equal "reserves_adjustments", category("Adjustment", "Sales > FailedDisbursement")
    assert_equal "reserves_adjustments", category("DebtRecovery", "Sales > DebtPayment")
    assert_equal "reserves_adjustments", category("Retrocharge", "Sales > Retrocharge")
  end

  def test_unknown_non_shipment_sales_paths_require_review
    assert_equal "uncategorized", category("RemovalShipment", "Sales > ProductCharges")
    assert_equal "uncategorized", category("MiscellaneousLedgerAdjustment", "Sales > Other")
    assert_equal "uncategorized", category("Adjustment", "Sales > Shipping")
    assert_equal "uncategorized", category("Other", "ProductCharges > Principal")
    assert_equal "uncategorized", category("Adjustment", "Shipping")
  end
end
