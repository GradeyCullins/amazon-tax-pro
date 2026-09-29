class CreateAmazonConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :amazon_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :selling_partner_id, null: false
      t.text :refresh_token, null: false
      t.string :region, null: false, default: "na"
      t.string :marketplace_id, null: false, default: "ATVPDKIKX0DER"
      t.integer :status, null: false, default: 0
      t.datetime :connected_at, null: false
      t.datetime :last_synced_at
      t.text :last_error

      t.timestamps
    end
    add_index :amazon_connections, :selling_partner_id, unique: true
  end
end
