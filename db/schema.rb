# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_05_25_000100) do
  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.integer "kind", null: false
    t.integer "balance_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "amazon_import_batches", force: :cascade do |t|
    t.string "filename", null: false
    t.integer "status", default: 0, null: false
    t.integer "row_count", default: 0, null: false
    t.datetime "imported_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "amazon_import_rows", force: :cascade do |t|
    t.integer "amazon_import_batch_id", null: false
    t.integer "source_row_number", null: false
    t.date "posted_on"
    t.string "settlement_id"
    t.string "order_id"
    t.string "transaction_type"
    t.string "amount_type"
    t.string "amount_description"
    t.string "description"
    t.string "marketplace"
    t.integer "amount_cents", default: 0, null: false
    t.string "tax_category", default: "uncategorized", null: false
    t.integer "status", default: 0, null: false
    t.text "raw_data"
    t.integer "transaction_id"
    t.integer "expense_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["amazon_import_batch_id"], name: "index_amazon_import_rows_on_amazon_import_batch_id"
    t.index ["expense_id"], name: "index_amazon_import_rows_on_expense_id"
    t.index ["transaction_id"], name: "index_amazon_import_rows_on_transaction_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.string "vendor", null: false
    t.string "category", null: false
    t.date "spent_on", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invoices", force: :cascade do |t|
    t.string "number", null: false
    t.string "customer_name", null: false
    t.date "due_on", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.date "transacted_on", null: false
    t.string "description", null: false
    t.integer "debit_account_id", null: false
    t.integer "credit_account_id", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credit_account_id"], name: "index_transactions_on_credit_account_id"
    t.index ["debit_account_id"], name: "index_transactions_on_debit_account_id"
  end

  create_table "turbo_tax_export_inputs", force: :cascade do |t|
    t.integer "tax_year", null: false
    t.string "business_name", default: "Amazon Seller Business", null: false
    t.integer "beginning_inventory_cents", default: 0, null: false
    t.integer "purchases_cents", default: 0, null: false
    t.integer "materials_cents", default: 0, null: false
    t.integer "labor_cents", default: 0, null: false
    t.integer "other_costs_cents", default: 0, null: false
    t.integer "ending_inventory_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tax_year"], name: "index_turbo_tax_export_inputs_on_tax_year", unique: true
  end

  add_foreign_key "amazon_import_rows", "amazon_import_batches"
  add_foreign_key "amazon_import_rows", "expenses"
  add_foreign_key "amazon_import_rows", "transactions"
  add_foreign_key "transactions", "accounts", column: "credit_account_id"
  add_foreign_key "transactions", "accounts", column: "debit_account_id"
end
