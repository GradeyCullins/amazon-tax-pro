class CreateAmazonImports < ActiveRecord::Migration[7.0]
  def change
    create_table :amazon_import_batches do |t|
      t.string :filename, null: false
      t.integer :status, null: false, default: 0
      t.integer :row_count, null: false, default: 0
      t.datetime :imported_at, null: false
      t.timestamps
    end

    create_table :amazon_import_rows do |t|
      t.references :amazon_import_batch, null: false, foreign_key: true
      t.integer :source_row_number, null: false
      t.date :posted_on
      t.string :settlement_id
      t.string :order_id
      t.string :transaction_type
      t.string :amount_type
      t.string :amount_description
      t.string :description
      t.string :marketplace
      t.integer :amount_cents, null: false, default: 0
      t.string :tax_category, null: false, default: "uncategorized"
      t.integer :status, null: false, default: 0
      t.text :raw_data
      t.references :transaction, foreign_key: true
      t.references :expense, foreign_key: true
      t.timestamps
    end
  end
end
