class AddReviewThresholdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :review_threshold_dollars, :integer
  end
end
