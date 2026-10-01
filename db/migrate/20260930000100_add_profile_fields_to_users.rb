class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :display_name, :string
    add_column :users, :business_name, :string
    add_column :users, :default_tax_year, :integer
  end
end
