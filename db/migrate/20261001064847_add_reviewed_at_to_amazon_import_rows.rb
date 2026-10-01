class AddReviewedAtToAmazonImportRows < ActiveRecord::Migration[8.1]
  def change
    # NULL means no person has reviewed the row; its status came from the auto-accept rule.
    add_column :amazon_import_rows, :reviewed_at, :datetime
    add_index :amazon_import_rows, [:user_id, :posted_on]

    reversible do |direction|
      direction.up do
        # Before auto-accept, every accepted (1) or skipped (2) row was a person's decision.
        execute "UPDATE amazon_import_rows SET reviewed_at = updated_at WHERE status IN (1, 2)"
      end
    end
  end
end
