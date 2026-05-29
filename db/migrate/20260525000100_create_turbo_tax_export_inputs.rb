class CreateTurboTaxExportInputs < ActiveRecord::Migration[7.0]
  def change
    create_table :turbo_tax_export_inputs do |t|
      t.integer :tax_year, null: false
      t.string :business_name, null: false, default: "Amazon Seller Business"
      t.integer :beginning_inventory_cents, null: false, default: 0
      t.integer :purchases_cents, null: false, default: 0
      t.integer :materials_cents, null: false, default: 0
      t.integer :labor_cents, null: false, default: 0
      t.integer :other_costs_cents, null: false, default: 0
      t.integer :ending_inventory_cents, null: false, default: 0
      t.timestamps
    end

    add_index :turbo_tax_export_inputs, :tax_year, unique: true
  end
end
