class AddSpApiSyncFields < ActiveRecord::Migration[8.1]
  def change
    change_table :amazon_import_batches do |t|
      t.integer :source, null: false, default: 0
      t.integer :tax_year
      t.integer :sync_status
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.integer :transactions_fetched, null: false, default: 0
      t.references :amazon_connection, foreign_key: { on_delete: :nullify }
    end

    add_column :amazon_import_rows, :external_id, :string
    add_index :amazon_import_rows, [:user_id, :external_id], unique: true
  end
end
