require "digest"

module SandboxSeller
  # Builds one tax year of fake but realistic Finances API v2024-06-19 transactions for the sandbox seller.
  # Output is deterministic per year (seeded RNG, IDs derived from stable keys), so re-syncing dedupes cleanly.
  class TransactionGenerator
    ZONE = AmazonTransactionNormalizer::REPORTING_TIME_ZONE
    MARKETPLACE_DETAILS = { "marketplaceId" => AmazonConnection::US_MARKETPLACE_ID, "marketplaceName" => "Amazon.com" }.freeze
    SETTLEMENT_DAYS = 14
    ORDERS_PER_DAY = 2.0
    # Prime Day in July, holiday rush in November and December.
    SEASONALITY = [nil, 0.8, 0.75, 0.85, 0.9, 1.0, 0.95, 1.2, 0.95, 0.9, 1.05, 1.5, 1.8].freeze
    TAX_RATES = [0, 0.06, 0.0625, 0.0725, 0.0825, 0.0875, 0.1025].freeze
    PRODUCTS = [
      { sku: "STG-BTL32-SLT", asin: "B0C7K2M9QX", title: "Summit Trail Insulated Water Bottle, 32 oz, Slate", price: 2799, fba_fee: 512, weight: 5 },
      { sku: "STG-BTL20-SGE", asin: "B0C7K3H1LW", title: "Summit Trail Insulated Water Bottle, 20 oz, Sage", price: 2299, fba_fee: 447, weight: 4 },
      { sku: "STG-CPMUG-BLK", asin: "B0CB8Q4ZTN", title: "Summit Trail Enamel Camp Mug, 12 oz, 2-Pack", price: 1999, fba_fee: 406, weight: 3 },
      { sku: "STG-HDLMP-400", asin: "B0CDJ6V2RP", title: "Summit Trail Rechargeable Headlamp, 400 Lumen", price: 3499, fba_fee: 389, weight: 3 },
      { sku: "STG-SPORK-TI4", asin: "B0CF2M7KXA", title: "Summit Trail Titanium Spork, 4-Pack", price: 1599, fba_fee: 322, weight: 2 },
      { sku: "STG-DRYBG-3PK", asin: "B0CHT9W5NE", title: "Summit Trail Roll-Top Dry Bags, 3-Pack (5L/10L/20L)", price: 2999, fba_fee: 478, weight: 3 },
      { sku: "STG-CHAIR-UL1", asin: "B0CK4R8YDM", title: "Summit Trail Ultralight Camp Chair, Charcoal", price: 6499, fba_fee: 789, weight: 1 },
      { sku: "STG-HAMMK-DBL", asin: "B0CM1X6FQS", title: "Summit Trail Double Camping Hammock with Straps", price: 4499, fba_fee: 641, weight: 2 }
    ].freeze

    def self.for_year(year)
      new(year).transactions
    end

    def initialize(year)
      @year = year.to_i
      @zone = ActiveSupport::TimeZone[ZONE]
      @growth = [1 + 0.15 * (@year - 2023), 0.5].max
    end

    def transactions
      @rng = Random.new(@year * 7_919 + 104_729)
      @transactions = []
      each_day { |day| generate_day(day) }
      generate_monthly_charges
      generate_review_items
      @transactions.select! { |transaction| transaction[:posted_at] >= year_start && transaction[:posted_at] < year_end }
      add_settlements_and_transfers
      @transactions.map { |transaction| build(**transaction) }
    end

    private

    def year_start = @zone.local(@year, 1, 1)
    def year_end = @zone.local(@year + 1, 1, 1)

    def each_day(&)
      (Date.new(@year, 1, 1)..Date.new(@year, 12, 31)).each(&)
    end

    def at(day, hour_range = 6..22)
      @zone.local(day.year, day.month, day.day, @rng.rand(hour_range), @rng.rand(60), @rng.rand(60))
    end

    def generate_day(day)
      poisson(ORDERS_PER_DAY * SEASONALITY[day.month] * @growth).times { |index| generate_order(day, index) }
    end

    def generate_order(day, index)
      product = weighted_product
      quantity = @rng.rand < 0.85 ? 1 : @rng.rand(2..3)
      order_id = format("11%d-%07d-%07d", @rng.rand(1..4), @rng.rand(10_000_000), @rng.rand(10_000_000))
      posted_at = at(day)
      principal = product[:price] * quantity
      tax_rate = TAX_RATES.sample(random: @rng)
      shipping = @rng.rand < 0.12 ? 599 : 0
      promotion = @rng.rand < 0.1 ? -(principal * [0.1, 0.15, 0.2].sample(random: @rng)).round : 0
      commission = -[((principal + shipping + promotion) * 0.15).round, 30].max

      leaves = [[%w[Sales ProductCharges], principal]]
      leaves << [%w[Sales Shipping], shipping] if shipping.positive?
      leaves << [%w[Sales Promotion], promotion] if promotion.negative?
      tax_leaves(leaves, principal + promotion, tax_rate, "Principal", "OurPriceTax")
      tax_leaves(leaves, shipping, tax_rate, "Shipping", "ShippingTax") if shipping.positive?
      leaves << [%w[Expenses AmazonFees Commission], commission]
      leaves << [%w[Expenses AmazonFees FBAPerUnitFulfillmentFee], -product[:fba_fee] * quantity]
      leaves << [%w[Expenses AmazonFees ShippingChargeback], -shipping] if shipping.positive?

      add(key: "order:#{day}:#{index}:#{order_id}", type: "Shipment", description: "Order Payment", posted_at: posted_at,
        leaves: leaves, order_id: order_id, items: [item(product, quantity, principal)])

      return unless @rng.rand < 0.045

      refund_principal = -(principal + promotion)
      refund_leaves = [[%w[Sales ProductCharges], refund_principal]]
      tax_leaves(refund_leaves, refund_principal, tax_rate, "Principal", "OurPriceTax")
      refund_leaves << [%w[Expenses AmazonFees Commission], -commission]
      refund_leaves << [%w[Expenses AmazonFees RefundCommission], -[(-commission * 0.2).round, 500].min]
      add(key: "refund:#{order_id}", type: "Refund", description: "Refund for Order", posted_at: posted_at + @rng.rand(4..30).days,
        leaves: refund_leaves, order_id: order_id, items: [item(product, quantity, refund_principal)])
    end

    def tax_leaves(leaves, taxable_cents, rate, suffix, collected_type)
      tax = (taxable_cents * rate).round
      return if tax.zero?

      leaves << [["Tax", collected_type], tax]
      leaves << [["Tax", "MarketplaceFacilitatorTax-#{suffix}"], -tax]
    end

    def generate_monthly_charges
      (1..12).each do |month|
        first = Date.new(@year, month, 1)
        busy = SEASONALITY[month] * @growth

        add(key: "subscription:#{first}", type: "ServiceFee", description: "Subscription Fee", posted_at: at(first + 1, 3..6),
          leaves: [[%w[Expenses AmazonFees Subscription], -3999]])
        storage = -((3_000 + @rng.rand(2_500)) * (month >= 10 ? 2.6 : 1) * busy).round
        add(key: "storage:#{first}", type: "ServiceFee", description: "FBA Inventory Storage Fee", posted_at: at(first + 7),
          leaves: [[%w[Expenses AmazonFees FBAStorageFee], storage]])

        [3, 13, 23].each do |day|
          add(key: "ads:#{first}:#{day}", type: "ProductAdsPayment", description: "Cost of Advertising", posted_at: at(first + day),
            leaves: [[%w[Expenses ProductAdsPayment], -((6_000 + @rng.rand(5_000)) * busy).round]])
        end

        if month.odd?
          add(key: "placement:#{first}", type: "ServiceFee", description: "FBA Inbound Placement Service Fee", posted_at: at(first + 17),
            leaves: [[%w[Expenses AmazonFees FBAInboundPlacementServiceFee], -(6_000 + @rng.rand(7_000))]])
        end
        if month % 3 == 2
          product = PRODUCTS.sample(random: @rng)
          cents = (product[:price] * 0.55).round * (units = @rng.rand(1..4))
          add(key: "reimbursement:#{first}", type: "Adjustment", description: "FBA Inventory Reimbursement - Lost:Warehouse", posted_at: at(first + 20),
            leaves: [[%w[Reimbursements FBAInventoryReimbursement], cents]], items: [item(product, units, cents)])
        end
        if [2, 8].include?(month)
          add(key: "long-term-storage:#{first}", type: "ServiceFee", description: "FBA Long-Term Storage Fee", posted_at: at(first + 14),
            leaves: [[%w[Expenses AmazonFees FBALongTermStorageFee], -(2_500 + @rng.rand(6_000))]])
        end
        if [4, 9].include?(month)
          add(key: "disposal:#{first}", type: "ServiceFee", description: "FBA Removal Order: Disposal Fee", posted_at: at(first + 10),
            leaves: [[%w[Expenses AmazonFees FBADisposalFee], -(1_200 + @rng.rand(3_000))]])
        end
      end
    end

    # A handful of transactions the category rules can't place, so Review always has work to do.
    def generate_review_items
      [
        [3, 12, "Adjustment", "Shipping Credit Adjustment", %w[Sales Shipping], 899],
        [5, 6, "MiscellaneousLedgerAdjustment", "Miscellaneous Adjustment", %w[Sales Other], 2_450],
        [6, 19, "RemovalShipment", "FBA Liquidations Proceeds", %w[Sales ProductCharges], 11_874],
        [8, 27, "Adjustment", "Shipping Credit Adjustment", %w[Sales Shipping], 599],
        [10, 2, "MiscellaneousLedgerAdjustment", "Miscellaneous Adjustment", %w[Sales Other], 1_375],
        [11, 14, "Retrocharge", "Retrocharge", %w[Sales Retrocharge], -412]
      ].each do |month, day, type, description, path, cents|
        date = Date.new(@year, month, day)
        add(key: "review:#{date}:#{type}", type: type, description: description, posted_at: at(date), leaves: [[path, cents]])
      end
    end

    # Groups transactions into 14-day settlements and closes each with a bank transfer of its positive balance.
    def add_settlements_and_transfers
      @transactions.sort_by! { |transaction| [transaction[:posted_at], transaction[:key]] }
      by_period = @transactions.group_by { |transaction| ((transaction[:posted_at] - year_start) / SETTLEMENT_DAYS.days).floor }
      balance = 0

      (0..(366 / SETTLEMENT_DAYS)).each do |period|
        settlement_id = (21_800_000_000 + (@year - 2020) * 100_000 + period * 37 + 11).to_s
        Array(by_period[period]).each do |transaction|
          transaction[:settlement_id] = settlement_id
          balance += transaction[:leaves].sum(&:last)
        end

        closes_at = year_start + ((period + 1) * SETTLEMENT_DAYS).days - 1.hour
        next if closes_at >= year_end || balance <= 0

        add(key: "transfer:#{period}", type: "Transfer", description: "Disbursement to bank account ending in 4821",
          posted_at: closes_at, leaves: [], total_cents: -balance, settlement_id: settlement_id)
        balance = 0
      end

      @transactions.sort_by! { |transaction| [transaction[:posted_at], transaction[:key]] }
    end

    def add(**transaction)
      @transactions << transaction
    end

    def build(key:, type:, description:, posted_at:, leaves:, order_id: nil, items: nil, total_cents: nil, settlement_id: nil)
      related = []
      related << { "relatedIdentifierName" => "ORDER_ID", "relatedIdentifierValue" => order_id } if order_id
      related << { "relatedIdentifierName" => "SETTLEMENT_ID", "relatedIdentifierValue" => settlement_id } if settlement_id

      {
        "sellingPartnerMetadata" => { "sellingPartnerId" => SELLING_PARTNER_ID, "accountType" => "Standard Orders", "marketplaceId" => AmazonConnection::US_MARKETPLACE_ID },
        "relatedIdentifiers" => related,
        "transactionType" => type,
        "transactionId" => Digest::SHA256.hexdigest("sandbox-seller:#{@year}:#{key}")[0, 40].upcase,
        "transactionStatus" => "RELEASED",
        "description" => description,
        "postedDate" => posted_at.utc.iso8601,
        "totalAmount" => money(total_cents || leaves.sum(&:last)),
        "marketplaceDetails" => MARKETPLACE_DETAILS,
        "items" => items,
        "breakdowns" => breakdowns(leaves)
      }.compact
    end

    def breakdowns(leaves)
      leaves.group_by { |path, _cents| path.first }.map do |type, entries|
        node = { "breakdownType" => type, "breakdownAmount" => money(entries.sum(&:last)) }
        children = entries.filter_map { |path, cents| [path.drop(1), cents] if path.size > 1 }
        node["breakdowns"] = breakdowns(children) if children.any?
        node
      end
    end

    def item(product, quantity, cents)
      {
        "description" => product[:title],
        "totalAmount" => money(cents),
        "contexts" => [{ "contextType" => "ProductContext", "asin" => product[:asin], "sku" => product[:sku], "quantityShipped" => quantity, "fulfillmentNetwork" => "AFN" }]
      }
    end

    def money(cents)
      { "currencyCode" => "USD", "currencyAmount" => (cents / 100.0).round(2) }
    end

    def weighted_product
      pick = @rng.rand(PRODUCTS.sum { |product| product[:weight] })
      PRODUCTS.find { |product| (pick -= product[:weight]).negative? }
    end

    def poisson(mean)
      limit = Math.exp(-mean)
      count = 0
      product = @rng.rand
      while product > limit
        count += 1
        product *= @rng.rand
      end
      count
    end
  end
end
