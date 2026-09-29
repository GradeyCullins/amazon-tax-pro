class ScopeAmazonDataToUsers < ActiveRecord::Migration[8.1]
  def up
    # Pre-account data was single-tenant demo data and is intentionally discarded.
    execute "DELETE FROM amazon_import_rows"
    execute "DELETE FROM amazon_import_batches"
    execute "DELETE FROM turbo_tax_export_inputs"

    add_reference :amazon_import_batches, :user, null: false, foreign_key: true
    add_reference :amazon_import_rows, :user, null: false, foreign_key: true
    add_reference :turbo_tax_export_inputs, :user, null: false, foreign_key: true

    remove_index :turbo_tax_export_inputs, :tax_year
    add_index :turbo_tax_export_inputs, [:user_id, :tax_year], unique: true
  end

  def down
    remove_index :turbo_tax_export_inputs, [:user_id, :tax_year]
    add_index :turbo_tax_export_inputs, :tax_year, unique: true

    remove_reference :turbo_tax_export_inputs, :user, foreign_key: true
    remove_reference :amazon_import_rows, :user, foreign_key: true
    remove_reference :amazon_import_batches, :user, foreign_key: true
  end
end
