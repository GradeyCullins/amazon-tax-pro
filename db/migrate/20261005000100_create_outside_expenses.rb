class CreateOutsideExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :outside_expenses do |t|
      t.references :user, null: false, foreign_key: true
      t.date :spent_on, null: false
      t.string :payee, null: false
      t.string :category, null: false
      t.integer :amount_cents, null: false
      t.integer :business_use_percent, null: false, default: 100
      t.string :description
      t.datetime :archived_at
      t.timestamps
    end

    add_index :outside_expenses, [:user_id, :spent_on, :archived_at]
  end
end
