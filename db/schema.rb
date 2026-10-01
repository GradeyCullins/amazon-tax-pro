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

ActiveRecord::Schema[8.1].define(version: 2026_09_30_000200) do
  create_table "accounts", force: :cascade do |t|
    t.integer "balance_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "amazon_connections", force: :cascade do |t|
    t.datetime "connected_at", null: false
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.string "marketplace_id", default: "ATVPDKIKX0DER", null: false
    t.text "refresh_token", null: false
    t.string "region", default: "na", null: false
    t.string "selling_partner_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["selling_partner_id"], name: "index_amazon_connections_on_selling_partner_id", unique: true
    t.index ["user_id"], name: "index_amazon_connections_on_user_id", unique: true
  end

  create_table "amazon_import_batches", force: :cascade do |t|
    t.integer "amazon_connection_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename", null: false
    t.datetime "finished_at"
    t.datetime "imported_at", null: false
    t.integer "row_count", default: 0, null: false
    t.integer "source", default: 0, null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "sync_status"
    t.integer "tax_year"
    t.integer "transactions_fetched", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["amazon_connection_id"], name: "index_amazon_import_batches_on_amazon_connection_id"
    t.index ["user_id"], name: "index_amazon_import_batches_on_user_id"
  end

  create_table "amazon_import_rows", force: :cascade do |t|
    t.integer "amazon_import_batch_id", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "amount_description"
    t.string "amount_type"
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "expense_id"
    t.string "external_id"
    t.string "marketplace"
    t.string "order_id"
    t.date "posted_on"
    t.text "raw_data"
    t.string "settlement_id"
    t.integer "source_row_number", null: false
    t.integer "status", default: 0, null: false
    t.string "tax_category", default: "uncategorized", null: false
    t.integer "transaction_id"
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["amazon_import_batch_id"], name: "index_amazon_import_rows_on_amazon_import_batch_id"
    t.index ["expense_id"], name: "index_amazon_import_rows_on_expense_id"
    t.index ["transaction_id"], name: "index_amazon_import_rows_on_transaction_id"
    t.index ["user_id", "external_id"], name: "index_amazon_import_rows_on_user_id_and_external_id", unique: true
    t.index ["user_id"], name: "index_amazon_import_rows_on_user_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.date "spent_on", null: false
    t.datetime "updated_at", null: false
    t.string "vendor", null: false
  end

  create_table "invoices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_name", null: false
    t.date "due_on", null: false
    t.string "number", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_cents", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "credit_account_id", null: false
    t.integer "debit_account_id", null: false
    t.string "description", null: false
    t.date "transacted_on", null: false
    t.datetime "updated_at", null: false
    t.index ["credit_account_id"], name: "index_transactions_on_credit_account_id"
    t.index ["debit_account_id"], name: "index_transactions_on_debit_account_id"
  end

  create_table "turbo_tax_export_inputs", force: :cascade do |t|
    t.integer "beginning_inventory_cents", default: 0, null: false
    t.string "business_name", default: "Amazon Seller Business", null: false
    t.datetime "created_at", null: false
    t.integer "ending_inventory_cents", default: 0, null: false
    t.integer "labor_cents", default: 0, null: false
    t.integer "materials_cents", default: 0, null: false
    t.integer "other_costs_cents", default: 0, null: false
    t.integer "purchases_cents", default: 0, null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "tax_year"], name: "index_turbo_tax_export_inputs_on_user_id_and_tax_year", unique: true
    t.index ["user_id"], name: "index_turbo_tax_export_inputs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "business_name"
    t.integer "default_tax_year"
    t.integer "review_threshold_dollars"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "amazon_connections", "users"
  add_foreign_key "amazon_import_batches", "amazon_connections", on_delete: :nullify
  add_foreign_key "amazon_import_batches", "users"
  add_foreign_key "amazon_import_rows", "amazon_import_batches"
  add_foreign_key "amazon_import_rows", "expenses"
  add_foreign_key "amazon_import_rows", "transactions"
  add_foreign_key "amazon_import_rows", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts", column: "credit_account_id"
  add_foreign_key "transactions", "accounts", column: "debit_account_id"
  add_foreign_key "turbo_tax_export_inputs", "users"
end
