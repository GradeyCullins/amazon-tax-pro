class CreateAccountingModels < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.integer :kind, null: false
      t.integer :balance_cents, null: false, default: 0
      t.timestamps
    end

    create_table :transactions do |t|
      t.date :transacted_on, null: false
      t.string :description, null: false
      t.references :debit_account, null: false, foreign_key: { to_table: :accounts }
      t.references :credit_account, null: false, foreign_key: { to_table: :accounts }
      t.integer :amount_cents, null: false
      t.timestamps
    end

    create_table :invoices do |t|
      t.string :number, null: false
      t.string :customer_name, null: false
      t.date :due_on, null: false
      t.integer :status, null: false, default: 0
      t.integer :total_cents, null: false
      t.timestamps
    end

    create_table :expenses do |t|
      t.string :vendor, null: false
      t.string :category, null: false
      t.date :spent_on, null: false
      t.integer :amount_cents, null: false
      t.timestamps
    end
  end
end
