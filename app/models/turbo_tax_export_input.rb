require "bigdecimal/util"

class TurboTaxExportInput < ApplicationRecord
  MONEY_FIELDS = %i[
    beginning_inventory_cents
    purchases_cents
    materials_cents
    labor_cents
    other_costs_cents
    ending_inventory_cents
  ].freeze

  validates :tax_year, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 2000 }
  validates :business_name, presence: true
  validates(*MONEY_FIELDS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })

  MONEY_FIELDS.each do |field|
    dollars_name = field.to_s.sub(/_cents\z/, "_dollars")

    define_method(dollars_name) do
      format("%.2f", public_send(field).to_i / 100.0)
    end

    define_method("#{dollars_name}=") do |value|
      public_send("#{field}=", (value.to_s.gsub(/[$,]/, "").to_d * 100).round)
    end
  end

  def self.for_year(year)
    find_or_initialize_by(tax_year: year.to_i) do |record|
      record.business_name = "Amazon Seller Business"
    end
  end

  def cost_of_goods_sold_cents
    beginning_inventory_cents + purchases_cents + materials_cents + labor_cents + other_costs_cents - ending_inventory_cents
  end
end
